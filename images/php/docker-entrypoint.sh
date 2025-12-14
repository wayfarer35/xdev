#!/bin/sh
set -e

# docker-entrypoint.sh (POSIX sh)
# 启动时根据 ENABLE_EXTENSIONS 环境变量启用预安装的 PHP 扩展。
# ENABLE_EXTENSIONS 可以是以逗号分隔的扩展名列表，或者设置为 "all" 来启用全部。

PHP_CONF_DIR="/usr/local/etc/php/conf.d"
AVAILABLE_DIR="/opt/php-extensions-available"
MAPPING_FILE="$AVAILABLE_DIR/extensions.map"

# Ensure conf.d exists
mkdir -p "$PHP_CONF_DIR"

# Load mapping (name=filename) into plain files under /tmp for lookup
# We'll use a simple lookup function that greps the mapping file
lookup_map() {
  name="$1"
  if [ -f "$MAPPING_FILE" ]; then
    awk -F= -v key="$name" '$1==key {print $2; exit}' "$MAPPING_FILE"
  fi
}

# Fallback: derive short name from ini file content
derive_shortname() {
  fpath="$1"
  sed -n -e 's/^[[:space:]]*extension[[:space:]]*=[[:space:]]*\(.*\)/\1/p' -e 's/^[[:space:]]*zend_extension[[:space:]]*=[[:space:]]*\(.*\)/\1/p' "$fpath" | sed -E 's/.*/\L&/' | sed -E 's/.*\\/([^/]+)\\.so$/\1/' | sed -E 's/\\.so$//' | head -n1
}

# Helper: enable one extension by creating symlink (preserve original filename)
enable_ext() {
  ext="$1"
  file="$(lookup_map "$ext")"
  if [ -n "$file" ] && [ -f "$AVAILABLE_DIR/$file" ]; then
    ln -sf "$AVAILABLE_DIR/$file" "$PHP_CONF_DIR/$file"
    echo "[entrypoint] enabled extension: $ext -> $file"
    return 0
  fi
  # fallback: try to find a matching file by pattern
  for f in "$AVAILABLE_DIR"/*"$ext"*.ini "$AVAILABLE_DIR"/*"-$ext".ini "$AVAILABLE_DIR"/${ext}.ini; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    ln -sf "$f" "$PHP_CONF_DIR/$base"
    echo "[entrypoint] enabled extension (fallback): $ext -> $base"
    return 0
  done
  # try to match by derived shortname
  for f in "$AVAILABLE_DIR"/*.ini; do
    [ -f "$f" ] || continue
    short=$(derive_shortname "$f")
    if [ "$short" = "$ext" ]; then
      base=$(basename "$f")
      ln -sf "$f" "$PHP_CONF_DIR/$base"
      echo "[entrypoint] enabled extension (derived): $ext -> $base"
      return 0
    fi
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
      # split by comma (POSIX-safe)
      OLD_IFS=$IFS
      IFS=','
      for e in $ENABLE_EXTENSIONS; do
        e_trim=$(echo "$e" | tr -d '\r' | sed -e 's/^\s*//' -e 's/\s*$//')
        [ -z "$e_trim" ] && continue
        enable_ext "$e_trim"
      done
      IFS=$OLD_IFS
      ;;
  esac
fi

# If no args provided, try php-fpm then php; otherwise execute whatever the user passed
if [ "$#" -eq 0 ]; then
  if command -v php-fpm >/dev/null 2>&1; then
    exec php-fpm
  elif command -v php >/dev/null 2>&1; then
    # fall back to php CLI
    exec php -a
  else
    echo "Error: neither php-fpm nor php found in PATH" >&2
    exit 127
  fi
else
  exec "$@"
fi
