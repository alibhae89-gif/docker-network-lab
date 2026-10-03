#!/usr/bin/env bash
# Generates steady traffic with a periodic burst that trips the rate limiter.
URL=${URL:-https://localhost:8443}
echo "Generating load against $URL (Ctrl+C to stop)"
while true; do
  # steady phase: roughly 4-5 requests/second for ~20 seconds
  for _ in $(seq 1 100); do
    curl -sk -o /dev/null "$URL/"
    sleep 0.2
  done
  # burst phase: 150 requests, 30 in parallel -> some get HTTP 429
  seq 1 150 | xargs -P 30 -I{} curl -sk -o /dev/null "$URL/health"
  echo "burst sent"
done
