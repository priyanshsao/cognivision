# shellcheck shell=bash


# Command is present or not.
EXISTS() {
    command -v "$1" >/dev/null 2>&1
}
 
DETECT() {
    local arch
 
    [[ -r /etc/os-release ]] || END "This script requires Linux (an Ubuntu-based environment)."
 
    # shellcheck disable=SC1091
    . /etc/os-release
 
    if [[ "${ID:-}" != "ubuntu" && " ${ID_LIKE:-} " != *" ubuntu "* ]]; then
        WARN "Detected ${PRETTY_NAME:-unknown OS}; this script is intended for Ubuntu."
    fi
 
    EXISTS apt-get || END "apt-get was not found."
 
    arch="$(dpkg --print-architecture)"
    case "$arch" in
        amd64) goArch="amd64"; protocArch="x86_64" ;;
        arm64) goArch="arm64"; protocArch="aarch_64" ;;
        *) END "Unsupported architecture for automatic Go install: $arch" ;;
    esac
}
 
# Ask for sudo once, up front, so a password prompt never hides behind a spinner.
ENSURE_SUDO() {
    if [[ -n "$sudoCmd" || $EUID -eq 0 ]]; then return 0; fi
 
    EXISTS sudo || END "Root privileges are required and sudo was not found."
    INFO "Administrator privileges are required"
    sudo -v || END "Could not obtain sudo privileges."
    sudoCmd="sudo"
}
 
# Non-interactive apt-get that waits for the dpkg lock instead of failing.
APT_GET() {
    # $sudoCmd is intentionally unquoted: it is empty when already root.
    # shellcheck disable=SC2086
    $sudoCmd env DEBIAN_FRONTEND=noninteractive apt-get -o "DPkg::Lock::Timeout=$APT_LOCK_TIMEOUT" -y -qq "$@"
}
 
# Directory where `go install` puts binaries (GOBIN, else the first GOPATH entry + /bin).
GO_BIN_DIR() {
    local dir gopath
 
    dir="$(go env GOBIN)"
    if [[ -z "$dir" ]]; then
        gopath="$(go env GOPATH)"
        dir="${gopath%%:*}/bin"
    fi
    echo "$dir"
}