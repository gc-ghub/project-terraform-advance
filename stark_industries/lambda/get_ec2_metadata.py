import json
import boto3
import os

def lambda_handler(event, context):
    ec2 = boto3.client("ec2")
    project = os.environ["PROJECT_NAME"]
    env = os.environ["ENV_NAME"]

    response = ec2.describe_instances(
        Filters=[
            {"Name": "tag:Project", "Values": [project]},
            {"Name": "tag:Environment", "Values": [env]}
        ]
    )

    instances = []

    for reservation in response.get("Reservations", []):
        for inst in reservation.get("Instances", []):
            instances.append({
                "instance_id": inst.get("InstanceId"),
                "instance_type": inst.get("InstanceType"),
                "ami_id": inst.get("ImageId"),
                "az": inst.get("Placement", {}).get("AvailabilityZone"),
                "private_ip": inst.get("PrivateIpAddress"),
                "public_ip": inst.get("PublicIpAddress"),
                "state": inst.get("State", {}).get("Name"),
                "tags": {t["Key"]: t["Value"] for t in inst.get("Tags", [])}
            })

    return {
        "statusCode": 200,
        "headers": {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "*"
        },
        "body": json.dumps(instances, indent=2)
    }
