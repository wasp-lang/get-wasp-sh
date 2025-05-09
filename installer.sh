#!/bin/sh

# NOTE: Heavily inspired by get-stack.hs script for installing stack.
# https://raw.githubusercontent.com/commercialhaskell/stack/stable/etc/scripts/get-stack.sh

# NOTE: These paths are used in the Wasp uninstall command, if you change it here,
#       change it there as well.
#       Link to Uninstall command: https://github.com/wasp-lang/wasp/blob/main/waspc/cli/src/Wasp/Cli/FileSystem.hs#L36
HOME_LOCAL_BIN="$HOME/.local/bin"
HOME_LOCAL_SHARE="$HOME/.local/share"
WASP_TEMP_DIR=
VERSION_ARG=

RED="\033[31m"
GREEN="\033[32m"
BOLD="\033[1m"
RESET="\033[0m"

while [ $# -gt 0 ]; do
    case "$1" in
        # -d|--dest)
        #     DEST="$2"
        #     shift 2
        #     ;;
        -v|--version)
            VERSION_ARG="$2"
            shift 2
            ;;
        *)
            echo "Invalid argument: $1" >&2
            exit 1
            ;;
    esac
done

main() {
    trap cleanup_temp_dir EXIT
    send_telemetry > /dev/null 2>&1 &
    install_based_on_os
}

install_based_on_os() {
    case "$(uname)" in
        "Linux")
            install_from_bin_package "wasp-linux-x86_64.tar.gz"
            ;;
        "Darwin")
            install_from_bin_package "wasp-macos-x86_64.tar.gz"
            ;;
        *)
            die "Sorry, this installer does not support your operating system: $(uname)."
    esac
}

get_os_info() {
    case "$(uname)" in
        "Linux")
            echo "linux"
            ;;
        "Darwin")
            echo "osx"
            ;;
        *)
            echo "Unknown"
            ;;
    esac
}

