# Online-IDE – Browserbasierte Java-Entwicklungsumgebung
 
Eine cloud-init-basierte VS Code Server Instanz pro Team, die jedem Studierenden eine

individuelle Entwicklungsumgebung im Browser bereitstellt. Jeder Nutzer meldet sich mit

persönlichen Zugangsdaten an und erhält eine eigene code-server-Session auf einem

dedizierten Port.
 
## User-Management
 
Jeder Nutzer bekommt einen eigenen Linux-Account (abgeleitet aus der E-Mail-Adresse)

und ein automatisch generiertes Passwort. Der Login in code-server erfolgt über dieses

Passwort. Zugangsdaten werden nach dem Deployment per Mail versendet. Innerhalb eines

Teams teilen sich alle Nutzer dieselbe VM, arbeiten aber auf isolierten Ports und in

separaten Home-Verzeichnissen.
 
## VM-Deployment
 
Es wird **eine VM pro Team** deployed. Bei zwei Teams entstehen zwei VMs. Jeder Nutzer

eines Teams erhält einen eigenen Port ab 8080 (aufsteigend pro Nutzer). Flavor: `gp1.small`.
 
## Deployment-Dauer
 
| Phase | Dauer |

|---|---|

| Packer Image Build (einmalig) | ca. 15–20 Min |

| Terraform Apply | ca. 2–5 Min |

| VM-Boot + cloud-init (User-Anlage, code-server-Start) | ca. 2–4 Min |

| **Gesamt erstmalig** | **ca. 20–30 Min** |
 
Bei vorhandenem Packer-Image entfällt der Build — dann ca. **5–10 Minuten** gesamt.
 
## Konfigurierbare Variablen
 
| Variable | Beschreibung | Pflicht |

|---|---|---|

| `assignment_files` | Java-Aufgabendatei pro User (`.java`) — landet unter `~/Coding-Aufgabe/` | Ja |

| `team_flavor_ids` | Flavor-ID pro Team — Picker-Auswahl | Nein |

| `network_uuid` | UUID des internen Netzwerks | Ja (Default vorhanden) |

| `floating_ip_pool` | Name des External Networks für öffentliche IP | Ja (Default vorhanden) |

| `shared_secgroup_id` | ID der Security Group | Ja (Default vorhanden) |
 
### Aufgabendateien (`assignment_files`)
 
Über den Wizard muss pro Nutzer eine individuelle `.java`-Datei hochgeladen werden.

Diese wird beim VM-Start automatisch unter `~/Coding-Aufgabe/<dateiname>.java`

abgelegt und ist direkt in code-server sichtbar.
 

## Pod-Variante (ab v2.0.0)

Ab Version `v2.0.0` läuft die Online-IDE als Pods statt als VMs (`appstore.yaml`,
App-Vertrag v2): **ein code-server-Pod je Person** mit eigenem Speicher (5 GiB), HTTPS-Link
und eigenem Passwort unter „Meine Zugänge". Keine VM, kein Packer-Build, kein OpenStack-Credential.
Das Image (`image/Dockerfile`) wird von `.github/workflows/image.yml` gebaut; nach einer Änderung
den neuen Digest in `appstore.yaml` eintragen und eine neue Version taggen. Die Versionen `v1.x`
(Terraform/Packer) laufen unverändert weiter.
