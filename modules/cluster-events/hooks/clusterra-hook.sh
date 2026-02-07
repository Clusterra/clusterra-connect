#!/bin/bash
# clusterra-hook.sh - Fire-and-forget event delivery to Clusterra via EventBridge
#
# This script sends Slurm job events directly to Clusterra's EventBus.
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

# Get EventBus ARN from environment or use default
EVENT_BUS_ARN="${CLUSTERRA_EVENT_BUS_ARN:-arn:aws:events:ap-south-1:306847926740:event-bus/clusterra-ingest}"

# Build JSON event from Slurm environment variables
# EventBridge expects a specific format for put-events
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DETAIL=$(cat <<EOF
{
  "cluster_id": "$CLUSTER_ID",
  "tenant_id": "$TENANT_ID",
  "job_id": "${SLURM_JOB_ID:-}",
  "user": "${SLURM_JOB_USER:-}",
  "partition": "${SLURM_JOB_PARTITION:-}",
  "node": "${SLURMD_NODENAME:-}",
  "exit_code": "${SLURM_JOB_EXIT_CODE:-}",
  "state": "${SLURM_JOB_STATE:-}",
  "nodes": "${SLURM_JOB_NODELIST:-}"
}
EOF
)

# Fire-and-forget: aws CLI runs in background
# Uses instance IAM role for authentication (no keys needed)
(aws events put-events \
  --entries "[{
    \"Source\": \"clusterra.slurm\",
    \"DetailType\": \"$EVENT_TYPE\",
    \"Detail\": $(echo "$DETAIL" | jq -c . | jq -Rs .),
    \"EventBusName\": \"$EVENT_BUS_ARN\"
  }]" \
  --region "${AWS_REGION:-ap-south-1}" \
  2>/dev/null) &

# Exit immediately - don't wait for aws CLI
exit 0
