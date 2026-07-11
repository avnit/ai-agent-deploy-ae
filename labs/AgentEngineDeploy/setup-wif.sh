#!/usr/bin/env bash
# Sets up Workload Identity Federation for GitHub Actions to authenticate
# to GCP without storing any credentials or API keys.
#
# Run this once from your local machine or Google Cloud Shell:
#   chmod +x setup-wif.sh && ./setup-wif.sh
#
# Prerequisites:
#   - gcloud CLI installed and authenticated (gcloud auth login)
#   - Owner or roles/iam.workloadIdentityPoolAdmin on the GCP project

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-data-vpc-sc-demo}"
LOCATION="${GOOGLE_CLOUD_LOCATION:-us-central1}"
GITHUB_OWNER="avnit"
GITHUB_REPO="ai-agent-deploy-ae"

POOL_ID="github-actions-pool"
PROVIDER_ID="github-provider"
SA_NAME="gemini-ci-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
# ─────────────────────────────────────────────────────────────────────────────

echo "▶ Using project: ${PROJECT_ID}"
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
echo "  Project number: ${PROJECT_NUMBER}"

WIF_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

# 1. Enable required APIs
echo "▶ Enabling APIs..."
gcloud services enable \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  aiplatform.googleapis.com \
  --project="${PROJECT_ID}"

# 2. Create service account
echo "▶ Creating service account: ${SA_EMAIL}"
gcloud iam service-accounts create "${SA_NAME}" \
  --display-name="Gemini CI GitHub Actions" \
  --project="${PROJECT_ID}" 2>/dev/null || echo "  (already exists)"

# 3. Grant Vertex AI / Gemini permissions to the service account
echo "▶ Granting Vertex AI User role..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/aiplatform.user" \
  --condition=None

# 4. Create Workload Identity Pool
echo "▶ Creating WIF pool: ${POOL_ID}"
gcloud iam workload-identity-pools create "${POOL_ID}" \
  --location="global" \
  --display-name="GitHub Actions Pool" \
  --project="${PROJECT_ID}" 2>/dev/null || echo "  (already exists)"

# 5. Create GitHub OIDC Provider inside the pool
echo "▶ Creating WIF provider: ${PROVIDER_ID}"
gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_ID}" \
  --location="global" \
  --workload-identity-pool="${POOL_ID}" \
  --display-name="GitHub Provider" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository == '${GITHUB_OWNER}/${GITHUB_REPO}'" \
  --project="${PROJECT_ID}" 2>/dev/null || echo "  (already exists)"

# 6. Allow the WIF pool to impersonate the service account
#    Scoped to this specific repo only
echo "▶ Binding WIF principal to service account..."
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_OWNER}/${GITHUB_REPO}" \
  --project="${PROJECT_ID}"

# ── Print GitHub Actions variables to set ────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Setup complete. Now add these to your GitHub repo:"
echo "  github.com/${GITHUB_OWNER}/${GITHUB_REPO}/settings/variables/actions"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "  VARIABLES (Settings → Secrets and variables → Actions → Variables):"
echo "  ┌──────────────────────────────────┬──────────────────────────────────────────────────────────────────────────────────────┐"
echo "  │ GOOGLE_CLOUD_PROJECT             │ ${PROJECT_ID}"
echo "  │ GOOGLE_CLOUD_LOCATION            │ ${LOCATION}"
echo "  │ SERVICE_ACCOUNT_EMAIL            │ ${SA_EMAIL}"
echo "  │ GCP_WIF_PROVIDER                 │ ${WIF_PROVIDER}"
echo "  │ GOOGLE_GENAI_USE_VERTEXAI        │ true"
echo "  │ GEMINI_MODEL                     │ gemini-2.5-flash"
echo "  └──────────────────────────────────┴──────────────────────────────────────────────────────────────────────────────────────┘"
echo ""
echo "  No secrets needed — WIF uses short-lived OIDC tokens, zero stored credentials."
echo ""
