#!/bin/sh

# NOTE: Heavily inspired by get-stack.hs script for installing stack.
# https://raw.githubusercontent.com/commercialhaskell/stack/stable/etc/scripts/get-stack.sh

# NOTE: These paths are also defined in:
# - https://github.com/wasp-lang/wasp/blob/main/waspc/cli/src/Wasp/Cli/FileSystem.hs
# - https://github.com/wasp-lang/wasp/blob/main/scripts/make-npm-packages/templates/main-package/preinstall.js
# TODO: Do not hardcode: https://github.com/wasp-lang/wasp/issues/980
HOME_LOCAL_BIN="$HOME/.local/bin"
HOME_LOCAL_SHARE="$HOME/.local/share"
WASP_LANG_DIR="$HOME_LOCAL_SHARE/wasp-lang"
NPM_MARKER_FILE="$WASP_LANG_DIR/.uses-npm"
NPM_MIGRATION_VERSION="0.21" # First version we'll refuse to install through installer

MIGRATE_TO_NPM_ARG=
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
    -v | --version)
        VERSION_ARG="$2"
        shift 2
        ;;
    migrate-to-npm)
        MIGRATE_TO_NPM_ARG=1
        shift
        ;;
    *)
        echo "Invalid argument: $1" >&2
        exit 1
        ;;
    esac
done

main() {
    if [ -n "$VERSION_ARG" ] && [ -n "$MIGRATE_TO_NPM_ARG" ]; then
        die "Error: Cannot use both -v/--version and migrate-to-npm arguments together.\nUse either -v/--version to install a specific version, or migrate-to-npm to migrate to npm."
    fi

    if [ -f "$NPM_MARKER_FILE" ]; then
        die "You are already using Wasp through npm.\n\nTo install the latest version of Wasp, run:\n  npm install -g @wasp.sh/wasp-cli\n\nIf you need to use the installer again, check our guide at:\n  https://wasp.sh/docs/guides/legacy/installer"
    fi

    if [ -n "$MIGRATE_TO_NPM_ARG" ]; then
        migrate_to_npm
        exit 0
    fi

    # Require version argument
    if [ -z "$VERSION_ARG" ]; then
        die "A version argument is required.\n\nUsage: curl -sSL https://get.wasp.sh/installer.sh | sh -s -- -v <version>\n\nFor Wasp $NPM_MIGRATION_VERSION and later, please use npm:\n  npm install -g @wasp.sh/wasp-cli"
    fi

    # Check version restrictions - reject when requested version >= migration version
    if version_gte "$VERSION_ARG" "$NPM_MIGRATION_VERSION"; then
        die "Wasp version $NPM_MIGRATION_VERSION and later must be installed via npm.\n\nIf you've already installed Wasp from installer, please migrate to the npm method first:\n  curl -sSL https://get.wasp.sh/installer.sh | sh -s -- migrate-to-npm\n\nTo install Wasp through npm, please run:\n  npm install -g @wasp.sh/wasp-cli@$VERSION_ARG\n\nYou can read more about this migration at:\n  https://wasp.sh/docs/guides/legacy/installer"
    fi

    # Warn about installing old version
    info "${RED}WARNING${RESET}: You are installing an older version of Wasp ($VERSION_ARG)."
    info "Starting with Wasp $NPM_MIGRATION_VERSION, the installer is deprecated and npm is the preferred installation method. You can read more about the migration at:\n  https://wasp.sh/docs/guides/legacy/installer"

    trap cleanup_temp_dir EXIT
    send_telemetry >/dev/null 2>&1 &

    # TODO: Consider installing into /usr/local/bin and /usr/local/share instead of into
    #   ~/.local/share and ~/.local/bin, since those are always on the PATH and are standard
    #  to install programs like this. But then we need to run some commands below with sudo.
    data_dst_dir="$HOME_LOCAL_SHARE/wasp-lang/$VERSION_ARG"
    bin_dst_dir="$HOME_LOCAL_BIN"

    install_version "$VERSION_ARG" "$data_dst_dir"

    link_wasp_version "$VERSION_ARG" "$data_dst_dir" "$bin_dst_dir"
    print_tips "$bin_dst_dir"
}

