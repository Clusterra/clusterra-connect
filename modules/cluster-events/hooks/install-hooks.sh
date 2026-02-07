#!/bin/bash
# install-hooks.sh
#
# Install Clusterra hooks on ParallelCluster head node
# Run this on the head node after cluster creation
#
# Usage: install-hooks.sh <cluster_id> <tenant_id> [eventbus_arn] [region]
#
# v3: Uses aws events put-events (cross-account EventBridge)

set -e

CLUSTER_ID="${1:-}"
TENANT_ID="${2:-}"
EVENT_BUS_ARN="${3:-arn:aws:events:ap-south-1:306847926740:event-bus/clusterra-ingest}"
AWS_REGION="${4:-ap-south-1}"

if [ -z "$CLUSTER_ID" ] || [ -z "$TENANT_ID" ]; then
    echo "Usage: install-hooks.sh <cluster_id> <tenant_id> [eventbus_arn] [region]"
    echo "  cluster_id:    Your Clusterra cluster ID (e.g., clusa1b2)"
    echo "  tenant_id:     Your Clusterra tenant ID"
    echo "  eventbus_arn:  Clusterra EventBus ARN (optional)"
    echo "  region:        AWS region (default: ap-south-1)"
    exit 1
fi

CLUSTERRA_DIR="/opt/clusterra"
SLURM_CONF="/opt/slurm/etc/slurm.conf"

echo "=== Installing Clusterra Hooks (v3 - EventBridge) ==="

# 1. Create directory
sudo mkdir -p "$CLUSTERRA_DIR"

# 2. Copy hook scripts (assuming they're in same dir as this script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sudo cp "$SCRIPT_DIR/clusterra-hook.sh" "$CLUSTERRA_DIR/"
sudo cp "$SCRIPT_DIR/prolog.sh" "$CLUSTERRA_DIR/"
sudo cp "$SCRIPT_DIR/epilog.sh" "$CLUSTERRA_DIR/"
sudo cp "$SCRIPT_DIR/slurmctld_prolog.sh" "$CLUSTERRA_DIR/"
sudo cp "$SCRIPT_DIR/slurmctld_epilog.sh" "$CLUSTERRA_DIR/"

# 3. Make executable
sudo chmod +x "$CLUSTERRA_DIR"/*

# 4. Create environment file (EventBridge version)
sudo mkdir -p /etc/clusterra
sudo tee /etc/clusterra/hooks.env > /dev/null <<EOF
# Clusterra Hook Configuration (v3 - EventBridge)
CLUSTER_ID=$CLUSTER_ID
TENANT_ID=$TENANT_ID
CLUSTERRA_EVENT_BUS_ARN=$EVENT_BUS_ARN
AWS_REGION=$AWS_REGION
EOF
sudo chmod 600 /etc/clusterra/hooks.env

# 5. Wrapper that sources env
sudo tee "$CLUSTERRA_DIR/run-hook.sh" > /dev/null <<'WRAPPER'
#!/bin/bash
source /etc/clusterra/hooks.env
export CLUSTER_ID TENANT_ID CLUSTERRA_EVENT_BUS_ARN AWS_REGION
exec "$@"
WRAPPER
sudo chmod +x "$CLUSTERRA_DIR/run-hook.sh"

# 6. Prefix-and-wrap: Backup existing customer hooks before installing wrappers
SLURM_ETC="/opt/slurm/etc"

echo "Setting up hook wrappers..."

# Backup existing prolog.sh if it exists and isn't already ours
if [ -f "$SLURM_ETC/prolog.sh" ] && ! grep -q "clusterra" "$SLURM_ETC/prolog.sh"; then
    echo "Backing up existing prolog.sh to prolog.sh.customer"
    sudo mv "$SLURM_ETC/prolog.sh" "$SLURM_ETC/prolog.sh.customer"
fi

# Backup existing epilog.sh if it exists and isn't already ours
if [ -f "$SLURM_ETC/epilog.sh" ] && ! grep -q "clusterra" "$SLURM_ETC/epilog.sh"; then
    echo "Backing up existing epilog.sh to epilog.sh.customer"
    sudo mv "$SLURM_ETC/epilog.sh" "$SLURM_ETC/epilog.sh.customer"
fi

# Install Clusterra wrappers at standard Slurm locations
sudo cp "$CLUSTERRA_DIR/prolog.sh" "$SLURM_ETC/prolog.sh"
sudo cp "$CLUSTERRA_DIR/epilog.sh" "$SLURM_ETC/epilog.sh"
sudo chmod +x "$SLURM_ETC/prolog.sh" "$SLURM_ETC/epilog.sh"

# 7. Update slurm.conf with slurmctld hooks (only if not already configured)
if ! grep -q "PrologSlurmctld=" "$SLURM_CONF"; then
    echo "Updating slurm.conf with Clusterra slurmctld hooks..."
    sudo tee -a "$SLURM_CONF" > /dev/null <<EOF

# Clusterra Hooks (added by install-hooks.sh v3)
PrologSlurmctld=$CLUSTERRA_DIR/slurmctld_prolog.sh
EpilogSlurmctld=$CLUSTERRA_DIR/slurmctld_epilog.sh
# Node-level hooks are at standard locations: /opt/slurm/etc/prolog.sh, epilog.sh
EOF
else
    echo "Slurm hooks already configured"
fi

# 8. Restart slurmctld
echo "Restarting slurmctld..."
sudo systemctl restart slurmctld || true

# 9. Test EventBridge access
echo "Testing Clusterra EventBridge access..."
TEST_RESULT=$(aws events put-events \
    --entries "[{
        \"Source\": \"clusterra.slurm\",
        \"DetailType\": \"test.install\",
        \"Detail\": \"{\\\"cluster_id\\\":\\\"$CLUSTER_ID\\\",\\\"tenant_id\\\":\\\"$TENANT_ID\\\",\\\"event\\\":\\\"hooks_installed\\\"}\",
        \"EventBusName\": \"$EVENT_BUS_ARN\"
    }]" \
    --region "$AWS_REGION" 2>&1) && {
    FAILED=$(echo "$TEST_RESULT" | jq -r '.FailedEntryCount // 0')
    if [ "$FAILED" = "0" ]; then
        echo " - EventBridge test successful"
    else
        echo " - Warning: EventBridge test failed (this is normal if IAM not yet propagated)"
        echo "   $TEST_RESULT"
    fi
} || {
    echo " - Warning: EventBridge test failed (check IAM permissions)"
    echo "   $TEST_RESULT"
}

echo ""
echo "=== Clusterra Hooks Installed (v3 - EventBridge) ==="
echo "Cluster ID: $CLUSTER_ID"
echo "Tenant ID: $TENANT_ID"
echo "EventBus ARN: $EVENT_BUS_ARN"
echo "Region: $AWS_REGION"
