# code-server for the pod runtime (appstore.yaml). One container per person; the
# platform sets user, read-only root filesystem and the password (env PASSWORD).
FROM docker.io/codercom/code-server:4.143.1

# fixuid (a Go binary in the upstream image) only serves upstream's own entrypoint, which the ENTRYPOINT below
# replaces. The platform sets the UID itself, so it is dead weight, and its Go standard library accounted for 31 of
# the findings of the Trivy scan.
# unzip unpacks a team's assignment ZIP at the first start (start.sh).
USER root
RUN rm -f /usr/local/bin/fixuid \
    && apt-get update \
    && apt-get install -y --no-install-recommends unzip \
    && rm -rf /var/lib/apt/lists/*
COPY --chmod=0755 start.sh /usr/local/bin/online-ide-start
USER 1000

# The cluster is IPv6-primary: listen on all families, not on 127.0.0.1.
# Not upstream's entrypoint script: it may try sudo, which the platform forbids. start.sh needs neither sudo nor root.
ENTRYPOINT ["/usr/local/bin/online-ide-start"]
CMD ["--bind-addr", "[::]:8080", "--auth", "password", "--disable-telemetry", "/home/coder"]
