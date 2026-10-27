# shellcheck shell=bash
#
# Message formats
INFO() {
    printf '%b[setup]%b %s\n' "$CYAN" "$RESET" "$*"
}

SUCCESS() {
    printf '%b✓%b %s\n' "$GREEN" "$RESET" "$*"
}

WARN() {
    printf '%bWARNING:%b %s\n' "$YELLOW" "$RESET" "$*" >&2
}

END() {
    printf '%bERROR:%b %s\n' "$RED" "$RESET" "$*" >&2
    exit 1
}

# Terminal ctrls 
HIDE_TERM_CURSOR()   { printf '\033[?25l'; }
UNHIDE_TERM_CURSOR() { printf '\033[?25h'; }
CLEAR_LINE()         { printf '\033[2K'; }


# SPIN <pid> <message> : animate until the background process <pid> ends.
SPIN() {
    local frameIndex=0
    while kill -0 "$1" 2>/dev/null; do
        printf '\r'
        CLEAR_LINE
        printf '%b%s%b %s' "$CYAN" "${SPINNER_FRAMES[frameIndex % ${#SPINNER_FRAMES[@]}]}" "$RESET" "$2"
        frameIndex=$((frameIndex + 1))
        sleep "$SPINNER_INTERVAL"
    done
}

# Print a failed step with the full captured output, then exit.
RUN_FAILED() {
    printf '%b✗ %s failed%b\n' "$RED" "$1" "$RESET" >&2
    printf '%bERROR:%b %s\n' "$RED" "$RESET" "Details for debugging:" >&2

    if [[ -s "$outputFile" ]]; then
        sed 's/^/    /' "$outputFile" >&2
    else
        echo "    (no output captured)" >&2
    fi

    exit 1
}

# RUN_INTERACTIVE <message> <command...>
# Runs the command in the background behind a spinner and returns its exit status.
# Its stdout/stderr is captured in $outputFile (shown only if a step fails).
RUN_INTERACTIVE() {
    local message="$1"
    local statusCode=0

    shift
    : >"$outputFile"

    if [[ $IS_TTY -eq 1 ]]; then
        HIDE_TERM_CURSOR

        # No input, stdout + stderr into the capture file, in the background.
        "$@" </dev/null >"$outputFile" 2>&1 &
        processId=$!

        SPIN "$processId" "$message"

        # Collect the background command's real exit status.
        wait "$processId" || statusCode=$?
        processId=""

        printf '\r'
        CLEAR_LINE
        UNHIDE_TERM_CURSOR
    else
        printf '%s...\n' "$message"
        "$@" </dev/null >"$outputFile" 2>&1 || statusCode=$?
    fi

    return "$statusCode"
}

# RUN <in-progress text> <done text> <command...>
# Spinner while running, then a check mark; on failure print details and exit.
RUN() {
    local work="$1"
    local onSuccess="$2"

    shift 2

    if RUN_INTERACTIVE "$work" "$@"; then
        SUCCESS "$onSuccess"
    else
        RUN_FAILED "$work"
    fi
}

# Trap handlers
ON_INTERRUPT() {
    printf '\n%bERROR:%b Interrupted\n' "$RED" "$RESET" >&2
    exit 130
}

ON_ERROR() {
    printf '%bERROR:%b Unexpected failure at line %s\n' "$RED" "$RESET" "$1" >&2
}

CLEANUP() {
    # Kill a background step that is still running (ignore "no such process").
    if [[ -n "$processId" ]]; then
        kill "$processId" 2>/dev/null || true
    fi

    # Never leave the terminal cursor hidden.
    if [[ $IS_TTY -eq 1 ]]; then
        UNHIDE_TERM_CURSOR
    fi

    if [[ -n "$tmpDir" ]]; then
        rm -rf "$tmpDir"
    fi
}