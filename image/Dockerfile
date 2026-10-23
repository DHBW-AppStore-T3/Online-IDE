# code-server for the pod runtime (appstore.yaml). One container per person; the
# platform sets user, read-only root filesystem and the password (env PASSWORD).
FROM docker.io/codercom/code-server:4.96.4

# The cluster is IPv6-primary: listen on all families, not on 127.0.0.1.
# No entrypoint script: it may try sudo, which the platform forbids.
ENTRYPOINT ["dumb-init", "/usr/bin/code-server"]
CMD ["--bind-addr", "[::]:8080", "--auth", "password", "--disable-telemetry", "/home/coder"]
