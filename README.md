# tidytext-releases

Public release surface for TidyText Offline: signed `.dmg`, updater `latest.json`, and related assets. App source lives in a private repo; this repo only hosts published binaries.

## Release & recovery

### Dual-tag flow

Releases are cut from the private source repo (`npm run release -- <version>`). `scripts/release.mjs` pushes tags in order:

1. **Source repo** — version tag (e.g. `v1.0.0`), polled until visible on origin
2. **This repo** — same version tag as a workflow trigger (`release.yml` fires on `v*` tag push)

Before cutting, sync this repo's local clone to `main` — `release.mjs` enforces that the trigger tag is created at current `origin/main`.

### Auto-resume

If the source tag landed but the releases tag or CI did not finish, re-run `npm run release -- <ver>` in the source repo. The script skips step 1 when the source tag is already on origin at HEAD and pushes the releases trigger tag.

### Stable recovery

When both tags exist but CI or published assets are broken, **re-run the failed tag-push Actions run** first. Do not re-push existing tags — Git rejects duplicate tag pushes, and a re-run preserves the stable (non-prerelease) channel.

If `tauri-action` fails on a duplicate release, delete the broken GitHub Release for that tag, then re-run.

### Retrigger from scratch

Delete the releases-repo tag **locally and on origin**, then re-run `npm run release -- <ver>` from the source repo. The source tag can stay in place.

### `workflow_dispatch` (prerelease only)

Actions → **Release (TidyText Offline)** rebuilds from the source tag but **always publishes as prerelease**. Use for dry runs, not stable recovery. Version input is without the `v` prefix (e.g. `1.0.0`).

### First release

1. Run **Release preflight (config doctor)** via `workflow_dispatch` and approve the `release` environment gate.
2. Cut the release from the source repo; approve the `release` environment when the tag-push run pauses.
3. After the first full audited release, flip `step-security/harden-runner` from `egress-policy: audit` to `block` with the captured allowlist (see comments in `.github/workflows/release.yml`).

### Reachability cron

The weekly **Release reachability (drift guard)** workflow checks `/releases/latest` anonymously. It only becomes meaningful once a **stable (non-prerelease) v1.0.0+** release exists — `/releases/latest` excludes prereleases. Expect failures until then.
