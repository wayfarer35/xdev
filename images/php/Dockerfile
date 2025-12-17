ARG PHP_TAG=8.4-fpm-bookworm

# Builder stage: compile/install extensions with build deps
FROM php:${PHP_TAG} AS builder

# Install dependencies for building extensions
ADD --chmod=0755 https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/

ARG SELECT_EXTENSIONS=""

# Prepare build deps and install extensions in single RUN to avoid leftover layers
RUN set -eux; \
    if [ -n "$SELECT_EXTENSIONS" ]; then \
        SEL=$(echo "$SELECT_EXTENSIONS" | tr ',' ' '); \
        echo "[builder] Installing extensions: $SEL"; \
        # Let install-php-extensions handle required system packages when possible
        # Fail the build if extension installation fails
        CFLAGS="${CFLAGS:-} -Wno-error" \
        CXXFLAGS="${CXXFLAGS:-} -Wno-error" \
        IPE_DEBUG=0 \
        IPE_ICU_EN_ONLY=1 \
        IPE_ASPELL_LANGUAGES='en' \
        install-php-extensions $SEL; \
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
    # strip extension shared objects to reduce size and remove static/aux files
    if command -v strip >/dev/null 2>&1; then \
        find /usr/local/lib/php/extensions -type f -name '*.so' -print0 | xargs -0 -r strip --strip-unneeded || true; \
        find /opt/php-extensions-available/lib -type f -name '*.so' -print0 | xargs -0 -r strip --strip-unneeded || true; \
    fi; \
    # remove static libs, libtool archives and pkgconfig leftovers
    find /usr/local -type f \( -name '*.a' -o -name '*.la' \) -delete 2>/dev/null || true; \
    rm -rf /usr/local/lib/pkgconfig /usr/local/share/doc /usr/local/share/man /usr/local/share/locale 2>/dev/null || true; \
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
    fi;


# Final runtime stage: smaller image
FROM php:${PHP_TAG}

# Copy prepared extensions and mapping from builder
COPY --from=builder /opt/php-extensions-available /opt/php-extensions-available
COPY --from=builder /opt/php-extensions-available/runtime /opt/php-extensions-available/runtime

# Merge collected runtime libs into /usr/local/lib (preserve symlinks) and clean up
RUN set -e; \
    if [ -d /opt/php-extensions-available/runtime ]; then \
        echo "Merging collected runtime libs into /usr/local/lib"; \
        cp -a /opt/php-extensions-available/runtime/. /usr/local/lib/ || true; \
        rm -rf /opt/php-extensions-available/runtime || true; \
        # remove redundant lib copies under /opt to reduce image size
        # keep /opt/php-extensions-available/lib and ini files for runtime inspection
        if command -v ldconfig >/dev/null 2>&1; then ldconfig || true; else export LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH:-}; fi; \
    fi

# Ensure entrypoint exists and is executable
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
