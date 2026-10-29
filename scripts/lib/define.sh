# shellcheck shell=bash
#
#
# Naming: FUNCTIONS and readonly CONSTANTS are UPPER_SNAKE_CASE, every other variable is camelCase.



# Is stdout a terminal? (decides spinner + colours)
if [[ -t 1 ]]; then readonly IS_TTY=1; else readonly IS_TTY=0; fi

# Colours only on a terminal, and only if NO_COLOR is not set.
if [[ $IS_TTY -eq 1 && -z "${NO_COLOR:-}" ]]; then
    readonly CYAN=$'\033[0;36m'
    readonly GREEN=$'\033[0;32m'
    readonly YELLOW=$'\033[0;33m'
    readonly RED=$'\033[0;31m'
    readonly RESET=$'\033[0m'
else
    readonly CYAN=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly RED=''
    readonly RESET=''
fi

readonly -a SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
readonly SPINNER_INTERVAL=0.1

readonly GO_INSTALL_DIR="/usr/local/go"
readonly GO_PROFILE_FILE="/etc/profile.d/go.sh"
readonly GO_DOWNLOAD_BASE="https://dl.google.com/go"

readonly PROTOC_DOWNLOAD_BASE="https://github.com/protocolbuffers/protobuf/releases/download"
readonly PROTOC_INSTALL_PREFIX="/usr/local"
readonly PROTOC_GEN_GO_MODULE="google.golang.org/protobuf/cmd/protoc-gen-go"

readonly -a REQUIRED_PACKAGES=(ca-certificates curl tar gzip)
readonly APT_LOCK_TIMEOUT=120

readonly REDIS_PING_RETRIES=20
readonly REDIS_PING_INTERVAL=0.5

readonly GO_VERSION_REGEX='^[0-9]+\.[0-9]+(\.[0-9]+)?$'
readonly PYTHON_VERSION_REGEX='^[0-9]+\.[0-9]+$'
readonly REDIS_VERSION_REGEX='^[0-9]+\.[0-9]+(\.[0-9]+)?$'
readonly PROTOC_VERSION_REGEX='^[0-9]+\.[0-9]+(\.[0-9]+)?$'
readonly PROTOC_GEN_GO_VERSION_REGEX='^[0-9]+\.[0-9]+(\.[0-9]+)?$'

# ask | keep | exact : what to do when a NEWER version is already installed
readonly NEWER_POLICY="${ON_NEWER_VERSION:-ask}"

# Requested versions
goVersion=""
pythonVersion=""
redisVersion=""
protocVersion=""
protocGenGoVersion=""

# Runtime
tmpDir=""         # temp dir, removed on exit
outputFile=""     # captures the output of the current background step
processId=""      # pid of the running background step
sudoCmd=""        # "sudo", or "" when already root
goArch=""         # amd64 | arm64
protocArch=""     # x86_64 | aarch_64 (protoc release naming)
originalPath=""   # PATH before this script extended it
pythonCmd=""      # interpreter used to create the virtualenv

# Per-dependency decision: 1 = needs installing, 0 = already satisfied / kept
needGo=0
needPython=0
needRedis=0
needProtoc=0
needProtocGenGo=0

# Newer-version prompt state
choice=""         # keep | exact
explained=0       # long explanation shown once
keptNewer=()      # e.g. ("Go 1.26.0")
foundCmd=""       # command reported by a check (used for Python)