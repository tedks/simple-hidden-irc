#!/usr/bin/env bash
set -euo pipefail

runfiles="${TEST_SRCDIR:?}/${TEST_WORKSPACE:?}"
stage="$(mktemp -d "${TEST_TMPDIR:?}/irc-config.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
mkdir -m 700 "$stage/tor-data" "$stage/hidden-service"
cp "$runfiles/ngircd.conf" "$stage/ngircd.conf"
cp "$runfiles/torrc" "$stage/torrc.source"

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

# Replace only the two container-owned directories before asking Tor to parse.
for expected in \
  'DataDirectory /var/lib/tor' \
  'HiddenServiceDir /var/lib/tor/hidden_service/' \
  'SocksPort 0' 'ControlPort 0' 'RunAsDaemon 0'; do
  key="${expected%% *}"
  mapfile -t found < <(grep -Ei "^[[:space:]]*${key}[[:space:]]+" "$stage/torrc.source")
  [[ ${#found[@]} -eq 1 && "${found[0]}" == "$expected" ]]
done
sed -e "s#^DataDirectory /var/lib/tor\$#DataDirectory $stage/tor-data#" \
  -e "s#^HiddenServiceDir /var/lib/tor/hidden_service/\$#HiddenServiceDir $stage/hidden-service/#" \
  "$stage/torrc.source" > "$stage/torrc"

tor --verify-config -f "$stage/torrc"
ngircd --config "$stage/ngircd.conf" --configtest
