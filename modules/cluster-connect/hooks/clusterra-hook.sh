#!/bin/bash
# clusterra-hook.sh - Fire-and-forget event delivery to Clusterra API
#
# This script sends Slurm job events directly to Clusterra API via HTTPS.
# Runs in background (&) to avoid blocking the Slurm scheduler.
#
# Usage (called by Slurm prolog/epilog):
#   clusterra-hook.sh <event_type>
#
# Event types: job.started, job.completed, job.failed, job.cancelled
#

set -o pipefail

# Load configuration
source /etc/clusterra/hooks.env 2>/dev/null || true

EVENT_TYPE="${1:-unknown}"

# Skip if not configured
if [[ -z "${CLUSTER_ID:-}" || -z "${TENANT_ID:-}" ]]; then
    exit 0
fi

# Get API endpoint from environment or use default
API_ENDPOINT="${CLUSTERRA_API_ENDPOINT:-api.clusterra.cloud}"

# Build JSON event payload
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PAYLOAD=$(cat <<EOF
{
  "cluster_id": "$CLUSTER_ID",
  "tenant_id": "$TENANT_ID",
  "source": "clusterra.slurm",
  "detail-type": "$EVENT_TYPE",
  "time": "$TIMESTAMP",
  "detail": {
    "job_id": "${SLURM_JOB_ID:-}",
    "user": "${SLURM_JOB_USER:-}",
    "partition": "${SLURM_JOB_PARTITION:-}",
    "node": "${SLURMD_NODENAME:-}",
    "exit_code": "${SLURM_JOB_EXIT_CODE:-}",
    "state": "${SLURM_JOB_STATE:-}",
    "nodes": "${SLURM_JOB_NODELIST:-}"
  }
}
EOF
)

# Fire-and-forget: curl runs in background
# No authentication needed - public API endpoint
(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "X-Cluster-ID: $CLUSTER_ID" \
  -d "$PAYLOAD" \
  "https://${API_ENDPOINT}/v1/internal/events" \
  -o /dev/null 2>/dev/null) &

# Exit immediately - don't wait for curl
exit 0
