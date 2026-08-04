#!/bin/sh
# shellcheck shell=dash
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0

ok()   { printf '  ok    %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
same() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 -- wanted [$3], got [$2]"; fi; }
head_() { printf '\n%s\n' "$1"; }

SCRIPTS="$(find "$ROOT" -name '*.sh' -not -path '*/build/*' -not -path '*/.git/*' | sort)"

head_ "Parses under every shell it will meet"
for shell in dash "busybox sh"; do
    command -v "${shell%% *}" >/dev/null 2>&1 || { printf '  --    %s not here, skipped\n' "$shell"; continue; }
    n=0
    for f in $SCRIPTS; do
        if $shell -n "$f" 2>"$TMP/err"; then n=$((n + 1)); else bad "$shell: ${f#"$ROOT"/} -- $(cat "$TMP/err")"; fi
    done
    ok "$shell: $n scripts"
done

head_ "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
    SC="shellcheck"
elif command -v docker >/dev/null 2>&1; then
    SC="docker run --rm -v $ROOT:/mnt -w /mnt koalaman/shellcheck:stable"
else
    SC=""
fi
if [ -n "$SC" ]; then
    rel=""
    for f in $SCRIPTS; do rel="$rel ${f#"$ROOT"/}"; done
    # shellcheck disable=SC2086
    if $SC --shell=sh --severity=warning $rel > "$TMP/sc" 2>&1; then
        ok "clean at warning level and above"
    else
        bad "$(grep -c '^In ' "$TMP/sc" 2>/dev/null || echo some) files have findings"
        sed -n '1,40p' "$TMP/sc" | sed 's/^/        /'
    fi
else
    printf '  --    no shellcheck and no docker, skipped\n'
fi

head_ "Recognises the system it is on"
mkdir -p "$TMP/bin"
fake_uname() {
    printf '#!/bin/sh\ncase "$1" in -s) echo "%s";; -m) echo x86_64;; esac\n' "$1" > "$TMP/bin/uname"
    chmod +x "$TMP/bin/uname"
    PATH="$TMP/bin:$PATH" sh -c ". '$ROOT/lib/platform.sh'; platform"
}
same "macOS"              "$(fake_uname Darwin)"            macos
same "Git Bash"           "$(fake_uname MINGW64_NT-10.0)"   windows
same "MSYS2"              "$(fake_uname MSYS_NT-10.0)"      windows
same "Cygwin"             "$(fake_uname CYGWIN_NT-10.0)"    windows
same "something unheard of" "$(fake_uname Plan9)"           unknown
rm -f "$TMP/bin/uname"
same "this machine"       "$(sh -c ". '$ROOT/lib/platform.sh'; platform")" \
                          "$(grep -qi microsoft /proc/version 2>/dev/null && echo wsl || echo linux)"

head_ "Finds tools that are installed but not on the PATH"
mkdir -p "$TMP/sbin"
printf '#!/bin/sh\necho hola\n' > "$TMP/sbin/notonpath"
chmod +x "$TMP/sbin/notonpath"
out=$(sh -c ". '$ROOT/lib/platform.sh'
    find_tool() {
        _f=\$(command -v \"\$1\" 2>/dev/null) && { printf %s \"\$_f\"; return 0; }
        for _d in '$TMP/sbin'; do [ -x \"\$_d/\$1\" ] && { printf %s \"\$_d/\$1\"; return 0; }; done
        return 1
    }
    find_tool notonpath")
same "looks past the PATH" "$out" "$TMP/sbin/notonpath"
same "and still reports a real absence" \
     "$(sh -c ". '$ROOT/lib/platform.sh'; find_tool definitelynothere || echo none")" none

head_ "Copes with a Mac having no md5sum"
printf '#!/bin/sh\n[ "$1" = -q ] && echo MAC-HASH\n' > "$TMP/bin/md5"
chmod +x "$TMP/bin/md5"
ln -sf /bin/sh "$TMP/bin/sh"
same "picks md5 when md5sum is absent" \
     "$(env PATH="$TMP/bin" "$TMP/bin/sh" -c ". '$ROOT/lib/platform.sh'; md5_of /etc/hostname")" \
     "MAC-HASH"

head_ "A cut-off download does nothing"
total=$(wc -l < "$ROOT/install.sh")
cut_ok=1
n=5
while [ "$n" -lt "$total" ]; do
    head -n "$n" "$ROOT/install.sh" > "$TMP/cut.sh"
    rm -rf "${TMP:?}/home"
    out=$(HOME="$TMP/home" sh "$TMP/cut.sh" 2>&1 || true)
    case "$out" in *Fetching*) bad "at $n of $total lines it tried to fetch"; cut_ok=0 ;; esac
    [ -d "$TMP/home" ] && { bad "at $n of $total lines it created files"; cut_ok=0; }
    n=$((n + 5))
done
[ "$cut_ok" = 1 ] && ok "cut at every 5th line of $total: never acts"

head_ "The instructions for fwz are well formed"
mkdir -p "$TMP/payload/payload" "$TMP/payload/converge.d"
: > "$TMP/payload/setup.sh"; : > "$TMP/payload/setup.conf"
: > "$TMP/payload/payload/bundle.js"; : > "$TMP/payload/payload/run.sh"
: > "$TMP/payload/converge.d/80-network"
if "$ROOT/firmware/steps/write-changes.sh" "$TMP/payload" "$ROOT/firmware/overlay" \
       "ssh-ed25519 AAAA test" '$1$abc$xxxxxxxxxxxxxxxxxxxxx.' > "$TMP/changes.txt" 2>"$TMP/opserr"
then
    bad_ops=0
    while IFS= read -r line; do
        case "$line" in ''|'#'*) continue ;; esac
        verb=${line%%	*}
        case "$verb" in
            mkdir|put|append|symlink|rm) ;;
            *) bad "write-changes.sh emitted an instruction fwz does not know: $verb"; bad_ops=1 ;;
        esac
        case "$line" in *"	"*) ;; *) bad "no tab in: $line"; bad_ops=1 ;; esac
    done < "$TMP/changes.txt"
    n=$(grep -cvE '^#|^$' "$TMP/changes.txt")
    [ "$bad_ops" = 0 ] && ok "$n instructions, all of a kind fwz understands"

    grep -q 'S97setup' "$TMP/changes.txt" && ok "runs our script before the intercom's own" \
        || bad "nothing sets up S97setup"
    grep -q 'S98dropbear' "$TMP/changes.txt" && ok "turns on shell access" || bad "no ssh"
    grep -q 'rm.*S99TcpDump2Mqtt' "$TMP/changes.txt" && ok "leaves out the packet-capture service" \
        || bad "the packet-capture service is still there"
    grep -q 'if-up.d/intercom' "$TMP/changes.txt" \
        && ok "the ports are re-opened every time an interface comes up" \
        || bad "the firewall hook is not in the image, so nothing would answer for long"
    grep -q 'converge.d/80-network' "$TMP/changes.txt" && ok "the converge steps go in" \
        || bad "no converge step reached the image"
