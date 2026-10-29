# shellcheck shell=bash


# NEWEST_OF <v1> <v2> ... : print the highest version.
NEWEST_OF() {
    printf '%s\n' "$@" | sort -V | tail -n1
}

# IS_SIMILAR <found> <required>
# True if equal, or if <required> is a prefix of <found> at a version boundary.
#   7.0.15 is similar to 7.0      
#   7.04 is not similar to 7.0
IS_SIMILAR() {
    local found="$1" 
    local req="$2"
    [[ "$found" == "$req" || "$found" == "$req"[.+~-]* ]]
}

# COMPARE_VERSION <found> <required>
# Return code: 0 = satisfies the request, 
# 2 = newer than requested,
# 1 = older / different
COMPARE_VERSION() {
    local found="$1"
    local req="$2"

    if IS_SIMILAR "$found" "$req"; then
        return 0
    fi

    if [[ "$(NEWEST_OF "$req" "$found")" == "$found" ]]; then
        return 2
    fi

    return 1
}