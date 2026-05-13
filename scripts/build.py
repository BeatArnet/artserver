from __future__ import annotations

import html
import json
import os
import shutil
from pathlib import Path
from typing import Any, TypedDict, cast


ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / "content" / "pages"
DIST = ROOT / "dist"


class NavItem(TypedDict, total=False):
    label: str
    url: str
    children: list["NavItem"]


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
    template = (ROOT / "templates" / "base.html").read_text(encoding="utf-8")

    if DIST.exists():
        remove_tree(DIST)
    DIST.mkdir(parents=True)
    copy_static()

    for source in sorted(CONTENT.glob("*.html")):
        if source.name.startswith("_"):
            continue
        meta, body = parse_page(source)
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
