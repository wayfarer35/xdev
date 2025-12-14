#!/usr/bin/env bash
set -e

# docker-entrypoint.sh
# 启动时根据 ENABLE_EXTENSIONS 环境变量启用预安装的 PHP 扩展。
# ENABLE_EXTENSIONS 可以是以逗号分隔的扩展名列表，或者设置为 "all" 来启用全部。

PHP_CONF_DIR="/usr/local/etc/php/conf.d"
AVAILABLE_DIR="/opt/php-extensions-available"
MAPPING_FILE="$AVAILABLE_DIR/extensions.map"

# Ensure conf.d exists
mkdir -p "$PHP_CONF_DIR"

# Load mapping (name=filename) into associative array
declare -A EXT_MAP
if [ -f "$MAPPING_FILE" ]; then
  while IFS='=' read -r name file; do
    # skip empty/comment lines
    [ -z "${name//[[:space:]]/}" ] && continue
    name=$(echo "$name" | tr -d ' \t\r')
    file=$(echo "$file" | tr -d ' \t\r')
    EXT_MAP["$name"]="$file"
  done < "$MAPPING_FILE"
fi

# Populate fallback mappings from available files (if mapping missing)
for f in "$AVAILABLE_DIR"/*.ini; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  # derive short name if not already mapped
  short=$(sed -n -e 's/^[[:space:]]*extension[[:space:]]*=[[:space:]]*\(.*\)/\1/p' -e 's/^[[:space:]]*zend_extension[[:space:]]*=[[:space:]]*\(.*\)/\1/p' "$f" | sed -E 's/.*/\L&/' | sed -E 's/.*\\/([^/]+)\\.so$/\1/' | sed -E 's/\\.so$//' | head -n1)
  if [ -z "$short" ]; then
    short=$(echo "$base" | sed -E 's/^[0-9]+-//' | sed -E 's/\.ini$//')
  fi
  if [ -n "$short" ] && [ -z "${EXT_MAP[$short]+_}" ]; then
    EXT_MAP["$short"]="$base"
  fi
done

# Helper: enable one extension by creating symlink (preserve original filename)
enable_ext() {
  local ext="$1"
  local file="${EXT_MAP[$ext]}"
  if [ -n "$file" ] && [ -f "$AVAILABLE_DIR/$file" ]; then
    ln -sf "$AVAILABLE_DIR/$file" "$PHP_CONF_DIR/$file"
    echo "[entrypoint] enabled extension: $ext -> $file"
    return 0
  fi
  # fallback: try to find a matching file by pattern
  for pat in "$AVAILABLE_DIR/"*"$ext"*.ini "$AVAILABLE_DIR/"*"-$ext".ini "$AVAILABLE_DIR/${ext}.ini"; do
    for f in $pat; do
      [ -f "$f" ] || continue
      base=$(basename "$f")
      ln -sf "$f" "$PHP_CONF_DIR/$base"
      echo "[entrypoint] enabled extension (fallback): $ext -> $base"
      return 0
    done
  done
  echo "[entrypoint] warning: extension ini not found for '$ext'" >&2
  return 1
}

# If ENABLE_EXTENSIONS not set, default to none (do nothing).
if [ -z "$ENABLE_EXTENSIONS" ]; then
  echo "[entrypoint] ENABLE_EXTENSIONS not set — no extensions will be enabled by default"
else
  case "$ENABLE_EXTENSIONS" in
    all|ALL)
      echo "[entrypoint] enabling all available extensions"
      for f in "$AVAILABLE_DIR"/*.ini; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .ini)
        enable_ext "$name"
      done
      ;;
    *)
      # split by comma
      IFS=',' read -ra EXTS <<< "$ENABLE_EXTENSIONS"
      for e in "${EXTS[@]}"; do
        e_trim=$(echo "$e" | tr -d '\r' | sed -e 's/^\s*//' -e 's/\s*$//')
        [ -z "$e_trim" ] && continue
        enable_ext "$e_trim"
      done
      ;;
  esac
fi

# If the first arg looks like php-fpm or php, exec it; otherwise execute whatever the user passed
if [ "$#" -eq 0 ]; then
  exec php-fpm
else
  exec "$@"
fi
