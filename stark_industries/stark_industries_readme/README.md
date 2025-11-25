# 🏢 Stark Industries – Multi-Region AWS Infrastructure (Terraform + CI/CD)

This project implements a **production-grade, multi-region, event-driven AWS architecture** fully deployed and managed using **Terraform**, with **GitHub Actions CI/CD**, **API Gateway**, **Lambda**, **S3 Replication**, **EC2**, **DynamoDB**, and strong IAM security.

It demonstrates enterprise patterns such as:

- Infrastructure as Code (IaC)
- Multi-region disaster recovery (DR)
- Event-driven architecture
- Secure presigned URL uploads
- Lambda-based backend logic
- Automated CI/CD for dev → prod
- Remote backend with versioning + locking
- Drift detection, import, workspaces, taint/untaint

---

## 📌 1. Architecture Overview

                 ┌─────────────────────────┐
                 │      Web Browser        │
                 │(Upload via API Gateway) │
                 └───────────┬─────────────┘
                             │
               ┌─────────────▼───────────────┐
               │       API Gateway           │
               │  /presign    /metadata      │
               └─────────────┬───────────────┘
                             │
                 ┌───────────▼────────────┐
                 │     Lambda Functions   │
                 │ 1. Presigner           │
                 │ 2. EC2 Metadata        │
                 │ 3. Replica Processor   │
                 └───────────┬────────────┘
                             │
                  ┌──────────▼────────────┐
                  │     Main S3 Bucket    │
                  │ (ap-south-1)          │
                  └──────────┬────────────┘
                             │ CRR Replication
                  ┌──────────▼────────────┐
                  │  Replica S3 Bucket    │
                  │ (ap-southeast-1)      │
                  └──────────┬────────────┘
                             │ Event Trigger
               ┌─────────────▼───────────────┐
               │   Lambda (Replica Handler)  │
               └─────────────┬───────────────┘
                             │
                 ┌───────────▼─────────────┐
                 │   DynamoDB Metadata      │
                 └──────────────────────────┘


---

## 📌 2. Features

### ✔️ Multi-Region S3 Replication  
Automatic replication from ap-south-1 → ap-southeast-1.

### ✔️ Event-Driven Pipeline  
Replica S3 triggers Lambda → updates DynamoDB → sends SNS email.

### ✔️ Secure File Upload (Presigned URLs)  
User uploads directly to S3 without AWS credentials.

### ✔️ API-Driven Architecture  
- `/presign` → generate upload URLs  
- `/metadata` → fetch EC2 metadata  

### ✔️ CI/CD with GitHub Actions  
- terraform-plan  
- terraform-apply-dev  
- terraform-apply-prod  
- terraform-destroy  

### ✔️ Fully Automated Terraform  
Remote backend, versioning, locking, workspaces.



## 📌 3. Component Overview

### ✔️ S3 Buckets
| Bucket | Region | Purpose |
|--------|--------|----------|
| Main bucket | ap-south-1 | Stores all uploaded files |
| Replica bucket | ap-southeast-1 | DR replication |
| Logging bucket | ap-south-1 | S3 access logs |

---

### ✔️ DynamoDB Table
Stores metadata for replicated files:
- object_key  
- size  
- bucket  
- timestamp  

---

### ✔️ Lambda Functions

#### 🔹 presigner.py
Generates presigned URLs for uploads.

#### 🔹 get_ec2_metadata.py
Returns EC2 metadata.

#### 🔹 process_replica.py
Triggered by replica S3 → writes metadata to DynamoDB.

---

### ✔️ API Gateway Endpoints

| Method | Path | Description |
|--------|-------|--------------|
| POST | `/presign` | Generate S3 upload URL |
| GET | `/metadata` | Return EC2 instance metadata |

---

## 📌 4. CI/CD Workflows (GitHub Actions)

### 1️⃣ terraform-plan.yml  
On pull request → lint + validate + plan.

### 2️⃣ terraform-apply-dev.yml  
Runs automatically on merge to `dev`.

### 3️⃣ terraform-apply-prod.yml  
Requires manual approval.

### 4️⃣ terraform-destroy.yml  
Manual trigger → destroy dev or prod.

---

## 📌 5. Full Workflow (End-to-End)

### Step 1 — Get Upload URL  
User calls `/presign` → receives presigned S3 URL.

### Step 2 — Upload File  
File uploaded directly to S3 (no AWS keys exposed).

### Step 3 — Cross-Region Replication  
AWS automatically replicates file.

### Step 4 — Replica Lambda Execution  
Lambda processes event:  
✔ reads metadata  
✔ writes to DynamoDB  
✔ sends SNS alert  

### Step 5 — Get EC2 Metadata  
API `/metadata` returns EC2 runtime meta information.

---

## 📌 6. Security

- No public S3 access  
- IAM least privilege  
- Terraform remote state encrypted  
- DynamoDB state locking  
- All Lambda IAM roles restricted  
- API Gateway secured  

---



