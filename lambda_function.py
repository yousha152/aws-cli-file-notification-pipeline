import json
import os
import boto3
from botocore.exceptions import ClientError

s3 = boto3.client("s3")
sns = boto3.client("sns")
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]

def lambda_handler(event, context):
    processed = 0
    failed = 0
    for record in event.get("Records", []):
        message_id = record.get("messageId", "unknown")
        try:
            bucket, key = _parse_message(record)
            metadata = _get_object_metadata(bucket, key)
            _publish_notification(bucket, key, metadata)
            processed += 1
            print(f"[{message_id}] Notified for s3://{bucket}/{key}")
        except (KeyError, json.JSONDecodeError) as e:
            failed += 1
            print(f"[{message_id}] Skipping malformed message: {e}")
        except ClientError as e:
            failed += 1
            error_code = e.response.get("Error", {}).get("Code", "Unknown")
            print(f"[{message_id}] AWS error ({error_code}): {e}")
            raise
        except Exception as e:
            failed += 1
            print(f"[{message_id}] Unexpected error: {e}")
            raise
    result = {"processed": processed, "failed": failed}
    print(f"Batch complete: {result}")
    return {"statusCode": 200, "body": json.dumps(result)}

def _parse_message(record):
    body = json.loads(record["body"])
    bucket = body["bucket"]
    key = body["key"]
    return bucket, key

def _get_object_metadata(bucket, key):
    response = s3.head_object(Bucket=bucket, Key=key)
    return {
        "size": response.get("ContentLength"),
        "content_type": response.get("ContentType", "unknown"),
        "last_modified": str(response.get("LastModified")),
        "etag": response.get("ETag", "").strip('"'),
        "storage_class": response.get("StorageClass", "STANDARD"),
    }

def _publish_notification(bucket, key, metadata):
    message = (
        f"A new file was uploaded to your S3 bucket.\n\n"
        f"File name:      {key}\n"
        f"Bucket:         {bucket}\n"
        f"Size:           {metadata['size']} bytes\n"
        f"Content type:   {metadata['content_type']}\n"
        f"Last modified:  {metadata['last_modified']}\n"
        f"ETag:           {metadata['etag']}\n"
        f"Storage class:  {metadata['storage_class']}\n"
    )
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"New file uploaded: {key}"[:100],
        Message=message,
    )
