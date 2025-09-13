#!/usr/bin/env python3
"""
Simple SQS consumer for LocalStack.
- Long polls the configured queue
- Prints JSON messages with basic formatting
- Deletes messages after successful processing

Requirements:
  pip install boto3

Environment (defaults shown):
  AWS_REGION=us-east-1
  AWS_ACCESS_KEY_ID=fake
  AWS_SECRET_ACCESS_KEY=fake
  SQS_ENDPOINT=http://localhost:4566
  SQS_QUEUE_URL=http://localhost:4566/000000000000/message-blaster-events
"""
import json
import os
import sys
import time
from typing import Any, Dict

import boto3
from botocore.config import Config

REGION = os.getenv("AWS_REGION", "us-east-1")
ACCESS_KEY = os.getenv("AWS_ACCESS_KEY_ID", "fake")
SECRET_KEY = os.getenv("AWS_SECRET_ACCESS_KEY", "fake")
SQS_ENDPOINT = os.getenv("SQS_ENDPOINT", "http://localhost:4566")
QUEUE_URL = os.getenv("SQS_QUEUE_URL", "http://localhost:4566/000000000000/message-blaster-events")

session = boto3.session.Session()
config = Config(retries={"max_attempts": 5, "mode": "standard"})
sqs = session.client(
    "sqs",
    region_name=REGION,
    aws_access_key_id=ACCESS_KEY,
    aws_secret_access_key=SECRET_KEY,
    endpoint_url=SQS_ENDPOINT,
    config=config,
)

def pretty_print(message_body: str) -> None:
    try:
        data = json.loads(message_body)
        print(json.dumps(data, indent=2, sort_keys=True))
    except json.JSONDecodeError:
        print(message_body)

def process_message(msg: Dict[str, Any]) -> bool:
    body = msg.get("Body", "")
    receipt = msg.get("ReceiptHandle")

    print("\n=== Received Message ===")
    pretty_print(body)

    # Delete the message when processed
    if receipt:
        sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=receipt)
        print("Deleted message.")
        return True
    return False

def main() -> int:
    print("Polling SQS:", QUEUE_URL)
    while True:
        try:
            resp = sqs.receive_message(
                QueueUrl=QUEUE_URL,
                MaxNumberOfMessages=10,
                WaitTimeSeconds=10,  # long polling
                VisibilityTimeout=30,
                MessageAttributeNames=["All"],
                AttributeNames=["All"],
            )
            messages = resp.get("Messages", [])
            if not messages:
                continue

            for msg in messages:
                ok = process_message(msg)
                if not ok:
                    print("Failed to process message:", msg.get("MessageId"))

        except KeyboardInterrupt:
            print("Exiting...")
            break
        except Exception as e:
            print("Error while polling:", repr(e))
            time.sleep(2)
    return 0

if __name__ == "__main__":
    sys.exit(main())
