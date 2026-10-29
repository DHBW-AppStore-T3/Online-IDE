# code-server for the pod runtime (appstore.yaml). One container per person; the
# platform sets user, read-only root filesystem and the password (env PASSWORD).
FROM docker.io/codercom/code-server:4.144.0

# fixuid (a Go binary in the upstream image) only serves upstream's own entrypoint, which the ENTRYPOINT below
# replaces. The platform sets the UID itself, so it is dead weight, and its Go standard library accounted for 31 of
# the findings of the Trivy scan.
#
# The tools below are what the VM version (v1.x, packer/provision.sh) installed for the students and what the pod
# version (v2.0.x) lost: curl, wget, git, build-essential (gcc, g++, make), python3 with pip, and nodejs with npm.
# python3-venv and python3-dev are added: pip does not install into the system Python of Debian 13 (PEP 668), so
# students work in a virtual environment (python3 -m venv .venv), and wheels that must be compiled need the headers.
# unzip is a convenience for the terminal; the assignment ZIP is unpacked by unpack-assignments.py (python3), not by it.
USER root
RUN rm -f /usr/local/bin/fixuid \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        nodejs \
        npm \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        unzip \
        wget \
    && rm -rf /var/lib/apt/lists/*
# Security updates the base image does not have yet, at every CI build: app-ci.yml sets SECURITY_REFRESH to a new
# value for each run, so the build cache cannot keep an older package state (app-registry README, "Sicherheitsupdates
# im Image"). After the expensive steps, which stay cached; everything below is rebuilt in each run.
ARG SECURITY_REFRESH
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/*
COPY --chmod=0755 start.sh /usr/local/bin/online-ide-start
COPY --chmod=0755 unpack-assignments.py /usr/local/bin/online-ide-unpack
USER 1000

# The root filesystem is read-only; HOME (/home/coder) is the persistent volume. So installs land there:
# pip falls back to ~/.local when the system site-packages are not writable (PIP_BREAK_SYSTEM_PACKAGES lifts the
# PEP 668 refusal for that user install), npm -g goes to ~/.npm-global.
ENV PIP_BREAK_SYSTEM_PACKAGES=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    NPM_CONFIG_PREFIX=/home/coder/.npm-global \
    PATH=/home/coder/.npm-global/bin:/home/coder/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# The cluster is IPv6-primary: listen on all families, not on 127.0.0.1.
# Not upstream's entrypoint script: it may try sudo, which the platform forbids. start.sh needs neither sudo nor root.
ENTRYPOINT ["/usr/local/bin/online-ide-start"]
CMD ["--bind-addr", "[::]:8080", "--auth", "password", "--disable-telemetry", "/home/coder"]
