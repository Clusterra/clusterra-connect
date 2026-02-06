#!/bin/bash
# clusterra-hook.sh - Fire-and-forget event delivery to Clusterra
#
# This script replaces the old Python + SQS approach with a simple curl call.
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
if [[ -z "${CLUSTERRA_API_URL:-}" || -z "${CLUSTER_ID:-}" ]]; then
    exit 0
fi

# Build JSON event from Slurm environment variables
EVENT=$(cat <<EOF
{
  "ts": "$(date -Iseconds)",
  "event": "$EVENT_TYPE",
  "cluster_id": "$CLUSTER_ID",
  "tenant_id": "${TENANT_ID:-}",
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

# Fire-and-forget: curl runs in background, output suppressed
# --max-time 5: Give up after 5 seconds (don't hang forever)
# -s: Silent mode (no progress bar)
# -f: Fail silently on HTTP errors (don't output error page)
(curl -s -f --max-time 5 \
  -X POST \
  -H "Content-Type: application/json" \
  -H "X-Cluster-ID: $CLUSTER_ID" \
  -d "$EVENT" \
  "${CLUSTERRA_API_URL}/v1/internal/events" \
  2>/dev/null) &

# Exit immediately - don't wait for curl
exit 0
