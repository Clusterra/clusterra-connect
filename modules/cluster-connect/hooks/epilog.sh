#!/bin/bash
# /opt/slurm/etc/epilog.sh (installed by Clusterra)
#
# Slurm Epilog - runs on COMPUTE node when job step finishes
# Sends job.ended event to Clusterra API asynchronously (v2 - curl)
#
# This script MUST exit 0 to avoid issues.

# Run Clusterra hook in background (async, non-blocking)
if [ -f /etc/clusterra/hooks.env ]; then
    source /etc/clusterra/hooks.env
    export CLUSTERRA_API_URL CLUSTER_ID TENANT_ID
fi
(/opt/clusterra/clusterra-hook.sh job.ended &)

# Chain to customer's original epilog if it was backed up during install
if [ -x /opt/slurm/etc/epilog.sh.customer ]; then
    exec /opt/slurm/etc/epilog.sh.customer
fi

exit 0
