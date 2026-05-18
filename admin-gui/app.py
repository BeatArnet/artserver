#!/usr/bin/env python3
from __future__ import annotations

import argparse
import html
import json
import shlex
import subprocess
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_APPS = ROOT / "artserver-apps.json"
DEFAULT_CATALOG = ROOT / "artserver-script-catalog.json"
STATIC_DIR = Path(__file__).resolve().parent / "static"


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


def as_list(value: object) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item) for item in value]
    return [str(value)]


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


class AdminData:
    def __init__(self, apps_path: Path, catalog_path: Path, runner_path: Path):
        self.apps_path = apps_path
        self.catalog_path = catalog_path
        self.runner_path = runner_path

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

    def page(self, title: str, active: str, body: str, notice: str = "") -> bytes:
        apps, _, _ = self.data.load()
        nav = self.nav(apps, active)
        notice_html = f'<div class="notice">{notice}</div>' if notice else ""
        content = f"""<!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{esc(title)} - Arkons Admin</title>
  <link rel="stylesheet" href="/static/styles.css">
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
          <h1>{esc(title)}</h1>
        </div>
        <div class="topbar-status">
          <span class="status-dot ok"></span>
          Konfiguration geladen
        </div>
      </header>
      {notice_html}
      {body}
    </main>
  </div>
</body>
</html>"""
        return content.encode("utf-8")

    def nav(self, apps: dict, active: str) -> str:
        items = []
        for area in apps.get("areas", []):
            if not area.get("navigation", True):
                continue
            area_id = area.get("id", "")
            href = "/" if area_id == "overview" else f"/area/{area_id}"
            selected = " active" if area_id == active else ""
            items.append(f'<a class="nav-item{selected}" href="{href}">{esc(area.get("label", area_id))}</a>')
        selected = " active" if active == "scripts" else ""
        items.append(f'<a class="nav-item{selected}" href="/scripts">Skripte</a>')
        selected = " active" if active == "jobs" else ""
        items.append(f'<a class="nav-item{selected}" href="/jobs">Jobs und Logs</a>')
        return '<nav class="nav">' + "\n".join(items) + "</nav>"

    def overview(self) -> bytes:
        apps, _, scripts = self.data.load()
        cards = []
        for area in apps.get("areas", []):
            if area.get("id") == "overview":
                continue
            cards.append(self.area_summary(area, scripts))
        body = f"""
<section class="intro hero-panel">
  <div>
    <h2>Arbeitszentrale für artserver</h2>
    <p>Diese Oberfläche bündelt Website, Server, Container und die Wartungsskripte der Anwendungen. Die Konfiguration kommt aus <code>artserver-apps.json</code> und <code>artserver-script-catalog.json</code>. Startbare Aktionen laufen über den Runner, damit im Browser keine freien Shell-Befehle ausgeführt werden.</p>
  </div>
  <dl class="hero-facts">
    <div><dt>Anwendungen</dt><dd>3 Container-Apps</dd></div>
    <div><dt>Runner</dt><dd>Skript-ID basiert</dd></div>
    <div><dt>Startschutz</dt><dd>Schutzwort je Risiko</dd></div>
  </dl>
</section>
<section class="overview-grid">
  {''.join(cards)}
</section>
"""
        return self.page("Übersicht", "overview", body)

    def area_summary(self, area: dict, scripts: dict[str, dict]) -> str:
        script_ids = area.get("scriptIds", [])
        startable = sum(1 for script_id in script_ids if script_is_server_startable(scripts.get(script_id, {})))
        checks = area.get("healthChecks") or area.get("statusChecks") or []
        containers = area.get("containerNames", [])
        return f"""
<article class="summary-card">
  <div class="summary-head">
    <h2>{esc(area.get("label", area.get("id", "")))}</h2>
    <span class="pill pill-ok">konfiguriert</span>
  </div>
  <p>{esc(area.get("summary", area.get("humanNotes", "")))}</p>
  <dl class="compact-facts">
    <div><dt>Typ</dt><dd>{esc(area.get("kind", ""))}</dd></div>
    <div><dt>Container</dt><dd>{len(containers)}</dd></div>
    <div><dt>Checks</dt><dd>{len(checks)}</dd></div>
    <div><dt>Skripte</dt><dd>{len(script_ids)} davon {startable} startbar</dd></div>
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
        script_blocks = "".join(self.script_block(script, [area.get("label", area_id)]) for script in assigned_scripts)
        if not script_blocks:
            script_blocks = '<p class="muted">Für diesen Bereich sind noch keine Skripte zugeordnet.</p>'

        body = f"""
