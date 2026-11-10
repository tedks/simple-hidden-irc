#!/usr/bin/env bash
set -euo pipefail

runfiles="${TEST_SRCDIR:?}/${TEST_WORKSPACE:?}"
stage="$(mktemp -d "${TEST_TMPDIR:?}/irc-config.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
mkdir -m 700 "$stage/tor-data" "$stage/hidden-service"
cp "$runfiles/ngircd.conf" "$stage/ngircd.conf"
cp "$runfiles/torrc" "$stage/torrc.source"

# The hidden-service target must be the one ngIRCd listens on locally.
grep -Eq '^[[:space:]]*Listen[[:space:]]*=[[:space:]]*127\.0\.0\.1[[:space:]]*$' "$stage/ngircd.conf"
irc_port="$(sed -nE 's/^[[:space:]]*Ports[[:space:]]*=[[:space:]]*([0-9]+)[[:space:]]*$/\1/p' "$stage/ngircd.conf")"
tor_ports="$(sed -nE 's/^HiddenServicePort ([0-9]+) 127\.0\.0\.1:([0-9]+)$/\1:\2/p' "$stage/torrc.source")"
[[ -n "$irc_port" && "$tor_ports" == "$irc_port:$irc_port" ]]

# Replace only the two container-owned directories before asking Tor to parse.
grep -Fxq 'DataDirectory /var/lib/tor' "$stage/torrc.source"
grep -Fxq 'HiddenServiceDir /var/lib/tor/hidden_service/' "$stage/torrc.source"
sed -e "s#^DataDirectory /var/lib/tor\$#DataDirectory $stage/tor-data#" \
  -e "s#^HiddenServiceDir /var/lib/tor/hidden_service/\$#HiddenServiceDir $stage/hidden-service/#" \
  "$stage/torrc.source" > "$stage/torrc"

tor --verify-config -f "$stage/torrc"
ngircd --config "$stage/ngircd.conf" --configtest
