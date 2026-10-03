# docker-network-lab

![Network tests](https://github.com/alibhae89-gif/docker-network-lab/actions/workflows/network-test.yml/badge.svg)

A segmented, load-balanced, TLS-terminated Docker network: Nginx in front, three app replicas behind it, and Redis on a private network that only the app can reach. A 12-check test suite proves the security and resilience properties, and runs in CI on every push alongside an image vulnerability scan.

## Architecture

```mermaid
flowchart LR
  Client -->|"HTTP :8080 (301 redirect)"| Nginx
  Client -->|"HTTPS :8443 (TLS, rate-limited)"| Nginx
  Nginx -->|"frontend 10.77.1.0/24"| W1["web 1"] & W2["web 2"] & W3["web 3"]
  W1 & W2 & W3 -->|"backend 10.77.2.0/24 (internal)"| Redis[("Redis")]
```

## Addressing plan

| Network | Subnet | Fixed addresses | Reachable from host/internet |
|---|---|---|---|
| frontend | 10.77.1.0/24 | nginx 10.77.1.10 | Only Nginx ports 8080 and 8443 |
| backend (internal) | 10.77.2.0/24 | redis 10.77.2.10 | No |

## Security controls

| Control | Implementation | Verified by |
|---|---|---|
| Encryption in transit | TLS 1.2/1.3 on :8443, HTTP redirects with 301 | tests 1-3 |
| Header hardening | HSTS, nosniff, X-Frame-Options, Nginx version hidden | tests 4-5 |
| Network segmentation | Redis on an `internal: true` network | tests 6, 8, 9 |
| Abuse protection | 10 req/s per IP, burst 20, HTTP 429 beyond that | test 12 |
| Resilience | Failed replica skipped after a 2s connect timeout | test 11 |
| Image security | Trivy scan (HIGH/CRITICAL) in CI, OS patches at build | CI `scan` job |

## Quick start

```bash
./scripts/gen-certs.sh                       # self-signed cert (not committed)
docker compose up -d --build --scale web=3
curl -sk https://localhost:8443/             # -k because the cert is self-signed
```

## Tests

```bash
./scripts/network-test.sh
```

Expected: `Passed: 12  Failed: 0`. Tests cover HTTPS, redirect, TLS 1.3, headers, version hiding, Redis not exposed, Nginx-to-web reachable, Nginx-to-Redis blocked, web-to-Redis reachable, load spread, failover, and rate limiting. Positive control tests make sure a "blocked" result is a real block, not a broken tool.

## Try it yourself

```bash
# Redis has no route out (expect: blocked)
docker compose exec -T redis wget -q -T 3 -O- http://1.1.1.1 || echo "blocked"

# Inspect the network design
docker network ls
docker network inspect $(docker network ls -q --filter name=backend)
```

## How this maps to the cloud

| Here | AWS equivalent |
|---|---|
| frontend network + Nginx | public subnet + load balancer |
| web replicas | app tier in an Auto Scaling group |
| backend internal network | private subnet, no internet gateway |
| Network tests | security group / NACL verification |

## Known limitations and roadmap

- The certificate is self-signed, so browsers warn and curl needs `-k`. `mkcert` fixes this for local browsers.
- Nginx resolves `web` at startup, so replicas added later need `docker compose restart nginx`.
- Roadmap: Prometheus + Grafana traffic dashboards, then a Terraform deployment of the same layout on AWS.
