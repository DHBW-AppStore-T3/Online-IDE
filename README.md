# Online-IDE – VS Code im Browser

Eine eigene Entwicklungsumgebung (code-server, VS Code im Browser) für jede Person eines Deployments, mit eigenem Speicher und eigenem Login. Die App läuft als Pods (`appstore.yaml`, App-Vertrag v2): **ein code-server-Pod je Person** mit 5 GiB Speicher im Home-Verzeichnis, HTTPS-Link und eigenem Passwort unter „Meine Zugänge“.

## User-Management

Jede Person erhält ihren eigenen Pod und ein von der Plattform erzeugtes Passwort. Der Login in code-server erfolgt mit diesem Passwort. Dateien liegen im persistenten Home-Verzeichnis (`/home/coder`) und überstehen Pause/Fortsetzen und Neustart.

- **Software:** code-server (Version siehe `image/Dockerfile`), Internetzugang ist erlaubt.
- **Kein `sudo`:** Systempakete (`apt`) können nicht installiert werden. Das Root-Dateisystem ist schreibgeschützt, schreibbar sind nur das Home-Verzeichnis und `/tmp`.

## Konfigurierbare Variablen

| Variable | Beschreibung | Pflicht |
|---|---|---|
| `assignments` | Aufgaben als ZIP-Datei (höchstens 1 MiB), eine Datei je Team | Nein |

Das ZIP wird beim ersten Start des Arbeitsplatzes jeder Person im Team nach `~/Coding-Aufgabe` entpackt (`image/start.sh`). Ohne ZIP startet der Arbeitsplatz leer. Ein Beispiel liegt als `aufgaben.zip` im Repository (wird auch vom Smoke-Test verwendet). Die Variable ist in `v2.0.1` noch nicht enthalten, sondern erst in der nächsten Version (nach neuem Image-Digest und Tag).

## Image und CI

`image/Dockerfile` wird von `.github/workflows/ci.yml` gebaut (zentrale Pipeline aus `app-registry`: Vertrag, hadolint, Smoke-Test, Trivy) und mit dem Sicherheitskontext der Plattform getestet (UID 1000, Read-only-Root, keine Capabilities; `.github/smoke-test.sh`). Bekannte, noch nicht behebbare Befunde im Upstream-Image stehen mit Ablaufdatum in `.trivyignore`.

- **Pull Request:** das Image wird gebaut und getestet, aber nicht veröffentlicht.
- **Push auf `main` oder `dev`:** das Image wird zusätzlich nach GHCR gepusht. Den Digest zeigt die Zusammenfassung des Jobs.
- Nach einer Änderung den neuen Digest in `appstore.yaml` eintragen und eine neue Version taggen. Die Plattform deployt nur Images, die per Digest festgelegt sind.

## Ältere Versionen

Die VM-Versionen (`v1.x`, cloud-init mit Terraform und Packer) wurden aus dem Repository entfernt. Sie bleiben über ihre Git-Tags (z. B. `v1.0.0`) abrufbar.