<section class="detail-layout">
  <div class="detail-primary">
    <section class="panel section-lead">
      <h2>Einordnung</h2>
      <p>{esc(area.get("humanNotes", area.get("summary", "")))}</p>
      {facts}
    </section>
    <section class="panel">
      <div class="section-title-row">
        <h2>Menüpunkte und Hilfestellung</h2>
        <span class="pill">{len(assigned_scripts)} zugeordnet</span>
      </div>
      <div class="script-list">
        {script_blocks}
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
        checks = area.get("healthChecks") or area.get("statusChecks") or []
        if not checks:
            return '<p class="muted">Noch keine Checks konfiguriert.</p>'
        items = []
        for check in checks:
            target = check.get("url") or check.get("service") or check.get("host") or ""
            if check.get("port"):
                target = f"{target}:{check.get('port')}"
            items.append(f"""
<div class="check-row">
  <span class="status-dot unknown"></span>
  <div>
    <strong>{esc(check.get("label", check.get("id", "")))}</strong>
    <span>{esc(check.get("type", ""))} · {esc(target)}</span>
  </div>
</div>
""")
        return "".join(items)

    def script_block(self, script: dict, areas: list[str] | None = None) -> str:
        run = script.get("run") or {}
        server_startable = script_is_server_startable(script)
        enabled_label = "startbar" if server_startable else "nur dokumentiert"
        enabled_class = "pill-ok" if server_startable else "pill-muted"
        confirmation = script.get("requiresConfirmation") or ""
        area_text = ", ".join(areas or [])
        action_form = self.action_form(script) if server_startable else self.not_startable_box(script)

        return f"""
<article class="script-item">
  <div class="script-head">
    <div>
      <h3>{esc(script.get("label", script.get("id", "")))}</h3>
      <div class="script-id">{esc(script.get("id", ""))}</div>
    </div>
    <div class="badges">
      <span class="pill {risk_class(script.get('risk', ''))}">{esc(script.get("risk", "unbekannt"))}</span>
      <span class="pill {enabled_class}">{enabled_label}</span>
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
        blocks = [
            ("Was macht dieser Menüpunkt?", [summary, details] if details != summary else [summary]),
            ("Wann verwenden?", as_list(script.get("whenToUse"))),
            ("Vor dem Start prüfen", as_list(script.get("beforeStart"))),
            ("Wirkung", as_list(script.get("effect"))),
            ("Erfolgskriterium", as_list(script.get("successCriteria"))),
            ("Rollback / wenn etwas schiefgeht", as_list(script.get("rollback"))),
        ]
        html_blocks = []
        if area_text:
            html_blocks.append(f"""
<div class="help-box help-assignment">
  <h4>Zugeordnet zu</h4>
  <p>{esc(area_text)}</p>
</div>
""")
        for title, values in blocks:
            if not values:
                continue
            if len(values) == 1:
                content = f"<p>{esc(values[0])}</p>"
            else:
                content = "<ul>" + "".join(f"<li>{esc(item)}</li>" for item in values if item) + "</ul>"
            html_blocks.append(f"""
