#!/bin/bash
# /opt/clusterra/epilog.sh
#
# Slurm Epilog - runs on COMPUTE node when job step finishes
# Sends job.ended event to SQS asynchronously
#
# This script MUST exit 0 to avoid issues.

# Run Python hook in background (async, non-blocking)
if [ -f /etc/clusterra/hooks.env ]; then
    source /etc/clusterra/hooks.env
    export CLUSTERRA_SQS_URL
fi
(/opt/clusterra/clusterra-hook.py job.ended &)

# Chain to customer's epilog if exists
if [ -x /opt/slurm/etc/customer_epilog.sh ]; then
    exec /opt/slurm/etc/customer_epilog.sh
fi

exit 0
