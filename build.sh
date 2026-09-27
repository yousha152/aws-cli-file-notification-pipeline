#!/usr/bin/env bash
set -euo pipefail

export AWS_REGION="ap-southeast-1"
export MY_EMAIL="your-email@example.com"
export BUCKET_NAME="your-s3-bucket-name"
export QUEUE_NAME="file-notify-pipeline-queue"
export TOPIC_NAME="file-notify-pipeline-topic"
export ROLE_NAME="file-notify-pipeline-lambda-role"
export FUNCTION_NAME="file-notify-pipeline-function"
export POLICY_NAME="file-notify-permissions"

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

# Task 1: S3 Bucket & File Creation
if [ "$AWS_REGION" = "us-east-1" ]; then
  aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" > /dev/null
else
  aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" \
    --create-bucket-configuration LocationConstraint="$AWS_REGION" > /dev/null
fi

echo "Hello pipeline, this is a sample file." > sample.txt
aws s3 cp sample.txt "s3://$BUCKET_NAME/sample.txt" > /dev/null
echo "=== S3 File Listing ==="
aws s3 ls "s3://$BUCKET_NAME"

# Task 2: SQS Queue & Test Message
aws sqs create-queue --queue-name "$QUEUE_NAME" --region "$AWS_REGION" > /dev/null
QUEUE_URL=$(aws sqs get-queue-url --queue-name "$QUEUE_NAME" --region "$AWS_REGION" --query 'QueueUrl' --output text)
QUEUE_ARN=$(aws sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names QueueArn --region "$AWS_REGION" --query 'Attributes.QueueArn' --output text)

aws sqs send-message --queue-url "$QUEUE_URL" --message-body "{\"bucket\": \"$BUCKET_NAME\", \"key\": \"sample.txt\"}" > /dev/null
echo "=== SQS Message Received ==="
aws sqs receive-message --queue-url "$QUEUE_URL"

# Task 3: SNS Topic & Email Subscribe
TOPIC_ARN=$(aws sns create-topic --name "$TOPIC_NAME" --region "$AWS_REGION" --query 'TopicArn' --output text)
aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint "$MY_EMAIL" > /dev/null

# Task 4: IAM Role (Least Privilege)
cat > lambda-trust-policy.json <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document file://lambda-trust-policy.json > /dev/null
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

cat > lambda-permissions-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {"Sid":"S3ReadOnlyOnThisBucket","Effect":"Allow","Action":"s3:GetObject","Resource":"arn:aws:s3:::$BUCKET_NAME/*"},
    {"Sid":"SQSReceiveDeleteOnThisQueue","Effect":"Allow","Action":["sqs:ReceiveMessage","sqs:DeleteMessage","sqs:GetQueueAttributes"],"Resource":"$QUEUE_ARN"},
    {"Sid":"SNSPublishOnThisTopic","Effect":"Allow","Action":"sns:Publish","Resource":"$TOPIC_ARN"},
    {"Sid":"CloudWatchLogsForThisFunctionOnly","Effect":"Allow","Action":["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"],"Resource":"arn:aws:logs:$AWS_REGION:$ACCOUNT_ID:log-group:/aws/lambda/$FUNCTION_NAME:*"}
  ]
}
EOF
aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME" --policy-document file://lambda-permissions-policy.json > /dev/null
sleep 10

# Task 5: Deploy Lambda
zip lambda_function.zip lambda_function.py > /dev/null
aws lambda create-function \
  --function-name "$FUNCTION_NAME" --runtime python3.12 --role "$ROLE_ARN" \
  --handler lambda_function.lambda_handler --zip-file fileb://lambda_function.zip \
  --timeout 30 --environment "Variables={SNS_TOPIC_ARN=$TOPIC_ARN}" --region "$AWS_REGION" > /dev/null

aws lambda wait function-active --function-name "$FUNCTION_NAME" --region "$AWS_REGION"

# Task 6: Event Source Mapping (SQS -> Lambda)
aws lambda create-event-source-mapping \
  --function-name "$FUNCTION_NAME" --event-source-arn "$QUEUE_ARN" \
  --batch-size 1 --region "$AWS_REGION" > /dev/null

for i in $(seq 1 12); do
  STATE=$(aws lambda list-event-source-mappings --function-name "$FUNCTION_NAME" --region "$AWS_REGION" --query 'EventSourceMappings[0].State' --output text)
  [ "$STATE" = "Enabled" ] && break
  sleep 5
done

# Task 7: Trigger Test Message
aws sqs send-message --queue-url "$QUEUE_URL" --message-body "{\"bucket\": \"$BUCKET_NAME\", \"key\": \"sample.txt\"}" > /dev/null
sleep 20

echo "=== CloudWatch Logs ==="
aws logs tail "/aws/lambda/$FUNCTION_NAME" --since 2m --region "$AWS_REGION"
