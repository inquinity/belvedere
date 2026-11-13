#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["pyyaml"]
# ///
"""Write the license notices for everything bundled inside mermaid.min.js.

mermaid.min.js is a single-file build that inlines Mermaid's dependencies
(d3, dagre, cytoscape, ELK, chevrotain, KaTeX, DOMPurify and about a hundred
more). Their notices must ship with every copy, and the bundle keeps only a
few of them as comments, so this script collects them:

1. reads Mermaid's own pnpm-lock.yaml at the mermaid@VERSION tag, which pins
   every package, at the exact version and checksum, that the published
   bundle was built from, and walks the dependencies of packages/mermaid;
2. fetches each of those packages with `npm pack`, checks it against the
   lockfile's SHA-512, and copies its LICENSE / COPYING / NOTICE files into
   one text file. Nothing from a package is run.

Today's npm resolution is not used: Mermaid's ranges resolve to newer
versions now, one of them a different major, so it would describe a bundle
that was never built. Type-declaration packages (@types/*) are left out: they
hold no code that reaches the bundle. Packages that serve only Node-side code
paths may still be listed; an unneeded notice is harmless, a missing one is not.

Network: raw.githubusercontent.com and registry.npmjs.org.
Run from the repository root:  uv run --script bin/make-mermaid-notices.py 12.3.0
"""
from __future__ import annotations

import base64
import hashlib
import json
import posixpath
import re
import subprocess
import sys
import tarfile
import tempfile
import urllib.parse
from pathlib import Path

import yaml

DEST = Path("belvedere/Vendor/Mermaid/Mermaid-THIRD-PARTY-NOTICES.txt")
REGISTRY = "https://registry.npmjs.org/"
NOTICE_PREFIXES = ("license", "licence", "copying", "notice")
# Where the source is, for components whose license asks binary
# distributors to say so.
SOURCE_OFFERS = {
    "elkjs": "https://github.com/kieler/elkjs/tree/{version}",
}


def run(*args: str, cwd: Path | None = None) -> str:
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True).stdout


def fetch_from_tag(version: str, path: str) -> str:
    tag = urllib.parse.quote(f"mermaid@{version}")
    return run("curl", "-fsSL",
               f"https://raw.githubusercontent.com/mermaid-js/mermaid/{tag}/{path}")


def closure(lock: dict, mermaid: str) -> dict[tuple[str, str], str | None]:
    """(name, version) -> lockfile integrity, or None for a workspace package."""
    importers = lock["importers"]
    snapshots = lock.get("snapshots") or {}
    packages = lock["packages"]
    found: dict[tuple[str, str], str | None] = {}

    def dependencies(entry: dict) -> dict[str, object]:
        merged: dict[str, object] = {}
        for field in ("dependencies", "optionalDependencies"):
            merged.update(entry.get(field) or {})
        return merged

    def visit_importer(path: str) -> None:
        for name, spec in dependencies(importers[path]).items():
            version = spec["version"] if isinstance(spec, dict) else str(spec)
            visit(name, version, path)

    def visit(name: str, version: str, importer: str) -> None:
        if name.startswith("@types/"):
            return
        if version.startswith("link:"):
            # A workspace package, such as packages/parser, built from the
            # same tag and published on npm under its own version.
            path = posixpath.normpath(posixpath.join(importer, version[len("link:"):]))
            manifest = json.loads(fetch_from_tag(mermaid, f"{path}/package.json"))
            key = (manifest["name"], manifest["version"])
            if key not in found:
                found[key] = None
                visit_importer(path)
            return
        base = version.split("(", 1)[0]
        key = (name, base)
        if key in found:
            return
        found[key] = packages[f"{name}@{base}"]["resolution"]["integrity"]
        snapshot = snapshots.get(f"{name}@{version}") or {}
        for child, child_version in dependencies(snapshot).items():
            visit(child, str(child_version), importer)

    visit_importer("packages/mermaid")
    return found


def notice_files(work: Path, name: str, version: str,
                 integrity: str | None) -> tuple[str, list[tuple[str, str]]]:
    tarball = work / run("npm", "pack", f"{name}@{version}", f"--registry={REGISTRY}",
                         "--silent", cwd=work).strip().splitlines()[-1]
    if integrity is not None:
        algorithm, expected = integrity.split("-", 1)
        actual = base64.b64encode(hashlib.new(algorithm, tarball.read_bytes()).digest()).decode()
        if actual != expected:
            raise RuntimeError(f"{name}@{version} does not match the lockfile's {algorithm}")
    files: list[tuple[str, str]] = []
    license_id = ""
    with tarfile.open(tarball) as archive:
        for member in archive.getmembers():
            parts = member.name.split("/")
            if len(parts) != 2 or not member.isfile():
                continue
            data = archive.extractfile(member).read().decode("utf-8", "replace")
            if parts[1] == "package.json":
                license_id = str(json.loads(data).get("license") or "no license field; see its file")
            elif parts[1].lower().startswith(NOTICE_PREFIXES):
                files.append((parts[1], data.strip()))
    tarball.unlink()
    if not files:
        raise RuntimeError(f"{name}@{version} ships no license file")
    return license_id, sorted(files)


def main() -> int:
    if len(sys.argv) != 2 or not re.fullmatch(r"\d+\.\d+\.\d+", sys.argv[1]):
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    mermaid = sys.argv[1]
    lock = yaml.safe_load(fetch_from_tag(mermaid, "pnpm-lock.yaml"))
    entries = closure(lock, mermaid)
    sections = []
    with tempfile.TemporaryDirectory() as temp:
        for (name, version), integrity in sorted(entries.items()):
            license_id, files = notice_files(Path(temp), name, version, integrity)
            sections.append((name, version, license_id, files))

    rule = "-" * 77
    out = [
        f"Third-party notices for mermaid.min.js (Mermaid {mermaid})",
        "",
        "mermaid.min.js is Mermaid's single-file build. Besides Mermaid itself,",
        "under the MIT License in LICENSE beside this file, it contains the",
        "packages below, at the versions pinned in Mermaid's pnpm-lock.yaml at",
        f"the mermaid@{mermaid} tag. Each package's own license files follow,",
        "unmodified. Written by bin/make-mermaid-notices.py; do not edit by hand.",
        "",
    ]
    out += [f"  {name} {version} -- {license_id}" for name, version, license_id, _ in sections]
    for name, version, _, _ in sections:
        if name in SOURCE_OFFERS:
            out += ["", f"Source code for {name} {version} is available at",
                    "  " + SOURCE_OFFERS[name].format(version=version)]
    for name, version, license_id, files in sections:
        out += ["", rule, "", f"{name} {version} ({license_id})"]
        for base, text in files:
            out += ["", f"[{base}]", "", text]
    DEST.write_text("\n".join(out) + "\n", encoding="utf-8")
    checked = sum(1 for integrity in entries.values() if integrity is not None)
    print(f"Wrote {DEST}: {len(sections)} packages, {checked} checked against the "
          "lockfile's SHA-512 (workspace packages have none; npm checks those)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
