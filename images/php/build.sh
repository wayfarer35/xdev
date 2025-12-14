#!/usr/bin/env bash
set -e

# PHP Versions
PHP_VERSIONS=("8.5" "8.4" "8.3" "8.2" "8.1" "8.0" "7.4" "7.3" "7.2" "7.1" "7.0" "5.6" "5.5")
# PHP Modes
MODES=("fpm" "cli")

# PHP image official versions and their available OS
declare -A PHP_OS_MAP
PHP_OS_MAP["5.5"]="alpine"
PHP_OS_MAP["5.6"]="alpine stretch jessie"
PHP_OS_MAP["8.5"]="alpine bookworm trixie"
PHP_OS_MAP["7.0"]="alpine stretch jessie"
PHP_OS_MAP["7.1"]="alpine stretch jessie"
PHP_OS_MAP["7.2"]="alpine stretch buster"
PHP_OS_MAP["7.3"]="alpine stretch buster bullseye"
PHP_OS_MAP["7.4"]="alpine buster bullseye"
PHP_OS_MAP["8.0"]="alpine buster bullseye"
PHP_OS_MAP["8.1"]="alpine buster bullseye bookworm trixie"
PHP_OS_MAP["8.2"]="alpine buster bullseye bookworm trixie"
PHP_OS_MAP["8.3"]="alpine bullseye bookworm trixie"
PHP_OS_MAP["8.4"]="alpine bullseye bookworm trixie"
PHP_OS_MAP["8.5"]="alpine bookworm trixie"

usage() {
        cat <<'EOF'
Usage: build.sh -v <php_version> -m <mode> -o <os> [options]

Required:
    -v <php_version>    PHP version. Supported: ${PHP_VERSIONS[*]}
    -m <mode>           Mode: ${MODES[*]}
    -o <os>             OS for the PHP image (depends on PHP version)

Options (mutually exclusive installers):
    --extensions="a b c"   Explicit space- or comma-separated list of extensions to install (overrides other selection).
    --exclude="a b c"      Exclude these extensions from the default full raw list (space- or comma-separated).

Other options:
    -d, --dry-run                 Print the docker build command and selected extensions, do not execute.
    --fail-on-generate            Exit with error if auto-generation of all-extensions.raw fails
    -h, --help                Show this help and exit

Examples:
    build.sh -v 8.4 -m fpm -o bullseye            # install default (all from all-extensions.raw)
    build.sh -v 8.4 -m fpm -o bullseye --exclude="xdebug xhprof"
    build.sh -v 8.4 -m fpm -o bullseye --extensions="pdo_mysql,redis"
    build.sh -v 8.4 -m fpm -o bullseye --dry-run
EOF
        exit 1
}

# parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v)
            PHP_VERSION="$2"; shift 2;;
        -m)
            MODE="$2"; shift 2;;
        -o)
            OS="$2"; shift 2;;
        --extensions=*)
            SELECT_EXTENSIONS="${1#*=}"; shift;;
        --exclude=*)
            EXCLUDE_LIST="${1#*=}"; shift;;
        -d|--dry-run)
            DRY_RUN=1; shift;;
        --fail-on-generate)
            FAIL_ON_GENERATE=1; shift;;
        -h|--help)
            usage;;
        *)
            echo "Unknown argument: $1" >&2; usage;;
    esac
done

# If PHP version not provided, prompt interactively
if [[ -z "$PHP_VERSION" ]]; then
    echo "Select PHP version:"
    select v in "${PHP_VERSIONS[@]}"; do
        PHP_VERSION=$v
        break
    done
fi

# Available PHP versions
PHP_VERSIONS=("8.5" "8.4" "8.3" "8.2" "8.1" "8.0" "7.4" "7.3" "7.2" "7.1" "7.0" "5.6" "5.5")
# Available modes (optional)
MODES=("fpm" "cli")

# Available OS values for each PHP official image version
# MODE is optional; if not provided it will be empty and image tag/build-arg will omit it

# Compute available OS list for the chosen PHP version and default OS if not provided
AVAILABLE_OS=(${PHP_OS_MAP[$PHP_VERSION]})
if [[ -z "$OS" ]]; then
    # default to the first entry in the map for this PHP version
    OS=${AVAILABLE_OS[0]}
fi

# If MODE was provided, validate it; if empty that's acceptable
if [[ -n "$MODE" ]] && [[ ! " ${MODES[*]} " =~ " $MODE " ]]; then
    echo "Error: Unsupported mode $MODE"
    exit 1
fi


# Read single merged raw file and compute extensions for this PHP_VERSION + OS
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXT_DIR="$SCRIPT_DIR/extensions"
RAW_FILE="$EXT_DIR/all-extensions.raw"

# Ensure RAW_FILE exists: if missing, try to run the bundled generator script
if [ ! -f "$RAW_FILE" ]; then
    GENERATOR="$SCRIPT_DIR/generate-extension-raw.sh"
    if [ -f "$GENERATOR" ]; then
        echo "all-extensions.raw not found; attempting to generate using $GENERATOR"
        if [ -x "$GENERATOR" ]; then
            if ! "$GENERATOR"; then
                echo "Warning: generator $GENERATOR failed" >&2
            fi
        else
            if ! bash "$GENERATOR"; then
                echo "Warning: generator $GENERATOR failed" >&2
            fi
        fi
        if [ -f "$RAW_FILE" ]; then
            echo "Generated $RAW_FILE"
        else
            echo "Warning: raw file $RAW_FILE still missing after generation attempt; no extensions will be selected by list" >&2
            if [ -n "${FAIL_ON_GENERATE:-}" ]; then
                echo "Error: generation failed and --fail-on-generate specified" >&2
                exit 2
            fi
        fi
    else
            echo "Warning: raw file $RAW_FILE not found and no generator present; no extensions will be selected by list" >&2
            if [ -n "${FAIL_ON_GENERATE:-}" ]; then
                echo "Error: no generator present and --fail-on-generate specified" >&2
                exit 2
            fi
    fi
