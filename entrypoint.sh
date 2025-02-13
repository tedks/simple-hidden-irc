#!/bin/bash
set -e

# Generate random operator password
OPER_PASS=$(pwgen -s 32 1)
echo "[Operator]" >> /etc/ngircd/ngircd.conf
echo "    Name = admin" >> /etc/ngircd/ngircd.conf
echo "    Password = $OPER_PASS" >> /etc/ngircd/ngircd.conf

# Create log directory with correct permissions
mkdir -p /var/log/tor
chown -R debian-tor:debian-tor /var/log/tor /var/lib/tor
chmod 700 /var/log/tor /var/lib/tor/hidden_service

# Start Tor as debian-tor user
echo "Starting Tor..."
su debian-tor -s /bin/bash -c 'tor' &

# Wait for Tor to generate the hidden service
while [ ! -f /var/lib/tor/hidden_service/hostname ]; do
    sleep 1
done

echo "Hidden service is ready!"
echo "Your IRC server is available at:"
cat /var/lib/tor/hidden_service/hostname
echo "Operator password: $OPER_PASS"

# Start ngircd in foreground
exec ngircd --nodaemon

