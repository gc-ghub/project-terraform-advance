import json
import boto3
import os

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET"]
EXPIRE_SECONDS = int(os.environ.get("PRESIGN_EXPIRES", "300"))

def lambda_handler(event, context):
    try:
        print("EVENT:", event)
        try:
            raw_body = event.get("body")
            body = json.loads(raw_body) if raw_body else {}
        except Exception:
            body = {}

        filename = body.get("filename")
        content_type = body.get("content_type", "application/octet-stream")

        if not filename:
            return response(400, {"error": "filename required"})

        key = f"uploads/{filename}"

        presigned_url = s3.generate_presigned_url(
            ClientMethod="put_object",
            Params={
                "Bucket": BUCKET,
                "Key": key,
                "ContentType": content_type
            },
            ExpiresIn=EXPIRE_SECONDS
        )

        return response(200, {"url": presigned_url, "key": key})

    except Exception as e:
        print("ERROR:", e)
        return response(500, {"error": str(e)})

def response(status, body):
    return {
        "statusCode": status,
        "headers": {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "*",
            "Access-Control-Allow-Methods": "GET,PUT,POST,OPTIONS",
            "Cache-Control": "no-store"
        },
        "body": json.dumps(body)
    }
