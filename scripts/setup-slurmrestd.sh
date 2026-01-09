#!/bin/bash
# Setup slurmrestd with JWT authentication for Clusterra integration
# This script runs on the head node after ParallelCluster configuration
# Compatible with Amazon Linux 2023

set -e

# Arguments
JWT_SECRET_ARN="${1:-}"

# Paths (ParallelCluster standard locations)
SLURM_CONF="/opt/slurm/etc/slurm.conf"
JWT_KEY_PATH="/opt/slurm/etc/jwt_hs256.key"
SLURMRESTD_PORT=6830

echo "=== Clusterra: Configuring slurmrestd for JWT authentication ==="

# Source Slurm environment
if [ -f /etc/profile.d/slurm.sh ]; then
    source /etc/profile.d/slurm.sh
fi

# 1. Generate or retrieve JWT key
if [ -n "$JWT_SECRET_ARN" ]; then
    echo "Retrieving JWT key from Secrets Manager..."
    # Check if secret exists and has a value
    SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$JWT_SECRET_ARN" --query 'SecretString' --output text 2>/dev/null || echo "")
    
    if [ -z "$SECRET_VALUE" ] || [ "$SECRET_VALUE" == "PLACEHOLDER" ]; then
        echo "Generating new JWT key..."
        JWT_KEY=$(openssl rand -hex 32)
        aws secretsmanager put-secret-value --secret-id "$JWT_SECRET_ARN" --secret-string "$JWT_KEY"
    else
        JWT_KEY="$SECRET_VALUE"
    fi
else
    echo "No secret ARN provided, generating local JWT key..."
    JWT_KEY=$(openssl rand -hex 32)
fi

# 2. Write JWT key to file
echo "$JWT_KEY" | sudo tee "$JWT_KEY_PATH" > /dev/null
sudo chmod 600 "$JWT_KEY_PATH"
sudo chown slurm:slurm "$JWT_KEY_PATH"
echo "JWT key written to $JWT_KEY_PATH"

# 3. Update slurm.conf with JWT authentication
if ! grep -q "AuthAltTypes=auth/jwt" "$SLURM_CONF"; then
    echo "Adding JWT authentication to slurm.conf..."
    sudo tee -a "$SLURM_CONF" << EOF

# JWT Authentication for slurmrestd (added by Clusterra)
AuthAltTypes=auth/jwt
AuthAltParameters=jwt_key=$JWT_KEY_PATH
EOF
fi

# 4. Restart slurmctld to pick up JWT config
echo "Restarting slurmctld..."
sudo systemctl restart slurmctld || true
sleep 3

# 5. Create slurmrestd systemd service
echo "Creating slurmrestd systemd service..."
sudo tee /etc/systemd/system/slurmrestd.service << EOF
[Unit]
Description=Slurm REST API (Clusterra)
After=slurmctld.service munge.service
Wants=slurmctld.service

[Service]
Type=simple
User=slurmrestd
Group=slurmrestd
Environment=SLURM_CONF=$SLURM_CONF
ExecStart=/opt/slurm/sbin/slurmrestd -a rest_auth/jwt 0.0.0.0:$SLURMRESTD_PORT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 6. Create slurmrestd user if not exists
if ! id slurmrestd &>/dev/null; then
    echo "Creating slurmrestd user..."
    sudo useradd -r -s /bin/false slurmrestd
fi

# 7. Give slurmrestd user access to JWT key
sudo chown slurm:slurmrestd "$JWT_KEY_PATH"
sudo chmod 640 "$JWT_KEY_PATH"

# 8. Enable and start slurmrestd
echo "Enabling and starting slurmrestd..."
sudo systemctl daemon-reload
sudo systemctl enable slurmrestd
sudo systemctl start slurmrestd || true

# 9. Verify
sleep 3
if sudo systemctl is-active slurmrestd; then
    echo "=== slurmrestd is running ==="
    ss -tlnp | grep $SLURMRESTD_PORT || true
else
    echo "=== slurmrestd failed to start, checking logs ==="
    sudo journalctl -u slurmrestd -n 20 --no-pager || true
fi

echo "=== Clusterra: slurmrestd setup complete ==="