# Download a Wasp binary package and install it in $HOME_LOCAL_BIN.
install_from_bin_package() {
    BIN_PACKAGE_NAME=$1

    LATEST_VERSION=$(get_latest_wasp_version)

    if [ -z "$VERSION_ARG" ]; then
        VERSION_TO_INSTALL=$LATEST_VERSION
    else
        VERSION_TO_INSTALL=$VERSION_ARG
    fi

    if [ "$VERSION_TO_INSTALL" = "$LATEST_VERSION" ]; then
        LATEST_VERSION_MESSAGE="latest"
    else
        LATEST_VERSION_MESSAGE="latest is $LATEST_VERSION"
    fi

    info "Installing wasp version $VERSION_TO_INSTALL ($LATEST_VERSION_MESSAGE).\n"

    # TODO: Consider installing into /usr/local/bin and /usr/local/share instead of into
    #   ~/.local/share and ~/.local/bin, since those are always on the PATH and are standard
    #  to install programs like this. But then we need to run some commands below with sudo.

    ##### Download and install the specified wasp release. #####

    DATA_DST_DIR="$HOME_LOCAL_SHARE/wasp-lang/$VERSION_TO_INSTALL"
    create_dir_if_missing "$DATA_DST_DIR"

    if [ -z "$(ls -A "$DATA_DST_DIR")" ]; then
        PACKAGE_URL="https://github.com/wasp-lang/wasp/releases/download/v${VERSION_TO_INSTALL}/${BIN_PACKAGE_NAME}"
        make_temp_dir
        info "Downloading binary package to temporary dir and unpacking it there...\n"
        dl_to_file "$PACKAGE_URL" "$WASP_TEMP_DIR/$BIN_PACKAGE_NAME" "Installation failed: There is no wasp version $VERSION_TO_INSTALL"
        echo ""

        info "Installing wasp data to $DATA_DST_DIR.\n"
        if ! tar xzf "$WASP_TEMP_DIR/$BIN_PACKAGE_NAME" -C "$DATA_DST_DIR"; then
            die "Installing data to $DATA_DST_DIR failed: unpacking binary package failed."
        fi
    else
        info "Found an existing installation on the disk, at $DATA_DST_DIR. Using it instead.\n"
    fi

    ##### Create executable that uses installed wasp release. #####

    BIN_DST_DIR="$HOME_LOCAL_BIN"
    create_dir_if_missing "$BIN_DST_DIR"

    if [ -e "$BIN_DST_DIR/wasp" ]; then
        info "Configuring wasp executable at $BIN_DST_DIR/wasp to use wasp version $VERSION_TO_INSTALL."
    else
        info "Installing wasp executable to $BIN_DST_DIR/wasp."
    fi
    # TODO: I should make sure here that $DATA_DST_DIR is abs path.
    #  It works for now because we set it to HOME_LOCAL_SHARE which
    #  we obtained using $HOME which is absolute, but if that changes
    #  and it is not absolute any more, .sh file generated below
    #  will not work properly.
    printf '#!/bin/sh\nwaspc_datadir=%s/data exec %s/wasp-bin "$@"\n' "$DATA_DST_DIR" "$DATA_DST_DIR" \
           > "$BIN_DST_DIR/wasp"
    if ! chmod +x "$BIN_DST_DIR/wasp"; then
        die "Failed to make $BIN_DST_DIR/wasp executable."
    fi

    info "\n=============================================="

    if ! on_path "$BIN_DST_DIR"; then
        info "\n${RED}WARNING${RESET}: It looks like '$BIN_DST_DIR' is not on your PATH! You will not be able to invoke wasp from the terminal by its name."
        info "  You can add it to your PATH by adding following line into your profile file (~/.profile or ~/.zshrc or ~/.bash_profile or ~/.bashrc or some other, depending on your configuration):"
        # The $PATH in the following line is a literal, we don't want it to be interpolated
        # shellcheck disable=SC2016
        info "      ${BOLD}"'export PATH=$PATH:'"$BIN_DST_DIR${RESET}"
    fi

    info "\n${GREEN}wasp has been successfully installed! To create your first app, do:${RESET}"
    if ! on_path "$BIN_DST_DIR"; then
        info " - Add wasp to your PATH as described above."
    fi
    info " - ${BOLD}wasp new MyApp${RESET}\n"

    info "Optional:"
    info " - to install bash completion for wasp, run ${BOLD}wasp completion${RESET} and follow the instructions."
}

create_dir_if_missing() {
    if [ ! -d "$1" ]; then
        info "$1 does not exist, creating it..."
        if ! mkdir -p "$1" 2>/dev/null; then
            die "Could not create directory: $1."
        fi
    fi
}

# Creates a temporary directory, which will be cleaned up automatically
# when the script finishes
make_temp_dir() {
    WASP_TEMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t wasp)"
}

# Cleanup the temporary directory if it's been created.
# Called automatically when the script exits.
cleanup_temp_dir() {
    if [ -n "$WASP_TEMP_DIR" ] ; then
        rm -rf "$WASP_TEMP_DIR"
        WASP_TEMP_DIR=""
    fi
}

# Print a message to stderr and exit with error code.
die() {
    printf "${RED}%b${RESET}\n" "$@" >&2
    exit 1
}

info() {
    printf "%b\n" "$@"
}

# Download a URL to file using 'curl' or 'wget'.
dl_to_file() {
    FILE_URL="$1"
    DST="$2"
    MSG_ON_404="$3"

    if has_curl ; then
        if ! OUTPUT=$(curl ${QUIET:+-sS} --fail -L -o "$DST" "$FILE_URL"); then
            if ! echo "$OUTPUT" | grep --quiet 'The requested URL returned error: 404'; then
                die "$MSG_ON_404"
            else
                die "curl download failed: $FILE_URL"
            fi
        fi
    elif has_wget ; then
        if ! OUTPUT=$(wget ${QUIET:+-q} "-O$DST" "$FILE_URL"); then
            if ! echo "$OUTPUT" | grep --quiet 'ERROR 404: Not Found'; then
                die "$MSG_ON_404"
            else
                die "wget download failed: $FILE_URL"
            fi
        fi
    else
        die "Neither wget nor curl is available, please install one to continue."
    fi
}

