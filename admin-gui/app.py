#!/usr/bin/env python3
from __future__ import annotations

import argparse
import html
import json
import os
import platform
import re
import shutil
import shlex
import socket
import subprocess
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, unquote, urlparse


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_APPS = ROOT / "artserver-apps.json"
DEFAULT_CATALOG = ROOT / "artserver-script-catalog.json"
STATIC_DIR = Path(__file__).resolve().parent / "static"
CHECK_TIMEOUT_SECONDS = 0.7


def first_existing_path(candidates: list[Path]) -> Path:
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return candidates[0]


DEFAULT_RUNNER = first_existing_path([
    ROOT / "admin" / "arkons-admin-runner.sh",
    ROOT / "deploy" / "artserver" / "admin" / "arkons-admin-runner.sh",
    Path("/home/art/arkons/deploy/artserver/admin/arkons-admin-runner.sh"),
])


def default_job_log_dir() -> Path:
    configured = os.environ.get("ARKONS_ADMIN_WEB_LOG_DIR")
    if configured:
        return Path(configured)
    if platform.system().lower().startswith("win"):
        return ROOT / "logs" / "admin" / "jobs"
    return Path("/home/art/arkons/logs/admin/jobs")


def read_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def esc(value: object) -> str:
    return html.escape("" if value is None else str(value), quote=True)


def risk_class(risk: str) -> str:
    return {
        "niedrig": "risk-low",
        "mittel": "risk-medium",
        "hoch": "risk-high",
    }.get((risk or "").lower(), "risk-unknown")


def script_is_server_startable(script: dict) -> bool:
    run = script.get("run") or {}
    return bool(script.get("enabled") is True and script.get("location") == "artserver" and run.get("type") == "ServerShell")


def script_is_local_startable(script: dict) -> bool:
    run = script.get("run") or {}
    return bool(
        script.get("enabled") is True
        and script.get("location") == "Entwicklungsrechner"
        and run.get("type") in {"LocalCommand", "LocalPowerShell"}
    )


def script_is_startable_here(script: dict) -> bool:
    if is_artserver_runtime():
        return script_is_server_startable(script)
    return script_is_local_startable(script)


def script_start_status(script: dict) -> tuple[str, str]:
    run = script.get("run") or {}
    run_type = run.get("type", "")
    location = script.get("location", "")
    if script.get("enabled") is not True:
        return "Start: noch nicht freigegeben", "pill-muted"
    if location == "artserver" and run_type == "ServerShell":
        return ("Start: auf artserver", "pill-ok") if is_artserver_runtime() else ("Start: auf artserver", "pill-local")
    if location == "Entwicklungsrechner" and run_type in {"LocalCommand", "LocalPowerShell", "AdminFunction"}:
        return ("Start: hier lokal", "pill-ok") if not is_artserver_runtime() and run_type != "AdminFunction" else ("Start: Entwicklungsrechner", "pill-local")
    return "Start: Ausführung prüfen", "pill-muted"


def as_list(value: object) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item) for item in value]
    return [str(value)]


def script_edit_value(script: dict, field: str) -> object:
    if field in script:
        return script.get(field)
    if field == "summary" and script.get("notes"):
        return script.get("notes")
    return ""


def bash_path(path: Path) -> str:
    """Gibt einen Pfad so zurück, dass Bash ihn auch unter Windows versteht."""
    text = str(path)
    if len(text) >= 3 and text[1:3] in (":\\", ":/"):
        drive = text[0].lower()
        rest = text[3:].replace("\\", "/")
        candidates = [f"/mnt/{drive}/{rest}", f"/{drive}/{rest}"]
        for candidate in candidates:
            probe = subprocess.run(
                ["bash", "-lc", f"test -e {shlex.quote(candidate)}"],
                capture_output=True,
                text=True,
                check=False,
            )
            if probe.returncode == 0:
                return candidate
        return candidates[0]
    return text


def expand_catalog_value(value: object) -> str:
    text = "" if value is None else str(value)
    return text.replace("{Root}", str(ROOT)).replace("{ProjectsRoot}", str(ROOT.parent))


def catalog_args(values: object) -> list[str]:
    if not values:
        return []
    if isinstance(values, list):
        return [expand_catalog_value(item) for item in values]
    return [expand_catalog_value(values)]


def local_powershell_command(run: dict, dry_run: bool) -> tuple[list[str], Path, bool]:
    script_path = Path(expand_catalog_value(run.get("path")))
    cwd = Path(expand_catalog_value(run.get("cwd") or ROOT))
    shell = shutil.which("pwsh") or shutil.which("powershell")
    if not shell:
        raise FileNotFoundError("PowerShell wurde nicht gefunden.")
    args = ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script_path)]
    args.extend(catalog_args(run.get("args")))
    dry_args = catalog_args(run.get("dryRunArgs"))
    if dry_run:
        if not dry_args:
            return [shell, *args], cwd, False
        args.extend(dry_args)
    return [shell, *args], cwd, True


def local_command(run: dict, dry_run: bool) -> tuple[list[str], Path, bool]:
    program = expand_catalog_value(run.get("path"))
    cwd = Path(expand_catalog_value(run.get("cwd") or ROOT))
    args = catalog_args(run.get("args"))
    dry_args = catalog_args(run.get("dryRunArgs"))
    if dry_run:
        if not dry_args:
            return [program, *args], cwd, False
        args.extend(dry_args)
    suffix = Path(program).suffix.lower()
    if suffix in {".cmd", ".bat"}:
        return ["cmd.exe", "/c", program, *args], cwd, True
    return [program, *args], cwd, True


def build_execution(script: dict, dry_run: bool, runner_path: Path, confirmation: str) -> tuple[list[str], Path, bool]:
    run = script.get("run") or {}
    run_type = run.get("type")
    if script_is_server_startable(script) and is_artserver_runtime():
        command = ["bash", bash_path(runner_path), "run", str(script.get("id", ""))]
        if confirmation:
            command.extend(["--confirm", confirmation])
        if dry_run:
            command.append("--dry-run")
        return command, ROOT, True
    if script_is_local_startable(script) and not is_artserver_runtime():
        if run_type == "LocalPowerShell":
            return local_powershell_command(run, dry_run)
        if run_type == "LocalCommand":
            return local_command(run, dry_run)
    raise ValueError("Dieses Skript ist auf dieser Maschine nicht direkt startbar.")


def is_artserver_runtime() -> bool:
    if platform.system().lower().startswith("win"):
        return False
    hostname = (platform.node() or "").lower()
    return hostname == "artserver" or Path("/home/art/arkons").exists()


def is_loopback_host(host: str) -> bool:
    return host in {"127.0.0.1", "localhost", "::1"}


def loopback_check_needs_artserver(check: dict) -> bool:
    check_type = str(check.get("type") or "")
    if check_type in {"httpHead", "httpJson"}:
        parsed = urlparse(str(check.get("url") or ""))
        return is_loopback_host(parsed.hostname or "")
    if check_type == "tcp":
        return is_loopback_host(str(check.get("host") or "127.0.0.1"))
    return False


