#!/usr/bin/env bash
#
# setup-ubuntu.sh - main pipeline.
#
# Usage:   ./scripts/setup-ubuntu.sh <go-version> <python-version> <redis-version>
# Example: ./scripts/setup-ubuntu.sh 1.25.0 3.12 7.0
#
# Naming: FUNCTIONS and readonly CONSTANTS are UPPER_SNAKE_CASE, variables are camelCase.

set -Eeuo pipefail

scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
libDir="$scriptDir/lib"

for lib in define terminal extract detect version helpers; do
    if [[ ! -r "$libDir/$lib.sh" ]]; then
        echo "ERROR: missing library file: $libDir/$lib.sh" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$libDir/$lib.sh"
done


PHASE_CHECK() {
    CHECK_DEP needGo     "Go"     CHECK_GO     "$goVersion"
    CHECK_DEP needPython "Python" CHECK_PYTHON "$pythonVersion"

    # A kept (newer) Python is reported as a command name; use it for the venv.
    if (( needPython == 0 )) && [[ -n "$foundCmd" ]]; then pythonCmd="$foundCmd"; fi
    CHECK_DEP needRedis  "Redis"  CHECK_REDIS  "$redisVersion"
}

PHASE_INSTALL() {
    if ! (( needGo || needPython || needRedis )); then return 0; fi

    ENSURE_SUDO
    RUN "Updating apt package index" "Package index updated" APT_GET update

    if (( needGo )); then
        if [[ -n "$(MISSING_SYSTEM_UTILITIES)" ]]; then
            RUN "Installing system utilities" "System utilities installed" INSTALL_SYSTEM_UTILITIES
        fi
        RUN "Installing Go $goVersion" "Go $goVersion installed" INSTALL_GO
    fi
    if (( needPython )); then
        RUN "Installing Python $pythonVersion" "Python $pythonVersion installed" INSTALL_PYTHON
        pythonCmd="python${pythonVersion}"
    fi
    if (( needRedis )); then
        RUN "Installing Redis $redisVersion" "Redis installed" INSTALL_REDIS
    fi
}

PHASE_VERIFY() {
    if (( needGo ));     then RUN "Verifying Go $goVersion"         "Go $goVersion verified"         CHECK_GO; fi
    if (( needPython )); then RUN "Verifying Python $pythonVersion" "Python $pythonVersion verified" CHECK_PYTHON; fi
    if (( needRedis ));  then RUN "Verifying Redis $redisVersion"   "Redis $redisVersion verified"   CHECK_REDIS; fi
}

PHASE_REDIS_SERVICE() {
    if (( needRedis )) || ! redis-cli ping 2>/dev/null | grep -qx PONG; then
        ENSURE_SUDO
        RUN "Starting Redis service" "Redis service running (PING ok)" START_REDIS
    else
        SUCCESS "Redis service already running (PING ok)"
    fi
}

PHASE_SUMMARY() {
    printf '\n'
    SUCCESS "Ubuntu setup completed successfully"
    if (( ${#keptNewer[@]} )); then
        WARN "Kept newer versions: ${keptNewer[*]}. They should work fine, but if something doesn't, rerun this script and choose [E] to install the exact versions."
    fi
    if (( needGo )); then
        INFO "Open a new shell (or run: source $GO_PROFILE_FILE) to get Go on your PATH."
    fi
}

# main script
MAIN() {
    EXTRACT "$@"

    tmpDir="$(mktemp -d)"
    outputFile="$tmpDir/output"
    : >"$outputFile"
    trap CLEANUP EXIT
    trap ON_INTERRUPT INT TERM
    trap 'ON_ERROR "$LINENO"' ERR

    DETECT
    export PATH="$GO_INSTALL_DIR/bin:$HOME/go/bin:$PATH"

    INFO "Requested versions: Go $goVersion, Python $pythonVersion, Redis $redisVersion"

    PHASE_CHECK
    PHASE_INSTALL
    PHASE_VERIFY
    PHASE_REDIS_SERVICE
    SETUP_PROJECT
    PHASE_SUMMARY
}

MAIN "$@"