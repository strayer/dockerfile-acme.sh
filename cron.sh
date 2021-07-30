#!/usr/bin/env bash
set -euo pipefail

die_func() {
  exit 1
}
trap die_func TERM

while true; do
  acme.sh --cron || exit 1
  sleep 86400 &
  wait
done
