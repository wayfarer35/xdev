ARG PHP_VERSION=8.4
ARG PHP_MODE=fpm
ARG OS=bookworm

FROM php:$PHP_VERSION-$PHP_MODE-$OS

COPY --from=ghcr.io/mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

ARG INSTALL_DEBUG_EXTENSIONS=true
ARG SELECT_EXTENSIONS=""
ARG INSTALL_DEFAULT_EXTENSIONS=false

# Install extensions: if SELECT_EXTENSIONS is set, install only those; otherwise skip installation
COPY extensions/default.list /tmp/default.list

RUN if [ -n "$SELECT_EXTENSIONS" ]; then \
        # allow comma or space separated lists passed via build arg
        set -e; \
        SEL=$(echo "$SELECT_EXTENSIONS" | tr ',' ' '); \
        install-php-extensions $SEL; \
        if [ "$INSTALL_DEBUG_EXTENSIONS" = "true" ]; then \
            install-php-extensions xdebug xhprof; \
        fi; \
    else \
        if [ "$INSTALL_DEFAULT_EXTENSIONS" = "true" ] && [ -f /tmp/default.list ]; then \
            echo "INSTALL_DEFAULT_EXTENSIONS=true: installing defaults from /tmp/default.list"; \
            install-php-extensions $(grep -v '^\s*#' /tmp/default.list | tr '\n' ' '); \
            if [ "$INSTALL_DEBUG_EXTENSIONS" = "true" ]; then \
                install-php-extensions xdebug xhprof; \
            fi; \
        else \
            echo "No SELECT_EXTENSIONS provided and INSTALL_DEFAULT_EXTENSIONS!=true; skipping extension installation"; \
        fi; \
    fi

# Move all generated ini files into a managed location and create a mapping
RUN mkdir -p /opt/php-extensions-available && \
        > /opt/php-extensions-available/extensions.map && \
        for f in /usr/local/etc/php/conf.d/*.ini; do \
            if [ -f "$f" ]; then \
                base=$(basename "$f"); \
                # copy with original filename to preserve load order (prefixes)
                cp "$f" "/opt/php-extensions-available/$base"; \
                # attempt to derive short name
                ext=$(sed -n -e 's/^[[:space:]]*extension[[:space:]]*=[[:space:]]*\(.*\)/\1/p' -e 's/^[[:space:]]*zend_extension[[:space:]]*=[[:space:]]*\(.*\)/\1/p' "$f" | sed -E 's/.*/\L&/' | sed -E 's/.*/\0/' | sed -E 's/.*\\/([^/]+)\\.so$/\\1/' | sed -E 's/\\.so$//' | head -n1); \
                if [ -z "$ext" ]; then \
                    ext=$(echo "$base" | sed -E 's/^[0-9]+-//' | sed -E 's/\.ini$//'); \
                fi; \
                # write mapping: shortname=originalfilename
                echo "$ext=$base" >> /opt/php-extensions-available/extensions.map; \
            fi; \
        done && \
        rm -f /usr/local/etc/php/conf.d/*.ini || true

# Add entrypoint to enable extensions at container start
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
