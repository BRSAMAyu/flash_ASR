#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  echo "Set SIGN_IDENTITY, e.g. 'Developer ID Application: Your Name (TEAMID)'" >&2
  exit 1
fi

"$ROOT/scripts/package_release.sh"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  "$ROOT/scripts/notarize_release.sh"
fi

echo "Release build done."
