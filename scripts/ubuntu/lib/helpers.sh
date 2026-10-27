# shellcheck shell=bash


CHECK_GO() {
    local bin="$GO_INSTALL_DIR/bin/go"
    local found
 
    [[ -x "$bin" ]] || bin="$(command -v go || true)"
    [[ -n "$bin" ]] || return 1
 
    found="$("$bin" version | awk '{print $3}')"
    found="${found#go}"
 
    echo "$found"
    COMPARE_VERSION "$found" "$goVersion"
}
 
PY_VERSION() {
    "$1" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])'
}
 
PY_HAS_VENV() {
    "$1" -c 'import venv, ensurepip' 2>/dev/null
}
 
CHECK_PYTHON() {
    local py="python${pythonVersion}"
    local found
    local cand
    local candVersion
    local statusCode
    local best=""
    local bestVersion=""
    local -a candidates=()
 
    # 1) the exact requested interpreter
    if EXISTS "$py"; then
        found="$(PY_VERSION "$py")" || return 1
 
        if IS_SIMILAR "$found" "$pythonVersion"; then
            if ! PY_HAS_VENV "$py"; then
                echo "$found (venv support missing)"
                return 1
            fi
            echo "$found"
            echo "$py"
            return 0
        fi
    fi
 
    # 2) otherwise the highest NEWER python3.N that supports venv
    mapfile -t candidates < <(compgen -c python3. | grep -E '^python3\.[0-9]+$' | sort -u)
 
    for cand in "${candidates[@]}"; do
        candVersion="$(PY_VERSION "$cand" 2>/dev/null)" || continue
 
        statusCode=0
        COMPARE_VERSION "$candVersion" "$pythonVersion" || statusCode=$?
        [[ $statusCode -eq 2 ]] || continue
 
        PY_HAS_VENV "$cand" || continue
 
        if [[ -z "$bestVersion" || "$(NEWEST_OF "$bestVersion" "$candVersion")" == "$candVersion" ]]; then
            best="$cand"
            bestVersion="$candVersion"
        fi
    done
 
    if [[ -n "$best" ]]; then
        echo "$bestVersion"
        echo "$best"
        return 2
    fi
 
    return 1
}
 
CHECK_REDIS() {
    local found
 
    EXISTS redis-server || return 1
 
    found="$(redis-server --version | sed -nE 's/.*v=([^ ]+).*/\1/p')"
 
    echo "$found"
    COMPARE_VERSION "$found" "$redisVersion"
}

# ASK_NEWER <label> <found> <requested>   -> sets choice=keep|exact
ASK_NEWER() {
    local label="$1"
    local found="$2"
    local req="$3"
    local reply=""

    WARN "$label $found is installed, which is newer than the requested $req."

    # Pre-answered via ON_NEWER_VERSION
    case "$NEWER_POLICY" in
        keep)  choice=keep;  INFO "ON_NEWER_VERSION=keep: keeping $label $found"; return 0 ;;
        exact) choice=exact; INFO "ON_NEWER_VERSION=exact: installing $label $req"; return 0 ;;
    esac

    if (( explained == 0 )); then
        cat >&2 <<'EOF'
    Having a newer version is fine. "Newer" does not mean "broken": most of the
    time it behaves exactly like the requested one. We only ask because this
    setup was prepared for the requested version, so a newer release MAY
    (rarely) behave differently.

    If something doesn't work later, simply run this script again and choose
    to install the exact version.

EOF
        explained=1
    fi

    # No terminal to ask on (CI, pipes): keep what the user already has.
    if [[ ! -t 0 ]]; then
        WARN "No interactive terminal; keeping $label $found. Rerun with ON_NEWER_VERSION=exact to install $req instead."
        choice=keep
        return 0
    fi

    printf '      [K] Keep %s %s  (recommended if everything already works)\n' "$label" "$found" >&2
    printf '      [E] Install the exact requested version %s\n' "$req" >&2
    case "$label" in
        Python) printf '          (installed side by side; your newer Python is not removed)\n' >&2 ;;
        Redis)  printf '          (this downgrades Redis; data files written by a newer Redis may become unreadable)\n' >&2 ;;
        Go)     printf '          (replaces the Go in %s)\n' "$GO_INSTALL_DIR" >&2 ;;
    esac

    while :; do
        read -r -p "    Your choice [K/e] (default K): " reply || reply=""
        case "${reply,,}" in
            ""|k|keep) choice=keep;  break ;;
            e|exact)   choice=exact; break ;;
            *) echo "    Please type K or E." >&2 ;;
        esac
    done
    echo >&2
}

# CHECK_DEP <flag-variable-name> <label> <check-function> <required-version>
# Runs a check behind a spinner and sets the flag variable to 1 (install) or 0 (skip).
CHECK_DEP() {
    local flagVar="$1"
    local label="$2"
    local checkFn="$3"
    local req="$4"
    local statusCode=0
    local found
    local cmd

    RUN_INTERACTIVE "Checking $label" "$checkFn" || statusCode=$?

    found="$(sed -n 1p "$outputFile")"
    cmd="$(sed -n 2p "$outputFile")"
    foundCmd=""

    case "$statusCode" in
        0)
            SUCCESS "$label $found already installed — skipped"
            foundCmd="$cmd"
            printf -v "$flagVar" 0
            ;;
        2)
            ASK_NEWER "$label" "$found" "$req"
            if [[ "$choice" == "keep" ]]; then
                SUCCESS "Keeping $label $found (newer than requested $req) — skipped"
                keptNewer+=("$label $found")
                foundCmd="$cmd"
                printf -v "$flagVar" 0
            else
                INFO "Will install exact $label $req"
                printf -v "$flagVar" 1
            fi
            ;;
        *)
            if [[ -n "$found" ]]; then
                WARN "$label $found found, but it does not satisfy the requested $req; installing the requested version"
            else
                INFO "$label not found; will install $req"
            fi
            printf -v "$flagVar" 1
            ;;
    esac
}

