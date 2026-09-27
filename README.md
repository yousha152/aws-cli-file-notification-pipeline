cat > README.md <<'EOF'
# 📢 AWS CLI Event-Driven File Notification Pipeline

A serverless, event-driven notification pipeline deployed strictly using the **AWS CLI** in the `ap-southeast-1` (Singapore) region. The architecture automatically extracts object metadata from Amazon S3 upon receiving trigger payloads via SQS and delivers detailed email reports using Amazon SNS.

---

## 🏗️ Architectural Workflow

```text
┌──────────────┐      ┌──────────────┐      ┌──────────────┐      ┌──────────────┐      ┌──────────────┐
│  Amazon S3   │ ───> │  Amazon SQS  │ ───> │  AWS Lambda  │ ───> │  Amazon SNS  │ ───> │ Email Inbox  │
│ (sample.txt) │      │  (Message)   │      │  (Function)  │      │(Notification)│      │ (Subscriber) │
└──────────────┘      └──────────────┘      └──────────────┘      └──────────────┘      └──────────────┘
                                                   │
                                                   ▼
                                            ┌──────────────┐
                                            │  CloudWatch  │
                                            │    Logs      │
                                            └──────────────┘
