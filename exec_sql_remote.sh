#!/usr/bin/env bash
set -euo pipefail

# ---- Config (env-overridable) ----
VM="${VM:-my-app-vm}"
ZONE="${ZONE:-europe-west1-b}"
APP_DIR="${APP_DIR:-/home/appsvc/app}"   # where docker-compose.yml and .env live on the VM
MYSQL_SVC="${MYSQL_SVC:-mysql}"
DB_NAME="${DB_NAME:-appdb}"
MYSQL_USER="${MYSQL_USER:-appuser}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-appuser}"

SQL_FILE="${1:-}"
if [[ -z "$SQL_FILE" ]]; then
  echo "Usage: VM=... ZONE=... APP_DIR=... $0 path/to/file.sql"
  exit 1
fi
if [[ "$SQL_FILE" != "-" && ! -f "$SQL_FILE" ]]; then
  echo "File not found: $SQL_FILE"
  exit 1
fi

# ---- Remote command ----
REMOTE_CMD=$(cat <<'EOSH'
set -euo pipefail

APP_DIR="${APP_DIR}"
MYSQL_SVC="${MYSQL_SVC}"
DB_NAME="${DB_NAME}"
MYSQL_USER="${MYSQL_USER}"

# 1) go to the project dir
cd "$APP_DIR" || { echo "Remote APP_DIR not found: $APP_DIR" >&2; exit 1; }

# 2) load MYSQL_PASSWORD:
PW="$(sudo -u appsvc grep -E '^MYSQL_PASSWORD=' /home/appsvc/app/.env | cut -d= -f2-)"
echo "Using DB: $DB_NAME, user: $MYSQL_USER"
echo "$(sudo -u appsvc grep -E '^MYSQL_PASSWORD=' /home/appsvc/app/.env | cut -d= -f2-)"
echo $PW

# 4) run mysql, reading SQL from stdin
docker compose exec -T "$MYSQL_SVC" \
  mysql -u"$MYSQL_USER" -p"$PW" "$DB_NAME"
EOSH
)

# ---- Execute over SSH; -T disables TTY to silence the warning ----
if [[ "$SQL_FILE" == "-" ]]; then
  gcloud compute ssh "$VM" --zone "$ZONE" -- -T \
    "APP_DIR='$APP_DIR' MYSQL_SVC='$MYSQL_SVC' DB_NAME='$DB_NAME' MYSQL_USER='$MYSQL_USER' bash -lc '$REMOTE_CMD'"
else
  gcloud compute ssh "$VM" --zone "$ZONE" -- -T \
    "APP_DIR='$APP_DIR' MYSQL_SVC='$MYSQL_SVC' DB_NAME='$DB_NAME' MYSQL_USER='$MYSQL_USER' bash -lc '$REMOTE_CMD'" \
    < "$SQL_FILE"
fi