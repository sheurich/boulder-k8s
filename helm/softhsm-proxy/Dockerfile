# SoftHSM2 with PKCS#11 daemon for Kubernetes
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    softhsm2 \
    libsofthsm2 \
    opensc \
    gnutls-bin \
    && rm -rf /var/lib/apt/lists/*

# Create softhsm config directory
RUN mkdir -p /var/lib/softhsm/tokens && \
    mkdir -p /etc/softhsm && \
    echo "directories.tokendir = /var/lib/softhsm/tokens" > /etc/softhsm/softhsm2.conf

# Default environment
ENV SOFTHSM2_CONF=/etc/softhsm/softhsm2.conf

# Make tokens directory world-writable for dev
RUN chmod -R 777 /var/lib/softhsm

# Default command - sleep to allow exec into container for HSM operations
CMD ["sleep", "infinity"]
