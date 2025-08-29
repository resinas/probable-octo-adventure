#!/usr/bin/env bash
set -euo pipefail

# ---------- CONFIG (edit or export as env before running) ----------
PROJECT_ID="${PROJECT_ID:-your-project-id}"
ZONE="${ZONE:-europe-southwest1-a}"
VM_NAME="${VM_NAME:-conferia-vm}"
MACHINE_TYPE="${MACHINE_TYPE:-e2-medium}"   # or e2-standard-2
DISK_SIZE_GB="${DISK_SIZE_GB:-50}"
DISK_TYPE="${DISK_TYPE:-pd-ssd}"

OS_USER="${OS_USER:-appsvc}"

# domain + email for Caddy/Let's Encrypt
DOMAIN="${DOMAIN:-example.com}"
EMAIL="${EMAIL:-admin@example.com}"

# Git repo containing docker-compose.yml, Caddyfile, etc.
REPO_URL="${REPO_URL:-https://github.com/you/your-app-repo.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"

# DB secrets (used to write .env on the VM)
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-change_me_root}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-change_me_app}"

SPRING_MAIL_HOST="${SPRING_MAIL_HOST:-example.com}"
SPRING_MAIL_PORT="${SPRING_MAIL_PORT:-587}"
SPRING_MAIL_USERNAME="${SPRING_MAIL_USERNAME:-admin@example.com}"
SPRING_MAIL_PASSWORD="${SPRING_MAIL_PASSWORD:-change_me_email}"

# Backups bucket (optional; leave empty to skip bucket creation)
GCS_BUCKET="${GCS_BUCKET:-conferia-backups-$(date +%s)}"
APPLY_LIFECYCLE="${APPLY_LIFECYCLE:-true}"

# Custom service account name (email will be NAME@PROJECT_ID.iam.gserviceaccount.com)
CUSTOM_SA_NAME="${CUSTOM_SA_NAME:-db-backup}"

# ---------- END CONFIG ----------

echo "Project:        $PROJECT_ID"
echo "Zone:           $ZONE"
echo "VM:             $VM_NAME  ($MACHINE_TYPE, ${DISK_SIZE_GB}GB ${DISK_TYPE})"
echo "Domain/Email:   $DOMAIN / $EMAIL"
echo "Spring Mail:    $SPRING_MAIL_HOST:$SPRING_MAIL_PORT / $SPRING_MAIL_USERNAME"
echo "Repo:           $REPO_URL @ $REPO_BRANCH"
echo "Bucket:         gs://$GCS_BUCKET  |  SA: $CUSTOM_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"
echo "OS User:        $OS_USER"
echo

# 0) Enable required APIs (safe to re-run)
gcloud services enable compute.googleapis.com --project "$PROJECT_ID"
gcloud services enable storage.googleapis.com --project "$PROJECT_ID"

# 1) create backups bucket
# Create SA (idempotent)
CUSTOM_SA_EMAIL="${CUSTOM_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
if ! gcloud iam service-accounts describe "$CUSTOM_SA_EMAIL" --project "$PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$CUSTOM_SA_NAME" \
    --display-name="App/DB Backup SA" --project "$PROJECT_ID"
fi

# Create bucket (idempotent)
if ! gcloud storage buckets describe "gs://${GCS_BUCKET}" --project "$PROJECT_ID" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${GCS_BUCKET}" \
    --project "$PROJECT_ID" \
    --location europe-west1 \
    --uniform-bucket-level-access
fi

# Optional lifecycle (tweak ages as you wish)
if [[ "$APPLY_LIFECYCLE" == "true" ]]; then
  tmpfile=$(mktemp)
  cat > "$tmpfile" <<'JSON'
{
  "rule": [
    { "action": {"type": "Delete"}, "condition": {"age": 35, "matchesPrefix": ["mysql/daily/"]} },
    { "action": {"type": "Delete"}, "condition": {"age": 8,  "matchesPrefix": ["mysql/binlog/"]} },
    { "action": {"type": "Delete"}, "condition": {"age": 90, "matchesPrefix": ["uploads-snapshots/"]} }
  ]
}
JSON
  gcloud storage buckets update "gs://${GCS_BUCKET}" --lifecycle-file="$tmpfile"
  rm -f "$tmpfile"
fi

# Grant bucket access to SA
gcloud storage buckets add-iam-policy-binding "gs://${GCS_BUCKET}" \
  --member="serviceAccount:${CUSTOM_SA_EMAIL}" \
  --role="roles/storage.objectAdmin" \
  --project "$PROJECT_ID"

# 2) Create firewall rules for HTTP/HTTPS (idempotent)
gcloud compute firewall-rules describe allow-http --project "$PROJECT_ID" >/dev/null 2>&1 || \
gcloud compute firewall-rules create allow-http --project "$PROJECT_ID" --allow tcp:80 --target-tags=http-server
gcloud compute firewall-rules describe allow-https --project "$PROJECT_ID" >/dev/null 2>&1 || \
gcloud compute firewall-rules create allow-https --project "$PROJECT_ID" --allow tcp:443 --target-tags=https-server