<div class="help-box">
  <h4>{esc(title)}</h4>
  {content}
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
        return f"""
<div class="execution-note">
  Dieser Eintrag ist im Katalog sichtbar, aber nicht für den Server-Runner freigegeben. Grund: Ort <code>{esc(script.get("location", ""))}</code>, Starttyp <code>{esc((script.get("run") or {}).get("type", ""))}</code>. Solche Skripte brauchen meist den Entwicklungsrechner, Parameter oder eine manuelle Prüfung.
</div>
"""

    def scripts_page(self) -> bytes:
        apps, catalog, _ = self.data.load()
        script_area_map = self.data.script_to_area_map()
        used: set[str] = set()
        content = []
        for area in apps.get("areas", []):
            area_scripts = []
            for script in catalog.get("scripts", []):
                if area.get("label") in script_area_map.get(script.get("id", ""), []):
                    area_scripts.append(script)
                    used.add(script.get("id", ""))
            if area_scripts:
                blocks = "".join(self.script_block(script, [area.get("label", "")]) for script in area_scripts)
                content.append(f'<section class="panel"><h2>{esc(area.get("label", ""))}</h2><div class="script-list">{blocks}</div></section>')

        remaining = [script for script in catalog.get("scripts", []) if script.get("id", "") not in used]
        if remaining:
            groups: dict[str, list[dict]] = {}
            for script in remaining:
                groups.setdefault(script.get("group", "Weitere"), []).append(script)
            for group in sorted(groups):
                blocks = "".join(self.script_block(script, []) for script in sorted(groups[group], key=lambda item: item.get("id", "")))
                content.append(f'<section class="panel"><h2>Nicht zugeordnet: {esc(group)}</h2><div class="script-list">{blocks}</div></section>')
        return self.page("Skripte", "scripts", "".join(content))

    def jobs_page(self) -> bytes:
        body = """
<section class="panel">
  <h2>Jobs und Logs</h2>
  <p>Der Runner schreibt Logs unter <code>/home/art/arkons/logs/admin/jobs</code>. In dieser ersten Web-Version wird das Ergebnis eines gestarteten Jobs direkt nach dem Start angezeigt. Eine dauerhafte Logliste folgt in der nächsten Etappe.</p>
</section>
"""
        return self.page("Jobs und Logs", "jobs", body)

    def job_result_page(self, script: dict, command: list[str], result: subprocess.CompletedProcess[str], dry_run: bool) -> bytes:
        status_class = "job-ok" if result.returncode == 0 else "job-failed"
        status_text = "erfolgreich" if result.returncode == 0 else f"Fehler {result.returncode}"
        body = f"""
<section class="panel job-result {status_class}">
  <h2>Job {esc(status_text)}</h2>
  <dl class="fact-list">
    <div><dt>Skript</dt><dd>{esc(script.get("label", script.get("id", "")))}</dd></div>
    <div><dt>ID</dt><dd>{esc(script.get("id", ""))}</dd></div>
    <div><dt>Modus</dt><dd>{'Dry-run' if dry_run else 'Start'}</dd></div>
    <div><dt>Zeit</dt><dd>{esc(datetime.now().strftime("%Y-%m-%d %H:%M:%S"))}</dd></div>
    <div><dt>Befehl</dt><dd>{esc(" ".join(command))}</dd></div>
  </dl>
  <h3>Ausgabe</h3>
  <pre><code>{esc(result.stdout or "(keine Standardausgabe)")}</code></pre>
  <h3>Fehlerausgabe</h3>
  <pre><code>{esc(result.stderr or "(keine Fehlerausgabe)")}</code></pre>
  <p><a class="text-link" href="/area/{esc((script.get("id", "").split(".", 1)[0] or ""))}">Zurück zur Anwendung</a></p>
</section>
"""
        return self.page("Job-Ergebnis", "jobs", body)

    def error_page(self, message: str) -> bytes:
        return self.page("Fehler", "", f'<section class="panel"><h2>Fehler</h2><p>{esc(message)}</p></section>')

    def not_found(self, message: str) -> bytes:
        return self.page("Nicht gefunden", "", f'<section class="panel"><p>{esc(message)}</p></section>')


class Handler(BaseHTTPRequestHandler):
    renderer: Renderer
    data: AdminData

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = unquote(parsed.path)
        if path == "/":
            self.send_html(self.renderer.overview())
            return
        if path.startswith("/area/"):
            self.send_html(self.renderer.area_page(path.removeprefix("/area/")))
            return
        if path == "/scripts":
            self.send_html(self.renderer.scripts_page())
            return
        if path == "/jobs":
            self.send_html(self.renderer.jobs_page())
            return
        if path == "/static/styles.css":
            self.send_static(STATIC_DIR / "styles.css", "text/css; charset=utf-8")
            return
        self.send_html(self.renderer.not_found(path), status=404)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = unquote(parsed.path)
        if not path.startswith("/run/"):
            self.send_html(self.renderer.not_found(path), status=404)
            return

        script_id = path.removeprefix("/run/")
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw_body = self.rfile.read(length).decode("utf-8")
        form = parse_qs(raw_body)
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
        if not script_is_server_startable(script):
            self.send_html(self.renderer.error_page("Dieses Skript ist nicht für den Server-Runner freigegeben."), status=400)
            return
        expected = script.get("requiresConfirmation") or ""
        if expected and confirmation != expected:
            self.send_html(self.renderer.error_page(f"Schutzwort fehlt oder stimmt nicht. Erwartet wird: {expected}"), status=400)
            return

        runner_path = bash_path(self.data.runner_path)
        command = ["bash", runner_path, "run", script_id]
        if expected:
            command.extend(["--confirm", confirmation])
        if dry_run:
            command.append("--dry-run")

        try:
            result = subprocess.run(
                command,
                cwd=str(ROOT),
                capture_output=True,
                text=True,
                timeout=3600,
                check=False,
            )
        except FileNotFoundError as exc:
            self.send_html(self.renderer.error_page(f"Runner konnte nicht gestartet werden: {exc}"), status=500)
            return
        except subprocess.TimeoutExpired as exc:
            stdout = exc.stdout if isinstance(exc.stdout, str) else ""
            stderr = exc.stderr if isinstance(exc.stderr, str) else ""
            result = subprocess.CompletedProcess(command, 124, stdout, stderr + "\nZeitlimit erreicht.")

        self.send_html(self.renderer.job_result_page(script, command, result, dry_run), status=200 if result.returncode == 0 else 500)

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
    args = parser.parse_args()

    data = AdminData(args.apps, args.catalog, args.runner)
    Handler.data = data
    Handler.renderer = Renderer(data)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Arkons Admin Web-GUI läuft auf http://{args.host}:{args.port}/")
    server.serve_forever()


if __name__ == "__main__":
    main()
