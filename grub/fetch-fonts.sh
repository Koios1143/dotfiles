#!/usr/bin/env bash
# Download the TTFs the YoRHa GRUB theme is built from.
#
# The design calls for IBM Plex Mono (ExtraLight/Light/Regular/SemiBold) and
# Chakra Petch Regular for the countdown digits. Both are OFL-licensed; we pull
# the static instances straight from google/fonts rather than depending on a
# system font package, so the build is reproducible on a bare machine.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="$here/vendor/fonts"
base="https://raw.githubusercontent.com/google/fonts/main/ofl"

files=(
  "ibmplexmono/IBMPlexMono-ExtraLight.ttf"
  "ibmplexmono/IBMPlexMono-Light.ttf"
  "ibmplexmono/IBMPlexMono-Regular.ttf"
  "ibmplexmono/IBMPlexMono-SemiBold.ttf"
  "ibmplexmono/OFL.txt"
  "chakrapetch/ChakraPetch-Regular.ttf"
  "chakrapetch/OFL.txt"
)

mkdir -p "$dest/ibmplexmono" "$dest/chakrapetch"

for rel in "${files[@]}"; do
  out="$dest/$rel"
  if [[ -s "$out" ]]; then
    printf '  have  %s\n' "$rel"
    continue
  fi
  printf '  get   %s\n' "$rel"
  curl -sfL --retry 3 --retry-all-errors -o "$out.part" "$base/$rel"
  mv "$out.part" "$out"
done

echo "fonts ready in $dest"
