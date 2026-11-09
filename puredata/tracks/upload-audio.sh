#!/bin/bash
# upload-audio.sh
# Uploads all audio files from the folder this script lives in
# to a GitHub release.
#
# Usage (in Terminal, inside the "tracks" folder):
#   ./upload-audio.sh v1.0.0          upload files one by one
#   ./upload-audio.sh v1.0.0 --zip    upload everything as Audio.zip
#
# Requirement: gh is installed and logged in
#   brew install gh && gh auth login

set -euo pipefail

TAG="${1:-}"
MODE="${2:-}"
MAX=$((2 * 1024 * 1024 * 1024 - 1))   # GitHub limit: below 2 GiB

if [ -z "$TAG" ]; then
  echo "Usage: $0 TAG [--zip]   (e.g. $0 v1.0.0)"
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh not found. Install it with: brew install gh"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Not logged in. Please run first: gh auth login"
  exit 1
fi

# Change to the folder this script lives in
cd "$(dirname "$0")"

if ! gh repo view >/dev/null 2>&1; then
  echo "No GitHub repository detected here."
  exit 1
fi

filesize() {
  stat -f%z "$1" 2>/dev/null || stat -c%s "$1"
}

human() {
  du -h "$1" | cut -f1
}

# Remove an incomplete or failed upload with the same name.
# Fails if there is none, which is fine.
drop_asset() {
  gh release delete-asset "$TAG" "$1" -y >/dev/null 2>&1 || true
}

# Collect audio files in this folder (no subfolders)
FILES=()
while IFS= read -r -d '' f; do
  FILES+=("${f#./}")
done < <(find . -maxdepth 1 -type f \( \
    -iname '*.wav' -o -iname '*.aif' -o -iname '*.aiff' \
    -o -iname '*.flac' -o -iname '*.mp3' -o -iname '*.ogg' \
    -o -iname '*.m4a' \) -print0 | sort -z)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "No audio files found in: $PWD"
  exit 1
fi

echo "Folder: $PWD"
echo "Found: ${#FILES[@]} audio files"
for f in "${FILES[@]}"; do
  echo "  $f  ($(human "$f"))"
done
echo

# Create the release if it does not exist yet
if ! gh release view "$TAG" >/dev/null 2>&1; then
  echo "Release $TAG does not exist yet, creating it ..."
  gh release create "$TAG" --title "$TAG" --notes ""
fi

# Option 1: as a ZIP containing a folder "Audio"
if [ "$MODE" = "--zip" ]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  mkdir "$TMP/Audio"
  for f in "${FILES[@]}"; do
    ln -s "$PWD/$f" "$TMP/Audio/$f"
  done
  echo "[1/3] Creating Audio.zip (no compression) ..."
  (cd "$TMP" && zip -0 -r Audio.zip Audio)
  size="$(filesize "$TMP/Audio.zip")"
  echo "[2/3] Zip finished: $(human "$TMP/Audio.zip")"
  if [ "$size" -gt "$MAX" ]; then
    echo "Audio.zip is larger than 2 GiB and would be rejected."
    echo "Upload without --zip or split it into several parts."
    exit 1
  fi
  drop_asset "Audio.zip"
  echo "[3/3] Uploading Audio.zip. There is no progress display,"
  echo "      this can take minutes on a slow connection."
  if gh release upload "$TAG" "$TMP/Audio.zip" --clobber; then
    echo "Done: Audio.zip uploaded to release $TAG."
    exit 0
  fi
  echo "Upload failed."
  drop_asset "Audio.zip"
  exit 1
fi

# Option 2: upload files one by one
ok=0
failed=()
n=0
for f in "${FILES[@]}"; do
  n=$((n + 1))
  size="$(filesize "$f")"
  if [ "$size" -gt "$MAX" ]; then
    echo "Skipped (over 2 GiB): $f"
    failed+=("$f")
    continue
  fi
  echo "[$n/${#FILES[@]}] Uploading: $f ($(human "$f")) ..."
  drop_asset "$(basename "$f")"
  if gh release upload "$TAG" "$f" --clobber; then
    echo "      done."
    ok=$((ok + 1))
  else
    echo "      FAILED."
    drop_asset "$(basename "$f")"
    failed+=("$f")
  fi
done

echo
echo "Uploaded: $ok of ${#FILES[@]}"
if [ "${#failed[@]}" -gt 0 ]; then
  echo "Not uploaded:"
  printf '  %s\n' "${failed[@]}"
  echo "You can simply run the script again."
  exit 1
fi
