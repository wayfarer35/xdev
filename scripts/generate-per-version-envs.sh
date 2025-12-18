#!/usr/bin/env bash
set -euo pipefail

RAW="images/php/extensions/all-extensions.raw"
OUTDIR="examples"
mkdir -p "$OUTDIR"

# versions to generate (match services in docker-compose)
VERSIONS=(8.5 8.4 8.3 8.2 8.1 8.0 7.4 7.3 7.2 7.1 7.0 5.6 5.5)

for v in "${VERSIONS[@]}"; do
  fname="$OUTDIR/.php-${v}.env"
  echo "# Per-service env for PHP ${v}" > "$fname"
  echo "# Set EXTENSION_<NAME>=1 to enable; default 0" >> "$fname"
  echo "# Generated from ${RAW}" >> "$fname"
  echo >> "$fname"
  # parse raw file: extension supported for version appears as a token
  awk -v ver="$v" 'BEGIN{FS="[[:space:]]+"} /^[[:space:]]*#/ {next} /^[[:space:]]*$/ {next} {ext=$1; for(i=2;i<=NF;i++){ if($i==ver){ print ext; break}} }' "$RAW" | sort -u | while read -r ext; do
    # normalize to uppercase and replace non-alnum with underscore
    envname=$(echo "$ext" | tr '[:lower:]' '[:upper:]' | sed -E 's/[^A-Z0-9]+/_/g')
    printf "EXTENSION_%s=0\n" "$envname" >> "$fname"
  done
  echo "Generated $fname"
done