fi

# parse raw lines: ext v1 v2 ... [| blocked=os1,os2]
# Priority: explicit SELECT_EXTENSIONS (via --extensions) already wins
if [ -z "${SELECT_EXTENSIONS:-}" ] && [ -f "$RAW_FILE" ]; then
    want=()
    while IFS= read -r l; do
        [[ -z "$l" ]] && continue
        [[ "$l" =~ ^# ]] && continue
        # split on '|' to separate blocked
        left=$(echo "$l" | cut -d'|' -f1)
        right=$(echo "$l" | sed -n 's/.*|\s*//p' || true)
        read -ra toks <<< "$left"
        ext=${toks[0]}
        versions=("")
        if [ ${#toks[@]} -gt 1 ]; then
            versions=("${toks[@]:1}")
        fi
        # check version membership
        ok=0
        for v in "${versions[@]}"; do
            if [ "$v" = "$PHP_VERSION" ]; then ok=1; break; fi
        done
        if [ $ok -eq 0 ]; then
            continue
        fi
        # check blocked list
        blocked=""
        if [ -n "$right" ] && echo "$right" | grep -q 'blocked='; then
            blocked=$(echo "$right" | sed -E 's/.*blocked=//')
        fi
        skip=0
        if [ -n "$blocked" ]; then
            IFS=',' read -ra btokens <<< "$blocked"
            for b in "${btokens[@]}"; do
                b=$(echo "$b" | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//')
                # token like 7.2-alpine or alpine3.10 or just buster
                if [[ "$b" == *"-"* ]]; then
                    ver_part="${b%%-*}"
                    os_part="${b#*-}"
                    if [ "$ver_part" = "$PHP_VERSION" ]; then
                        if [[ "$OS" = "$os_part" || "$OS" == "$os_part"* || "$os_part" == "$OS"* ]]; then
                            skip=1; break
                        fi
                    fi
                else
                    # token might be a php version or an os (alpine, alpine3.10, buster)
                    if [ "$b" = "$PHP_VERSION" ]; then
                        skip=1; break
                    fi
                    if [[ "$OS" = "$b" || "$OS" == "$b"* || "$b" == "$OS"* ]]; then
                        skip=1; break
                    fi
                fi
            done
        fi
        if [ $skip -eq 0 ]; then
            want+=("$ext")
        fi
    done < "$RAW_FILE"
    # dedupe while preserving order
    # if EXCLUDE_LIST provided, filter those out
    if [ -n "${EXCLUDE_LIST:-}" ]; then
        # normalize exclude into newline list
        excl=$(echo "$EXCLUDE_LIST" | tr ',' ' ' | tr ' ' '\n' | sed '/^$/d')
        # build associative to speed-up membership
        declare -A exmap
        while IFS= read -r e; do exmap["$e"]=1; done <<< "$excl"
        filtered=()
        for x in "${want[@]}"; do
            if [ -z "${exmap[$x]:-}" ]; then
                filtered+=("$x")
            fi
        done
        want=("${filtered[@]}")
    fi
    SELECT_EXTENSIONS=$(printf "%s\n" "${want[@]}" | awk '!seen[$0]++{print}' | tr '\n' ' ' | sed -e 's/^ \+//' -e 's/ \+$//')
fi


# Validate OS
if [[ ! " ${AVAILABLE_OS[*]} " =~ " $OS " ]]; then
    echo "Error: Unsupported OS $OS for PHP $PHP_VERSION"
    echo "Available: ${AVAILABLE_OS[*]}"
    exit 1
fi

# Compute PHP_TAG to handle optional MODE (e.g. "8.4-fpm-bullseye" or "8.4-bullseye")
if [ -n "${MODE:-}" ]; then
    PHP_TAG="${PHP_VERSION}-${MODE}-${OS}"
else
    PHP_TAG="${PHP_VERSION}-${OS}"
fi

# Build image tag using PHP_TAG
IMAGE_TAG="xdev:php-${PHP_TAG}"
echo "Building Docker image: $IMAGE_TAG"

DOCKER_CMD="docker"
if ! docker info >/dev/null 2>&1; then
    if command -v sudo >/dev/null 2>&1; then
        DOCKER_CMD="sudo docker"
    else
        echo "Error: docker requires root privileges. Please add your user to the docker group or run with sudo."
        exit 1
    fi
fi

# Compute PHP_TAG to handle optional MODE (e.g. "8.4-fpm-bullseye" or "8.4-bullseye")
if [ -n "${MODE:-}" ]; then
    PHP_TAG="${PHP_VERSION}-${MODE}-${OS}"
else
    PHP_TAG="${PHP_VERSION}-${OS}"
fi

BUILD_CMD="$DOCKER_CMD build --build-arg PHP_TAG=\"$PHP_TAG\""
if [ -n "$SELECT_EXTENSIONS" ]; then
    BUILD_CMD="$BUILD_CMD --build-arg SELECT_EXTENSIONS=\"$SELECT_EXTENSIONS\""
fi

BUILD_CMD="$BUILD_CMD -t $IMAGE_TAG ."

if [ -n "${DRY_RUN:-}" ]; then
    echo "DRY-RUN:" 
    echo "$BUILD_CMD"
else
    # Execute the built command
    eval "$BUILD_CMD"
fi
