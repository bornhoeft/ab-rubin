#!/bin/bash
# upload-audio.sh
# Lädt alle Audiodateien aus dem Ordner, in dem dieses Skript
# liegt, in ein GitHub-Release hoch.
#
# Aufruf (im Terminal, im Ordner "tracks"):
#   ./upload-audio.sh v1.0.0          Dateien einzeln hochladen
#   ./upload-audio.sh v1.0.0 --zip    alles als Audio.zip hochladen
#
# Voraussetzung: gh ist installiert und angemeldet
#   brew install gh && gh auth login

set -euo pipefail

TAG="${1:-}"
MODE="${2:-}"
MAX=$((2 * 1024 * 1024 * 1024 - 1))   # GitHub: unter 2 GiB

if [ -z "$TAG" ]; then
  echo "Aufruf: $0 TAG [--zip]   (z. B. $0 v1.0.0)"
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh nicht gefunden. Installation: brew install gh"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Nicht angemeldet. Bitte zuerst: gh auth login"
  exit 1
fi

# In den Ordner wechseln, in dem das Skript liegt
cd "$(dirname "$0")"

if ! gh repo view >/dev/null 2>&1; then
  echo "Hier wurde kein GitHub-Repository erkannt."
  exit 1
fi

filesize() {
  stat -f%z "$1" 2>/dev/null || stat -c%s "$1"
}

human() {
  du -h "$1" | cut -f1
}

# Unvollständigen oder fehlgeschlagenen Upload gleichen Namens
# entfernen. Schlägt fehl, wenn es keinen gibt, das ist in Ordnung.
drop_asset() {
  gh release delete-asset "$TAG" "$1" -y >/dev/null 2>&1 || true
}

# Audiodateien in diesem Ordner einsammeln (ohne Unterordner)
FILES=()
while IFS= read -r -d '' f; do
  FILES+=("${f#./}")
done < <(find . -maxdepth 1 -type f \( \
    -iname '*.wav' -o -iname '*.aif' -o -iname '*.aiff' \
    -o -iname '*.flac' -o -iname '*.mp3' -o -iname '*.ogg' \
    -o -iname '*.m4a' \) -print0 | sort -z)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "Keine Audiodateien gefunden in: $PWD"
  exit 1
fi

echo "Ordner: $PWD"
echo "Gefunden: ${#FILES[@]} Audiodateien"
for f in "${FILES[@]}"; do
  echo "  $f  ($(human "$f"))"
done
echo

# Release anlegen, falls es noch nicht existiert
if ! gh release view "$TAG" >/dev/null 2>&1; then
  echo "Release $TAG existiert noch nicht, wird angelegt ..."
  gh release create "$TAG" --title "$TAG" --notes ""
fi

# Variante 1: als ZIP mit Ordner "Audio"
if [ "$MODE" = "--zip" ]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  mkdir "$TMP/Audio"
  for f in "${FILES[@]}"; do
    ln -s "$PWD/$f" "$TMP/Audio/$f"
  done
  echo "[1/3] Erstelle Audio.zip (ohne Kompression) ..."
  (cd "$TMP" && zip -0 -r Audio.zip Audio)
  size="$(filesize "$TMP/Audio.zip")"
  echo "[2/3] Zip fertig: $(human "$TMP/Audio.zip")"
  if [ "$size" -gt "$MAX" ]; then
    echo "Audio.zip ist größer als 2 GiB und wird abgelehnt."
    echo "Ohne --zip hochladen oder in mehrere Teile aufteilen."
    exit 1
  fi
  drop_asset "Audio.zip"
  echo "[3/3] Lade Audio.zip hoch. Es gibt keine Fortschritts-"
  echo "      anzeige, das kann bei langsamer Leitung Minuten dauern."
  if gh release upload "$TAG" "$TMP/Audio.zip" --clobber; then
    echo "Fertig: Audio.zip in Release $TAG hochgeladen."
    exit 0
  fi
  echo "Upload fehlgeschlagen."
  drop_asset "Audio.zip"
  exit 1
fi

# Variante 2: Dateien einzeln hochladen
ok=0
failed=()
n=0
for f in "${FILES[@]}"; do
  n=$((n + 1))
  size="$(filesize "$f")"
  if [ "$size" -gt "$MAX" ]; then
    echo "Übersprungen (über 2 GiB): $f"
    failed+=("$f")
    continue
  fi
  echo "[$n/${#FILES[@]}] Lade hoch: $f ($(human "$f")) ..."
  drop_asset "$(basename "$f")"
  if gh release upload "$TAG" "$f" --clobber; then
    echo "      fertig."
    ok=$((ok + 1))
  else
    echo "      FEHLGESCHLAGEN."
    drop_asset "$(basename "$f")"
    failed+=("$f")
  fi
done

echo
echo "Hochgeladen: $ok von ${#FILES[@]}"
if [ "${#failed[@]}" -gt 0 ]; then
  echo "Nicht hochgeladen:"
  printf '  %s\n' "${failed[@]}"
  echo "Das Skript lässt sich einfach erneut starten."
  exit 1
fi
