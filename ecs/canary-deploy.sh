#!/usr/bin/env bash
# canary-deploy.sh — shift traffic between stable and canary target groups
#
# Usage:
#   ./canary-deploy.sh promote 20    # send 20% to canary
#   ./canary-deploy.sh promote 50    # send 50% to canary
#   ./canary-deploy.sh promote 100   # fully promote canary (blue/green complete)
#   ./canary-deploy.sh rollback      # send 100% back to stable
#
# Prerequisites: aws cli v2, jq

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
LISTENER_ARN="${ALB_LISTENER_ARN:?Set ALB_LISTENER_ARN}"
STABLE_TG_ARN="${STABLE_TG_ARN:?Set STABLE_TG_ARN}"
CANARY_TG_ARN="${CANARY_TG_ARN:?Set CANARY_TG_ARN}"

RULE_ARN="${ALB_RULE_ARN:?Set ALB_RULE_ARN}"

shift_traffic() {
  local canary_pct="$1"
  local stable_pct=$((100 - canary_pct))

  echo "⇢ Shifting traffic: Stable ${stable_pct}%  |  Canary ${canary_pct}%"

  aws elbv2 modify-rule \
    --region "$REGION" \
    --rule-arn "$RULE_ARN" \
    --actions "[
      {
        \"Type\": \"forward\",
        \"ForwardConfig\": {
          \"TargetGroups\": [
            {\"TargetGroupArn\": \"${STABLE_TG_ARN}\", \"Weight\": ${stable_pct}},
            {\"TargetGroupArn\": \"${CANARY_TG_ARN}\", \"Weight\": ${canary_pct}}
          ],
          \"TargetGroupStickinessConfig\": {\"Enabled\": false}
        }
      }
    ]" > /dev/null

  echo "✓ Done. Monitor the dashboard at your ALB DNS."
}

CMD="${1:-}"
PCT="${2:-10}"

case "$CMD" in
  promote)
    if [[ "$PCT" -lt 1 || "$PCT" -gt 100 ]]; then
      echo "Error: percentage must be 1–100" >&2; exit 1
    fi
    shift_traffic "$PCT"
    ;;
  rollback)
    echo "⚠ Rolling back — sending 100% to stable"
    shift_traffic 0
    ;;
  *)
    echo "Usage: $0 promote <1-100> | rollback"
    exit 1
    ;;
esac
