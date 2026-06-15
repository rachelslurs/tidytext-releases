# tidytext-releases

Public release surface for TidyText Offline: signed `.dmg`, updater `latest.json`, and related assets. App source lives in a private repo; this repo only hosts published binaries.

## Cutting a release

Releases are cut from the private source repo (`npm run release -- <version>`). That script (`scripts/release.mjs`) pushes tags in order:

1. **Source repo** — version tag (e.g. `v1.0.0`), polled until visible on origin
2. **This repo** — same version tag as a workflow trigger

Before cutting, sync this repo's local clone to `main` — `release.mjs` enforces that the trigger tag is created at current `origin/main`.

## Release recovery

- **Partial failure** (source tag pushed, releases tag or CI not done): re-run `npm run release -- <ver>` in the source repo — it auto-resumes.
- **Both tags exist, CI or assets broken:** re-run the failed **tag-push** Actions run first. Do not re-push existing tags.
- **Retrigger from scratch:** delete the releases-repo tag locally **and** on origin, then re-run from the source repo. If `tauri-action` fails on a duplicate release, delete the broken GitHub Release for that tag before re-running.
- **`workflow_dispatch`** (Actions → "Release (TidyText Offline)"): rebuilds from the source tag but **always publishes as prerelease**. Version input is without the `v` prefix (e.g. `1.0.0`).

## First release checklist

1. Run **Release preflight (config doctor)** via `workflow_dispatch` and approve the `release` environment gate.
2. Cut the release from the source repo; approve the `release` environment when the tag-push run pauses.
3. After the first full audited release, flip `step-security/harden-runner` from `egress-policy: audit` to `block` with the captured allowlist (see comments in `.github/workflows/release.yml`).
