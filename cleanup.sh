#!/usr/bin/env bash
set -euo pipefail

# ======== EDIT THESE (or pass as env) ========
PROJECT_ID="${PROJECT_ID:-your-project-id}"
ZONE="${ZONE:-europe-southwest1-a}"
VM_NAME="${VM_NAME:-my-app-vm}"

# Bucket & SA must match what you used on deploy
GCS_BUCKET="${GCS_BUCKET:-my-app-backups-CHANGE-ME}"
CUSTOM_SA_NAME="${CUSTOM_SA_NAME:-db-backup}"   # -> email will be db-backup@PROJECT.iam.gserviceaccount.com

# Optional removals (set to true to remove)
DELETE_FIREWALL_RULES="${DELETE_FIREWALL_RULES:-false}"   # removes allow-http / allow-https

# ============================================

echo "Cleanup plan for project: $PROJECT_ID"
echo "- VM                : $VM_NAME (zone: $ZONE)"
echo "- Bucket            : gs://$GCS_BUCKET"
echo "- Service account   : ${CUSTOM_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
echo "- Delete FW rules   : $DELETE_FIREWALL_RULES (allow-http/allow-https)"
echo

read -r -p "Proceed with cleanup? This is DESTRUCTIVE. Type 'yes' to continue: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 1; }

# Ensure APIs (in case you run this from a bare machine)
gcloud services enable compute.googleapis.com storage.googleapis.com --project "$PROJECT_ID" >/dev/null

# Helper: check existence quietly
exists() { eval "$@" >/dev/null 2>&1; }

# --- 1) Delete VM (if exists)
echo ">> Deleting VM (if exists): $VM_NAME"
if exists gcloud compute instances describe "$VM_NAME" --project "$PROJECT_ID" --zone "$ZONE"; then
  gcloud compute instances delete "$VM_NAME" --project "$PROJECT_ID" --zone "$ZONE" --quiet
else
  echo "   VM not found, skipping."
fi

# --- 2) Remove bucket IAM binding for SA (if both exist)
CUSTOM_SA_EMAIL="${CUSTOM_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
if exists gcloud storage buckets describe "gs://${GCS_BUCKET}" --project "$PROJECT_ID"; then
  echo ">> Removing bucket IAM binding for SA (if present)"
  gcloud storage buckets remove-iam-policy-binding "gs://${GCS_BUCKET}" \
    --member="serviceAccount:${CUSTOM_SA_EMAIL}" \
    --role="roles/storage.objectAdmin" \
    --project "$PROJECT_ID" || true

  echo ">> Deleting ALL objects in bucket (this can take time)..."
  # Remove versioned & non-versioned contents
  gcloud storage rm -r "gs://${GCS_BUCKET}/**" --project "$PROJECT_ID" || true

  echo ">> Deleting bucket"
  gcloud storage buckets delete "gs://${GCS_BUCKET}" --project "$PROJECT_ID" --quiet || true
else
  echo "   Bucket not found, skipping."
fi

# --- 3) Delete custom service account
echo ">> Deleting service account (if exists): $CUSTOM_SA_EMAIL"
if exists gcloud iam service-accounts describe "$CUSTOM_SA_EMAIL" --project "$PROJECT_ID"; then
  # Delete any keys if your org created some (we didn't in our flow)
  for KEY in $(gcloud iam service-accounts keys list --iam-account="$CUSTOM_SA_EMAIL" --project "$PROJECT_ID" --format='value(name)' || true); do
    echo "   Deleting key $KEY"
    gcloud iam service-accounts keys delete "$KEY" --iam-account="$CUSTOM_SA_EMAIL" --project "$PROJECT_ID" --quiet || true
  done
  gcloud iam service-accounts delete "$CUSTOM_SA_EMAIL" --project "$PROJECT_ID" --quiet
else
  echo "   Service account not found, skipping."
fi

# --- 4) (Optional) Delete firewall rules
if [[ "$DELETE_FIREWALL_RULES" == "true" ]]; then
  echo ">> Deleting firewall rules allow-http / allow-https (if exist)"
  exists gcloud compute firewall-rules describe allow-http  --project "$PROJECT_ID" && \
    gcloud compute firewall-rules delete allow-http  --project "$PROJECT_ID" --quiet || true
  exists gcloud compute firewall-rules describe allow-https --project "$PROJECT_ID" && \
    gcloud compute firewall-rules delete allow-https --project "$PROJECT_ID" --quiet || true
else
  echo "   Skipping firewall rule deletion (set DELETE_FIREWALL_RULES=true to remove)."
fi



echo
echo "✅ Cleanup finished."
echo "If you pointed a domain at the VM IP, update/remove that DNS record."