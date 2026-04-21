# CodePulse Review Action

Trigger a [CodePulse](https://review.codepulsehq.com) code review for your pull request the moment your CI jobs complete — no Slack paste, no waiting for a human to nudge the bot.

Authentication is handled via GitHub's built-in OIDC provider, so there are **no secrets to configure**.

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

That's it. Once your `test` and `lint` jobs pass, CodePulse reviews the PR and posts inline comments + a summary back to GitHub.

---

## Why this exists

You already have a CI pipeline that decides when a PR is "ready." Maybe your tests take 8 minutes and you don't want CodePulse reviewing half-broken code. Maybe you run three different linters and only care about the review if they all agree. Maybe you want the review on some branches and not others.

The GitHub Action gives you **explicit, deterministic control** over when the review runs — using the same `needs:` mechanism you already use everywhere else. No branch protection required. No bot to @-mention. No Slack paste.

## Prerequisites

1. **Install the CodePulse GitHub App** on your repo or organization from your [CodePulse dashboard](https://review.codepulsehq.com). The action posts reviews as the CodePulse App; it won't work on a repo the App isn't installed on.
2. **Enable the *GitHub Action trigger* feature** in your dashboard → Settings → Triggers.

That's it. No token generation, no webhook URL configuration, no secrets in your repo.

## How it works

1. The GitHub Actions runner asks GitHub's OIDC provider for a short-lived JWT identifying this workflow run. Audience is pinned to `codepulse` so a token minted for another service can't be silently replayed.
2. The action POSTs `{oidc_token, pr_number, head_sha}` to `https://review.codepulsehq.com/github/action-trigger`.
3. CodePulse verifies the JWT against GitHub's public JWKS, looks up which workspace owns the repo's organization, and dispatches the review if all gates pass (feature flag, seat license, monthly quota).
4. The action logs a GitHub Actions annotation (`::notice::`, `::warning::`, or `::error::`) describing what happened and exits.

## Supported events

**`pull_request` events only.** Workflows triggered by `push`, `workflow_dispatch`, `schedule`, or anything else are rejected with `auth_failed`.

**Fork PRs cannot trigger reviews.** GitHub doesn't grant `id-token: write` to workflows running from forks — that's a GitHub security feature, not a CodePulse restriction. External contributors' PRs still get reviewed through the normal webhook path when a maintainer installs the App at the org level.

## Exit codes

The action's design principle: **your CI only turns red when something you can fix is wrong.** Operator-side problems (quota, billing, our infrastructure) warn but don't break your merges.

| Situation | Exit | Annotation |
|---|:---:|---|
| Review queued | `0` | `::notice::` |
| Already in flight for this SHA | `0` | `::notice::` |
| Head SHA has moved since workflow started | `0` | `::warning::` |
| Couldn't fetch the PR to verify head SHA | `0` | `::warning::` |
| Monthly quota exhausted | `0` | `::warning::` |
| PR author not licensed | `0` | `::warning::` |
| Feature flag disabled | `0` | `::warning::` |
| CodePulse API unreachable | `0` | `::warning::` |
| CodePulse App not installed on this repo | **`1`** | `::error::` |
| OIDC authentication failed | **`1`** | `::error::` |

## Inputs

| Input | Required | Default | Description |
|---|:---:|---|---|
| `api-url` | no | `https://review.codepulsehq.com` | Override for staging or self-hosted deployments. You almost never need to set this. |

## Runner support

Linux and macOS runners. Windows runners aren't supported in v1 — the step uses bash.

## Version pinning

- `@v1` — floats with minor and patch releases within the v1 major (recommended).
- `@v1.0.0` — exact version.
- `@<sha>` — commit pin for maximum stability.

## Security

- **No secrets on your side.** OIDC tokens are short-lived (minutes) and bound to this specific workflow run. Nothing to rotate, nothing to leak.
- **Audience binding.** Tokens are minted with audience `codepulse`; our endpoint rejects any other audience.
- **Installation-scoped.** Reviews post as the CodePulse GitHub App using the installation token for the target org. The action never gains access to a repo the App isn't installed on.

The action itself is ~100 lines of bash. [Read the source.](./trigger.sh)

## Full documentation

See [review.codepulsehq.com/docs/github-action](https://review.codepulsehq.com/docs/github-action) for the complete setup guide, troubleshooting, and FAQ.

## Questions / issues

- **How to use it:** [review.codepulsehq.com/docs/github-action](https://review.codepulsehq.com/docs/github-action)
- **Bug in the action:** [open an issue](https://github.com/codepulsehq/review-action/issues) on this repo
- **Everything else (billing, seat licenses, feature requests):** hello@codepulsehq.com

## License

MIT. See [`LICENSE`](./LICENSE).
