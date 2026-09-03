#!/usr/bin/env bash
# CodePulse review trigger — requests a GitHub Actions OIDC token with
# audience=codepulse, POSTs it to the CodePulse API, and maps the JSON
# response to a GHA annotation + exit code.
#
# Exit codes:
#   0 - Review queued, already in flight, or operator-side denial.
#   1 - Caller-fixable problem (App not installed, OIDC misconfigured).
#
# Required env (set by action.yml):
#   CODEPULSE_API_URL, PR_NUMBER, HEAD_SHA
# Required env (injected by GitHub when permissions: id-token: write):
#   ACTIONS_ID_TOKEN_REQUEST_TOKEN, ACTIONS_ID_TOKEN_REQUEST_URL

set -euo pipefail

if [[ -z "${PR_NUMBER:-}" || -z "${HEAD_SHA:-}" ]]; then
    echo "::error::This action only supports pull_request events." >&2
    exit 1
fi

if [[ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" || -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]]; then
    echo "::error::OIDC token env missing. Add 'permissions: id-token: write' to this job. Fork PRs cannot trigger CodePulse reviews." >&2
    exit 1
fi

audience="codepulse"
token_url="${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${audience}"

oidc_response="$(curl -fsS \
    -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
    -H "Accept: application/json" \
    "${token_url}")" || {
    echo "::error::Failed to fetch OIDC token from GitHub." >&2
    exit 1
}

oidc_token="$(printf '%s' "${oidc_response}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["value"])')" || {
    echo "::error::GitHub returned an unparseable OIDC token response." >&2
    exit 1
}

api_response="$(curl -sS -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "User-Agent: codepulse-review-action" \
    --data "$(OIDC_TOKEN="${oidc_token}" PR_NUMBER="${PR_NUMBER}" HEAD_SHA="${HEAD_SHA}" python3 -c '
import json, os
print(json.dumps({
    "oidc_token": os.environ["OIDC_TOKEN"],
    "pr_number": int(os.environ["PR_NUMBER"]),
    "head_sha": os.environ["HEAD_SHA"],
}))
')" \
    "${CODEPULSE_API_URL}/github/action-trigger")" || {
    # Network-class error — don't break user CI.
    echo "::warning::CodePulse unreachable; skipping review trigger." >&2
    exit 0
}

http_code="$(printf '%s' "${api_response}" | tail -n1)"
body="$(printf '%s' "${api_response}" | sed '$d')"

if [[ "${http_code:0:1}" == "5" && "${http_code}" != "503" ]]; then
    echo "::warning::CodePulse API returned HTTP ${http_code}; skipping." >&2
    exit 0
fi

if [[ "${http_code:0:1}" == "3" ]]; then
    # We don't follow redirects (a redirect response body isn't the API's
    # JSON contract) — surface it as a soft failure rather than crashing
    # on the JSON parse below. This is what breaks when api-url points at
    # a domain that's since been redirected to a newer one.
    echo "::warning::CodePulse API returned HTTP ${http_code} (redirect); skipping. Check that api-url points at the current CodePulse domain." >&2
    exit 0
fi

# Parse defensively: any non-JSON or unexpected-shape body (an HTML error
# page, an empty response, a plain-text upstream error, etc.) must fall
# through to the "Unexpected CodePulse response" warning below rather than
# crashing the caller's build with an unhandled traceback.
parsed="$(printf '%s' "${body}" | python3 -c '
import json, sys

try:
    data = json.load(sys.stdin)
    if not isinstance(data, dict):
        raise ValueError("response body is not a JSON object")
except Exception:
    print("")
    print("")
else:
    print(data.get("status") or "")
    print(data.get("message") or "")
')"
status="$(printf '%s' "${parsed}" | sed -n '1p')"
message="$(printf '%s' "${parsed}" | sed -n '2p')"

case "${status}" in
    dispatched)
        echo "::notice::CodePulse review queued for PR #${PR_NUMBER} (sha=${HEAD_SHA:0:7})."
        ;;
    already_claimed)
        echo "::notice::CodePulse review already in flight for this head SHA."
        ;;
    stale_sha)
        echo "::warning::Head SHA has moved since this workflow started; skipping."
        ;;
    pr_fetch_failed)
        echo "::warning::CodePulse couldn't fetch the PR to verify head SHA; skipping."
        ;;
    flag_off)
        echo "::warning::github_action_trigger is disabled for this workspace."
        ;;
    seat_denied)
        echo "::warning::${message}"
        ;;
    quota_exhausted)
        echo "::warning::CodePulse monthly review quota exhausted. See your dashboard."
        ;;
    dispatch_failed)
        echo "::warning::CodePulse dispatch failed (${message}); skipping."
        ;;
    no_installation)
        echo "::error::${message}" >&2
        exit 1
        ;;
    auth_failed)
        echo "::error::OIDC authentication failed: ${message}" >&2
        exit 1
        ;;
    *)
        echo "::warning::Unexpected CodePulse response: ${body}" >&2
        ;;
esac

exit 0
