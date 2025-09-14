#!/bin/bash
set -e

# --- Config (override via env if needed) ---
BASE="${BASE:-http://localhost:7770}"
API="${API:-/gradio_api}"                 # set to "" if no prefix
CURL_OPTS="${CURL_OPTS:-}"                # e.g. "-b cookies.txt -c cookies.txt"
MPV_OPTS="${MPV_OPTS:---really-quiet}"    # extra mpv flags

# play: reads audio bytes from stdin and plays with mpv
# Usage:
#   vall_e_x ... | play
play() {
  command -v mpv >/dev/null || { echo "mpv is required" >&2; return 2; }
  # Read from stdin ("-") and play
  mpv $MPV_OPTS -
}

# vall_e_x: POST JSON to vall_e_x_generate, wait for SSE, stream audio to stdout
# Usage:
#   vall_e_x '{"data":[...]}'
#   echo '{"data":[...]}' | vall_e_x -
vall_e_x() {
  command -v jq >/dev/null || { echo "jq is required" >&2; return 2; }

  local json
  if [[ $# -gt 0 && "$1" != "-" ]]; then
    json="$1"
  else
    json="$(cat)"  # read JSON from stdin
  fi

  local eid final_data path url1 url2

  # 1) Start job -> event_id
  eid=$(curl -sS $CURL_OPTS -X POST "$BASE$API/call/vall_e_x_generate" \
          -H 'Content-Type: application/json' -d "$json" | jq -r '.event_id')
  [[ -n "$eid" && "$eid" != "null" ]] || { echo "Failed to get event_id" >&2; return 1; }

  # 2) Grab the final SSE payload (JSON array)
  final_data=$(curl -Ns $CURL_OPTS "$BASE$API/call/vall_e_x_generate/$eid" \
                 | sed -n 's/^data: //p' | tail -n 1)
  [[ -n "$final_data" ]] || { echo "No final data from stream" >&2; return 1; }

  # 3) Build download URL from .path (ignore any buggy .url)
  path=$(jq -r '.[0].path // empty' <<<"$final_data")
  [[ -n "$path" ]] || { echo "No file path in response" >&2; return 1; }
  url1="$BASE$API/file=$path"   # common
  url2="$BASE/file=$path"       # fallback

  # 4) Stream audio bytes to stdout (binary-safe)
  curl -fsSL $CURL_OPTS "$url1" || curl -fsSL $CURL_OPTS "$url2"
}