# 3) Create VM with startup-script that installs docker, pulls repo, writes .env, enables systemd
STARTUP_SCRIPT=$(cat <<'EOF'
#!/bin/bash
set -euo pipefail

# Read metadata vars
META() { curl -fs -H "Metadata-Flavor: Google" "http://metadata/computeMetadata/v1/instance/attributes/$1"; }

DOMAIN=$(META DOMAIN)
EMAIL=$(META EMAIL)
REPO_URL=$(META REPO_URL)
REPO_BRANCH=$(META REPO_BRANCH)
MYSQL_ROOT_PASSWORD=$(META MYSQL_ROOT_PASSWORD)
MYSQL_PASSWORD=$(META MYSQL_PASSWORD)
GCS_BUCKET=$(META GCS_BUCKET)
SPRING_MAIL_HOST=$(META SPRING_MAIL_HOST)
SPRING_MAIL_PORT=$(META SPRING_MAIL_PORT)
SPRING_MAIL_USERNAME=$(META SPRING_MAIL_USERNAME)
SPRING_MAIL_PASSWORD=$(META SPRING_MAIL_PASSWORD)

OS_USER=$(META OS_USER)

# Create service user if missing
if ! id -u "$OS_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$OS_USER"
fi

APP_UID="$(id -u "$OS_USER")"
APP_GID="$(id -g "$OS_USER")"


# Install Docker + Compose
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release git
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian $(. /etc/os-release; echo $VERSION_CODENAME) stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin


# Allow the service user to talk to Docker
usermod -aG docker "$OS_USER"


# App directory under the service user’s home
APP_DIR="/home/${OS_USER}/app"
sudo -u "$OS_USER" mkdir -p "$APP_DIR"
cd "$APP_DIR"

# Fetch app repo
if [[ ! -d .git ]]; then
  sudo -u ${OS_USER} git clone -b "${REPO_BRANCH}" "${REPO_URL}" .
else
  sudo -u ${OS_USER} git fetch && sudo -u ${OS_USER} git checkout "${REPO_BRANCH}" && sudo -u ${OS_USER} git pull
fi

# Create uploads dir
sudo -u ${OS_USER} mkdir -p "$APP_DIR/uploads"
chown -R "$OS_USER:$OS_USER" "$APP_DIR/uploads"


# Write .env (used by docker-compose.yml)
cat > "${APP_DIR}/.env" <<ENVEOF
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
DOMAIN=${DOMAIN}
EMAIL=${EMAIL}
GCS_BUCKET=${GCS_BUCKET}
SPRING_MAIL_HOST=${SPRING_MAIL_HOST}
SPRING_MAIL_PORT=${SPRING_MAIL_PORT}
SPRING_MAIL_USERNAME=${SPRING_MAIL_USERNAME}
SPRING_MAIL_PASSWORD=${SPRING_MAIL_PASSWORD}
APP_UID=${APP_UID}
APP_GID=${APP_GID}
ENVEOF
chown "${OS_USER}:${OS_USER}" "${APP_DIR}/.env"
chmod 600 "${APP_DIR}/.env"

# Create systemd unit for the compose stack
# systemd unit runs as OS_USER with docker group
cat >/etc/systemd/system/app-stack.service <<SYSEOF
[Unit]
Description=App + DB + Caddy (Docker Compose)
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
User=${OS_USER}
Group=${OS_USER}
SupplementaryGroups=docker
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
RemainAfterExit=yes
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
SYSEOF

systemctl daemon-reload
systemctl enable app-stack
systemctl start app-stack
EOF
)
#sudo -u ${OS_USER} /usr/bin/docker compose -f ${APP_DIR}/docker-compose.yml pull || true

echo "$STARTUP_SCRIPT" > startup.sh

# Create the VM (idempotent-ish; will fail if the name already exists)
gcloud compute instances create "$VM_NAME" \
  --project "$PROJECT_ID" \
  --zone "$ZONE" \
  --machine-type "$MACHINE_TYPE" \
  --boot-disk-size "${DISK_SIZE_GB}GB" \
  --boot-disk-type "$DISK_TYPE" \
  --image-family debian-12 \
  --image-project debian-cloud \
  --tags=http-server,https-server \
  --scopes=https://www.googleapis.com/auth/devstorage.read_write \
  --service-account "$CUSTOM_SA_EMAIL" \
  --metadata-from-file startup-script=<(echo "$STARTUP_SCRIPT") \
  --metadata \
DOMAIN="$DOMAIN",EMAIL="$EMAIL",REPO_URL="$REPO_URL",REPO_BRANCH="$REPO_BRANCH",MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD",MYSQL_PASSWORD="$MYSQL_PASSWORD",GCS_BUCKET="$GCS_BUCKET",SPRING_MAIL_HOST="$SPRING_MAIL_HOST",SPRING_MAIL_PORT="$SPRING_MAIL_PORT",SPRING_MAIL_USERNAME="$SPRING_MAIL_USERNAME",SPRING_MAIL_PASSWORD="$SPRING_MAIL_PASSWORD",OS_USER="$OS_USER" 

echo
echo "VM provisioning kicked off. Fetch the external IP:"
gcloud compute instances describe "$VM_NAME" --project "$PROJECT_ID" --zone "$ZONE" \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)'

echo
echo "➡ Point your domain's A record to that IP. Caddy will auto-issue TLS once DNS propagates."
echo "➡ To watch first boot logs: gcloud compute ssh $VM_NAME --project $PROJECT_ID --zone $ZONE -- journalctl -u app-stack -f"