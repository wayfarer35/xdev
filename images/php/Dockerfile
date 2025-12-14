ARG PHP_TAG=8.4-fpm-bookworm

# Builder stage: compile/install extensions with build deps
FROM php:${PHP_TAG} as builder


COPY --from=ghcr.io/mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

ARG SELECT_EXTENSIONS=""

# Prepare build deps and install extensions in single RUN to avoid leftover layers
RUN set -e; \
    if [ -n "$SELECT_EXTENSIONS" ]; then \
        SEL=$(echo "$SELECT_EXTENSIONS" | tr ',' ' '); \
        echo "[builder] Installing extensions: $SEL"; \
    # Let install-php-extensions handle required system packages when possible
    install-php-extensions $SEL || true; \
    else \
        echo "[builder] No SELECT_EXTENSIONS provided; skipping extension build"; \
    fi; \
    # collect generated ini files and create mapping
    mkdir -p /opt/php-extensions-available; \
    > /opt/php-extensions-available/extensions.map; \
    for f in /usr/local/etc/php/conf.d/*.ini; do \
        if [ -f "$f" ]; then \
            base=$(basename "$f"); \
            cp "$f" "/opt/php-extensions-available/$base"; \
            ext=$(sed -n -e 's/^[[:space:]]*extension[[:space:]]*=[[:space:]]*\(.*\)/\1/p' -e 's/^[[:space:]]*zend_extension[[:space:]]*=[[:space:]]*\(.*\)/\1/p' "$f" | sed -E 's/.*/\L&/' | sed -E 's/.*/\0/' | sed -E 's/.*\\/([^/]+)\\.so$/\\1/' | sed -E 's/\\.so$//' | head -n1); \
            if [ -z "$ext" ]; then \
                ext=$(echo "$base" | sed -E 's/^[0-9]+-//' | sed -E 's/\.ini$//'); \
            fi; \
            echo "$ext=$base" >> /opt/php-extensions-available/extensions.map; \
        fi; \
    done; \
    # try to collect extension .so files from common dirs
    mkdir -p /opt/php-extensions-available/lib; \
    cp -a /usr/local/lib/php/extensions/. /opt/php-extensions-available/lib/ 2>/dev/null || true; \
    # collect runtime shared libs referenced by extension .so files
    mkdir -p /opt/php-extensions-available/runtime; \
    if command -v ldd >/dev/null 2>&1; then \
        find /opt/php-extensions-available/lib -type f -name '*.so' -print0 | xargs -0 -n1 sh -c 'ldd "$0" 2>/dev/null | awk "/=>/ {print \$3} /ld-linux/ {print \$1}"' | sed '/^\s*$/d' | sort -u > /tmp/runtime-libs.list || true; \
        while IFS= read -r lib; do \
            if [ -n "$lib" ] && [ -f "$lib" ]; then \
                mkdir -p /opt/php-extensions-available/runtime/$(dirname "$lib"); \
                cp -L "$lib" "/opt/php-extensions-available/runtime/$lib" 2>/dev/null || true; \
            fi; \
        done < /tmp/runtime-libs.list || true; \
        rm -f /tmp/runtime-libs.list || true; \
    fi

# Final runtime stage: smaller image
FROM php:${PHP_TAG}

# Copy prepared extensions and mapping from builder
COPY --from=builder /opt/php-extensions-available /opt/php-extensions-available

# Copy only runtime libraries discovered during build
RUN set -e; \
    if [ -d /opt/php-extensions-available/runtime ]; then \
        echo "Copying runtime libs into /usr/local/lib"; \
        # copy preserving structure where possible
        cd /; \
        find /opt/php-extensions-available/runtime -type f -print0 | xargs -0 -I{} sh -c 'd=$(dirname "{}" | sed "s@/opt/php-extensions-available/runtime@@"); mkdir -p "$d"; cp "{}" "$d"' || true; \
        if command -v ldconfig >/dev/null 2>&1; then \
            ldconfig || true; \
        else \
            # ensure runtime path includes /usr/local/lib
            export LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH:-}; \
        fi; \
    fi

# Ensure entrypoint exists and is executable
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
