# secure-container-pipeline

# DevSecOps Secure Container Pipeline

## Overview

This project demonstrates how **DevSecOps security controls can be integrated directly into an Azure DevOps CI pipeline**.

The goal is to automatically scan source code, dependencies, Kubernetes configuration, and Docker images before allowing a container image to be pushed to **Azure Container Registry (ACR)**.

The pipeline is designed to stop when serious security issues are detected.

---

## Project Objectives

This project was created to practice:

- DevSecOps pipeline security
- Static Application Security Testing
- Dependency vulnerability scanning
- Secret scanning
- Kubernetes configuration scanning
- Container vulnerability scanning
- Security quality gates
- Azure DevOps pipelines
- Azure Container Registry
- Role-Based Access Control
- Workload Identity Federation
- Vulnerability remediation

---

## Tools Used

- Azure DevOps
- Azure Pipelines
- Microsoft Security DevOps
- Trivy
- Checkov
- Bandit
- Docker
- Azure Container Registry
- Kubernetes
- Azure CLI
- Git

---

## Project Structure

```text
secure-container-pipeline/
│
├── app/
│   └── app.py
│
├── k8s/
│   ├── deployment.yaml
│   └── network-policy.yaml
│
├── Dockerfile
├── requirements.txt
├── .gitignore
└── azure-pipelines.yml
```

---

## Architecture

```text
Developer
   ↓
Git Push
   ↓
Azure DevOps Repository
   ↓
Azure Pipeline
   ↓
Microsoft Security DevOps
   ↓
Trivy Repository Scan
   ↓
Docker Build
   ↓
Trivy Container Scan
   ↓
Security Gate
   ↓
Azure Container Registry
```

If a serious vulnerability is detected, the pipeline stops before the container is pushed to ACR.

---

## Step 1 — Create Azure Resources

A resource group was created for the project.

```bash
az group create \
  --name rg-devsecops-security \
  --location canadacentral
```

An Azure Container Registry was then created:

```bash
az acr create \
  --resource-group rg-devsecops-security \
  --name <ACR_NAME> \
  --sku Basic
```

The registry ID was stored in a variable:

```bash
ACR_ID=$(az acr show \
  --resource-group rg-devsecops-security \
  --name <ACR_NAME> \
  --query id \
  --output tsv)
```

---

## Step 2 — Configure Azure DevOps Service Connection

An Azure Resource Manager service connection was created in Azure DevOps using:

```text
Workload Identity Federation
```

This avoids storing long-lived service principal secrets in the pipeline.

The service connection identity was granted permission to push images to ACR.

Example:

```bash
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "AcrPush" \
  --scope "$ACR_ID"
```

The service principal object ID was used instead of the App Registration object ID.

---

## Step 3 — Application

A simple Flask API was created.

```python
from flask import Flask, jsonify

app = Flask(__name__)


@app.route("/")
def home():
    return jsonify({
        "application": "secure-api",
        "status": "running"
    })


@app.route("/health")
def health():
    return jsonify({
        "status": "healthy"
    })


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=8080
    )
```

The `/health` endpoint is also used by the Kubernetes readiness probe.

---

## Step 4 — Secure Docker Image

The application is packaged using Docker.

```dockerfile
FROM python:3.12-slim-bookworm

WORKDIR /app

COPY requirements.txt .

RUN pip install \
    --no-cache-dir \
    -r requirements.txt

COPY app ./app

RUN useradd \
    --create-home \
    appuser

USER appuser

EXPOSE 8080

CMD ["python", "app/app.py"]
```

The container runs as a non-root user to reduce security risk.

---

## Step 5 — Kubernetes Security

The Kubernetes deployment includes security controls such as:

```yaml
securityContext:
  runAsNonRoot: true

  seccompProfile:
    type: RuntimeDefault
```

The container also prevents privilege escalation:

```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true

  capabilities:
    drop:
      - ALL
```

A readiness probe was also configured:

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8080

  initialDelaySeconds: 5
  periodSeconds: 10
```

This allows Kubernetes to confirm that the application is ready before sending traffic to it.

---

## Step 6 — Kubernetes Network Policy

Checkov detected that the workload did not have an associated NetworkPolicy.

A NetworkPolicy was added:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy

metadata:
  name: secure-api-network-policy

spec:
  podSelector:
    matchLabels:
      app: secure-api

  policyTypes:
    - Ingress

  ingress:
    - from:
        - podSelector: {}

      ports:
        - protocol: TCP
          port: 8080
```

This demonstrates how security findings can be remediated directly in Kubernetes configuration.

---

## Step 7 — Microsoft Security DevOps

The Microsoft Security DevOps extension was installed in Azure DevOps.

The pipeline uses:

```yaml
- task: MicrosoftSecurityDevOps@1

  displayName: 'DevSecOps - SAST and IaC Scan'

  inputs:
    categories: 'code,IaC'
    tools: 'bandit,checkov'
    break: true
    publish: true
    artifactName: 'CodeAnalysisLogs'
```

The tools perform checks such as:

```text
Bandit
   ↓
Python security scanning

Checkov
   ↓
Kubernetes / IaC security scanning
```

The pipeline can fail when serious security findings are detected.

---

## Step 8 — Repository Security Scan

Trivy scans the project before the Docker image is built.

```bash
trivy fs \
  --scanners vuln,secret,misconfig \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  .
```

This checks for:

- Vulnerable dependencies
- Exposed secrets
- Configuration problems
- Infrastructure misconfigurations