else
    bad "write-changes.sh failed: $(cat "$TMP/opserr")"
fi

head_ "Only the ports the design names are opened"
HOOK="$ROOT/firmware/overlay/etc/network/if-up.d/intercom"
[ -x "$HOOK" ] && ok "the hook is there and can be run" \
    || bad "the hook is missing or not executable: $HOOK"

same "opens exactly the ports meant to answer" \
    "$(grep -oE '^open (tcp|udp) [0-9]+' "$HOOK" | awk '{print $2"/"$3}' | sort | tr '\n' ' ')" \
    "tcp/1984 tcp/8080 tcp/8555 udp/8555 "

kept_in=1
for p in 6554 8554 40004 5060 7667 3478; do
    grep -qE "^open (tcp|udp) $p( |\$)" "$HOOK" && { bad "$p is opened, and never should be"; kept_in=0; }
done
[ "$kept_in" = 1 ] && ok "nothing answered on this board is reachable from off it"

grep -qE '\-p (tcp|udp) -j ACCEPT' "$HOOK" \
    && bad "a rule opens a whole protocol rather than a named port" \
    || ok "no rule opens a whole protocol"

grep -qE 'INPUT 1 -p ' "$HOOK" \
    && bad "a rule is inserted with no source restriction" \
    || ok "no rule is inserted without a source"

same "trusts private address space, and nothing else" \
    "$(sed -n 's/^PRIVATE="\(.*\)"$/\1/p' "$HOOK")" \
    "10.0.0.0/8 172.16.0.0/12 192.168.0.0/16"
