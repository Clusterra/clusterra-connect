import json
import os
import boto3

# Initialize EventBridge client outside handler for reuse
events_client = boto3.client("events")


def handler(event, context):
    """
    Forwarder Lambda: Enriches events with Tenant/Cluster ID and forwards to SaaS Bus.

    Environment Variables:
    - CLUSTER_ID
    - TENANT_ID
    - CLUSTER_NAME
    - SAAS_BUS_ARN
    """
    try:
        # 1. Config
        cluster_id = os.environ.get("CLUSTER_ID")
        tenant_id = os.environ.get("TENANT_ID")
        cluster_name = os.environ.get("CLUSTER_NAME")
        saas_bus_arn = os.environ.get("SAAS_BUS_ARN")

        if not saas_bus_arn:
            print("ERROR: SAAS_BUS_ARN is missing")
            return

        # 2. Prepare Event
        # We keep the original source and detail-type, but enrich the detail
        detail = event.get("detail", {})

        # Ensure detail is a dict (sometimes it might be a string if malformed, though rare from AWS)
        if not isinstance(detail, dict):
            detail = {"raw_detail": str(detail)}

        # Add Metadata
        detail["tenant_id"] = tenant_id
        detail["cluster_id"] = cluster_id
        detail["cluster_name"] = cluster_name

        # 3. Forward
        entry = {
            "Source": event.get("source", "clusterra.forwarder"),
            "DetailType": event.get("detail-type", "Unknown Event"),
            "Detail": json.dumps(detail),
            "EventBusName": saas_bus_arn,
            "Resources": event.get("resources", []),
        }

        # Keep original time if possible, otherwise let AWS set it
        if "time" in event:
            entry["Time"] = event["time"]

        print(f"Forwarding event: {entry['Source']} / {entry['DetailType']}")

        response = events_client.put_events(Entries=[entry])

        if response["FailedEntryCount"] > 0:
            print(f"ERROR: Failed to forward event: {response}")
        else:
            print(f"SUCCESS: Event forwarded. ID: {response['Entries'][0]['EventId']}")

    except Exception as e:
        print(f"CRITICAL: Event forwarder failed: {e}")
        # We strictly swallow errors to prevent Lambda retry loops from spamming logs
        # unless it's a transient network issue, but for now we safeguard.
        raise e
