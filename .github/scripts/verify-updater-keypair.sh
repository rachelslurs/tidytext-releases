#!/usr/bin/env bash
# Verify the Tauri updater keypair: prove the PRIVATE signing key (TAURI_SIGNING_PRIVATE_KEY +
# TAURI_SIGNING_PRIVATE_KEY_PASSWORD, read from the env) is the counterpart of the PUBLIC key the
# app ships. A mismatch means a published v1 could never verify a v2 update — a SILENT dead updater
# that forces every existing install to reinstall by hand. Signs a throwaway probe with the private
# key and verifies it against the pubkey; exits non-zero (with ::error::) on mismatch.
#
# ONE logic, TWO callers, TWO pubkey SOURCES:
#   --conf <path>       extract plugins.updater.pubkey from a tauri.conf.json on disk.
#                       release.yml passes the working tree it checked out AT THE TAG — the
#                       AUTHORITATIVE gate: it validates the exact bytes that compile and ship.
#   --pubkey-b64 <b64>  use this base64 minisign public key directly.
#                       preflight.yml passes the pubkey it fetched via `gh api .../contents/..?ref=`
#                       — the fail-fast doctor, run during env setup before build minutes are spent.
#
# minisign is used for BOTH sign and verify (tauri signer has no verify subcommand), so everything
# stays as plain minisign files — no tauri-.sig base64 layer to reconcile. If `minisign -S` cannot
# LOAD the rsign2-generated secret key (a format edge case — NOT a mismatch; you'll see a minisign
# load error here, not the MISMATCH line below), sign with the tauri CLI instead:
#   tauri signer sign -k "$TAURI_SIGNING_PRIVATE_KEY" -p "$TAURI_SIGNING_PRIVATE_KEY_PASSWORD" <probe>
#   base64 -d <probe>.sig > <probe>.minisig   # then: minisign -V -p <pub> -m <probe> -x <probe>.minisig
# NO secret value is ever printed; the private key only ever lands in a file under a temp dir.
set -euo pipefail

fail() { echo "::error::$*"; exit 1; }

PUBKEY_B64=""
CONF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pubkey-b64) PUBKEY_B64="${2:-}"; shift 2 ;;
    --conf)       CONF="${2:-}"; shift 2 ;;
    *) fail "unknown argument: $1 (use --conf <path> or --pubkey-b64 <base64>)" ;;
  esac
done

[ -n "${TAURI_SIGNING_PRIVATE_KEY:-}" ]          || fail "TAURI_SIGNING_PRIVATE_KEY is not set in the env"
[ -n "${TAURI_SIGNING_PRIVATE_KEY_PASSWORD:-}" ] || fail "TAURI_SIGNING_PRIVATE_KEY_PASSWORD is not set in the env"

# Resolve the pubkey (base64 of a minisign .pub) from whichever source the caller gave us.
if [ -n "$CONF" ]; then
  [ -f "$CONF" ] || fail "tauri.conf.json not found at: $CONF"
  command -v jq >/dev/null 2>&1 || fail "jq is required to read $CONF"
  PUBKEY_B64="$(jq -r '.plugins.updater.pubkey // empty' "$CONF")"
  [ -n "$PUBKEY_B64" ] || fail "plugins.updater.pubkey is missing or empty in $CONF"
elif [ -n "$PUBKEY_B64" ] && [ "$PUBKEY_B64" != "null" ]; then
  :
else
  fail "no pubkey: pass --conf <path> or --pubkey-b64 <base64>"
fi

# minisign on both ubuntu (apt) and macOS (brew) runners. On the first, audited release this brew
# egress is captured into the recommended harden-runner policy — keep its hosts when flipping to block.
if ! command -v minisign >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew install minisign
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq && sudo apt-get install -y -qq minisign
  else
    fail "minisign not installed and no known installer (brew/apt) found"
  fi
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Decode with openssl (portable across the Linux/macOS runners; matches release.yml's usage).
printf '%s' "$TAURI_SIGNING_PRIVATE_KEY" | openssl base64 -d -A > "$WORK/sk.key"
printf '%s' "$PUBKEY_B64"               | openssl base64 -d -A > "$WORK/updater.pub"
echo "tidytext updater keypair self-check" > "$WORK/probe.txt"

KEYID="$(grep -oE '[0-9A-F]{16}' "$WORK/updater.pub" | head -1 || true)"

# Sign with the private key (password on stdin — CI has no tty), then verify against the pubkey.
# A LOAD failure on the next line trips set -e and exits with minisign's own error (a tooling issue,
# NOT the MISMATCH path); only a successful sign that fails verification is a true key mismatch.
printf '%s\n' "$TAURI_SIGNING_PRIVATE_KEY_PASSWORD" | minisign -S -s "$WORK/sk.key" -m "$WORK/probe.txt"
if minisign -V -p "$WORK/updater.pub" -m "$WORK/probe.txt"; then
  echo "✓ updater keypair OK — release signing key matches the updater pubkey (key ID ${KEYID:-unknown})"
else
  fail "updater keypair MISMATCH — TAURI_SIGNING_PRIVATE_KEY is not the counterpart of the updater pubkey (key ID ${KEYID:-unknown}); a shipped build would have a dead v1->v2 auto-update"
fi