def run_http_check(check: dict, timeout: float = CHECK_TIMEOUT_SECONDS) -> tuple[str, str]:
    url = str(check.get("url") or "")
    if not url:
        return "unknown", "keine URL konfiguriert"
    method = "HEAD" if check.get("type") == "httpHead" else "GET"
    request = urllib.request.Request(url, method=method)
    if check.get("hostHeader"):
        request.add_header("Host", str(check.get("hostHeader")))
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            if 200 <= response.status < 400:
                return "ok", f"HTTP {response.status}"
            return "failed", f"HTTP {response.status}"
    except urllib.error.HTTPError as exc:
        return ("ok", f"HTTP {exc.code}") if 200 <= exc.code < 400 else ("failed", f"HTTP {exc.code}")
    except OSError as exc:
        return "failed", str(exc)


def run_tcp_check(check: dict, timeout: float = CHECK_TIMEOUT_SECONDS) -> tuple[str, str]:
    host = str(check.get("host") or "127.0.0.1")
    port = int(check.get("port") or 0)
    if not port:
        return "unknown", "kein Port konfiguriert"
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return "ok", f"{host}:{port} erreichbar"
    except OSError as exc:
        return "failed", str(exc)


def run_systemd_check(check: dict, timeout: float = CHECK_TIMEOUT_SECONDS) -> tuple[str, str]:
    service = str(check.get("service") or "")
    if not service:
        return "unknown", "kein Dienst konfiguriert"
    if platform.system().lower().startswith("win"):
        return "unknown", "systemd nur auf artserver prüfbar"
    try:
        result = subprocess.run(
            ["systemctl", "is-active", "--quiet", service],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        return "unknown", str(exc)
    return ("ok", "aktiv") if result.returncode == 0 else ("failed", "nicht aktiv")


def run_configured_check(check: dict) -> dict[str, str]:
    check_type = str(check.get("type") or "")
    if check_type == "systemd" and not is_artserver_runtime():
        state, message = "remote", "nur auf artserver direkt prüfbar"
    elif loopback_check_needs_artserver(check) and not is_artserver_runtime():
        state, message = "remote", "interner artserver-Check; lokal nicht aussagekräftig"
    elif check_type in {"httpHead", "httpJson"}:
        state, message = run_http_check(check)
    elif check_type == "tcp":
        state, message = run_tcp_check(check)
    elif check_type == "systemd":
        state, message = run_systemd_check(check)
    else:
        state, message = "unknown", f"unbekannter Checktyp: {check_type}"

    target = check.get("url") or check.get("service") or check.get("host") or ""
    if check.get("port"):
        target = f"{target}:{check.get('port')}"
    return {
        "label": str(check.get("label", check.get("id", ""))),
        "type": check_type,
        "target": str(target),
        "state": state,
        "message": message,
    }


def area_check_results(area: dict) -> list[dict[str, str]]:
    checks = area.get("healthChecks") or area.get("statusChecks") or []
    return [run_configured_check(check) for check in checks]


def area_runtime_status(area: dict) -> tuple[str, str, str, list[dict[str, str]]]:
    results = area_check_results(area)
    if not results:
        return "unklar", "pill-muted", "keine Checks", results
    failed = [item for item in results if item["state"] == "failed"]
    unknown = [item for item in results if item["state"] == "unknown"]
    remote = [item for item in results if item["state"] == "remote"]
    if failed:
        return "Störung", "pill-bad", f"{len(failed)} von {len(results)} Checks fehlgeschlagen", results
    if remote and len(remote) == len(results):
        return "auf artserver prüfen", "pill-local", f"{len(remote)} Checks nur auf artserver aussagekräftig", results
    if remote:
        return "teilweise prüfbar", "pill-warn", f"{len(remote)} von {len(results)} Checks nur auf artserver", results
    if unknown:
        return "unklar", "pill-warn", f"{len(unknown)} von {len(results)} Checks unklar", results
    return "läuft", "pill-ok", f"{len(results)} von {len(results)} Checks ok", results


class AdminData:
    def __init__(self, apps_path: Path, catalog_path: Path, runner_path: Path, job_log_dir: Path):
        self.apps_path = apps_path
        self.catalog_path = catalog_path
        self.runner_path = runner_path
        self.job_log_dir = job_log_dir

    def load(self) -> tuple[dict, dict, dict[str, dict]]:
        apps = read_json(self.apps_path)
        catalog = read_json(self.catalog_path)
        scripts = {entry["id"]: entry for entry in catalog.get("scripts", [])}
        return apps, catalog, scripts

    def script_to_area_map(self) -> dict[str, list[str]]:
        apps, _, _ = self.load()
        mapping: dict[str, list[str]] = {}
        for area in apps.get("areas", []):
            label = area.get("label", area.get("id", ""))
            for script_id in area.get("scriptIds", []):
                mapping.setdefault(script_id, []).append(label)
        return mapping


class Renderer:
    def __init__(self, data: AdminData):
        self.data = data

    def page(self, title: str, active: str, body: str, notice: str = "", active_script_id: str = "") -> bytes:
        apps, _, _ = self.data.load()
        nav = self.nav(apps, active, active_script_id)
        notice_html = f'<div class="notice">{notice}</div>' if notice else ""
        area_ids = {str(area.get("id", "")) for area in apps.get("areas", [])}
        h1_attrs = ""
        if active_script_id:
            h1_attrs = f' data-edit-source="script" data-edit-id="{esc(active_script_id)}" data-edit-field="label"'
        elif active in area_ids:
            h1_attrs = f' data-edit-source="area" data-edit-id="{esc(active)}" data-edit-field="label"'
        content = f"""<!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{esc(title)} - Arkons Admin</title>
  <link rel="stylesheet" href="/static/styles.css">
  <script src="/static/editor.js" defer></script>
</head>
<body>
  <div class="shell">
    <aside class="sidebar">
      <div class="brand">
        <div class="brand-mark">A</div>
        <div>
          <div class="brand-title">Arkons Admin</div>
          <div class="brand-subtitle">artserver</div>
        </div>
      </div>
      {nav}
    </aside>
    <main class="main">
      <header class="topbar">
        <div>
          <div class="eyebrow">Zentrale Administrationsoberfläche</div>
          <h1{h1_attrs}>{esc(title)}</h1>
        </div>
        <div class="topbar-status">
          <div class="config-status">
            <span class="status-dot ok"></span>
            Konfiguration geladen
          </div>
          <div class="page-edit-actions">
            <button type="button" class="page-edit-start" data-edit-start>Texte bearbeiten</button>
            <button type="button" class="page-edit-save" data-edit-save hidden>Speichern</button>
            <button type="button" class="page-edit-cancel secondary" data-edit-cancel hidden>Abbrechen</button>
          </div>
        </div>
      </header>
      {notice_html}
      {body}
    </main>
  </div>
</body>
</html>"""
        return content.encode("utf-8")

    def nav(self, apps: dict, active: str, active_script_id: str = "") -> str:
        _, _, scripts = self.data.load()
        items = []
        for area in apps.get("areas", []):
            if not area.get("navigation", True):
                continue
            area_id = area.get("id", "")
            href = "/" if area_id == "overview" else f"/area/{area_id}"

            is_active_area = (area_id == active)
            selected = " active" if is_active_area and not active_script_id else ""

            items.append(f'<div class="nav-group">')
            items.append(f'<a class="nav-item{selected}" href="{href}">{esc(area.get("label", area_id))}</a>')

            if is_active_area and area.get("scriptIds"):
                items.append('<div class="nav-sub">')
                for sid in area.get("scriptIds", []):
                    s = scripts.get(sid)
                    if not s:
                        continue
                    s_label = s.get("label", sid)
                    s_sel = " active" if sid == active_script_id else ""
                    items.append(f'<a class="nav-sub-item{s_sel}" href="{self.script_href(sid, area_id)}">{esc(s_label)}</a>')
                items.append('</div>')
            items.append('</div>')

        selected = " active" if active == "jobs" and not active_script_id else ""
        items.append(f'<a class="nav-item{selected}" href="/jobs">Jobs und Logs</a>')
        return '<nav class="nav">' + "\n".join(items) + "</nav>"

    def script_href(self, script_id: str, area_id: str = "") -> str:
        href = f"/script/{esc(script_id)}"
        if area_id:
            href += f"?area={esc(area_id)}"
        return href

    def field_textarea(self, field: str, label: str, value: object, rows: int = 3, is_list: bool = False, hint: str = "") -> str:
        if is_list:
            text = "\n".join(as_list(value)) if value else ""
            hint = hint or "Eine Zeile pro Eintrag."
        else:
            text = "" if value is None else str(value)
        hint_html = f'<span class="edit-hint">{esc(hint)}</span>' if hint else ""
        return f"""
<div class="edit-field">
  <label>
    <span class="edit-label">{esc(label)}</span>
    {hint_html}
  </label>
  <textarea name="{esc(field)}" rows="{rows}" spellcheck="true">{esc(text)}</textarea>
</div>"""

    def field_input(self, field: str, label: str, value: object, hint: str = "") -> str:
        hint_html = f'<span class="edit-hint">{esc(hint)}</span>' if hint else ""
        return f"""
<div class="edit-field">
  <label>
    <span class="edit-label">{esc(label)}</span>
    {hint_html}
  </label>
  <input name="{esc(field)}" value="{esc(value)}">
</div>"""

    def inline_editor(self, title: str, action: str, return_to: str, fields_html: str) -> str:
        return f"""
<details class="inline-editor">
  <summary>{esc(title)}</summary>
  <form class="edit-form inline-edit-form" method="post" action="{esc(action)}">
    <input type="hidden" name="return_to" value="{esc(return_to)}">
    {fields_html}
    <div class="edit-actions">
      <button type="submit">Speichern</button>
    </div>
  </form>
</details>
"""

    def overview_config(self, apps: dict) -> tuple[str, str, list[dict[str, str]]]:
        admin_gui = apps.get("adminGui") or {}
        title = admin_gui.get("overviewTitle") or "Arbeitszentrale für artserver"
        summary = admin_gui.get("overviewSummary") or "Diese Oberfläche bündelt Website, Server, Container und die Wartungsskripte der Anwendungen. Die Konfiguration kommt aus artserver-apps.json und artserver-script-catalog.json. Startbare Aktionen laufen über den Runner, damit im Browser keine freien Shell-Befehle ausgeführt werden."
        facts = admin_gui.get("overviewFacts") or [
            {"label": "Anwendungen", "value": "3 Container-Apps"},
            {"label": "Runner", "value": "Skript-ID basiert"},
            {"label": "Startschutz", "value": "Schutzwort je Risiko"},
        ]
        return str(title), str(summary), [{"label": str(item.get("label", "")), "value": str(item.get("value", ""))} for item in facts[:3]]

    def overview_editor(self, apps: dict) -> str:
        title, summary, facts = self.overview_config(apps)
        fields = [
            self.field_input("overviewTitle", "Titel", title),
            self.field_textarea("overviewSummary", "Beschreibung", summary, rows=4),
        ]
        for index, fact in enumerate(facts):
            fields.append(self.field_input(f"factLabel{index}", f"Fakt {index + 1}: Beschriftung", fact.get("label", "")))
            fields.append(self.field_input(f"factValue{index}", f"Fakt {index + 1}: Wert", fact.get("value", "")))
        return self.inline_editor("Texte bearbeiten", "/save-overview", "/", "".join(fields))

    def area_inline_editor(self, area: dict, return_to: str) -> str:
        fields = "".join([
            self.field_input("label", "Name", area.get("label", area.get("id", ""))),
            self.field_textarea("summary", "Kurzbeschreibung", area.get("summary", ""), rows=3),
            self.field_textarea("humanNotes", "Einordnung", area.get("humanNotes", ""), rows=4),
        ])
        return self.inline_editor("Texte bearbeiten", f"/save-area/{esc(area.get('id', ''))}", return_to, fields)

    def script_inline_editor(self, script: dict, return_to: str) -> str:
        fields = "".join([
            self.field_input("label", "Name im Menü", script.get("label", script.get("id", ""))),
            self.field_textarea("summary", "Kurzbeschreibung", script_edit_value(script, "summary"), rows=3),
            self.field_textarea("details", "Detailbeschreibung", script_edit_value(script, "details"), rows=5),
            self.field_textarea("whenToUse", "Wann verwenden?", script_edit_value(script, "whenToUse"), rows=3),
            self.field_textarea("beforeStart", "Vor dem Start prüfen", script_edit_value(script, "beforeStart"), rows=4, is_list=True),
            self.field_textarea("effect", "Wirkung", script_edit_value(script, "effect"), rows=4, is_list=True),
            self.field_textarea("successCriteria", "Erfolgskriterium", script_edit_value(script, "successCriteria"), rows=4, is_list=True),
            self.field_textarea("rollback", "Rollback / wenn etwas schiefgeht", script_edit_value(script, "rollback"), rows=3),
        ])
        return self.inline_editor("Texte bearbeiten", f"/save-script/{esc(script.get('id', ''))}", return_to, fields)

    def overview(self) -> bytes:
        apps, _, scripts = self.data.load()
        title, summary, facts = self.overview_config(apps)
        areas = [area for area in apps.get("areas", []) if area.get("id") != "overview"]
        statuses = self.area_statuses(areas)
        cards = []
        for area in areas:
            cards.append(self.area_summary(area, scripts, statuses.get(area.get("id", ""))))
        body = f"""
<section class="intro hero-panel">
  <div>
    <h2 data-edit-source="overview" data-edit-field="overviewTitle">{esc(title)}</h2>
    <p data-edit-source="overview" data-edit-field="overviewSummary">{esc(summary)}</p>
  </div>
  <dl class="hero-facts">
    {''.join(f"<div><dt data-edit-source=\"overview\" data-edit-field=\"factLabel{index}\">{esc(fact.get('label', ''))}</dt><dd data-edit-source=\"overview\" data-edit-field=\"factValue{index}\">{esc(fact.get('value', ''))}</dd></div>" for index, fact in enumerate(facts))}
  </dl>
</section>
<section class="overview-grid">
  {''.join(cards)}
</section>
"""
        return self.page("Übersicht", "overview", body)

    def area_statuses(self, areas: list[dict]) -> dict[str, tuple[str, str, str, list[dict[str, str]]]]:
        statuses: dict[str, tuple[str, str, str, list[dict[str, str]]]] = {}
        if not areas:
            return statuses
        with ThreadPoolExecutor(max_workers=min(8, len(areas))) as pool:
            future_map = {pool.submit(area_runtime_status, area): area for area in areas}
            for future in as_completed(future_map):
                area = future_map[future]
                area_id = area.get("id", "")
                try:
                    statuses[area_id] = future.result()
                except Exception as exc:
                    statuses[area_id] = ("unklar", "pill-warn", f"Checkfehler: {exc}", [])
        return statuses

    def area_summary(self, area: dict, scripts: dict[str, dict], status: tuple[str, str, str, list[dict[str, str]]] | None = None) -> str:
        script_ids = area.get("scriptIds", [])
        enabled = sum(1 for script_id in script_ids if scripts.get(script_id, {}).get("enabled") is True)
        checks = area.get("healthChecks") or area.get("statusChecks") or []
        containers = area.get("containerNames", [])
        status_label, status_class, status_detail, _ = status or area_runtime_status(area)
        return f"""
<article class="summary-card">
  <div class="summary-head">
    <h2 data-edit-source="area" data-edit-id="{esc(area.get('id', ''))}" data-edit-field="label">{esc(area.get("label", area.get("id", "")))}</h2>
    <span class="pill {status_class}" title="{esc(status_detail)}">{esc(status_label)}</span>
  </div>
  <p data-edit-source="area" data-edit-id="{esc(area.get('id', ''))}" data-edit-field="summary">{esc(area.get("summary", area.get("humanNotes", "")))}</p>
  <dl class="compact-facts">
    <div><dt>Typ</dt><dd>{esc(area.get("kind", ""))}</dd></div>
    <div><dt>Status</dt><dd>{esc(status_detail)}</dd></div>
    <div><dt>Container</dt><dd>{len(containers)}</dd></div>
    <div><dt>Checks</dt><dd>{len(checks)}</dd></div>
    <div><dt>Menüpunkte</dt><dd>{len(script_ids)} davon {enabled} freigegeben</dd></div>
  </dl>
  <a class="text-link" href="/area/{esc(area.get('id', ''))}">Details öffnen</a>
</article>
"""

    def area_page(self, area_id: str) -> bytes:
        apps, _, scripts = self.data.load()
        area = next((item for item in apps.get("areas", []) if item.get("id") == area_id), None)
        if area is None:
            return self.not_found(f"Bereich nicht gefunden: {area_id}")

        facts = self.area_facts(area)
        checks = self.checks(area)
        assigned_scripts = [scripts[script_id] for script_id in area.get("scriptIds", []) if script_id in scripts]
        if assigned_scripts:
            first_script = assigned_scripts[0]
            script_hint = f"""
      <p>Die einzelnen Menüpunkte stehen links als Untermenü direkt unter <strong>{esc(area.get("label", area_id))}</strong>.</p>
      <p class="muted">Im Hauptfenster wird danach immer genau ein gewählter Menüpunkt angezeigt, nicht die ganze Liste.</p>
      <a class="text-link" href="{self.script_href(first_script.get("id", ""), area_id)}">Ersten Menüpunkt öffnen: {esc(first_script.get("label", first_script.get("id", "")))}</a>
"""
        else:
            script_hint = '<p class="muted">Für diesen Bereich sind noch keine Menüpunkte zugeordnet.</p>'

        body = f"""
<section class="detail-layout">
  <div class="detail-primary">
    <section class="panel section-lead">
      <h2>Einordnung</h2>
      <p data-edit-source="area" data-edit-id="{esc(area_id)}" data-edit-field="humanNotes">{esc(area.get("humanNotes", area.get("summary", "")))}</p>
      {facts}
    </section>
    <section class="panel">
      <div class="section-title-row">
        <h2>Menüpunkte</h2>
        <span class="pill">{len(assigned_scripts)} im linken Untermenü</span>
      </div>
      <div class="menu-hint">
        {script_hint}
      </div>
    </section>
  </div>
  <aside class="detail-side">
    <section class="panel">
      <h2>Statuschecks</h2>
      {checks}
    </section>
  </aside>
</section>
"""
        return self.page(str(area.get("label", area_id)), area_id, body)

    def script_page(self, script_id: str, requested_area_id: str = "") -> bytes:
        apps, _, scripts = self.data.load()
        script = scripts.get(script_id)
        if not script:
            return self.not_found(f"Skript nicht gefunden: {script_id}")

        active_area_id = ""
        for area in apps.get("areas", []):
            if area.get("id") == requested_area_id and script_id in area.get("scriptIds", []):
                active_area_id = requested_area_id
                break
        if not active_area_id:
            for area in apps.get("areas", []):
                if script_id in area.get("scriptIds", []):
                    active_area_id = area.get("id", "")
                    break

        areas = self.data.script_to_area_map().get(script_id, [])

        body = f"""
<section class="detail-layout">
  <div class="detail-primary">
    <div class="script-list">
      {self.script_block(script, areas, show_edit_link=True)}
    </div>
  </div>
</section>
"""
        return self.page(script.get("label", script_id), active_area_id, body, active_script_id=script_id)

    def edit_page(self, script_id: str, notice: str = "") -> bytes:
        _, _, scripts = self.data.load()
        script = scripts.get(script_id)
        if not script:
            return self.not_found(f"Skript nicht gefunden: {script_id}")

        def textarea(field: str, label: str, hint: str = "", is_list: bool = False) -> str:
            raw = script_edit_value(script, field)
            if is_list:
                value = "\n".join(as_list(raw)) if raw else ""
            else:
                value = raw or ""
            hint_html = f'<span class="edit-hint">{esc(hint)}</span>' if hint else ""
            list_note = ' <span class="edit-hint">(eine Zeile pro Eintrag)</span>' if is_list else ""
            return f"""
<div class="edit-field">
  <label for="field-{esc(field)}">
    <span class="edit-label">{esc(label)}{list_note}</span>
    {hint_html}
  </label>
  <textarea id="field-{esc(field)}" name="{esc(field)}" rows="4" spellcheck="true">{esc(value)}</textarea>
</div>"""

        fields_html = "".join([
            textarea("summary",         "Kurzbeschreibung",         "Ein Satz, der erklärt, was dieser Menüpunkt tut."),
            textarea("details",         "Detailbeschreibung",        "Ausführliche Erklärung für Kontext und Hintergrund."),
            textarea("whenToUse",       "Wann verwenden?",           "Typische Auslöser oder Situationen."),
            textarea("beforeStart",     "Vor dem Start prüfen",      "Checkliste, mehrere Zeilen möglich.", is_list=True),
            textarea("effect",          "Wirkung",                   "Was passiert konkret? Mehrere Zeilen möglich.", is_list=True),
            textarea("successCriteria", "Erfolgskriterium",          "Woran erkennt man Erfolg? Mehrere Zeilen.", is_list=True),
            textarea("rollback",        "Rollback / wenn etwas schiefgeht", "Was tun, wenn etwas falsch läuft?"),
        ])

        body = f"""
<section class="panel edit-panel">
  <div class="edit-header">
    <div>
      <h2>Texte bearbeiten</h2>
      <div class="script-id" style="margin-top:4px;">{esc(script_id)}</div>
    </div>
    <a class="text-link" href="/script/{esc(script_id)}">← Zurück zum Skript</a>
  </div>
  <form class="edit-form" method="post" action="/save/{esc(script_id)}">
    {fields_html}
    <div class="edit-actions">
      <button type="submit">Speichern</button>
      <a class="btn-cancel" href="/script/{esc(script_id)}">Abbrechen</a>
    </div>
  </form>
</section>
"""
        return self.page(f"Bearbeiten: {script.get('label', script_id)}", "", body, notice=notice)

    def area_facts(self, area: dict) -> str:
        rows = []
        for label, key in [
            ("Repository", "repository"),
            ("GitHub", "github"),
            ("Öffentliche URL", "publicUrl"),
            ("Vorschau", "previewUrl"),
        ]:
            if area.get(key):
                rows.append((label, area[key]))
        for value in area.get("containerNames", []):
            rows.append(("Container", value))
        for value in area.get("internalUrls", []):
            rows.append(("Interne Adresse", value))
        if not rows:
            return ""
        return "<dl class=\"fact-list\">" + "".join(
            f"<div><dt>{esc(label)}</dt><dd>{esc(value)}</dd></div>" for label, value in rows
        ) + "</dl>"

    def checks(self, area: dict) -> str:
        results = area_check_results(area)
        if not results:
            return '<p class="muted">Noch keine Checks konfiguriert.</p>'
        items = []
        dot_class = {
            "ok": "ok",
            "failed": "failed",
            "unknown": "unknown",
            "remote": "remote",
        }
        label = {
            "ok": "läuft",
            "failed": "Störung",
            "unknown": "unklar",
            "remote": "auf artserver prüfen",
        }
        for result in results:
            items.append(f"""
<div class="check-row">
  <span class="status-dot {dot_class.get(result['state'], 'unknown')}"></span>
  <div>
    <strong>{esc(result["label"])}</strong>
    <span>{esc(label.get(result["state"], "unklar"))} · {esc(result["type"])} · {esc(result["target"])} · {esc(result["message"])}</span>
  </div>
</div>
""")
        return "".join(items)

    def script_block(self, script: dict, areas: list[str] | None = None, show_edit_link: bool = False) -> str:
        run = script.get("run") or {}
        start_label, start_class = script_start_status(script)
        risk = script.get("risk", "unbekannt")
        confirmation = script.get("requiresConfirmation") or ""
        area_text = ", ".join(areas or [])
        action_form = self.action_form(script) if script_is_startable_here(script) else self.not_startable_box(script)
        script_id = script.get("id", "")

        return f"""
<article class="script-item">
  <div class="script-head">
    <div>
      <h3 data-edit-source="script" data-edit-id="{esc(script_id)}" data-edit-field="label">{esc(script.get("label", script_id))}</h3>
      <div class="script-id">{esc(script_id)}</div>
    </div>
    <div class="badges">
      <span class="pill {risk_class(risk)}">{esc(f"Risiko: {risk}")}</span>
      <span class="pill {start_class}">{esc(start_label)}</span>
    </div>
  </div>
  {self.help_sections(script, area_text)}
  {action_form}
  <details>
    <summary>Technische Ausführung anzeigen</summary>
    <dl class="fact-list">
      <div><dt>Quelle</dt><dd>{esc(script.get("source", ""))}</dd></div>
      <div><dt>Ort</dt><dd>{esc(script.get("location", ""))}</dd></div>
      <div><dt>Ordner</dt><dd>{esc(run.get("cwd", "-"))}</dd></div>
      <div><dt>Befehl</dt><dd>{esc(run.get("command", run.get("function", run.get("path", "-"))))}</dd></div>
      <div><dt>Schutz</dt><dd>{esc(confirmation or "kein Schutzwort")}</dd></div>
    </dl>
  </details>
</article>
"""

    def help_sections(self, script: dict, area_text: str) -> str:
        summary = script.get("summary") or script.get("notes") or "Noch keine Beschreibung hinterlegt."
        details = script.get("details") or script.get("notes") or ""
        script_id = script.get("id", "")
        html_blocks = []
        if area_text:
            html_blocks.append(f"""
<div class="help-box help-assignment">
  <h4>Zugeordnet zu</h4>
  <p>{esc(area_text)}</p>
</div>
""")
        description_parts = [("summary", summary)]
        if details and details != summary:
            description_parts.append(("details", details))
        description_content = "".join(
            f'<p data-edit-source="script" data-edit-id="{esc(script_id)}" data-edit-field="{field}">{esc(value)}</p>'
            for field, value in description_parts
        )
        html_blocks.append(f"""
<div class="help-box">
  <h4>Was macht dieser Menüpunkt?</h4>
  {description_content}
</div>
""")

        text_blocks = [
            ("Wann verwenden?", "whenToUse", script.get("whenToUse")),
            ("Rollback / wenn etwas schiefgeht", "rollback", script.get("rollback")),
        ]
        list_blocks = [
            ("Vor dem Start prüfen", "beforeStart", script.get("beforeStart")),
            ("Wirkung", "effect", script.get("effect")),
            ("Erfolgskriterium", "successCriteria", script.get("successCriteria")),
        ]

        for title, field, value in text_blocks:
            values = as_list(value)
            if not values:
                continue
            html_blocks.append(f"""
<div class="help-box">
  <h4>{esc(title)}</h4>
  <p data-edit-source="script" data-edit-id="{esc(script_id)}" data-edit-field="{esc(field)}">{esc(values[0])}</p>
</div>
""")

        for title, field, value in list_blocks:
            values = as_list(value)
            if not values:
                continue
            items = "".join(f"<li>{esc(item)}</li>" for item in values if item)
            html_blocks.append(f"""
<div class="help-box">
  <h4>{esc(title)}</h4>
  <ul data-edit-source="script" data-edit-id="{esc(script_id)}" data-edit-field="{esc(field)}" data-edit-list="true">{items}</ul>
</div>
""")
        return '<div class="help-stack">' + "".join(html_blocks) + "</div>"

    def action_form(self, script: dict) -> str:
        confirmation = script.get("requiresConfirmation") or ""
        confirmation_field = ""
        if confirmation:
            confirmation_field = f"""
<label>
  Schutzwort
  <input name="confirmation" autocomplete="off" placeholder="{esc(confirmation)}">
</label>
"""
        else:
            confirmation_field = '<input type="hidden" name="confirmation" value="">'
        return f"""
<form class="action-form" method="post" action="/run/{esc(script.get("id", ""))}">
  {confirmation_field}
  <div class="button-row">
    <button type="submit" name="mode" value="run">Starten</button>
    <button type="submit" name="mode" value="dry-run" class="secondary">Dry-run</button>
  </div>
</form>
"""

    def not_startable_box(self, script: dict) -> str:
        run = script.get("run") or {}
        run_type = run.get("type", "")
        location = script.get("location", "")
        if script.get("enabled") is not True:
            message = "Dieser Menüpunkt ist dokumentiert, aber noch nicht für den direkten Start freigegeben."
        elif location == "artserver" and not is_artserver_runtime():
            message = "Dieser Menüpunkt läuft auf artserver. Die lokale Weboberfläche zeigt ihn an, startet ihn aber nicht direkt."
        elif location == "Entwicklungsrechner":
            message = "Dieser Menüpunkt ist für den Entwicklungsrechner vorgesehen. Auf artserver kann dieses lokale Windows-Skript nicht direkt gestartet werden."
        else:
            message = "Dieser Menüpunkt hat eine technische Ausführung, passt aber noch nicht zum aktuellen Web-Runner."
        return f"""
<div class="execution-note">
  {esc(message)} Ort: <code>{esc(location)}</code>, Starttyp: <code>{esc(run_type)}</code>.
</div>
"""

    def scripts_page(self) -> bytes:
        apps, catalog, _ = self.data.load()
        script_area_map = self.data.script_to_area_map()
        content = []
        remaining = [
            script
            for script in catalog.get("scripts", [])
            if not script_area_map.get(script.get("id", ""))
        ]
        if remaining:
            groups: dict[str, list[dict]] = {}
            for script in remaining:
                groups.setdefault(script.get("group", "Weitere"), []).append(script)
            for group in sorted(groups):
                content.append(self.script_index_section(f"Nicht zugeordnet: {group}", "", sorted(groups[group], key=lambda item: item.get("id", ""))))
        else:
            content.append("""
<section class="panel section-lead">
  <h2>Keine losen Skripte</h2>
  <p>Alle Skripte aus dem Katalog sind bereits einer Kategorie zugeordnet. Die normalen Menüpunkte stehen links direkt unter der passenden Kategorie.</p>
</section>
""")

        intro = """
<section class="panel section-lead">
  <h2>Skriptkatalog</h2>
  <p>Diese Seite zeigt nur Skripte, die noch keiner Kategorie zugeordnet sind. Zugeordnete Menüpunkte stehen links direkt unter ihrer Kategorie.</p>
</section>
"""
        return self.page("Skripte", "scripts", intro + "".join(content))

    def script_index_section(self, title: str, area_id: str, scripts: list[dict]) -> str:
        links = "".join(
            f"""
<a class="script-index-link" href="{self.script_href(script.get("id", ""), area_id)}">
  <span>{esc(script.get("label", script.get("id", "")))}</span>
  <small>{esc(script.get("id", ""))}</small>
</a>
"""
            for script in scripts
        )
        area_link = f'<a class="text-link" href="/area/{esc(area_id)}">Kategorie öffnen</a>' if area_id else ""
        return f"""
<section class="panel script-index-section">
  <div class="section-title-row">
    <h2>{esc(title)}</h2>
    <span class="pill">{len(scripts)} Menüpunkte</span>
  </div>
  <div class="script-index-list">
    {links}
  </div>
  {area_link}
</section>
"""

    def recent_job_logs(self) -> str:
        log_dir = self.data.job_log_dir
        if not log_dir.exists():
            return '<p class="muted">Auf dieser Maschine wurden noch keine Web-Job-Logs geschrieben.</p>'

        logs = sorted(log_dir.glob("*.log"), key=lambda item: item.stat().st_mtime, reverse=True)[:20]
        if not logs:
            return '<p class="muted">Auf dieser Maschine wurden noch keine Web-Job-Logs geschrieben.</p>'

        items = []
        for log_file in logs:
            stat = log_file.stat()
            changed = datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M:%S")
            size_kb = max(1, round(stat.st_size / 1024))
            items.append(f"""
<a class="log-row" href="/job-log/{quote(log_file.name)}">
  <span>{esc(log_file.name)}</span>
  <small>{esc(changed)} · {size_kb} KB</small>
</a>
""")
        return '<div class="log-list">' + "".join(items) + "</div>"

    def jobs_page(self) -> bytes:
        machine = platform.node() or "diese Maschine"
        system = platform.system() or "unbekannt"
        log_dir = self.data.job_log_dir
        body = f"""
<section class="panel">
  <h2>Jobs und Logs</h2>
  <p>Diese Weboberfläche läuft auf <strong>{esc(machine)}</strong> ({esc(system)}). Web-Logs werden auf genau dieser Maschine gespeichert.</p>
  <dl class="fact-list">
    <div><dt>Log-Ordner</dt><dd><code>{esc(log_dir)}</code></dd></div>
  </dl>
</section>
<section class="panel">
  <div class="section-title-row">
    <h2>Letzte Web-Job-Logs</h2>
    <span class="pill">diese Maschine</span>
  </div>
  {self.recent_job_logs()}
</section>
"""
        return self.page("Jobs und Logs", "jobs", body)

    def job_log_page(self, filename: str) -> bytes:
        safe_name = Path(filename).name
        if safe_name != filename or not safe_name.endswith(".log"):
            return self.not_found("Log nicht gefunden")
        log_file = self.data.job_log_dir / safe_name
        if not log_file.exists() or not log_file.is_file():
            return self.not_found("Log nicht gefunden")
        text = log_file.read_text(encoding="utf-8", errors="replace")
        body = f"""
<section class="panel">
  <h2>{esc(safe_name)}</h2>
  <p><a class="text-link" href="/jobs">Zurück zu Jobs und Logs</a></p>
  <pre><code>{esc(text)}</code></pre>
</section>
"""
        return self.page("Job-Log", "jobs", body)

    def job_result_page(self, script: dict, command: list[str], result: subprocess.CompletedProcess[str], dry_run: bool, log_path: Path | None = None, log_error: str = "") -> bytes:
        status_class = "job-ok" if result.returncode == 0 else "job-failed"
        status_text = "erfolgreich" if result.returncode == 0 else f"Fehler {result.returncode}"
        log_row = ""
        if log_path:
            log_row = f'<div><dt>Web-Log</dt><dd><code>{esc(log_path)}</code></dd></div>'
        elif log_error:
            log_row = f'<div><dt>Web-Log</dt><dd>{esc(log_error)}</dd></div>'
        body = f"""
<section class="panel job-result {status_class}">
  <h2>Job {esc(status_text)}</h2>
  <dl class="fact-list">
    <div><dt>Skript</dt><dd>{esc(script.get("label", script.get("id", "")))}</dd></div>
    <div><dt>ID</dt><dd>{esc(script.get("id", ""))}</dd></div>
    <div><dt>Modus</dt><dd>{'Dry-run' if dry_run else 'Start'}</dd></div>
    <div><dt>Zeit</dt><dd>{esc(datetime.now().strftime("%Y-%m-%d %H:%M:%S"))}</dd></div>
    <div><dt>Befehl</dt><dd>{esc(" ".join(command))}</dd></div>
    {log_row}
  </dl>
  <h3>Ausgabe</h3>
  <pre><code>{esc(result.stdout or "(keine Standardausgabe)")}</code></pre>
  <h3>Fehlerausgabe</h3>
  <pre><code>{esc(result.stderr or "(keine Fehlerausgabe)")}</code></pre>
  <p><a class="text-link" href="/script/{esc(script.get("id", ""))}">Zurück zum Skript</a></p>
</section>
"""
        return self.page("Job-Ergebnis", "jobs", body)

    def error_page(self, message: str) -> bytes:
        return self.page("Fehler", "", f'<section class="panel"><h2>Fehler</h2><p>{esc(message)}</p></section>')

    def not_found(self, message: str) -> bytes:
        return self.page("Nicht gefunden", "", f'<section class="panel"><p>{esc(message)}</p></section>')


class AppsEditor:
    """Schreibt veränderte Oberflächen- und Bereichstexte in artserver-apps.json zurück."""

    AREA_TEXT_FIELDS = ["label", "summary", "humanNotes"]

    def __init__(self, apps_path: Path):
        self.apps_path = apps_path

    def save_overview(self, form: dict[str, list[str]]) -> None:
        with self.apps_path.open("r", encoding="utf-8") as fh:
            apps = json.load(fh)

        admin_gui = apps.setdefault("adminGui", {})
        admin_gui["overviewTitle"] = (form.get("overviewTitle") or [""])[0].strip()
        admin_gui["overviewSummary"] = (form.get("overviewSummary") or [""])[0].strip()

        facts = []
        for index in range(3):
            label = (form.get(f"factLabel{index}") or [""])[0].strip()
            value = (form.get(f"factValue{index}") or [""])[0].strip()
            if label or value:
                facts.append({"label": label, "value": value})
        admin_gui["overviewFacts"] = facts

        self._write(apps)

    def save_area(self, area_id: str, form: dict[str, list[str]]) -> None:
        with self.apps_path.open("r", encoding="utf-8") as fh:
            apps = json.load(fh)

        for area in apps.get("areas", []):
            if area.get("id") != area_id:
                continue
            for field in self.AREA_TEXT_FIELDS:
                raw = (form.get(field) or [""])[0].strip()
                if raw:
                    area[field] = raw
                elif field in area:
                    del area[field]
            break

        self._write(apps)

    def save_inline(self, overview_fields: dict[str, str], area_fields: dict[str, dict[str, str]]) -> None:
        if not overview_fields and not area_fields:
            return
        with self.apps_path.open("r", encoding="utf-8") as fh:
            apps = json.load(fh)

        if overview_fields:
            admin_gui = apps.setdefault("adminGui", {})
            if "overviewTitle" in overview_fields:
                admin_gui["overviewTitle"] = overview_fields["overviewTitle"].strip()
            if "overviewSummary" in overview_fields:
                admin_gui["overviewSummary"] = overview_fields["overviewSummary"].strip()

            facts = admin_gui.get("overviewFacts") or [
                {"label": "Anwendungen", "value": "3 Container-Apps"},
                {"label": "Runner", "value": "Skript-ID basiert"},
                {"label": "Startschutz", "value": "Schutzwort je Risiko"},
            ]
            facts = [{"label": str(item.get("label", "")), "value": str(item.get("value", ""))} for item in facts[:3]]
            while len(facts) < 3:
                facts.append({"label": "", "value": ""})
            for index in range(3):
                label_key = f"factLabel{index}"
                value_key = f"factValue{index}"
                if label_key in overview_fields:
                    facts[index]["label"] = overview_fields[label_key].strip()
                if value_key in overview_fields:
                    facts[index]["value"] = overview_fields[value_key].strip()
            admin_gui["overviewFacts"] = [fact for fact in facts if fact["label"] or fact["value"]]

        for area in apps.get("areas", []):
            area_id = area.get("id", "")
            fields = area_fields.get(area_id)
            if not fields:
                continue
            for field in self.AREA_TEXT_FIELDS:
                if field not in fields:
                    continue
                value = fields[field].strip()
                if value:
                    area[field] = value
                elif field in area:
                    del area[field]

        self._write(apps)

    def _write(self, apps: dict) -> None:
        text = json.dumps(apps, ensure_ascii=False, indent=2) + "\n"
        self.apps_path.write_text(text, encoding="utf-8")


class CatalogEditor:
    """Schreibt veränderte Menüpunkt-Texte direkt in die catalog.json zurück."""

    def __init__(self, catalog_path: Path):
        self.catalog_path = catalog_path

    TEXT_FIELDS = ["summary", "details", "whenToUse", "rollback"]
    LIST_FIELDS = ["beforeStart", "effect", "successCriteria"]

    def save(self, script_id: str, form: dict[str, list[str]]) -> None:
        with self.catalog_path.open("r", encoding="utf-8") as fh:
            catalog = json.load(fh)

        for entry in catalog.get("scripts", []):
            if entry.get("id") != script_id:
                continue
            if "label" in form:
                raw_label = (form.get("label") or [""])[0].strip()
                if raw_label:
                    entry["label"] = raw_label
            for field in self.TEXT_FIELDS:
                raw = (form.get(field) or [""])[0].strip()
                if raw:
                    entry[field] = raw
                    if field == "summary" and "notes" in entry:
                        del entry["notes"]
                elif field in entry:
                    del entry[field]
                    if field == "summary" and "notes" in entry:
                        del entry["notes"]
            for field in self.LIST_FIELDS:
                raw = (form.get(field) or [""])[0]
                items = [line.strip() for line in raw.splitlines() if line.strip()]
                if items:
                    entry[field] = items
                elif field in entry:
                    del entry[field]
            break

        text = json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"
        self.catalog_path.write_text(text, encoding="utf-8")

    def save_inline(self, script_fields: dict[str, dict[str, str]]) -> None:
        if not script_fields:
            return
        with self.catalog_path.open("r", encoding="utf-8") as fh:
            catalog = json.load(fh)

        for entry in catalog.get("scripts", []):
            script_id = entry.get("id", "")
            fields = script_fields.get(script_id)
            if not fields:
                continue
            label = fields.get("label")
            if label is not None and label.strip():
                entry["label"] = label.strip()
            for field in self.TEXT_FIELDS:
                if field not in fields:
                    continue
                value = fields[field].strip()
                if value:
                    entry[field] = value
                    if field == "summary" and "notes" in entry:
                        del entry["notes"]
                elif field in entry:
                    del entry[field]
                    if field == "summary" and "notes" in entry:
                        del entry["notes"]
            for field in self.LIST_FIELDS:
                if field not in fields:
                    continue
                items = [line.strip() for line in fields[field].splitlines() if line.strip()]
                if items:
                    entry[field] = items
                elif field in entry:
                    del entry[field]

        text = json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"
        self.catalog_path.write_text(text, encoding="utf-8")


class Handler(BaseHTTPRequestHandler):
    renderer: Renderer
    data: AdminData
    apps_editor: AppsEditor
    catalog_editor: CatalogEditor

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = unquote(parsed.path)
        if path == "/":
            self.send_html(self.renderer.overview())
            return
        if path.startswith("/area/"):
            self.send_html(self.renderer.area_page(path.removeprefix("/area/")))
            return
        if path.startswith("/script/"):
            query = parse_qs(parsed.query)
            requested_area_id = (query.get("area") or [""])[0]
            self.send_html(self.renderer.script_page(path.removeprefix("/script/"), requested_area_id))
            return
        if path == "/scripts":
            self.redirect("/")
            return
        if path == "/jobs":
            self.send_html(self.renderer.jobs_page())
            return
        if path.startswith("/job-log/"):
            self.send_html(self.renderer.job_log_page(path.removeprefix("/job-log/")))
            return
        if path.startswith("/edit/"):
            self.send_html(self.renderer.edit_page(path.removeprefix("/edit/")))
            return
        if path == "/static/styles.css":
            self.send_static(STATIC_DIR / "styles.css", "text/css; charset=utf-8")
            return
        if path == "/static/editor.js":
            self.send_static(STATIC_DIR / "editor.js", "application/javascript; charset=utf-8")
            return
        self.send_html(self.renderer.not_found(path), status=404)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = unquote(parsed.path)
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw_body = self.rfile.read(length).decode("utf-8")

        if path == "/save-inline-texts":
            try:
                payload = json.loads(raw_body or "{}")
                overview_fields: dict[str, str] = {}
                area_fields: dict[str, dict[str, str]] = {}
                script_fields: dict[str, dict[str, str]] = {}

                for item in payload.get("items", []):
                    if not isinstance(item, dict):
                        continue
                    source = str(item.get("source", ""))
                    item_id = str(item.get("id", ""))
                    field = str(item.get("field", ""))
                    value = str(item.get("value", ""))
                    if not field:
                        continue
                    if source == "overview":
                        overview_fields[field] = value
                    elif source == "area" and item_id:
                        area_fields.setdefault(item_id, {})[field] = value
                    elif source == "script" and item_id:
                        script_fields.setdefault(item_id, {})[field] = value

                self.apps_editor.save_inline(overview_fields, area_fields)
                self.catalog_editor.save_inline(script_fields)
                self.send_json({"ok": True})
            except Exception as exc:
                self.send_json({"ok": False, "error": str(exc)}, status=500)
            return

        form = parse_qs(raw_body)

        if path.startswith("/save/"):
            script_id = path.removeprefix("/save/")
            try:
                self.catalog_editor.save(script_id, form)
                self.redirect(f"/script/{script_id}")
            except Exception as exc:
                self.send_html(self.renderer.edit_page(script_id, notice=f"Fehler beim Speichern: {exc}"), status=500)
            return

        if path == "/save-overview":
            try:
                self.apps_editor.save_overview(form)
                self.redirect((form.get("return_to") or ["/"])[0] or "/")
            except Exception as exc:
                self.send_html(self.renderer.error_page(f"Fehler beim Speichern: {exc}"), status=500)
            return

        if path.startswith("/save-area/"):
            area_id = path.removeprefix("/save-area/")
            try:
                self.apps_editor.save_area(area_id, form)
                self.redirect((form.get("return_to") or [f"/area/{area_id}"])[0] or f"/area/{area_id}")
            except Exception as exc:
                self.send_html(self.renderer.error_page(f"Fehler beim Speichern: {exc}"), status=500)
            return

        if path.startswith("/save-script/"):
            script_id = path.removeprefix("/save-script/")
            try:
                self.catalog_editor.save(script_id, form)
                self.redirect((form.get("return_to") or [f"/script/{script_id}"])[0] or f"/script/{script_id}")
            except Exception as exc:
                self.send_html(self.renderer.error_page(f"Fehler beim Speichern: {exc}"), status=500)
            return

        if not path.startswith("/run/"):
            self.send_html(self.renderer.not_found(path), status=404)
            return

        script_id = path.removeprefix("/run/")
        confirmation = (form.get("confirmation") or [""])[0].strip()
        mode = (form.get("mode") or ["run"])[0]
        dry_run = mode == "dry-run"
        self.run_script(script_id, confirmation, dry_run)

    def run_script(self, script_id: str, confirmation: str, dry_run: bool) -> None:
        _, _, scripts = self.data.load()
        script = scripts.get(script_id)
        if not script:
            self.send_html(self.renderer.error_page(f"Skript-ID nicht gefunden: {script_id}"), status=404)
            return
        if not script_is_startable_here(script):
            start_label, _ = script_start_status(script)
            self.send_html(self.renderer.error_page(f"Dieses Skript kann hier noch nicht direkt gestartet werden. Status: {start_label}."), status=400)
            return
        expected = script.get("requiresConfirmation") or ""
        if expected and confirmation != expected:
            self.send_html(self.renderer.error_page(f"Schutzwort fehlt oder stimmt nicht. Erwartet wird: {expected}"), status=400)
            return

        try:
            command, cwd, should_execute = build_execution(script, dry_run, self.data.runner_path, confirmation)
        except (FileNotFoundError, ValueError) as exc:
            self.send_html(self.renderer.error_page(f"Skript konnte nicht vorbereitet werden: {exc}"), status=500)
            return

        if dry_run and not should_execute:
            stdout = "Dry-run: kein Befehl gestartet.\n"
            stdout += f"Ordner: {cwd}\n"
            stdout += f"Befehl: {' '.join(command)}\n"
            result = subprocess.CompletedProcess(command, 0, stdout, "")
            log_path, log_error = self.write_job_log(script, command, result, dry_run)
            self.send_html(self.renderer.job_result_page(script, command, result, dry_run, log_path, log_error), status=200)
            return

        try:
            result = subprocess.run(
                command,
                cwd=str(cwd),
                capture_output=True,
                text=True,
                timeout=3600,
                check=False,
            )
        except FileNotFoundError as exc:
            self.send_html(self.renderer.error_page(f"Skript konnte nicht gestartet werden: {exc}"), status=500)
            return
        except subprocess.TimeoutExpired as exc:
            stdout = exc.stdout if isinstance(exc.stdout, str) else ""
            stderr = exc.stderr if isinstance(exc.stderr, str) else ""
            result = subprocess.CompletedProcess(command, 124, stdout, stderr + "\nZeitlimit erreicht.")

        log_path, log_error = self.write_job_log(script, command, result, dry_run)
        self.send_html(self.renderer.job_result_page(script, command, result, dry_run, log_path, log_error), status=200 if result.returncode == 0 else 500)

    def write_job_log(self, script: dict, command: list[str], result: subprocess.CompletedProcess[str], dry_run: bool) -> tuple[Path | None, str]:
        try:
            log_dir = self.data.job_log_dir
            log_dir.mkdir(parents=True, exist_ok=True)
            safe_id = re.sub(r"[^A-Za-z0-9_.-]+", "-", str(script.get("id", "job"))).strip("-") or "job"
            stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            log_path = log_dir / f"{stamp}-{safe_id}.log"
            text = "\n".join([
                "== Arkons Admin Web-Job ==",
                f"Zeit: {datetime.now().isoformat(timespec='seconds')}",
                f"Maschine: {platform.node() or 'unbekannt'} ({platform.system() or 'unbekannt'})",
                f"Skript-ID: {script.get('id', '')}",
                f"Name: {script.get('label', '')}",
                f"Modus: {'Dry-run' if dry_run else 'Start'}",
                f"Exitcode: {result.returncode}",
                f"Befehl: {' '.join(command)}",
                "",
                "== Ausgabe ==",
                result.stdout or "(keine Standardausgabe)",
                "",
                "== Fehlerausgabe ==",
                result.stderr or "(keine Fehlerausgabe)",
                "",
            ])
            log_path.write_text(text, encoding="utf-8")
            return log_path, ""
        except OSError as exc:
            return None, f"Web-Log konnte nicht geschrieben werden: {exc}"

    def redirect(self, location: str) -> None:
        if not location.startswith("/"):
            location = "/"
        self.send_response(303)
        self.send_header("Location", location)
        self.end_headers()

    def send_json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_html(self, payload: bytes, status: int = 200) -> None:
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def send_static(self, path: Path, content_type: str) -> None:
        if not path.exists():
            self.send_response(404)
            self.end_headers()
            return
        payload = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format: str, *args: object) -> None:
        return


def main() -> None:
    parser = argparse.ArgumentParser(description="Arkons Admin Web-GUI")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18110)
    parser.add_argument("--apps", type=Path, default=DEFAULT_APPS)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--runner", type=Path, default=DEFAULT_RUNNER)
    parser.add_argument("--job-log-dir", type=Path, default=default_job_log_dir())
    args = parser.parse_args()

    data = AdminData(args.apps, args.catalog, args.runner, args.job_log_dir)
    Handler.data = data
    Handler.renderer = Renderer(data)
    Handler.apps_editor = AppsEditor(args.apps)
    Handler.catalog_editor = CatalogEditor(args.catalog)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Arkons Admin Web-GUI läuft auf http://{args.host}:{args.port}/")
    server.serve_forever()


if __name__ == "__main__":
    main()
