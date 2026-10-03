#!/usr/bin/env bash
PASS=0; FAIL=0
URL=https://localhost:8443

check() {  # check "description" ok|fail "command"
  local desc="$1" expect="$2" cmd="$3"
  eval "$cmd" >/dev/null 2>&1
  local rc=$?
  if { [ "$expect" = "ok" ] && [ $rc -eq 0 ]; } || { [ "$expect" = "fail" ] && [ $rc -ne 0 ]; }; then
    echo "PASS: $desc"; PASS=$((PASS+1))
  else
    echo "FAIL: $desc"; FAIL=$((FAIL+1))
  fi
}

wait_ready() {
  for _ in $(seq 1 30); do
    curl -skf "$URL/health" >/dev/null && return 0
    sleep 1
  done
  return 1
}

redirects() { [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/)" = "301" ]; }

tls13() { curl -skv "$URL/health" 2>&1 | grep -q "TLSv1.3"; }

has_headers() {
  local h
  h=$(curl -sk -D - -o /dev/null "$URL/health")
  echo "$h" | grep -qi '^strict-transport-security' && echo "$h" | grep -qi '^x-content-type-options'
}

no_version_leak() { ! curl -sk -D - -o /dev/null "$URL/health" | grep -qi '^server: nginx/'; }

web_to_redis() {
  docker compose exec -T web python -c "import socket; socket.create_connection(('redis',6379),2)"
}

spread() {
  local n
  n=$(for _ in $(seq 1 12); do curl -sk "$URL/"; echo; done | grep -o '"served_by":"[^"]*"' | sort -u | wc -l)
  [ "$n" -ge 2 ]
}

failover() {
  local cid ok=0
  cid=$(docker compose ps -q web | head -1)
  docker stop "$cid" >/dev/null
  for _ in $(seq 1 8); do
    curl -skf -m 10 "$URL/health" >/dev/null && ok=$((ok+1))
  done
  docker start "$cid" >/dev/null
  docker compose restart nginx >/dev/null 2>&1
  wait_ready
  [ "$ok" -eq 8 ]
}

rate_limited() {
  local c
  c=$(seq 1 100 | xargs -P 20 -I{} curl -sk -o /dev/null -w '%{http_code}\n' "$URL/health" | grep -c 429)
  [ "$c" -ge 1 ]
}

metrics_hidden() { [ "$(curl -sk -o /dev/null -w "%{http_code}" "$URL/metrics")" = "404" ]; }

echo "Waiting for the app to be ready..."
wait_ready || { echo "App never became ready"; exit 1; }

check "HTTPS reachable on :8443"                      ok   "curl -skf $URL/health"
check "HTTP :8080 redirects to HTTPS (301)"           ok   "redirects"
check "TLS 1.3 negotiated"                            ok   "tls13"
check "Security headers present (HSTS, nosniff)"      ok   "has_headers"
check "Nginx version not leaked in Server header"     ok   "no_version_leak"
check "Redis port NOT exposed to the host"            fail "timeout 2 bash -c '</dev/tcp/127.0.0.1/6379'"
check "Nginx can reach web (control test)"            ok   "docker compose exec -T nginx wget -q -T 2 -O- http://web:5000/health"
check "Nginx CANNOT reach Redis (segmentation)"       fail "docker compose exec -T nginx wget -q -T 2 -O- http://redis:6379"
check "Web CAN reach Redis"                           ok   "web_to_redis"
check "Load spread over 2+ replicas"                  ok   "spread"
check "Failover: all requests succeed, one replica down" ok "failover"
check "Metrics endpoint hidden from public proxy (404)" ok "metrics_hidden"
check "Rate limiting returns HTTP 429 under burst"    ok   "rate_limited"

echo
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
