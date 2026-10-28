# Online-IDE – VS Code im Browser

Eine eigene Entwicklungsumgebung (code-server, VS Code im Browser) für jede Person eines Deployments, mit eigenem Speicher und eigenem Login. Die App läuft als Pods (`appstore.yaml`, App-Vertrag v2): **ein code-server-Pod je Person** mit 5 GiB Speicher im Home-Verzeichnis, HTTPS-Link und eigenem Passwort unter „Meine Zugänge“.

## User-Management

Jede Person erhält ihren eigenen Pod und ein von der Plattform erzeugtes Passwort. Der Login in code-server erfolgt mit diesem Passwort. Dateien liegen im persistenten Home-Verzeichnis (`/home/coder`) und überstehen Pause/Fortsetzen und Neustart.

Weil die App `scope: user` hat, bekommt im Wizard jede Person ein eigenes Team; Gruppen mit gemeinsamer Umgebung gibt es nicht. Die VM-Version (`v1.x`) hatte eine VM je Team mit einem Zugang je Person.

## Software im Terminal

Ab `v2.2.0` ist wieder installiert, was die VM-Version hatte:

| Werkzeug | Hinweis |
|---|---|
| `gcc`, `g++`, `make` | `build-essential` |
| `python3`, `pip`, `python3 -m venv` | Debian 13 erlaubt kein `pip install` ins System-Python; pro Projekt `python3 -m venv .venv` benutzen. Ohne venv installiert `pip` nach `~/.local`. |
| `node`, `npm` | `npm install -g` landet in `~/.npm-global` (im PATH) |
| `git`, `curl`, `wget`, `unzip` | |

Das Root-Dateisystem ist schreibgeschützt, schreibbar sind nur das Home-Verzeichnis und `/tmp`. `sudo` und `apt` gibt es nicht. Internetzugang ist erlaubt (Paketquellen wie PyPI und npm). Java ist **nicht** enthalten; dafür gibt es die Java-IDE.

## Konfigurierbare Variablen

| Variable | Beschreibung | Pflicht |
|---|---|---|
| `assignments` | Aufgaben als ZIP-Datei (höchstens 1 MiB), eine Datei je Team, also je Person | Nein |

Das ZIP wird beim ersten Start des Arbeitsplatzes nach `~/Coding-Aufgabe` entpackt (`image/unpack-assignments.py`). Ohne ZIP startet der Arbeitsplatz leer. Ein Beispiel liegt als `aufgaben.zip` im Repository (wird auch vom Smoke-Test verwendet). Die Variable gibt es ab `v2.1.0`.

### Wie das ZIP geprüft wird

Das Backend prüft den Upload beim Anlegen des Deployments (Inhalt, Einträge, entpackte Größe, Pfade, Links); das Image prüft **noch einmal selbst**, bevor etwas auf die Platte kommt:

- Das ganze Archiv wird vorab geprüft: höchstens 2000 Einträge, 32 MiB je Eintrag und 64 MiB insgesamt, gezählt an den Bytes, die wirklich aus dem Entpacker kommen (die Angaben im ZIP-Header werden nicht geglaubt). Jede Prüfsumme wird verifiziert.
- **Ein einziger schlechter Eintrag verwirft das ganze Archiv:** absolute Pfade, `..`, `.` oder leere Pfadteile, Backslashes, Steuerzeichen, zu lange oder zu tief verschachtelte Pfade, doppelte Namen (auch nur durch Groß/Klein), symbolische Links und Gerätedateien, verschlüsselte Einträge, andere Kompression als Deflate, überlappende Einträge.
- Es werden nur normale Dateien (Modus 0644) und Verzeichnisse angelegt, nichts wird ausführbar. macOS-Metadaten (`__MACOSX/`, `.DS_Store`, `._*`) werden weggelassen. Ebenso Editor- und Git-Konfiguration: Verzeichnisse namens `.vscode`, `.devcontainer` und `.git` (in jeder Tiefe) werden nicht entpackt, mit einem Hinweis im Container-Log. Workspace-Tasks, Einstellungen oder Git-Hooks können Befehle ausführen, sobald Studierende den Ordner als vertrauenswürdig öffnen oder den ersten Git-Befehl ausführen; ein Aufgaben-ZIP ist dafür nicht der Ort.
- Es wird erst in ein Staging-Verzeichnis entpackt und nur ein vollständiges Ergebnis an den Zielort verschoben; bestehende Dateien werden nie überschrieben. Danach legt `.appstore-unpacked` fest, dass spätere Starts nichts mehr anfassen.
- Wird das ZIP abgelehnt, steht der Grund im Container-Log (`online-ide: assignments rejected: …`), und die IDE startet mit leerem Arbeitsplatz.

Getestet wird das bei jedem Build in `.github/test-unpack.py` mit gebauten Angriffsarchiven (Zip-Slip, Links, Bomben, überlappende Einträge, falsche Header, …).

## Image und CI

`image/Dockerfile` wird von `.github/workflows/ci.yml` gebaut (zentrale Pipeline aus `app-registry`: Vertrag, hadolint, Smoke-Test, Trivy) und mit dem Sicherheitskontext der Plattform getestet (UID 1000, Read-only-Root, keine Capabilities; `.github/smoke-test.sh`). Bekannte, noch nicht behebbare Befunde im Upstream-Image stehen mit Ablaufdatum in `.trivyignore`.

- **Pull Request:** das Image wird gebaut und getestet, aber nicht veröffentlicht.
- **Push auf `main`:** das Image wird zusätzlich nach GHCR gepusht. Den Digest zeigt die Zusammenfassung des Jobs.
- Nach einer Änderung den neuen Digest in `appstore.yaml` eintragen und eine neue Version taggen. Die Plattform deployt nur Images, die per Digest festgelegt sind.

## Ältere Versionen

Die VM-Versionen (`v1.x`, cloud-init mit Terraform und Packer) wurden aus dem Repository entfernt. Sie bleiben über ihre Git-Tags (z. B. `v1.0.0`) abrufbar.
