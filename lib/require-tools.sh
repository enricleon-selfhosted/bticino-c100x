#!/bin/sh
# shellcheck shell=dash

_rt_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
for _cand in "$_rt_dir/platform.sh" "$_rt_dir/lib/platform.sh" "$_rt_dir/../lib/platform.sh" \
             "$_rt_dir/../../lib/platform.sh" "$_rt_dir/../../../lib/platform.sh"; do
    # shellcheck source=/dev/null
    [ -f "$_cand" ] && { . "$_cand"; break; }
done

HOST_TOOLS="curl tar"

resolve_tools() {
    MISSING_TOOLS=""
    for _tool in ${1:-$HOST_TOOLS}; do
        if _path=$(find_tool "$_tool"); then
            eval "TOOL_$(echo "$_tool" | tr '[:lower:]-' '[:upper:]_')=\"\$_path\""
        else
            MISSING_TOOLS="$MISSING_TOOLS $_tool"
        fi
    done
    MISSING_TOOLS="${MISSING_TOOLS# }"
}

require_tools() {
    _want="${*:-$HOST_TOOLS}"
    resolve_tools "$_want"

    if [ "$(platform)" = windows ] && [ -n "$MISSING_TOOLS" ]; then
        cat >&2 <<'EOF'

STOP: this is Git Bash, MSYS2 or Cygwin, and the firmware cannot be built here.

Building it means writing into a Linux filesystem, and Windows has no support for one. The
tools have never been ported to this shell either. Two ways on:

  1. WSL. It is a real Linux and it is one command. In PowerShell:

         wsl --install

     Then open this folder in Ubuntu and run ./install.sh again. Windows is needed for
     MyHomeSuite to flash the intercom anyway, so this is not an extra machine.

  2. Run it again with --docker, which does this part in a container.

EOF
        return 1
    fi

    if [ -n "$MISSING_TOOLS" ]; then
        _packages=""
        for _t in $MISSING_TOOLS; do
            _p=$(package_for "$_t")
            case " $_packages " in *" $_p "*) ;; *) _packages="$_packages $_p" ;; esac
        done

        _cmd=$(install_command "$_packages") || {
            cat >&2 <<EOF

STOP: missing $MISSING_TOOLS

No package manager was found here, so they cannot be installed for you. Install them and
run it again, or use --docker to install nothing at all.

EOF
            return 1
        }

        echo
        echo "Missing:$MISSING_TOOLS"
        echo
        echo "On $(platform_name) that is one command:"
        if [ "$(platform)" = macos ] && ! check_cmd brew; then
            cat <<'EOF'

Homebrew is not installed. It is the usual way to get command-line tools on a Mac:

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

Or run this again with --docker instead.
EOF
        fi
        echo
        echo "    $_cmd"
        echo

        if [ "${ASSUME_YES:-0}" != 1 ]; then
            if [ ! -t 0 ]; then
                echo "Run that, then try again. Or use --docker to install nothing." >&2
                return 1
            fi
            printf 'Run it now? [Y/n] '
            read -r _answer
            case "$_answer" in [Nn]*)
                echo "Nothing installed. --docker is there if you would rather not." >&2
                return 1 ;;
            esac
        fi

        echo "   installing"
        eval "$_cmd" || { echo "STOP: that did not work. Run it by hand." >&2; return 1; }

        resolve_tools "$_want"
        [ -n "$MISSING_TOOLS" ] && { echo "STOP: still missing:$MISSING_TOOLS" >&2; return 1; }
        echo "   got them"
    fi

    return 0
}
