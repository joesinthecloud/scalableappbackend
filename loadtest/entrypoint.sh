#!/usr/bin/env sh
set -eu

: "${TARGET_HOST:?TARGET_HOST required}"
: "${USERS:=50}"
: "${SPAWN_RATE:=5}"
: "${RUN_TIME:=3m}"

exec locust \
  --host "${TARGET_HOST}" \
  --headless \
  -u "${USERS}" \
  -r "${SPAWN_RATE}" \
  --run-time "${RUN_TIME}" \
  --stop-timeout 30 \
  --only-summary
