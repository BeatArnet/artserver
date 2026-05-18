# artserver Skriptordnung

Stand: 2026-05-16

Ziel: Die Skripte auf `artserver` bleiben auffindbar, aber alte Einmal-, Migrations- und Temporärdateien liegen nicht mehr zwischen den produktiven Wartungsskripten.

## Grundregel

- Produktive Skripte bleiben dort, wo sie von Diensten, Timern oder App-Dokumentation erwartet werden.
- Alte Skripte werden archiviert, nicht gelöscht.
- App-eigene Skripte bleiben im jeweiligen App-Ordner, wenn die App-Dokumentation darauf verweist.
- Zentrale Bedienung läuft über `artserver-admin.ps1`.

## Zentrale Bedienung vom Windows-Rechner

```powershell
.\artserver-admin.ps1
```

Wichtige Menüpunkte:

- `11`: Server-Skripte anzeigen
- `22`: Aufräumkandidaten anzeigen
- `32`: Skripte ordnen und Altlasten archivieren

## Produktiv wichtig

Diese Skripte nicht verschieben:

- `/home/art/scripts/update_artserver.sh`: Systemupdate
- `/home/art/scripts/borg-restore-guided.sh`: Borg-Restore
- `/home/art/scripts/artserver_setup.sh`: Neuaufbau/Basissetup, nur bewusst verwenden
- `/home/art/arkons/deploy/apply-arkons-preview.sh`: Arkons-Caddy-Vorschau
- `/home/art/arkons/deploy/artserver/docker/*.sh`: Docker-, Smoke-, Caddy- und Cleanup-Helfer
- `/opt/apps/Menueplan/ops/backup.sh`: wird von `menuplan-backup.service` verwendet
- `/opt/apps/Menueplan/ops/laptop_headless.sh`: Headless-Notebook-Betrieb
- `/opt/apps/robowait/scripts/backup.sh`: RoboWait Backup
- `/opt/apps/robowait/scripts/update-artserver.sh`: RoboWait Update
- `/opt/apps/robowait/scripts/smoke-docker.sh`: RoboWait Docker-Smoke-Test

## App-eigene Skripte, nicht zentral verschieben

Diese Skripte wirken alt, sind aber Teil der App-Ordner oder App-Dokumentation:

- `/opt/apps/Menueplan/ops/install.sh`
- `/opt/apps/Menueplan/ops/restore.sh`
- `/opt/apps/robowait/scripts/install-artserver.sh`
- `/opt/apps/robowait/scripts/restore.sh`
- `/opt/apps/robowait/scripts/robowait-admin.ps1`
- `/opt/apps/Arzttarif/deploy/ubuntu/migrate_to_ubuntu.sh`
- `/opt/apps/Arzttarif/scripts/oaat_linux_setup.sh`

Sie werden nicht ins zentrale Admin-Menü als Schnellstart eingebaut, weil Installation, Restore und Migration Daten überschreiben können.

## Bereits archiviert

Arzttarif-Host-Migrationsskripte wurden bereits durch die Docker-Bereinigung archiviert:

```text
/home/art/scripts/archive/20260516-110724-arzttarif-host-cleanup/
```

Darin liegen:

- `migrate_arzttarif_to_ubuntu.sh`
- `oaat-update-apps.sh`

## Wird durch Menüpunkt 32 archiviert

Menüpunkt `32` führt auf dem Server aus:

```text
/home/art/arkons/deploy/organize-artserver-scripts.sh
```

Archiviert werden:

- `/home/art/scripts/install-artserver.sh`
- alte Inhalte aus `/opt/apps/robowait/.tmp`
- alte Inhalte aus `/opt/apps/robowait/.tmp-deploy`

Zielorte:

- `/home/art/scripts/archive/<Zeitstempel>-script-cleanup/`
- `/opt/apps/robowait/archive/<Zeitstempel>-script-cleanup/`

Ein Bericht wird geschrieben nach:

```text
/home/art/artserver-hub/script-cleanup-<Zeitstempel>.txt
```

## Warum nicht mehr?

Man könnte noch mehr verschieben, aber das wäre riskanter:

- Die Arzttarif-Migrationsskripte im App-Ordner werden in der Arzttarif-Dokumentation referenziert.
- Die RoboWait-Skripte im App-Ordner gehören zum RoboWait-Projekt.
- Systemd verweist produktiv auf Menüplan-Backup und RoboWait-Dienste.

Darum ist die erste Aufräumrunde bewusst eng gefasst.
