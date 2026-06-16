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

1. Run **Release preflight (config doctor)** via `workflow_dispatch` and approve the `release` environment gate. It validates every `release` secret, the read PAT's reach, the Apple key/cert, **and** the updater signing key (see [Updater signing key](#updater-signing-key)). Leave the `version` input blank to check against `main` (fail-fast); pass it only once the source tag exists, to validate that exact tag.
2. Cut the release from the source repo; approve the `release` environment when the tag-push run pauses. The build re-verifies the updater keypair against the checked-out tag before building (authoritative).
3. After the first full audited release, flip `step-security/harden-runner` from `egress-policy: audit` to `block` with the captured allowlist (see comments in `.github/workflows/release.yml`). The allowlist includes the keypair step's minisign/Homebrew egress — keep it.

### Updater signing key

The Tauri updater verifies each update against the minisign public key baked into the *installed* app, so the private key in the `release` environment (`TAURI_SIGNING_PRIVATE_KEY`) must always be the counterpart of the `pubkey` in the source repo's `src-tauri/tauri.conf.json`. A mismatch is silent: the build succeeds and v1 installs fine, but v1 can never verify a v2 update — every existing install would then need a manual reinstall. **Once a release ships, treat the keypair as permanent** (Tauri has no updater key rotation).

Two checks guard this, sharing one script — `.github/scripts/verify-updater-keypair.sh`, which signs a throwaway probe with the private key and verifies it against the pubkey (no secret value is printed):

- **In-build (authoritative)** — `release.yml`, right after the source checkout, validates against the `tauri.conf.json` it just checked out *at the release tag* (the exact bytes that ship), before the build. Immune to validating a different/force-moved/skipped tag.
- **Preflight (fail-fast)** — the config doctor validates against the pubkey fetched from the source repo at the release tag (`version` input), or against `main` with a warning if no version is given. Surfaces drift during setup, before build minutes.

Because preflight with a `version` requires that source tag to already exist, the typical pre-cut run leaves `version` blank (validates `main`); the in-build check is the real gate on the shipped tag. If `minisign -S` ever fails to *load* the key (an rsign2/minisign format edge case, not a mismatch), use the `tauri signer sign` → `base64 -d` → `minisign -V -x` fallback noted in the script.

### Reachability cron

The weekly **Release reachability (drift guard)** workflow checks `/releases/latest` anonymously. It only becomes meaningful once a **stable (non-prerelease) v1.0.0+** release exists — `/releases/latest` excludes prereleases. Expect failures until then.
