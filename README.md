# CodePulse Review Action

Trigger a [CodePulse](https://review.codepulsehq.com) code review for your pull
request once your CI jobs complete.

## Prerequisites

1. Install the CodePulse GitHub App on your repo or organization from
   your CodePulse dashboard.
2. Enable the **GitHub Action trigger** feature flag in your CodePulse
   dashboard → Settings → Triggers.

## Usage

Add this job to your existing workflow:

```yaml
jobs:
  test:
    # ... your existing tests
  lint:
    # ... your existing lint

  codepulse:
    needs: [test, lint]
    runs-on: ubuntu-latest
    permissions:
      id-token: write
    steps:
      - uses: codepulsehq/review-action@v1
```

`needs:` gates when the review runs — only after your chosen jobs pass.
`permissions: id-token: write` is required; without it, the action can't
authenticate to CodePulse.

## How it works

1. GitHub Actions mints a short-lived OIDC token identifying this
   workflow run.
2. The action POSTs it to `https://review.codepulsehq.com/github/action-trigger`.
3. CodePulse verifies the token, checks that the App is installed on
   your org, and dispatches a review if all gates (feature flag, seat
   license, monthly quota) pass.

## Supported events

Only `pull_request` events are supported. Other event types are
rejected with `auth_failed`.

Fork PRs cannot trigger reviews: GitHub does not grant
`id-token: write` to workflows running from forks.

## Exit behavior

| Situation | Exit code | Annotation |
|---|---|---|
| Review queued | 0 | notice |
| Already in flight for this SHA | 0 | notice |
| Head SHA has moved since workflow started | 0 | warning |
| Couldn't fetch the PR to verify head SHA | 0 | warning |
| Quota exhausted | 0 | warning |
| Author not licensed | 0 | warning |
| Flag disabled | 0 | warning |
| CodePulse App not installed | **1** | error |
| OIDC authentication failed | **1** | error |
| CodePulse API unreachable | 0 | warning |

Your CI stays green unless *your* configuration is the problem.

## Runner support

Linux and macOS runners (the step uses bash). Windows runners are not
supported in v1.
