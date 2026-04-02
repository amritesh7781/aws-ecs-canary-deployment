# AWS ECS Canary Deployment — Live Demo

A self-contained demo that visualises canary traffic splitting in real time.
Open the dashboard in a browser and watch requests bounce between stable (v1) and canary (v2) containers.

## What you'll see

| Element | What it shows |
|---|---|
| **Latest Response** | Version label, type (stable / canary), and the exact container ID that served the request |
| **Traffic Distribution** | Animated bar showing the live v1 / v2 split as requests accumulate |
| **Active Containers** | One card per unique container — pulses and glows when it receives a hit |
| **Request History** | Colour-coded pills (blue = v1, amber = v2) for every request, newest first |

---

## Run locally (Docker Compose)

```bash
# Build and start: 2× v1 replicas + 1 canary v2 + nginx proxy
BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ) docker compose up --build

# Open the dashboard
open http://localhost:8080
```

The default split is **80% stable / 20% canary**, matching a typical initial canary rollout.

### Change the traffic split

Edit `nginx/nginx.conf` and adjust the `weight` values:

```nginx
upstream canary_backend {
    server app-v1-a:3000 weight=4;   # stable replica A
    server app-v1-b:3000 weight=4;   # stable replica B
    server app-v2:3000   weight=2;   # canary ← increase to promote
}
```

Then restart nginx to apply:

```bash
docker compose restart nginx
```

---

## Deploy to AWS ECS

### 1. Build and push images

```bash
ACCOUNT=123456789012
REGION=us-east-1
REPO=${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/canary-demo

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REPO

# Stable
docker build ./app \
  --build-arg VERSION=v1 \
  --build-arg VERSION_LABEL=1.0.0 \
  --build-arg BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  -t $REPO:v1

# Canary
docker build ./app \
  --build-arg VERSION=v2 \
  --build-arg VERSION_LABEL=2.0.0 \
  --build-arg BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  -t $REPO:v2

docker push $REPO:v1
docker push $REPO:v2
```

### 2. Register task definitions

```bash
# Update ACCOUNT_ID and REGION placeholders first
aws ecs register-task-definition --cli-input-json file://ecs/task-definition-v1.json
aws ecs register-task-definition --cli-input-json file://ecs/task-definition-v2.json
```

### 3. Create two ECS services with separate ALB target groups

- **canary-demo-stable** → Target Group A (stable)
- **canary-demo-canary** → Target Group B (canary)

Configure an ALB listener rule with weighted forwarding:
- Target Group A weight: 80
- Target Group B weight: 20

### 4. Shift traffic progressively

```bash
export AWS_REGION=us-east-1
export ALB_LISTENER_ARN=arn:aws:elasticloadbalancing:...
export STABLE_TG_ARN=arn:aws:elasticloadbalancing:...
export CANARY_TG_ARN=arn:aws:elasticloadbalancing:...
export ALB_RULE_ARN=arn:aws:elasticloadbalancing:...

# Promote canary to 20%
./ecs/canary-deploy.sh promote 20

# After validating metrics, promote to 50%
./ecs/canary-deploy.sh promote 50

# Full promotion
./ecs/canary-deploy.sh promote 100

# Emergency rollback
./ecs/canary-deploy.sh rollback
```

---

## Project structure

```
.
├── app/
│   ├── server.js          # Express API — returns version, container ID, uptime
│   ├── package.json
│   ├── Dockerfile         # Multi-version build via BUILD_ARGS
│   └── public/
│       └── index.html     # Live dashboard (polls /api/info every 800ms)
├── nginx/
│   └── nginx.conf         # Weighted upstream — mimics ALB target groups locally
├── docker-compose.yml     # 2× v1 + 1× v2 + nginx
└── ecs/
    ├── task-definition-v1.json
    ├── task-definition-v2.json
    └── canary-deploy.sh   # ALB weight-shift script
```
