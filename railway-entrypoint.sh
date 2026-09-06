#!/bin/bash
# Railway wrapper for AList.
#
# 1. Makes sure the data directory exists before AList looks for config.json,
#    along with an empty `local/` beside it: AList's Local driver refuses a root
#    folder that does not exist yet, so without this the first storage a deployer
#    adds fails with "root folder ... not exists" and there is no shell to fix it.
# 2. Selects Meilisearch as the search index, and turns on automatic index
#    updates, the first time the deployment comes up — through AList's own admin
#    API. AList keeps both in settings rows, so they are unreachable from the
#    environment; without this step the Meilisearch service is provisioned,
#    wired and never used.
#
# The step is guarded three ways so it can never revert an operator's choice: it
# runs only while the setting still holds AList's shipped default ("none"), only
# while no marker file exists on the volume, and only when a Meilisearch host is
# actually configured.
set -u

DATA_DIR=/opt/alist/data
MARKER="$DATA_DIR/.railway-search-index-seeded"
LOCAL_PORT="${HTTP_PORT:-5244}"

mkdir -p "$DATA_DIR" "$DATA_DIR/local"

seed_search_index() {
  local base="http://127.0.0.1:${LOCAL_PORT}"
  local i token items current payload

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

  # Read the whole settings row back and edit only its value: AList's save
  # endpoint replaces the record, so posting a bare {key,value} pair would blank
  # the type, group and option list the admin UI renders from.
  items=$(curl -fsS -m 10 "$base/api/admin/setting/get?keys=search_index,auto_update_index" \
    -H "Authorization: $token" 2>/dev/null | jq -c '.data // empty')
  if [ -z "${items:-}" ]; then
    echo "[railway] search index: could not read the index settings" >&2
    return 0
  fi

  current=$(printf '%s' "$items" | jq -r '.[] | select(.key == "search_index") | .value')
  if [ "$current" != "none" ]; then
    echo "[railway] search index: already set to '$current', leaving it alone" >&2
    : > "$MARKER"
    return 0
  fi

  # Saving runs AList's own hook, which creates the index on Meilisearch. It
  # fails while Meilisearch is still starting, and Railway orders no service
  # against another, so retry rather than giving up on the first attempt.
  payload=$(printf '%s' "$items" | jq -c 'map(if .key == "search_index" then .value = "meilisearch" elif .key == "auto_update_index" then .value = "true" else . end)')
  for i in $(seq 1 30); do
    if curl -fsS -m 60 -X POST "$base/api/admin/setting/save" \
        -H "Authorization: $token" -H 'Content-Type: application/json' \
        --data-binary "$payload" \
        2>/dev/null | jq -e '.code == 200' >/dev/null 2>&1; then
      echo "[railway] search index: search_index set to meilisearch, auto update on" >&2
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