grep -q 'INPUT 1 -i "$IFACE" -s "$src"' "$HOOK" \
    && ok "every rule names both the interface and the source" \
    || bad "a rule does not bind to the wireless interface"

CONST="$ROOT/custom_components/bticino_c100x/const.py"
same "Home Assistant calls the controller on the port that is opened" \
    "$(sed -n 's/^PORT_CONTROLLER *= *\([0-9]*\).*/\1/p' "$CONST")" "8080"
same "Home Assistant calls go2rtc on the port that is opened" \
    "$(sed -n 's/^PORT_GO2RTC *= *\([0-9]*\).*/\1/p' "$CONST")" "1984"
grep -q 'listen: ":1984"' "$ROOT/device/go2rtc.yaml" \
    && ok "go2rtc answers on the api port that is opened" || bad "go2rtc's api port disagrees"
grep -q 'listen: ":8555"' "$ROOT/device/go2rtc.yaml" \
    && ok "go2rtc answers on the media port that is opened" || bad "go2rtc's media port disagrees"
grep -q 'listen: "127.0.0.1:8554"' "$ROOT/device/go2rtc.yaml" \
    && ok "go2rtc's own video stays on this board" || bad "go2rtc's internal video is not on loopback"

head_ "Both installers ask the same questions"
grep -oE 'ask [a-z]+\.[a-z_]+' "$ROOT/install.sh"   | awk '{print $2}' | sort > "$TMP/q-sh"
grep -oE "Ask '[a-z]+\.[a-z_]+'" "$ROOT/install.ps1" | tr -d "'" | awk '{print $2}' | sort > "$TMP/q-ps"
if cmp -s "$TMP/q-sh" "$TMP/q-ps"; then
    ok "$(wc -l < "$TMP/q-sh" | tr -d ' ') questions, the same on both"
else
    bad "they ask different things:"
    diff "$TMP/q-sh" "$TMP/q-ps" | sed 's/^/        /'
fi

for k in $(cat "$TMP/q-sh"); do
    grep -rql "$k" "$ROOT/firmware" "$ROOT/device" "$ROOT/lib" 2>/dev/null \
        || bad "nothing reads $k"
done
ok "every answer is read somewhere"

if grep -rq '8\*19\*20\|8\*20\*20' "$ROOT/custom_components" 2>/dev/null; then
    bad "a door sequence is written into the integration"
else
    ok "the integration consumes events, not bus sequences"
fi

head_ "Nothing personal ships"
leaks=0
allowed_ip='^(0\.0\.0\.0|127\.0\.0\.1|255\.255\.255\.[0-9]+|224\.0\.0\.0|240\.0\.0\.0|239\.255\.76\.67|10\.0\.0\.5|10\.0\.0\.0|172\.16\.0\.0|192\.168\.1\.[0-9]+|192\.168\.0\.0)$'
for f in $(cd "$ROOT" && git ls-files | grep -v 'self-test'); do
    for ip in $(grep -aoE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$ROOT/$f" 2>/dev/null | sort -u); do
        printf '%s' "$ip" | grep -qE "$allowed_ip" || {
            bad "the address $ip is in $f, and it is not one of the allowed ones"
            leaks=1
        }
    done
done

hits=$(cd "$ROOT" && git ls-files -z | xargs -0 grep -alE '\b([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b' 2>/dev/null | grep -v self-test || true)
[ -n "$hits" ] && { bad "a hardware address is in: $(echo "$hits" | tr '\n' ' ')"; leaks=1; }

hits=$(cd "$ROOT" && git ls-files -z | xargs -0 grep -aoE 'ssh-(rsa|ed25519) AAAA[A-Za-z0-9+/=]{30,}' 2>/dev/null | head -3 || true)
[ -n "$hits" ] && { bad "what looks like a real public key: $(echo "$hits" | cut -c1-60)"; leaks=1; }

hits=$(cd "$ROOT" && git ls-files -z | xargs -0 grep -anE '/lovelace/[a-z]' 2>/dev/null \
       | grep -viE 'your-dashboard|YOUR_DASHBOARD' | grep -v self-test || true)
[ -n "$hits" ] && { bad "a dashboard address: $(echo "$hits" | head -1)"; leaks=1; }

PRIVATE="$ROOT/tools/private-strings"
if [ -r "$PRIVATE" ]; then
    while IFS= read -r pat; do
        case "$pat" in ''|'#'*) continue ;; esac
        hits=""
        for pf in $(cd "$ROOT" && git ls-files | grep -v self-test); do
            grep -aE "$pat" "$ROOT/$pf" 2>/dev/null \
                | grep -qvE 'github\.com/|githubusercontent\.com/|"@enricleon-selfhosted"' && hits="$hits $pf"
        done
        [ -n "$hits" ] && { bad "$pat still in:$hits"; leaks=1; }
    done < "$PRIVATE"
