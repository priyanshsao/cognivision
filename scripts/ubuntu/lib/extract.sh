# shellcheck shell=bash
#

USAGE() {
    cat >&2 <<EOF
Usage: $0 <go-version> <python-version> <redis-version>

Example:
  $0 1.25.0 3.12 7.0

Environment:
  ON_NEWER_VERSION=keep|exact   answer the "newer version found" question
                                without prompting (default: ask)
  NO_COLOR=1                    disable colours
EOF
}

EXTRACT() {
    case "${1:-}" in
        -h|--help) USAGE; exit 0 ;;
    esac

    if [[ $# -ne 3 ]]; then
        USAGE
        exit 2
    fi

    goVersion="$1"
    pythonVersion="$2"
    redisVersion="$3"

    [[ "$goVersion" =~ $GO_VERSION_REGEX ]] || {
        USAGE
        END "Invalid Go version '$goVersion' (expected e.g. 1.25.0)"
    }

    [[ "$pythonVersion" =~ $PYTHON_VERSION_REGEX ]] || {
        USAGE
        END "Invalid Python version '$pythonVersion' (expected e.g. 3.12)"
    }

    [[ "$redisVersion" =~ $REDIS_VERSION_REGEX ]] || {
        USAGE
        END "Invalid Redis version '$redisVersion' (expected e.g. 7.0)"
    }

    case "$NEWER_POLICY" in
        ask|keep|exact) ;;
        *) END "ON_NEWER_VERSION must be 'keep' or 'exact' (got '$NEWER_POLICY')" ;;
    esac

    pythonCmd="python${pythonVersion}"
}