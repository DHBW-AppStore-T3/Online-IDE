#cloud-config

# Create team groups
groups:
%{ for team in teams ~}
  - ${team}
%{ endfor ~}

# Create user accounts
users:
%{ for user_id, user in users ~}
  - name: ${user.username}
    groups: ${user.team}
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
%{ endfor ~}

# Set passwords
chpasswd:
  list: |
%{ for user_id, user in users ~}
    ${user.username}:${passwords[user_id]}
%{ endfor ~}
  expire: false

# Enable SSH password authentication
ssh_pwauth: true

# Write assignment files to neutral staging path
write_files:
%{ if length(assignment_files) > 0 ~}
%{ for _, file in assignment_files ~}
  - path: /tmp/assignment/${file.name}
    permissions: '0644'
    owner: root:root
    encoding: b64
    content: ${file.content_b64}
%{ endfor ~}
%{ endif ~}

# Start code-server per user as a systemd service — each user gets a dedicated instance on a dedicated port
runcmd:
%{ for user_id, user in users ~}
  # ${user.username}: code-server on port ${lookup(user_ports, user_id, 8080)}
  - mkdir -p /home/${user.username}/Coding-Aufgabe
  # Extract assignment ZIPs into each user's workspace
  - |
    if [ -d /tmp/assignment ] && [ "$(ls -A /tmp/assignment 2>/dev/null)" ]; then
      for srcfile in /tmp/assignment/*.zip; do
        [ -f "$srcfile" ] || continue
        unzip -o "$srcfile" -d /home/${user.username}/Coding-Aufgabe/ > /dev/null 2>&1 || true
      done
    fi
  - chown -R ${user.username}:${user.username} /home/${user.username}/Coding-Aufgabe
  - find /home/${user.username}/Coding-Aufgabe -type f -exec chmod 644 {} \;
  - mkdir -p /home/${user.username}/.local/share/code-server
  - mkdir -p /home/${user.username}/.config/code-server
  - chown -R ${user.username}:${user.username} /home/${user.username}/.local
  - chown -R ${user.username}:${user.username} /home/${user.username}/.config
  - |
    cat > /home/${user.username}/.config/code-server/config.yaml << 'EOFCONFIG${user_id}'
    bind-addr: 0.0.0.0:${lookup(user_ports, user_id, 8080)}
    auth: password
    password: "${passwords[user_id]}"
    cert: false
    user-data-dir: /home/${user.username}/.local/share/code-server
    EOFCONFIG${user_id}
  - chown ${user.username}:${user.username} /home/${user.username}/.config/code-server/config.yaml
  - chmod 600 /home/${user.username}/.config/code-server/config.yaml
  - |
    cat > /etc/systemd/system/code-server-${user.username}.service << 'EOFSVC${user_id}'
    [Unit]
    Description=code-server for ${user.username}
    After=network.target

    [Service]
    Type=simple
    User=${user.username}
    WorkingDirectory=/home/${user.username}
    ExecStart=/usr/bin/code-server --config /home/${user.username}/.config/code-server/config.yaml
    Restart=always
    RestartSec=10

    [Install]
    WantedBy=multi-user.target
    EOFSVC${user_id}
  - systemctl daemon-reload
  - systemctl enable code-server-${user.username}
  - systemctl start code-server-${user.username}
%{ endfor ~}
  # Clean up staging directory
  - rm -rf /tmp/assignment