MISSING_SYSTEM_UTILITIES() {
    local pkg
 
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed' || echo "$pkg"
    done
}
 
INSTALL_SYSTEM_UTILITIES() {
    local -a missing=()
 
    mapfile -t missing < <(MISSING_SYSTEM_UTILITIES)
    if (( ${#missing[@]} )); then
        APT_GET install "${missing[@]}"
    fi
}
 
INSTALL_GO() {
    local archive="go${goVersion}.linux-${goArch}.tar.gz"
    local url="${GO_DOWNLOAD_BASE}/${archive}"
    local expected
    local actual
 
    curl -fsSL --retry 3 "$url" -o "$tmpDir/$archive" \
        || { echo "Could not download $url (check the version and your network)"; return 1; }
    curl -fsSL --retry 3 "$url.sha256" -o "$tmpDir/$archive.sha256" \
        || { echo "Could not download checksum $url.sha256"; return 1; }
 
    expected="$(tr -d '[:space:]' <"$tmpDir/$archive.sha256")"
    actual="$(sha256sum "$tmpDir/$archive" | awk '{print $1}')"
    [[ "$expected" == "$actual" ]] \
        || { echo "Checksum mismatch for $archive (expected $expected, got $actual)"; return 1; }
 
    # $sudoCmd is intentionally unquoted: it is empty when already root.
    # shellcheck disable=SC2086
    {
        # Official guidance: remove any previous install before extracting.
        $sudoCmd rm -rf "$GO_INSTALL_DIR" || return 1
        $sudoCmd tar -C "$(dirname "$GO_INSTALL_DIR")" -xzf "$tmpDir/$archive" || return 1
 
        # Prepend so this Go wins over any other Go in future shells.
        # (single quotes are intentional: $PATH must stay literal in the profile file)
        # shellcheck disable=SC2016
        printf 'export PATH="%s/bin:$PATH"\n' "$GO_INSTALL_DIR" | $sudoCmd tee "$GO_PROFILE_FILE" >/dev/null
    }
}
 
INSTALL_PYTHON() {
    apt-cache show "python${pythonVersion}" >/dev/null 2>&1 \
        || { echo "Python ${pythonVersion} is not available as 'python${pythonVersion}' in the enabled apt repositories."
             echo "Enable a repository that provides it (e.g. a PPA) or install it separately, then rerun."; return 1; }
 
    APT_GET install "python${pythonVersion}" "python${pythonVersion}-venv" "python${pythonVersion}-dev"
}
 
INSTALL_REDIS() {
    local aptVersion
    local pick=""
 
    # First apt version (newest first) that matches the requested one.
    while IFS= read -r aptVersion; do
        if IS_SIMILAR "${aptVersion#*:}" "$redisVersion"; then pick="$aptVersion"; break; fi
    done < <(apt-cache madison redis-server | awk -F'|' '{gsub(/ /, "", $2); print $2}')
 
    [[ -n "$pick" ]] \
        || { echo "No redis-server $redisVersion found in the enabled apt repositories."
             echo "Configure a repository providing it, or change the requested version."; return 1; }
 
    APT_GET install --allow-downgrades "redis-server=$pick" "redis-tools=$pick"
}
 
START_REDIS() {
    # $sudoCmd is intentionally unquoted: it is empty when already root.
    # shellcheck disable=SC2086
    if [[ -d /run/systemd/system ]]; then
        $sudoCmd systemctl enable --now redis-server || return 1
    elif EXISTS service; then
        $sudoCmd service redis-server start || return 1
    else
        echo "No init system found (systemctl/service). Start Redis manually."
        return 1
    fi
 
    for _ in $(seq "$REDIS_PING_RETRIES"); do
        if redis-cli ping 2>/dev/null | grep -qx PONG; then return 0; fi
        sleep "$REDIS_PING_INTERVAL"
    done
 
    echo "Redis did not respond to PING."
    return 1
}

SETUP_GO_DEPS() {
    go mod download
}

PIP_INSTALL_REQUIREMENTS() {
    .venv/bin/python -m pip install -q --disable-pip-version-check -r requirements.txt
}

SETUP_PROJECT() {
    local pyMajorMinor

    if [[ -f go.mod ]]; then
        RUN "Downloading Go module dependencies" "Go module dependencies downloaded" SETUP_GO_DEPS
    fi

    if [[ -f requirements.txt ]]; then
        pyMajorMinor="$("$pythonCmd" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"

        # A virtualenv built by a different Python minor version is unreliable: rebuild it.
        if [[ -x .venv/bin/python ]] \
            && ! .venv/bin/python -c "import sys; sys.exit(0 if '%d.%d' % sys.version_info[:2] == '$pyMajorMinor' else 1)"; then
            WARN ".venv was created with a different Python version; recreating it with Python $pyMajorMinor"
            rm -rf .venv
        fi

        if [[ ! -d .venv ]]; then
            RUN "Creating Python virtual environment" "Python virtual environment created" \
                "$pythonCmd" -m venv .venv
        else
            SUCCESS "Python virtual environment already exists"
        fi

        RUN "Installing Python project dependencies" "Python project dependencies installed" \
            PIP_INSTALL_REQUIREMENTS
    fi
}