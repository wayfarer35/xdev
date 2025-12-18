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
    rm -rf /usr/local/lib/pkgconfig /usr/local/share/doc /usr/local/share/man /usr/local/share/locale 2>/dev/null || true; 


# Final runtime stage: smaller image
FROM php:${PHP_TAG}

# Copy prepared extensions and mapping from builder
COPY --from=builder /opt/php-extensions-available /opt/php-extensions-available

# Install collected extension .so files into the standard PHP extensions dir
RUN set -e; \
    if [ -d /opt/php-extensions-available/lib ]; then \
        echo "Copying extension .so files into /usr/local/lib/php/extensions"; \
        mkdir -p /usr/local/lib/php/extensions; \
        cp -a /opt/php-extensions-available/lib/. /usr/local/lib/php/extensions/ || true; \
    fi; \
    # update dynamic linker cache
    if command -v ldconfig >/dev/null 2>&1; then ldconfig || true; else export LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH:-}; fi; \
    # runtime checks: list enabled modules and check shared lib dependencies for missing symbols
    if command -v php >/dev/null 2>&1; then \
        php -m > /opt/php-extensions-available/php-modules.txt || true; \
    fi; \
    echo "Checking .so dependencies (ldd) for missing libraries..."; \
    > /opt/php-extensions-available/missing-libs.log; \
    if command -v ldd >/dev/null 2>&1; then \
        # collect any missing library names from ldd (one invocation per .so)
        find /usr/local/lib/php/extensions -type f -name '*.so' -print0 | xargs -0 -n1 -I{} sh -c 'ldd "$1" 2>/dev/null | sed -n "s/.*=> \(.*not found\).*/\1/p" | sed -n "/^/p"' _ '{}' >> /opt/php-extensions-available/missing-libs.log || true; \
        # more detailed scan: for each so, record missing libs per file (avoid process-substitution)
        find /usr/local/lib/php/extensions -type f -name '*.so' -print0 | xargs -0 -n1 -I{} sh -c 'miss=$(ldd "$1" 2>/dev/null | grep -E "not found" || true); if [ -n "$miss" ]; then echo "--- $1 ---" >> /opt/php-extensions-available/missing-libs.log; echo "$miss" >> /opt/php-extensions-available/missing-libs.log; fi' _ '{}' || true; \
    fi; \
    if [ -s /opt/php-extensions-available/missing-libs.log ]; then \
        echo "Warning: missing shared libs detected; see /opt/php-extensions-available/missing-libs.log"; \
        sed -n '1,200p' /opt/php-extensions-available/missing-libs.log || true; \
    else \
        echo "All extension shared libs appear satisfied."; \
        rm -f /opt/php-extensions-available/missing-libs.log || true; \
    fi; \
    # cleanup: remove copied lib directory (we keep ini files and extensions.map for introspection)
    rm -rf /opt/php-extensions-available/lib || true; \
    # keep only ini files and extensions.map under /opt/php-extensions-available
    find /opt/php-extensions-available -maxdepth 1 -type f ! -name '*.ini' ! -name 'extensions.map' -print0 | xargs -0 -r rm -f || true

# Ensure entrypoint exists and is executable
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
