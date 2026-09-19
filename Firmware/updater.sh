#!/usr/bin/env bash
#
# Firmware updated for 6522 Tester 
# Verify avrdude, check GitHub for latest hex files,
#
# Repository: https://github.com/MyRetroStore/6522-Tester
#

set -o pipefail

# Configuration defaults
REPO="MyRetroStore/6522-Tester"
REPO_URL="https://github.com/$REPO"
REPO_API_LATEST="https://api.github.com/repos/$REPO/releases/latest"
RAW_VERSION_URL="https://raw.githubusercontent.com/$REPO/main/version"

SCRIPT_VERSION="1.0"
WEBSITE_URL="https://myretrostore.co.uk"

TIMEOUT=5
PORT=""
BAUD=115200

# Colors for terminal output
if [ -t 1 ]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    NC=$'\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

log_info() {
    printf "%s\n" "${BLUE}[INFO]${NC} $1"
}

log_ok() {
    printf "%s\n" "${GREEN}[OK]${NC} $1"
}

log_warn() {
    printf "%s\n" "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    printf "%s\n" "${RED}[ERROR]${NC} $1" >&2
}

print_usage() {
    cat <<USAGE_EOF
Usage: $(basename "$0") [OPTIONS] [PORT]

Check if avrdude is installed, query GitHub Releases for the latest
firmware file, and check/update an Arduino Mega 2560.

Script version: $SCRIPT_VERSION
Website:        $WEBSITE_URL
GitHub page:    $REPO_URL
Releases API:   $REPO_API_LATEST

Arguments:
  PORT                  Optional serial port (e.g. /dev/ttyACM0).
                        If omitted, will attempt auto-detection.

Options:
  -p, --port <port>     Specify serial port (e.g. /dev/ttyACM0)
  -t, --timeout <sec>   Read timeout in seconds (default: $TIMEOUT)
  -v, --version         Show the script version and exit
  -h, --help            Show this help message and exit

Examples:
  $(basename "$0")
  $(basename "$0") -p /dev/ttyACM0
USAGE_EOF
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -v|--version)
            printf '%s version %s\n' "$(basename "$0")" "$SCRIPT_VERSION"
            exit 0
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
        *)
            if [ -z "$PORT" ]; then
                PORT="$1"
            else
                log_error "Unexpected argument: $1"
                print_usage
                exit 1
            fi
            shift
            ;;
    esac
done

printf "%s\n" "${BOLD}====================================================${NC}"
printf "%s\n" "${BOLD}          Firmware updater for 6522 Tester      ${NC}"
printf "%s\n" "${BOLD}                 Script Version $SCRIPT_VERSION                     ${NC}"
printf "%s\n            $WEBSITE_URL"
printf "%s\n     $REPO_URL\n"
printf "%s\n\n" "${BOLD}====================================================${NC}"

log_info "Checking for avrdude..."
if ! command -v avrdude &>/dev/null; then
    log_error "avrdude is not installed or not in system PATH."
    log_error "Please install avrdude to proceed (e.g., 'sudo apt install avrdude')."
    exit 1
fi

AVRDUDE_BIN=$(command -v avrdude)
AVRDUDE_VER=$(avrdude -v 2>&1 | grep -i "version" | head -n 1 | sed 's/^[[:space:]]*//')
if [ -n "$AVRDUDE_VER" ]; then
    log_ok "avrdude found at $AVRDUDE_BIN ($AVRDUDE_VER)"
else
    log_ok "avrdude found at $AVRDUDE_BIN"
fi

echo ""

log_info "Checking latest release via GitHub"

if ! command -v curl &>/dev/null; then
    log_error "curl is required to communicate with GitHub API."
    exit 1
fi

RELEASE_JSON=$(curl -fsSL --connect-timeout 8 --max-time 15 \
    -H "Accept: application/vnd.github.v3+json" \
    "$REPO_API_LATEST" 2>/dev/null)