fi
[ "$leaks" = 0 ] && ok "every address in here is one that is meant to be"

head_ "Home Assistant gets everything from one integration"
COMPONENT="$ROOT/custom_components/bticino_c100x"
shape=0
[ -f "$COMPONENT/manifest.json" ] || { bad "there is no manifest.json"; shape=1; }
grep -q '"domain": "bticino_c100x"' "$COMPONENT/manifest.json" 2>/dev/null \
    || { bad "the manifest domain does not match the folder it sits in"; shape=1; }
grep -q '"version"' "$COMPONENT/manifest.json" 2>/dev/null \
    || { bad "the manifest has no version, and HACS will not install it"; shape=1; }
grep -q '"config_flow": true' "$COMPONENT/manifest.json" 2>/dev/null \
    || { bad "without a config flow the address would have to be edited in by hand"; shape=1; }
for platform in sensor binary_sensor switch select button image; do
    [ -f "$COMPONENT/$platform.py" ] || { bad "$platform.py is missing"; shape=1; }
done
[ "$shape" = 0 ] && ok "the integration is the shape HACS and Home Assistant expect"

if command -v python3 >/dev/null 2>&1; then
    head_ "The integration is valid python"
    if (cd "$COMPONENT" && python3 -m py_compile ./*.py 2>/dev/null); then
        ok "every file compiles"
    else
        bad "something in the integration does not compile"
    fi
    rm -rf "$COMPONENT/__pycache__"
fi

head_ "Nothing has to be copied in or filled in by hand"
byhand=0
[ -d "$ROOT/homeassistant" ] \
    && { bad "there is a YAML package again, and HACS cannot install one"; byhand=1; }
hits=$(grep -rlE 'INTERCOM_HOST|GO2RTC_HOST|YOUR_PHONE' "$ROOT/custom_components" 2>/dev/null || true)
[ -n "$hits" ] && { bad "the integration still carries something to fill in: $(echo "$hits" | tr '\n' ' ')"; byhand=1; }
hits=$(cd "$ROOT" && git ls-files -z 2>/dev/null | xargs -0 grep -lE 'GO2RTC_HOST' 2>/dev/null | grep -v self-test || true)
[ -n "$hits" ] && { bad "GO2RTC_HOST is left over in: $(echo "$hits" | tr '\n' ' ')"; byhand=1; }
[ "$byhand" = 0 ] && ok "the address is asked for once, in the interface, and nothing else is edited"

head_ "Every address points at a real repository"
placeholder=$(cd "$ROOT" && git ls-files -z 2>/dev/null | xargs -0 grep -l 'OWNER/' 2>/dev/null | grep -v self-test || true)
[ -n "$placeholder" ] \
    && bad "the repository owner is still a placeholder in: $(echo "$placeholder" | tr '\n' ' ')" \
    || ok "the install commands and the download addresses are real"

head_ "The cards are offered, not placed"
hits=$(cd "$ROOT" && git ls-files -z 2>/dev/null | xargs -0 grep -lE '/lovelace/[a-z]' 2>/dev/null | grep -v self-test || true)
[ -n "$hits" ] && bad "a dashboard address is named in: $(echo "$hits" | tr '\n' ' ')" \
    || ok "no dashboard is named anywhere"

head_ "Installing needs no python"
onpath=""
for f in "$ROOT/install.sh" "$ROOT/install.ps1" "$ROOT/firmware/build.sh" \
         "$ROOT/lib"/*.sh "$ROOT/firmware/steps"/*.sh; do
    [ -f "$f" ] || continue
    sed 's/#.*//' "$f" | grep -qE '(^|[^a-z])python[0-9]?[ "]|\.py[ "]' && onpath="$onpath $f"
done
[ -z "$onpath" ] && ok "nothing on the install path touches python" \
    || bad "python has crept onto the install path: $onpath"

head_ "The cards travel with the integration"
CARDS="$ROOT/custom_components/bticino_c100x/www/bticino-c100x-cards.js"
if [ -f "$ROOT/hacs.json" ] && [ -f "$CARDS" ]; then
    grep -q '"filename"' "$ROOT/hacs.json" 2>/dev/null \
        && bad "hacs.json still describes a lone dashboard card" \
        || ok "hacs.json describes an integration"
    for card in intercom-button intercom-video; do
        grep -q "customElements.define('$card'" "$CARDS" 2>/dev/null \
            && ok "registers $card" || bad "$card is not registered"
    done
    grep -q '/api/bticino_c100x/ws' "$CARDS" 2>/dev/null \
        && grep -q 'f"/api/{DOMAIN}/ws"' "$ROOT/custom_components/bticino_c100x/webrtc.py" 2>/dev/null \
        && ok "the card and the integration agree on where the handshake happens" \
        || bad "the card and the integration disagree on the signalling address"
else
    bad "no hacs.json or no cards, so nothing could be installed through HACS"
fi

head_ "The runtime is packed by fwz, not by whatever the machine has"
packed=0
for f in "$ROOT/firmware/steps/fetch-runtime.sh" "$ROOT/install.ps1"; do
    if grep -qE '(^|[^-])tar +-?c' "$f" 2>/dev/null; then
        bad "$(basename "$f") packs with the system tar again"
        packed=1
    fi
    grep -q 'pack --root' "$f" 2>/dev/null \
        || { bad "$(basename "$f") does not pack with fwz"; packed=1; }
done
for f in "$ROOT/firmware/steps/fetch-runtime.sh" "$ROOT/install.ps1"; do
    grep -q 'runtime.manifest' "$f" 2>/dev/null \
        || { bad "$(basename "$f") does not read runtime.manifest, so it can drift"; packed=1; }
    for path in node/bin/node node/bin/node.bin; do
        grep -q -- "$path" "$f" 2>/dev/null \
            || { bad "$(basename "$f") does not keep $path runnable"; packed=1; }
    done
done
[ -f "$ROOT/firmware/steps/runtime.manifest" ] \
    || { bad "there is no runtime.manifest for them to read"; packed=1; }
[ "$packed" = 0 ] && ok "both pack with fwz, from one list, and agree on what stays runnable"

head_ "Docker is only ever used because you asked"
sneaky=0
: > "$TMP/sneaky"
for f in $SCRIPTS "$ROOT/install.ps1"; do
    [ -f "$f" ] || continue
    case "$f" in *self-test.sh) continue ;; esac
    awk -v name="${f#"$ROOT"/}" '
        function refusal(s) { return s ~ /STOP|exit 1|ForegroundColor Red|err |die / }
        /^[[:space:]]*#/ { next }
        {
            if (probe && refusal($0)) { probe = 0 }
            else if (probe && NF && ++seen >= 5) {
                print name ":" probe ": uses docker just because it is installed"
                probe = 0
            }
        }
        /(check_cmd|command -v|Test-Command)[^|]*[Dd]ocker/ {
            if (refusal($0)) next
            probe = NR; seen = 0
        }
        END { if (probe) print name ":" probe ": uses docker just because it is installed" }
    ' "$f" >> "$TMP/sneaky"
done
if [ -s "$TMP/sneaky" ]; then
    while read -r line; do bad "$line"; done < "$TMP/sneaky"
    sneaky=1
fi
[ "$sneaky" = 0 ] && ok "no script reaches for docker on its own"

if command -v docker >/dev/null 2>&1 && ! (command -v node >/dev/null 2>&1 && node --version 2>/dev/null | grep -q '^v18\.'); then
    out=$("$ROOT/device/build-controller.sh" 2>&1 || true)
    case "$out" in
        *"needs node 18"*) ok "the controller build refuses instead of using the docker that is here" ;;
        *)                 bad "the controller build did something other than refuse" ;;
    esac
fi

printf '\n%s\n' "-----------------------------------------"
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