migrate_to_npm() {
    info "Migrating from installer-based Wasp to npm-based Wasp...\n"

    # Remove installer Wasp binary
    wasp_bin="$HOME_LOCAL_BIN/wasp"
    if [ -f "$wasp_bin" ]; then
        info "Removing Wasp executable at $wasp_bin..."
        rm -f "$wasp_bin" || die "Failed to remove $wasp_bin"
    fi

    # Remove version directories but keep the wasp-lang dir for the marker
    if [ -d "$WASP_LANG_DIR" ]; then
        info "Removing installer version directories..."
        for dir in "$WASP_LANG_DIR"/*/; do
            info "Removing $dir..."
            if [ -d "$dir" ]; then
                rm -rf "$dir" || die "Failed to remove $dir"
            fi
        done
    fi

    create_dir_if_missing "$WASP_LANG_DIR"
    touch "$NPM_MARKER_FILE" || die "Failed to create npm marker file at $NPM_MARKER_FILE"

    info "\n${GREEN}Ready for the next step!${RESET}\n"
    info "Now you can install Wasp via npm by running the following command:"
    info "  ${BOLD}npm install -g @wasp.sh/wasp-cli${RESET}\n"
}

# Compare two semver versions (major.minor only).
# Returns 0 (true) if v1 >= v2, 1 (false) otherwise.
version_gte() {
    v1_major=$(echo "$1" | cut -d. -f1)
    v1_minor=$(echo "$1" | cut -d. -f2)
    v2_major=$(echo "$2" | cut -d. -f1)
    v2_minor=$(echo "$2" | cut -d. -f2)

    [ "$v1_major" -gt "$v2_major" ] && return 0
    [ "$v1_major" -lt "$v2_major" ] && return 1
    [ "$v1_minor" -ge "$v2_minor" ]
}

# Compare two semver versions (major.minor only).
# Returns 0 (true) if v1 >= v2, 1 (false) otherwise.
version_gte() {
    v1_major=$(echo "$1" | cut -d. -f1)
    v1_minor=$(echo "$1" | cut -d. -f2)
    v2_major=$(echo "$2" | cut -d. -f1)
    v2_minor=$(echo "$2" | cut -d. -f2)

    [ "$v1_major" -gt "$v2_major" ] && return 0
    [ "$v1_major" -lt "$v2_major" ] && return 1
    [ "$v1_minor" -ge "$v2_minor" ]
}

install_version() {
    version_name=$1
    data_dst_dir=$2

    info "Installing wasp version $version_name.\n"

    if [ -z "$(ls -A "$data_dst_dir")" ]; then
        package_url=$(decide_package_url_for_version "$version_name")
        package_file=$(download_package_url "$version_name" "$package_url")
        install_from_package_file "$package_file" "$data_dst_dir"
    else
        info "Found an existing installation on the disk, at $data_dst_dir. Using it instead.\n"
    fi
}

decide_package_url_for_version() {
    version_name=$1
    asset_name=$(get_asset_name_for_os)
    echo "https://github.com/wasp-lang/wasp/releases/download/v$version_name/$asset_name"
}

get_asset_name_for_os() {
    case "$(uname)" in
    "Linux") echo "wasp-linux-x86_64.tar.gz" ;;
    "Darwin") echo "wasp-macos-x86_64.tar.gz" ;;
    *)
        die "Sorry, this installer does not support your operating system: $(uname)."
        ;;
    esac
}

download_package_url() {
    version_name=$1
    package_url=$2

    info "Downloading binary package to temporary dir.\n"

    temp_dir=$(ensure_temp_dir)
    output_file="$temp_dir/$version_name"
    dl_to_file "$package_url" "$output_file" "Download failed: There is no wasp version ${version_name}\n"
    echo "$output_file"
}

install_from_package_file() {
    package_file=$1
    data_dst_dir=$2

    create_dir_if_missing "$data_dst_dir"

    info "Installing wasp data to $data_dst_dir.\n"
    if ! tar xzf "$package_file" -C "$data_dst_dir"; then
        die "Installing data to $data_dst_dir failed: unpacking binary package failed."
    fi
}

link_wasp_version() {
    version_name=$1
    data_dst_dir=$2
    bin_dst_dir=$3

    bin_dst="$3/wasp"

    create_dir_if_missing "$bin_dst_dir"

    if [ -e "$bin_dst" ]; then
        info "Configuring wasp executable at $bin_dst to use wasp version $version_name."
    else
        info "Installing wasp executable to $bin_dst."
    fi
    # TODO: I should make sure here that $data_dst_dir is abs path.
    #  It works for now because we set it to HOME_LOCAL_SHARE which
    #  we obtained using $HOME which is absolute, but if that changes
    #  and it is not absolute any more, .sh file generated below
    #  will not work properly.
    printf '#!/bin/sh\nwaspc_datadir=%s/data exec %s/wasp-bin "$@"\n' "$data_dst_dir" "$data_dst_dir" \
        >"$bin_dst"
    if ! chmod +x "$bin_dst"; then
        die "Failed to make $bin_dst executable."
    fi
}

print_tips() {
    bin_dst_dir=$1

    info "\n=============================================="

    if ! on_path "$bin_dst_dir"; then
        info "\n${RED}WARNING${RESET}: It looks like '$bin_dst_dir' is not on your PATH! You will not be able to invoke wasp from the terminal by its name."
        info "  You can add it to your PATH by adding following line into your profile file (~/.profile or ~/.zshrc or ~/.bash_profile or ~/.bashrc or some other, depending on your configuration):"
        # The $PATH in the following line is a literal, we don't want it to be interpolated
        # shellcheck disable=SC2016
        info "      ${BOLD}"'export PATH=$PATH:'"$bin_dst_dir${RESET}"
    fi

    info "\n${GREEN}wasp has been successfully installed! To create your first app, do:${RESET}"
    if ! on_path "$bin_dst_dir"; then
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

# Don't use directly, use the ensure_temp_dir function.
WASP_TEMP_DIR=

# Creates a temporary directory, which will be cleaned up automatically
# when the script finishes, and returns its path.
ensure_temp_dir() {
    if [ -z "$WASP_TEMP_DIR" ]; then
        WASP_TEMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t wasp)"
    fi
    echo "$WASP_TEMP_DIR"
}

# Cleanup the temporary directory if it's been created.
# Called automatically when the script exits.
cleanup_temp_dir() {
    if [ -n "$WASP_TEMP_DIR" ]; then
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
    printf "%b\n" "$@" >&2
}

# Download a URL to file using 'curl' or 'wget'.
dl_to_file() {
    file_url="$1"
    dst="$2"
    msg_on_404="$3"

    if has_curl; then
        if ! output=$(curl ${QUIET:+-sS} --fail -L -o "$dst" "$file_url"); then
            if ! echo "$output" | grep --quiet 'The requested URL returned error: 404'; then
                die "$msg_on_404"
            else
                die "curl download failed: $file_url"
            fi
        fi
    elif has_wget; then
        if ! output=$(wget ${QUIET:+-q} "-O$dst" "$file_url"); then
            if ! echo "$output" | grep --quiet 'ERROR 404: Not Found'; then
                die "$msg_on_404"
            else
                die "wget download failed: $file_url"
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
    command -v "$1" >/dev/null 2>&1
}

# Check whether the given (query) path is listed in the PATH environment variable.
on_path() {
    # Below we normalize PATH and query regarding ~ by ensuring ~ is expanded to $HOME, avoiding
    # false negatives in case where ~ is expanded in query but not in PATH and vice versa.

    # NOTE: If $PATH or $1 have '|' somewhere in it, sed commands bellow will fail due to using | as their delimiter.

    # If ~ is after : or if it is the first character in the path, replace it with expanded $HOME.
    # For example, if $PATH is ~/martin/bin:~/martin/~tmp/bin,
    # result will be /home/martin/bin:/home/martin/~tmp/bin .
    path_normalized=$(printf '%s' "$PATH" | sed -e "s|:~|:$HOME|g" | sed -e "s|^~|$HOME|")

    # Replace ~ with expanded $HOME if it is the first character in the query path.
    query_normalized=$(printf '%s' "$1" | sed -e "s|^~|$HOME|")

    echo ":$path_normalized:" | grep -q ":$query_normalized:"
}

# Returns 0 if any of the listed env vars is set (regardless of its value). Otherwise returns 1.
check_if_on_ci() {
    # Keep in sync with the same list in:
    # - https://github.com/wasp-lang/wasp/blob/main/scripts/make-npm-packages/templates/main-package/postinstall.js
    # - https://github.com/wasp-lang/wasp/blob/main/waspc/src/Wasp/Util.hs
    if [ -n "$(printenv BUILD_ID BUILD_NUMBER CI CI_APP_ID CI_BUILD_ID CI_BUILD_NUMBER CI_NAME CONTINUOUS_INTEGRATION RUN_ID)" ]; then
        return 0
    else
        return 1
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

POSTHOG_WASP_PUBLIC_API_KEY='CdDd2A0jKTI2vFAsrI9JWm3MqpOcgHz1bMyogAcwsE4'
send_telemetry() {
    context=""
    if check_if_on_ci; then
        context="${context} CI"
    fi
    context=$(echo "$context" | sed 's/^[ ]*//') # Remove any leading spaces.

    data='{ "api_key": "'$POSTHOG_WASP_PUBLIC_API_KEY'", "type": "capture", "event": "install-script:run", "distinct_id": "'$(random)$(date +'%s%N')'", "properties": { "os": "'$(get_os_info)'", "context": "'$context'" } }'

    url="https://app.posthog.com/capture"
    header="Content-Type: application/json"

    if [ -z "$WASP_TELEMETRY_DISABLE" ]; then
        if has_curl; then
            curl -sfL -d "$data" --header "$header" "$url" >/dev/null 2>&1
        elif has_wget; then
            wget -q --post-data="$data" --header="$header" "$url" >/dev/null 2>&1
        fi
    fi
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

main
