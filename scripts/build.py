from __future__ import annotations

import html
import json
import os
import re
import shutil
import tomllib
from pathlib import Path
from typing import Any, NotRequired, TypedDict, cast


ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / "content" / "pages"
DIST = ROOT / "dist"
TEXTS = ROOT / "content" / "textbausteine.toml"
TOKEN_RE = re.compile(r"\{\{\s*(text|paragraphs|list|cards|steps|gallery):([A-Za-z0-9_.-]+)(?::([^}]+))?\s*\}\}")


class NavItem(TypedDict):
    label: str
    url: str
    children: NotRequired[list["NavItem"]]


def parse_page(path: Path) -> tuple[dict[str, str], str]:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        raise ValueError(f"{path} needs front matter")
    _, front, body = text.split("---\n", 2)
    meta: dict[str, str] = {}
    for line in front.splitlines():
        if not line.strip():
            continue
        key, value = line.split(":", 1)
        meta[key.strip()] = value.strip().strip('"')
    for key in ("title", "description", "path"):
        if key not in meta:
            raise ValueError(f"{path} misses '{key}'")
    return meta, body.strip()


def load_texts() -> dict[str, Any]:
    if not TEXTS.exists():
        return {}
    with TEXTS.open("rb") as handle:
        return cast(dict[str, Any], tomllib.load(handle))


def text_value(data: dict[str, Any], path: str) -> Any:
    value: Any = data
    for part in path.split("."):
        if not isinstance(value, dict) or part not in value:
            raise KeyError(f"Textbaustein fehlt: {path}")
        value = value[part]
    return value


def escaped(value: Any) -> str:
    return html.escape(str(value), quote=True)


def paragraph_items(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(item) for item in value]
    return [part.strip() for part in str(value).split("\n\n") if part.strip()]


def render_paragraphs(value: Any) -> str:
    return "\n".join(f"          <p>{escaped(item)}</p>" for item in paragraph_items(value))


def render_list(value: Any) -> str:
    if not isinstance(value, list):
        raise TypeError("list-Textbausteine müssen Listen sein")
    items = "\n".join(f"            <li>{escaped(item)}</li>" for item in value)
    return f'          <ul class="plain-list">\n{items}\n          </ul>'


def render_cards(value: Any, extra_class: str | None = None) -> str:
    if not isinstance(value, list):
        raise TypeError("cards-Textbausteine müssen Listen sein")
    item_class = "product-feature"
    if extra_class:
        item_class = f"{item_class} {html.escape(extra_class.strip(), quote=True)}"
    cards: list[str] = ['          <div class="product-feature-grid expanded">']
    for item in value:
        if not isinstance(item, dict):
            raise TypeError("cards-Einträge müssen Tabellen sein")
        cards.append(f'            <article class="{item_class}">')
        if item.get("kicker"):
            cards.append(f'              <span class="feature-kicker">{escaped(item["kicker"])}</span>')
        cards.append(f'              <h3>{escaped(item.get("title", ""))}</h3>')
        cards.append(f'              <p>{escaped(item.get("body", ""))}</p>')
        cards.append("            </article>")
    cards.append("          </div>")
    return "\n".join(cards)


def render_steps(value: Any) -> str:
    if not isinstance(value, list):
        raise TypeError("steps-Textbausteine müssen Listen sein")
    steps: list[str] = ['          <ol class="process-steps">']
    for item in value:
        if not isinstance(item, dict):
            raise TypeError("steps-Einträge müssen Tabellen sein")
        steps.append("            <li>")
        steps.append(f'              <span class="step-label">{escaped(item.get("label", ""))}</span>')
        steps.append("              <div>")
        steps.append(f'                <h3>{escaped(item.get("title", ""))}</h3>')
        steps.append(f'                <p>{escaped(item.get("body", ""))}</p>')
        steps.append("              </div>")
        steps.append("            </li>")
    steps.append("          </ol>")
    return "\n".join(steps)