---

## Step 9 — Build the Container

The Docker image is built only after the earlier security checks succeed.

```bash
docker build \
  --pull \
  --no-cache \
  -t secure-api:<BUILD_ID> \
  .
```

`--pull` ensures the latest version of the base image is retrieved.

`--no-cache` prevents older cached layers from being reused.

---

## Step 10 — Container Security Scan

Trivy scans the completed Docker image.

A full vulnerability report is generated first:

```bash
trivy image \
  --severity HIGH,CRITICAL \
  --exit-code 0 \
  secure-api:<BUILD_ID>
```

The pipeline then applies a security gate:

```bash
trivy image \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  --exit-code 1 \
  secure-api:<BUILD_ID>
```

This causes the pipeline to fail when HIGH or CRITICAL vulnerabilities with available fixes are detected.

Unfixed vulnerabilities remain visible in the security report.

---

## Security Gate Workflow

```text
Docker Image
     ↓
Trivy Scan
     ↓
HIGH / CRITICAL Finding
     ↓
Is a fix available?
   ┌───────┴───────┐
  Yes              No
   │                │
Pipeline Fail     Report
   │
Fix Vulnerability
   │
Commit Changes
   │
Run Pipeline Again
```

---

## Step 11 — Push Approved Image to ACR

The image is pushed to ACR only after all security checks pass.

Example:

```bash
az acr login \
  --name <ACR_NAME>
```

Then:

```bash
docker tag \
  secure-api:<BUILD_ID> \
  <ACR_NAME>.azurecr.io/secure-api:<BUILD_ID>
```

Push:

```bash
docker push \
  <ACR_NAME>.azurecr.io/secure-api:<BUILD_ID>
```

This ensures that only security-approved images reach the registry.

---

## Pipeline Workflow

```text
Git Push
   ↓
Microsoft Security DevOps
   ↓
Bandit
   ↓
Checkov
   ↓
Trivy Repository Scan
   ↓
Docker Build
   ↓
Trivy Image Scan
   ↓
Security Gate
   ↓
PASS
   ↓
Push Image to ACR
```

If any blocking security check fails:

```text
Finding Detected
      ↓
Pipeline Failed
      ↓
Image Not Pushed
```

---

## Security Issues Discovered

During the project, several issues were intentionally introduced or discovered.

Examples included:

### Privileged Container

```yaml
securityContext:
  privileged: true
```

This was removed and replaced with secure container settings.

---

### Missing Readiness Probe

Checkov reported:

```text
CKV_K8S_9
Readiness Probe Should be Configured
```

A readiness probe using `/health` was added.

---

### Missing Network Policy

Checkov reported:

```text
CKV2_K8S_6
```

A Kubernetes NetworkPolicy was created and associated with the application pods.

---

### Container Vulnerabilities

Trivy detected vulnerabilities in operating system packages inside the Docker image.

The base image was changed to:

```dockerfile
FROM python:3.12-slim-bookworm
```

The pipeline was also configured to report all serious vulnerabilities while blocking vulnerabilities that currently have available fixes.

---

## Troubleshooting

### Wrong Service Principal ID

Error:

```text
PrincipalTypeNotSupported
Principals of type Application cannot validly be used in role assignments.
```

Cause:

The App Registration object ID was used instead of the Service Principal object ID.

Solution:

```bash
SP_OBJECT_ID=$(az ad sp show \
  --id "$APP_ID" \
  --query id \
  --output tsv)
```

Then use:

```bash
--assignee-object-id "$SP_OBJECT_ID"
```

---

### Trivy Fails the Pipeline

Example:

```text
Bash exited with code '1'
```

This usually means Trivy detected a vulnerability matching the configured security gate.

Check the report before changing the pipeline.

The failure is intentional when using:

```bash
--exit-code 1
```

---

### Checkov Reports Kubernetes Findings

Example:

```text
CKV_K8S_9
```

Fix the Kubernetes manifest and rerun the pipeline.

The intended workflow is:

```text
Scan
 ↓
Finding
 ↓
Remediation
 ↓
Commit
 ↓
Pipeline
 ↓
Rescan
```

---

## Key DevSecOps Concepts Demonstrated

This project demonstrates:

- Shift-left security
- SAST
- Dependency scanning
- Secret scanning
- Infrastructure as Code security
- Kubernetes security
- Container security
- Security quality gates
- Least privilege
- Workload Identity Federation
- Vulnerability remediation
- Automated security enforcement

---

## Key Takeaway

The main lesson from this project is that DevSecOps is not simply about producing security reports.

Security tools should influence whether software is allowed to progress through the delivery process.

```text
Insecure Code / Image
        ↓
Security Scanner
        ↓
Pipeline Failure
        ↓
Developer Fix
        ↓
Rescan
        ↓
PASS
        ↓
Approved Artifact
```

By integrating security controls directly into Azure Pipelines, vulnerable application code, infrastructure configuration, and container images can be identified before they reach production.

---

## Project Result

The completed workflow provides:

```text
Source Code
    ↓
Automated Security Scanning
    ↓
Infrastructure Security Checks
    ↓
Container Build
    ↓
Container Vulnerability Scan
    ↓
Security Quality Gate
    ↓
Azure Container Registry
```

This project demonstrates a practical **DevSecOps CI security pipeline using Azure DevOps, Docker, Kubernetes, Trivy, Checkov, and Azure Container Registry**.