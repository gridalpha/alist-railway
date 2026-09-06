#!/bin/bash
# Railway wrapper for AList.
#
# 1. Makes sure the data directory exists before AList looks for config.json.
# 2. Selects Meilisearch as the search index the first time the deployment comes
#    up, through AList's own admin API. AList keeps that choice in a settings
#    row, so it is unreachable from the environment; without this step the
#    Meilisearch service is provisioned, wired and never used.
#
# The step is guarded three ways so it can never revert an operator's choice: it
# runs only while the setting still holds AList's shipped default ("none"), only
# while no marker file exists on the volume, and only when a Meilisearch host is
# actually configured.
set -u

DATA_DIR=/opt/alist/data
MARKER="$DATA_DIR/.railway-search-index-seeded"
LOCAL_PORT="${HTTP_PORT:-5244}"

mkdir -p "$DATA_DIR"

seed_search_index() {
  local base="http://127.0.0.1:${LOCAL_PORT}"
  local i token item current

  # AList has to be serving before it can be configured through its own API.
  for i in $(seq 1 90); do
    curl -fsS -m 5 "$base/ping" >/dev/null 2>&1 && break
    sleep 2
  done

  for i in $(seq 1 30); do
    token=$(curl -fsS -m 10 -X POST "$base/api/auth/login" \
      -H 'Content-Type: application/json' \
      --data-binary "$(jq -nc --arg p "${ALIST_ADMIN_PASSWORD:-}" '{username:"admin",password:$p}')" \
      2>/dev/null | jq -r '.data.token // empty')
    [ -n "${token:-}" ] && break
    sleep 10
  done
  if [ -z "${token:-}" ]; then
    echo "[railway] search index: could not sign in as admin, leaving search_index unchanged" >&2
    return 0
  fi

  item=$(curl -fsS -m 10 "$base/api/admin/setting/get?key=search_index" \
    -H "Authorization: $token" 2>/dev/null | jq -c '.data // empty')
  if [ -z "${item:-}" ]; then
    echo "[railway] search index: could not read the search_index setting" >&2
    return 0
  fi

  current=$(printf '%s' "$item" | jq -r '.value')
  if [ "$current" != "none" ]; then
    echo "[railway] search index: already set to '$current', leaving it alone" >&2
    : > "$MARKER"
    return 0
  fi

  # Saving runs AList's own hook, which creates the index on Meilisearch. It
  # fails while Meilisearch is still starting, and Railway orders no service
  # against another, so retry rather than giving up on the first attempt.
  for i in $(seq 1 30); do
    if curl -fsS -m 60 -X POST "$base/api/admin/setting/save" \
        -H "Authorization: $token" -H 'Content-Type: application/json' \
        --data-binary "$(printf '%s' "$item" | jq -c '[.value = "meilisearch"]')" \
        2>/dev/null | jq -e '.code == 200' >/dev/null 2>&1; then
      echo "[railway] search index: search_index set to meilisearch" >&2
      : > "$MARKER"
      return 0
    fi
    sleep 10
  done
  echo "[railway] search index: Meilisearch did not accept the index, retrying on the next boot" >&2
}

if [ -n "${MEILISEARCH_HOST:-}" ] && [ -n "${ALIST_ADMIN_PASSWORD:-}" ] && [ ! -f "$MARKER" ]; then
  seed_search_index &
fi

exec /entrypoint.sh
