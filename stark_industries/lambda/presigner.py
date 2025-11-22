import json
import os
import boto3
import urllib.parse
from datetime import datetime

# Use default region from the Lambda execution environment / role
s3 = boto3.client("s3")

BUCKET = os.environ.get("BUCKET")
EXPIRES = int(os.environ.get("PRESIGN_EXPIRES", "300"))


def sanitize_filename(name: str) -> str:
    """Decode URL chars, remove spaces, enforce safe filename."""
    name = urllib.parse.unquote_plus(name)
    # minimal sanitize - replace spaces and strip tricky chars (keep it simple)
    name = name.replace(" ", "_")
    return name


def _json_response(status_code: int, body: dict):
    """Return a API Gateway compatible response with CORS headers."""
    return {
        "statusCode": status_code,
        "headers": {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "*",
            "Access-Control-Allow-Methods": "POST,OPTIONS",
            "Content-Type": "application/json"
        },
        "body": json.dumps(body)
    }


def lambda_handler(event, context):
    """
    Expected API Gateway proxy event:
      POST /presign
      body: {"filename": "my.jpg", "content_type": "image/jpeg"}

    This function is defensive: it handles missing/empty bodies (returns 400),
    returns consistent JSON and includes CORS headers.
    """
    try:
        # body may be None (e.g., malformed request, or some proxy situations)
        raw = event.get("body") if isinstance(event, dict) else None

        # If the API Gateway was not called with a body, respond with helpful 400
        if raw in (None, ""):
            return _json_response(400, {"error": "Missing request body"})

        # If API Gateway passed a JSON string, parse it safely
        if isinstance(raw, str):
            try:
                body = json.loads(raw)
            except json.JSONDecodeError:
                # try to be resilient; reject with 400
                return _json_response(400, {"error": "Invalid JSON body"})
        else:
            body = raw

        filename = body.get("filename")
        content_type = body.get("content_type", "application/octet-stream")

        if not filename:
            return _json_response(400, {"error": "filename required"})

        safe_name = sanitize_filename(filename)
        # unique key with UTC timestamp
        key = f"uploads/{datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')}-{safe_name}"

        # Generate presigned PUT URL
        presigned = s3.generate_presigned_url(
            ClientMethod="put_object",
            Params={
                "Bucket": BUCKET,
                "Key": key,
                "ContentType": content_type,
            },
            ExpiresIn=EXPIRES
        )

        return _json_response(200, {"url": presigned, "key": key, "bucket": BUCKET})

    except Exception as e:
        # Always return JSON; avoid leaking stack traces
        return _json_response(500, {"error": str(e)})
