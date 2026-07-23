#cloud-config

# Team-Gruppen erstellen
groups:
%{ for team in teams ~}
  - ${team}
%{ endfor ~}

# User-Accounts erstellen
users:
%{ for user_id, user in users ~}
  - name: ${user.username}
    groups: ${user.team}
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
%{ endfor ~}

# Passwörter setzen
chpasswd:
  list: |
%{ for user_id, user in users ~}
    ${user.username}:${passwords[user_id]}
%{ endfor ~}
  expire: false

# SSH Passwort-Authentifizierung aktivieren
ssh_pwauth: true

# Team-Aufgaben in neutralen Staging-Pfad schreiben
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

# code-server pro User als System-Service starten
# Jeder User bekommt eigenen code-server auf eigenem Port mit eigenem Passwort
runcmd:
%{ for user_id, user in users ~}
  # User ${user.username}: code-server auf Port ${lookup(user_ports, user_id, 8080)}
  - mkdir -p /home/${user.username}/Coding-Aufgabe
  # Team-Aufgaben für jeden User kopieren
  - |
    if [ -d /tmp/assignment ] && [ "$(ls -A /tmp/assignment 2>/dev/null)" ]; then
      for srcfile in /tmp/assignment/*; do
        fname=$(basename "$srcfile")
        if echo "$fname" | grep -qi '\.zip$'; then
          unzip -o "$srcfile" -d /home/${user.username}/Coding-Aufgabe/ > /dev/null 2>&1 || true
        else
          cp "$srcfile" /home/${user.username}/Coding-Aufgabe/"$fname"
        fi
      done
    fi
  - chown -R ${user.username}:${user.username} /home/${user.username}/Coding-Aufgabe
  - chmod 644 /home/${user.username}/Coding-Aufgabe/* 2>/dev/null || true
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
  # Staging-Verzeichnis aufräumen
  - rm -rf /tmp/assignment
