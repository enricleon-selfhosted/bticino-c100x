#!/bin/sh
# shellcheck shell=dash

check_cmd() { command -v "$1" >/dev/null 2>&1; }
need_cmd()  { check_cmd "$1" || { echo "STOP: this needs '$1' and it is not here" >&2; exit 1; }; }

platform() {
    case "$(uname -s 2>/dev/null)" in
        Darwin)               echo macos ;;
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then echo wsl; else echo linux; fi ;;
        MINGW*|MSYS*|CYGWIN*) echo windows ;;
        *)                    echo unknown ;;
    esac
}

platform_name() {
    case "$(platform)" in
        macos)   echo "macOS" ;;
        wsl)     echo "Windows, inside WSL" ;;
        windows) echo "Windows, outside WSL" ;;
        linux)
            case "$(distro)" in
                unknown) echo "Linux" ;;
                *) printf '%s%s\n' "$(distro | cut -c1 | tr '[:lower:]' '[:upper:]')" \
                                    "$(distro | cut -c2-)" ;;
            esac ;;
        *)       echo "an unrecognised system" ;;
    esac
}

distro() {
    [ -r /etc/os-release ] || { echo unknown; return; }
    ( . /etc/os-release && echo "${ID:-unknown}" )
}

find_tool() {
    _f=$(command -v "$1" 2>/dev/null) && { printf '%s' "$_f"; return 0; }

    for _prefix in /opt/homebrew /usr/local; do
        for _sub in bin sbin; do
            [ -x "$_prefix/$_sub/$1" ] && { printf '%s' "$_prefix/$_sub/$1"; return 0; }
        done
    done

    for _d in /sbin /usr/sbin /usr/local/sbin; do
        [ -x "$_d/$1" ] && { printf '%s' "$_d/$1"; return 0; }
    done
    return 1
}

if check_cmd md5sum; then
    md5_of() { md5sum "$1" | cut -d' ' -f1; }
elif check_cmd md5; then
    md5_of() { md5 -q "$1"; }
else
    md5_of() { echo "no md5 tool on this machine" >&2; return 1; }
fi

sh_c_for_root() {
    if [ "$(id -u 2>/dev/null)" = 0 ]; then echo 'sh -c'
    elif check_cmd sudo;                then echo 'sudo -E sh -c'
    elif check_cmd su;                  then echo 'su -c'
    else                                     echo 'sh -c'   # will fail, and say why
    fi
}

pkg_manager() {
    for _m in brew apt-get dnf pacman apk zypper; do
        check_cmd "$_m" && { echo "$_m"; return 0; }
    done
    return 1
}

install_command() {
    _root=$(sh_c_for_root)
    case "$(pkg_manager)" in
        brew)     echo "brew install$*" ;;
        apt-get)  echo "$_root 'apt-get update -qq && apt-get install -y$*'" ;;
        dnf)      echo "$_root 'dnf install -y$*'" ;;
        pacman)   echo "$_root 'pacman -S --needed --noconfirm$*'" ;;
        apk)      echo "$_root 'apk add$*'" ;;
        zypper)   echo "$_root 'zypper install -y$*'" ;;
        *)        return 1 ;;
    esac
}

package_for() {
    echo "$1"
}

local_ip() {
    if check_cmd ip; then
        ip -o -f inet addr show 2>/dev/null \
            | awk '$2 != "lo" {split($4,a,"/"); print a[1]; exit}'
    elif check_cmd ipconfig && check_cmd route; then
        _if=$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')
        [ -n "$_if" ] && ipconfig getifaddr "$_if" 2>/dev/null
    elif check_cmd ifconfig; then
        ifconfig 2>/dev/null | awk '/inet /{ if ($2 != "127.0.0.1") { print $2; exit } }'
    fi
}

random_password() {
    if [ -r /dev/urandom ]; then
        LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom 2>/dev/null | head -c 16
    fi
}
