FROM debian:bullseye-slim

# Install required packages
RUN apt-get update && apt-get install -y \
    tor \
    ngircd \
    pwgen \
    && rm -rf /var/lib/apt/lists/*

# Configure Tor
RUN mkdir -p /var/lib/tor/hidden_service/ && \
    chown -R debian-tor:debian-tor /var/lib/tor && \
    chmod 700 /var/lib/tor/hidden_service/
COPY torrc /etc/tor/torrc

# Configure ngircd
COPY ngircd.conf /etc/ngircd/ngircd.conf

# Setup entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