def render_gallery(value: Any, extra_class: str | None = None) -> str:
    if not isinstance(value, list):
        raise TypeError("gallery-Textbausteine müssen Listen sein")
    cls = "screenshot-gallery"
    if extra_class:
        cls = f"{cls} {html.escape(extra_class.strip(), quote=True)}"
    figures: list[str] = [f'          <div class="{cls}">']
    for item in value:
        if not isinstance(item, dict):
            raise TypeError("gallery-Einträge müssen Tabellen sein")
        figures.append("            <figure>")
        figures.append(f'              <img loading="lazy" src="{escaped(item.get("src", ""))}" alt="{escaped(item.get("alt", ""))}">')
        figures.append(f'              <figcaption>{escaped(item.get("caption", ""))}</figcaption>')
        figures.append("            </figure>")
    figures.append("          </div>")
    return "\n".join(figures)


def render_content_tokens(body: str, texts: dict[str, Any]) -> str:
    def replace(match: re.Match[str]) -> str:
        kind, path, extra = match.group(1), match.group(2), match.group(3)
        value = text_value(texts, path)
        if kind == "text":
            return escaped(value)
        if kind == "paragraphs":
            return render_paragraphs(value)
        if kind == "list":
            return render_list(value)
        if kind == "cards":
            return render_cards(value, extra)
        if kind == "steps":
            return render_steps(value)
        if kind == "gallery":
            return render_gallery(value, extra)
        raise ValueError(f"Unbekannter Textbaustein-Typ: {kind}")

    return TOKEN_RE.sub(replace, body)


def render_links(items: list[NavItem], current: str, nav: bool) -> str:
    lines = []
    for item in items:
        label = html.escape(item["label"])
        url = item["url"]
        children = item.get("children", [])
        active = url == current or any(child["url"] == current for child in children)
        current_attr = ' aria-current="page"' if nav and active else ""
        if nav and children:
            child_links = "\n".join(
                f'            <a href="{child["url"]}">{html.escape(child["label"])}</a>'
                for child in children
            )
            lines.append(
                f'        <div class="nav-item has-menu"><a href="{url}"{current_attr}>{label}</a><div class="submenu">\n{child_links}\n          </div></div>'
            )
        else:
            lines.append(f'        <a href="{url}"{current_attr}>{label}</a>')
    return "\n".join(lines)


def output_path(page_path: str) -> Path:
    clean = page_path.strip("/")
    if clean == "":
        return DIST / "index.html"
    return DIST / clean / "index.html"


def copy_static() -> None:
    for name in ("assets", "downloads"):
        src = ROOT / name
        dst = DIST / name
        if dst.exists():
            shutil.rmtree(dst)
        if src.exists():
            shutil.copytree(src, dst)


def remove_tree(path: Path) -> None:
    def retry_writeable(function, item, _excinfo):
        os.chmod(item, 0o700)
        function(item)

    shutil.rmtree(path, onerror=retry_writeable)


def main() -> None:
    site = cast(
        dict[str, Any],
        json.loads((ROOT / "content" / "site.json").read_text(encoding="utf-8")),
    )
    texts = load_texts()
    template = (ROOT / "templates" / "base.html").read_text(encoding="utf-8")

    if DIST.exists():
        remove_tree(DIST)
    DIST.mkdir(parents=True)
    copy_static()

    for source in sorted(CONTENT.glob("*.html")):
        if source.name.startswith("_"):
            continue
        meta, body = parse_page(source)
        body = render_content_tokens(body, texts)
        current = meta["path"]
        title = meta["title"]
        if title != site["siteName"]:
            title = f'{title} | {site["siteName"]}'
        page = template
        replacements = {
            "{{ title }}": html.escape(title),
            "{{ description }}": html.escape(meta["description"]),
            "{{ siteName }}": html.escape(site["siteName"]),
            "{{ address }}": html.escape(site["address"]),
            "{{ nav }}": render_links(cast(list[NavItem], site["nav"]), current, True),
            "{{ footerLinks }}": render_links(
                cast(list[NavItem], site["footerLinks"]), current, False
            ),
            "{{ body }}": body,
        }
        for marker, value in replacements.items():
            page = page.replace(marker, value)
        target = output_path(current)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(page + "\n", encoding="utf-8")
        print(f"built {target.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