if [ -z "$RELEASE_JSON" ]; then
    log_warn "Failed to fetch latest release from GitHub API. Falling back to raw version check..."
    REMOTE_VERSION=$(curl -fsSL --connect-timeout 8 --max-time 15 "$RAW_VERSION_URL" 2>/dev/null | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    printf '%s\n' "$REMOTE_VERSION"
    if [ -z "$REMOTE_VERSION" ]; then
        log_error "Could not retrieve version information from $REPO_URL."
        exit 1
    fi
    RELEASE_TAG="v$REMOTE_VERSION"
    RELEASE_NAME="Version $REMOTE_VERSION"
    HEX_NAME=""
    HEX_URL=""
    HEX_SIZE=0
else
    if command -v jq &>/dev/null; then
        RELEASE_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name // empty')
        RELEASE_NAME=$(echo "$RELEASE_JSON" | jq -r '.name // empty')

	HEX_NAME=$(echo "$RELEASE_JSON" | jq -r '.assets[] | select(.name | test("\\.hex$"; "i")) | .name' | head -n 1)
	HEX_URL=$(echo "$RELEASE_JSON" | jq -r '.assets[] | select(.name | test("\\.hex$"; "i")) | .browser_download_url' | head -n 1)
	HEX_SIZE=$(echo "$RELEASE_JSON" | jq -r '.assets[] | select(.name | test("\\.hex$"; "i")) | .size' | head -n 1)
	    else
        PARSED_INFO=$(python3 - << 'PYTHON_EOF' <<< "$RELEASE_JSON" 2>/dev/null
import sys, json
try:
    data = json.load(sys.stdin)
    tag = data.get("tag_name", "")
    name = data.get("name", "")
    hex_asset = next(
	    (a for a in data.get("assets", [])
	     if a.get("name", "").lower().endswith(".hex")),
	    None
	   )
    print(f"TAG={tag}")
    print(f"NAME={name}")
    if bl_asset:
        print(f"BL_ASSET={bl_asset.get('name', '')}")
    if hex_asset:
        print(f"HEX_NAME={hex_asset.get('name', '')}")
        print(f"HEX_URL={hex_asset.get('browser_download_url', '')}")
        print(f"HEX_SIZE={hex_asset.get('size', 0)}")
except Exception:
    sys.exit(1)
PYTHON_EOF
        )
        RELEASE_TAG=$(echo "$PARSED_INFO" | grep '^TAG=' | cut -d= -f2-)
        RELEASE_NAME=$(echo "$PARSED_INFO" | grep '^NAME=' | cut -d= -f2-)
        HEX_NAME=$(echo "$PARSED_INFO" | grep '^HEX_NAME=' | cut -d= -f2-)
        HEX_URL=$(echo "$PARSED_INFO" | grep '^HEX_URL=' | cut -d= -f2-)
        HEX_SIZE=$(echo "$PARSED_INFO" | grep '^HEX_SIZE=' | cut -d= -f2-)
    fi
fi

# Sanitize version string (strip leading 'v')
REMOTE_VERSION=$(echo "$RELEASE_TAG" | sed 's/^[vV]//')

if [ -z "$REMOTE_VERSION" ]; then
    log_error "Unable to parse release version from GitHub API response."
    exit 1
fi

log_ok "Latest Version : ${BOLD}$RELEASE_TAG${NC}"

echo ""

# -----------------------------------------------------------------------------
# STEP 3: Detect Arduino Mega 2560 Port
# -----------------------------------------------------------------------------
log_info "Detecting Arduino Mega 2560..."

detect_mega_port() {
    # 1. Search /dev/serial/by-id
    if [ -d "/dev/serial/by-id" ]; then
        for dev in /dev/serial/by-id/*; do
            [ -e "$dev" ] || continue
            if [[ "$dev" =~ Arduino || "$dev" =~ 0042 || "$dev" =~ 0010 || "$dev" =~ Mega ]]; then
                readlink -f "$dev"
                return 0
            fi
        done
    fi

    # 2. Search udev properties of ttyACM and ttyUSB devices
    for dev in /dev/ttyACM* /dev/ttyUSB*; do
        [ -e "$dev" ] || continue
        if command -v udevadm &>/dev/null; then
            local udev_info
            udev_info=$(udevadm info -q property -n "$dev" 2>/dev/null)
            if echo "$udev_info" | grep -Ei "Mega.*2560|ID_MODEL_ID=0042|ID_MODEL_ID=0010" >/dev/null; then
                echo "$dev"
                return 0
            fi
        fi
    done

    # 3. Fallback: check if /dev/ttyACM0 exists
    if [ -e "/dev/ttyACM0" ]; then
        echo "/dev/ttyACM0"
        return 0
    fi

    return 1
}

if [ -z "$PORT" ]; then
    PORT=$(detect_mega_port)
    if [ -z "$PORT" ]; then
        log_error "Arduino Mega 2560 could not be automatically detected."
        log_error "Please connect the board"
        exit 1
    fi
    log_ok "Auto-detected Arduino Mega 2560 at: $PORT"
else
    if [ ! -e "$PORT" ]; then
        log_error "Specified port '$PORT' does not exist."
        exit 1
    fi
    log_ok "Using specified port: $PORT"
fi

# Check permissions on the port
if [ ! -r "$PORT" ] || [ ! -w "$PORT" ]; then
    log_error "Current user ($USER) lacks read/write permissions for $PORT."
    log_error "Run 'sudo usermod -aG dialout $USER' and log back in, or run with appropriate privileges."
    exit 1
fi

echo ""

# -----------------------------------------------------------------------------
# STEP 4: Read Version from Arduino Mega 2560
# -----------------------------------------------------------------------------
log_info "Reading firmware version from $PORT"

read_version_bash() {
    local port="$1"
    local baud="$2"
    local timeout="$3"
    local version=""
    local line=""

    stty -F "$port" "$baud" cs8 -cstopb -parenb -echo raw -echoe -echok -echoctl -echoke -hupcl min 0 time 10 2>/dev/null || return 1
    exec 3<>"$port" || return 1
    sleep 1.6
    printf "version\r\n" >&3

    local end_time=$((SECONDS + timeout))
    while [ $SECONDS -lt $end_time ]; do
        if IFS= read -t 1 -r line <&3; then
            clean_line=$(printf "%s" "$line" | tr -d '\r\n')
            if [ -n "$clean_line" ]; then
                if [[ "$clean_line" =~ [Ff]irmware[[:space:]]+[Vv]ersion:[[:space:]]*([0-9]+(\.[0-9]+)*) ]]; then
                    version="${BASH_REMATCH[1]}"
                    break
                elif [[ "$clean_line" =~ [Vv]ersion:[[:space:]]*([0-9]+(\.[0-9]+)*) ]]; then
                    version="${BASH_REMATCH[1]}"
                    break
                elif [[ "$clean_line" =~ ^([0-9]+\.[0-9]+(\.[0-9]+)?)$ ]]; then
                    version="${BASH_REMATCH[1]}"
                    break
                fi
            fi
        fi
    done

    exec 3>&- 2>/dev/null
    exec 3<&- 2>/dev/null

    echo "$version"
}

read_version_python() {
    local port="$1"
    local baud="$2"
    local timeout="$3"

    python3 - "$port" "$baud" "$timeout" << 'PYTHON_EOF' 2>/dev/null
import sys, re, time
try:
    import serial
except ImportError:
    sys.exit(1)

port = sys.argv[1]
baud = int(sys.argv[2])
timeout = int(sys.argv[3])

try:
    ser = serial.Serial(port, baud, timeout=1)
    time.sleep(1.8)
    ser.write(b"version\r\n")
    start = time.time()
    version = ""
    while time.time() - start < timeout:
        line = ser.readline().decode('utf-8', errors='ignore').strip()
        if not line:
            continue
        m = re.search(r'(?:Firmware\s+Version|Version):\s*([0-9]+(?:\.[0-9]+)*)', line, re.IGNORECASE)
        if m:
            version = m.group(1)
            break
        m2 = re.match(r'^([0-9]+(?:\.[0-9]+)+)$', line)
        if m2:
            version = m2.group(1)
            break
    ser.close()
    if version:
        print(version)
        sys.exit(0)
    sys.exit(2)
except Exception:
    sys.exit(3)
PYTHON_EOF
}

ARDUINO_VERSION=""
ARDUINO_VERSION=$(read_version_bash "$PORT" "$BAUD" "$TIMEOUT")

if [ -z "$ARDUINO_VERSION" ] && command -v python3 &>/dev/null; then
    ARDUINO_VERSION=$(read_version_python "$PORT" "$BAUD" "$TIMEOUT")
fi

if [ -z "$ARDUINO_VERSION" ]; then
    log_error "Could not read firmware version from Arduino Mega 2560 on $PORT."
    log_error "Ensure the board is connected and running."
    exit 1
fi

log_ok "Arduino Mega 2560 reported version: ${BOLD}$ARDUINO_VERSION${NC}"

echo ""

# -----------------------------------------------------------------------------
# STEP 5: Compare Versions & Summary
# -----------------------------------------------------------------------------

NEEDS_UPDATE=false
if [ "$ARDUINO_VERSION" = "$REMOTE_VERSION" ]; then
    printf "%s\n" "${GREEN}${BOLD}STATUS: Up to date! The Arduino is running the latest version (${ARDUINO_VERSION}).${NC}"
else
    NEEDS_UPDATE=true
    printf "%s\n" "${YELLOW}${BOLD}STATUS: Update Available!${NC}"
    printf "  Installed on Board : %s\n" "${BLUE}v${ARDUINO_VERSION}${NC}"
    printf "  Available Online   : %s\n" "${GREEN}v${REMOTE_VERSION}${NC}"
fi

TARGET_HEX="${HEX_NAME:-updater.hex}"

download_hex() {
    if [ -z "$HEX_URL" ]; then
        log_error "Cannot download: No .hex asset found in release $RELEASE_TAG."
        return 1
    fi
    log_info "Downloading $HEX_NAME from $HEX_URL..."
    if curl -fSL --progress-bar -o "$TARGET_HEX" "$HEX_URL"; then
            log_ok "Downloaded: $PWD/$TARGET_HEX"
            return 0
    else
        log_error "Failed to download $HEX_NAME."
        return 1
    fi
}

flash_hex() {
    local hex_file="$1"
    if [ ! -f "$hex_file" ]; then
        log_error "HEX file '$hex_file' not found for flashing."
        return 1
    fi

    log_info "Flashing '$hex_file' to Arduino Mega 2560 at $PORT with avrdude..."
    local avr_cmd="avrdude -c wiring -p m2560 -P $PORT -b 115200 -D -U flash:w:${hex_file}:i"
    printf "%s\n" "${CYAN}> $avr_cmd${NC}"

    if eval "${avr_cmd[@]}"; then
        log_ok "Firmware successfully flashed!"
        log_info "Re-checking board version after flash..."
	sleep 5
        NEW_VER=$(read_version_bash "$PORT" "$BAUD" "$TIMEOUT")
        if [ -n "$NEW_VER" ]; then
            log_ok "Arduino Mega 2560 now reports version: ${BOLD}$NEW_VER${NC}"
        fi
        return 0
    else
        log_error "avrdude flashing failed."
        return 1
    fi
}

if  [ "$NEEDS_UPDATE" = true ] && [ -n "$HEX_URL" ] && [ -t 0 ]; then
    echo ""
    read -r -p "Would you like to download and flash the latest firmware now? [y/N]: " confirm
    if [[ "$confirm" =~ ^[yY]([eE][sS])?$ ]]; then
        if download_hex; then
            flash_hex "$TARGET_HEX"
        fi
    fi
elif [ "$DO_DOWNLOAD" = false ] && [ "$NEEDS_UPDATE" = true ] && [ -n "$HEX_NAME" ]; then
    printf "\n%s\n" "To download and flash this update automatically, run:"
fi

exit 0
