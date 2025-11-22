import json
import boto3
import os

dynamodb = boto3.client("dynamodb")
sns = boto3.client("sns")

def lambda_handler(event, context):
    table = os.environ["TABLE_NAME"]
    topic = os.environ["SNS_TOPIC"]

    record = event["Records"][0]
    bucket = record["s3"]["bucket"]["name"]
    key = record["s3"]["object"]["key"]
    size = record["s3"]["object"].get("size", 0)

    # Store in DynamoDB
    dynamodb.put_item(
        TableName=table,
        Item={
            "object_key": { "S": key },
            "bucket": { "S": bucket },
            "size": { "N": str(size) }
        }
    )

    # Send notification
    sns.publish(
        TopicArn=topic,
        Subject="New S3 Replicated Object",
        Message=f"Object {key} replicated to bucket {bucket}"
    )

    return {"status": "ok"}