# Check whether 'wget' command exists.
has_wget() {
    has_cmd wget
}

# Check whether 'curl' command exists.
has_curl() {
    has_cmd curl
}

# Check whether the given command exists.
has_cmd() {
    command -v "$1" > /dev/null 2>&1
}

# Check whether the given (query) path is listed in the PATH environment variable.
on_path() {
    # Below we normalize PATH and query regarding ~ by ensuring ~ is expanded to $HOME, avoiding
    # false negatives in case where ~ is expanded in query but not in PATH and vice versa.

    # NOTE: If $PATH or $1 have '|' somewhere in it, sed commands bellow will fail due to using | as their delimiter.

    # If ~ is after : or if it is the first character in the path, replace it with expanded $HOME.
    # For example, if $PATH is ~/martin/bin:~/martin/~tmp/bin,
    # result will be /home/martin/bin:/home/martin/~tmp/bin .
    PATH_NORMALIZED=$(printf '%s' "$PATH" | sed -e "s|:~|:$HOME|g" | sed -e "s|^~|$HOME|")

    # Replace ~ with expanded $HOME if it is the first character in the query path.
    QUERY_NORMALIZED=$(printf '%s' "$1" | sed -e "s|^~|$HOME|")

    echo ":$PATH_NORMALIZED:" | grep -q ":$QUERY_NORMALIZED:"
}

# Returns 0 if any of the listed env vars is set (regardless of its value). Otherwise returns 1.
check_if_on_ci() {
    # Inspired by the list of env vars we use in waspc/cli/.../Telemetry/Project.hs (wasp repo).
    if [ -n "$(printenv BUILD_ID BUILD_NUMBER CI CI_APP_ID CI_BUILD_ID CI_BUILD_NUMBER CI_NAME CONTINUOUS_INTEGRATION RUN_ID)" ]; then
	return 0;
    else
	return 1;
    fi
}

random() {
    # We can't use $RANDOM because it is not supported on `dash`
    # (Ubuntu and Debian use it) 
    # https://github.com/wasp-lang/wasp/issues/2560#issuecomment-2740577162
    # Instead we use the portable workaround suggested by
    # ShellCheck https://www.shellcheck.net/wiki/SC3028
    awk 'BEGIN { srand(); print int(rand()*32768) }' /dev/null
}

send_telemetry() {
    POSTHOG_WASP_PUBLIC_API_KEY='CdDd2A0jKTI2vFAsrI9JWm3MqpOcgHz1bMyogAcwsE4'

    CONTEXT=""
    if check_if_on_ci; then
	CONTEXT="${CONTEXT} CI"
    fi
    CONTEXT=$(echo "$CONTEXT" | sed 's/^[ ]*//') # Remove any leading spaces.

    DATA='{ "api_key": "'$POSTHOG_WASP_PUBLIC_API_KEY'", "type": "capture", "event": "install-script:run", "distinct_id": "'$(random)$(date +'%s%N')'", "properties": { "os": "'$(get_os_info)'", "context": "'$CONTEXT'" } }'

    URL="https://app.posthog.com/capture"
    HEADER="Content-Type: application/json"

    if [ -z "$WASP_TELEMETRY_DISABLE" ]; then
        if has_curl; then
            curl -sfL -d "$DATA" --header "$HEADER" "$URL" > /dev/null 2>&1
        elif has_wget; then
            wget -q --post-data="$DATA" --header="$HEADER" "$URL" > /dev/null 2>&1
        fi
    fi
}

get_latest_wasp_version() {
    if has_curl; then
        curl -LIs -o /dev/null -w '%{url_effective}' https://github.com/wasp-lang/wasp/releases/latest | awk -F/ '{print $NF}' | cut -c2-
    elif has_wget; then
        wget --spider --max-redirect=0 https://github.com/wasp-lang/wasp/releases/latest 2>&1 | awk '/Location: /,// { print }' | awk '{print $2}' | awk -F/ '{print $NF}' | cut -c2-
    fi
}

main
