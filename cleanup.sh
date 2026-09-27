#!/usr/bin/env bash
set -uo pipefail

export AWS_REGION="ap-southeast-1"
export QUEUE_NAME="file-notify-queue"
export TOPIC_NAME="file-notify-topic"
export ROLE_NAME="file-notify-lambda-role"
export FUNCTION_NAME="file-notify-function"
export POLICY_NAME="file-notify-permissions"

if [ -z "${BUCKET_NAME:-}" ]; then
  read -p "Enter BUCKET_NAME to delete: " BUCKET_NAME
fi

QUEUE_URL=$(aws sqs get-queue-url --queue-name "$QUEUE_NAME" --region "$AWS_REGION" --query 'QueueUrl' --output text 2>/dev/null || true)
TOPIC_ARN=$(aws sns list-topics --region "$AWS_REGION" --query "Topics[?ends_with(TopicArn, ':$TOPIC_NAME')].TopicArn | [0]" --output text 2>/dev/null || true)
MAPPING_UUID=$(aws lambda list-event-source-mappings --function-name "$FUNCTION_NAME" --region "$AWS_REGION" --query 'EventSourceMappings[0].UUID' --output text 2>/dev/null || true)

echo "Deleting event source mapping..."
[ -n "$MAPPING_UUID" ] && [ "$MAPPING_UUID" != "None" ] && aws lambda delete-event-source-mapping --uuid "$MAPPING_UUID" --region "$AWS_REGION" || true

echo "Deleting Lambda function..."
aws lambda delete-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" || true

echo "Deleting IAM policies and role..."
aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME" || true
aws iam delete-role --role-name "$ROLE_NAME" || true

echo "Deleting SQS queue..."
[ -n "$QUEUE_URL" ] && [ "$QUEUE_URL" != "None" ] && aws sqs delete-queue --queue-url "$QUEUE_URL" --region "$AWS_REGION" || true

echo "Deleting SNS subscriptions and topic..."
if [ -n "$TOPIC_ARN" ] && [ "$TOPIC_ARN" != "None" ]; then
  for SUB_ARN in $(aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" --region "$AWS_REGION" --query 'Subscriptions[].SubscriptionArn' --output text 2>/dev/null); do
    [ "$SUB_ARN" != "PendingConfirmation" ] && aws sns unsubscribe --subscription-arn "$SUB_ARN" --region "$AWS_REGION" || true
  done
  aws sns delete-topic --topic-arn "$TOPIC_ARN" --region "$AWS_REGION" || true
fi

echo "Deleting S3 objects and bucket..."
aws s3 rm "s3://$BUCKET_NAME" --recursive || true
aws s3api delete-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" || true

echo "Deleting CloudWatch Log Group..."
aws logs delete-log-group --log-group-name "/aws/lambda/$FUNCTION_NAME" --region "$AWS_REGION" || true

echo "✅ Cleanup complete!"
