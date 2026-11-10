#!/usr/bin/env bash
set -euo pipefail

runfiles="${TEST_SRCDIR:?}/${TEST_WORKSPACE:?}"
stage="$(mktemp -d "${TEST_TMPDIR:?}/irc-config.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
mkdir -m 700 "$stage/tor-data" "$stage/hidden-service"
cp "$runfiles/ngircd.conf" "$stage/ngircd.conf"
cp "$runfiles/torrc" "$stage/torrc.source"
printf 'Bazel configuration fixture\n' > "$stage/motd"
mapfile -t sections < <(grep -E '^[[:space:]]*\[[^]]+\]' "$stage/ngircd.conf")
[[ ${#sections[@]} -eq 3 && "${sections[0]}" == '[Global]' && \
  "${sections[1]}" == '[Limits]' && "${sections[2]}" == '[Options]' ]]

# Reject duplicate or extra listeners and hidden-service mappings before
# giving the parsers the scratch copies.
mapfile -t listeners < <(grep -Ei '^[[:space:]]*Listen[[:space:]]*=' "$stage/ngircd.conf")
[[ ${#listeners[@]} -eq 1 && "${listeners[0]}" =~ ^[[:space:]]*Listen[[:space:]]*=[[:space:]]*127\.0\.0\.1[[:space:]]*$ ]]
mapfile -t ports < <(grep -Ei '^[[:space:]]*Ports[[:space:]]*=' "$stage/ngircd.conf")
[[ ${#ports[@]} -eq 1 && "${ports[0]}" =~ ^[[:space:]]*Ports[[:space:]]*=[[:space:]]*([0-9]+)[[:space:]]*$ ]]
irc_port="${BASH_REMATCH[1]}"
mapfile -t hidden_ports < <(grep -Ei '^[[:space:]]*HiddenServicePort[[:space:]]+' "$stage/torrc.source")
[[ ${#hidden_ports[@]} -eq 1 && "${hidden_ports[0]}" =~ ^HiddenServicePort[[:space:]]+([0-9]+)[[:space:]]+127\.0\.0\.1:([0-9]+)[[:space:]]*$ ]]
[[ "${BASH_REMATCH[1]}" == "$irc_port" && "${BASH_REMATCH[2]}" == "$irc_port" ]]
if grep -Eiq '^[[:space:]]*IncludeDir[[:space:]]*=' "$stage/ngircd.conf"; then
  echo 'ngIRCd IncludeDir would read undeclared host configuration' >&2
  exit 1
fi
mapfile -t motd_lines < <(grep -Ei '^[[:space:]]*MotdFile[[:space:]]*=' "$stage/ngircd.conf")
[[ ${#motd_lines[@]} -eq 1 && "${motd_lines[0]}" == '    MotdFile = /etc/ngircd/motd' ]]
sed -i "s#^    MotdFile = /etc/ngircd/motd\$#    MotdFile = $stage/motd#" "$stage/ngircd.conf"
for key in ServerUID ServerGID; do
  mapfile -t identity_lines < <(grep -Ei "^[[:space:]]*${key}[[:space:]]*=" "$stage/ngircd.conf")
  [[ ${#identity_lines[@]} -eq 1 && "${identity_lines[0]}" == "    $key = irc" ]]
done
test_user="$(id -un)"
test_group="$(id -gn)"
[[ -n "$test_user" && -n "$test_group" ]]
sed -i "s#^    ServerUID = irc\$#    ServerUID = $test_user#" "$stage/ngircd.conf"
sed -i "s#^    ServerGID = irc\$#    ServerGID = $test_group#" "$stage/ngircd.conf"

# Replace only the two container-owned directories before asking Tor to parse.
for expected in \
  'DataDirectory /var/lib/tor' \
  'HiddenServiceDir /var/lib/tor/hidden_service/' \
  'SocksPort 0' 'ControlPort 0' 'RunAsDaemon 0' 'Log notice stdout'; do
  key="${expected%% *}"
  mapfile -t found < <(grep -Ei "^[[:space:]]*${key}[[:space:]]+" "$stage/torrc.source")
  [[ ${#found[@]} -eq 1 && "${found[0]}" == "$expected" ]]
done
mapfile -t active_tor < <(grep -Ev '^[[:space:]]*(#|$)' "$stage/torrc.source")
[[ ${#active_tor[@]} -eq 7 ]]
sed -e "s#^DataDirectory /var/lib/tor\$#DataDirectory $stage/tor-data#" \
  -e "s#^HiddenServiceDir /var/lib/tor/hidden_service/\$#HiddenServiceDir $stage/hidden-service/#" \
  "$stage/torrc.source" > "$stage/torrc"

tor --defaults-torrc /dev/null --verify-config -f "$stage/torrc"
if ! ngircd_output="$(ngircd --config "$stage/ngircd.conf" --configtest 2>&1)"; then
  printf '%s\n' "$ngircd_output" >&2
  exit 1
fi
printf '%s\n' "$ngircd_output"
[[ "$ngircd_output" == *'Ok, dump of your server configuration follows:'* ]]
while IFS= read -r diagnostic; do
  case "$diagnostic" in
    ' - No administrative information configured but required by RFC!') ;;
    *) echo "ngIRCd config diagnostic: $diagnostic" >&2; exit 1 ;;
  esac
done < <(printf '%s\n' "$ngircd_output" | grep '^ - ' || true)
