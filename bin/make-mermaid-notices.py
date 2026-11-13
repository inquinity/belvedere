#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["pyyaml"]
# ///
"""Write the license notices for everything bundled inside mermaid.min.js.

mermaid.min.js is a single-file build that inlines Mermaid's dependencies
(d3, dagre, cytoscape, ELK, chevrotain, langium, KaTeX, DOMPurify and more).
Their notices must ship with every copy, and the bundle keeps only a few of
them as comments, so this script collects them from what the bundle says it
contains:

1. fetches mermaid@VERSION with `npm pack` and reads the `sources` of
   dist/mermaid.min.js.map. Each package path there names the package and
   the exact version that was built in. Code taken from Mermaid's own parser
   package is followed into that package's chunk maps (the published copy's;
   versions come from Mermaid's lockfile, which pinned the build), and code that a dependency had already bundled with webpack (vscode-uri,
   with path-browserify inside it) is attributed through WEBPACK_BUNDLES.
   Any source the script cannot attribute stops it: a missing notice is the
   failure this script exists to prevent;
2. fetches each package at that version with `npm pack`, checks it against
   the SHA-512 in Mermaid's pnpm-lock.yaml at the mermaid@VERSION tag where
   the lockfile has it (npm checks the registry's own checksum either way),
   and copies its LICENSE / COPYING / NOTICE files into one text file.

Nothing from a package is run. Mermaid's dependency ranges are not resolved
today: they would describe a bundle that was never built.

Network: registry.npmjs.org and raw.githubusercontent.com.
Run from the repository root:  uv run --script bin/make-mermaid-notices.py 12.3.0
"""
from __future__ import annotations

import base64
import hashlib
import json
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
PARSER = "@mermaid-js/parser"
PNPM_PATH = re.compile(r"node_modules/\.pnpm/([^/]+)/node_modules/((?:@[^/]+/)?[^/]+)/")
# Packages that ship webpack builds of their own; their sources appear in a
# map as webpack://LIB/... rather than as package paths.
WEBPACK_BUNDLES = {"vscode-uri": ("path-browserify",)}
# Mermaid's own code, and webpack's generated module runtime, need no notice.
OWN_CODE = (re.compile(r"^(\.\./)+src/"), re.compile(r"^webpack://LIB/webpack/"))
# Where the source is, for components whose license asks binary
# distributors to say so.
SOURCE_OFFERS = {"elkjs": "https://github.com/kieler/elkjs/tree/{version}"}
# Notices for code a package carries from elsewhere without its own license
# file. DOMPurify's dist includes a Babel regenerator-runtime helper.
EMBEDDED = {
    "dompurify": ("Babel regenerator-runtime helper, built into DOMPurify's dist",
                  "https://raw.githubusercontent.com/babel/babel/main/packages/babel-helpers/LICENSE"),
}


def run(*args: str, cwd: Path | None = None) -> str:
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True).stdout


def fetch(url: str) -> str:
    return run("curl", "-fsSL", url)


def from_tag(mermaid: str, path: str) -> str:
    tag = urllib.parse.quote(f"mermaid@{mermaid}")
    return fetch(f"https://raw.githubusercontent.com/mermaid-js/mermaid/{tag}/{path}")


class Tarballs:
    """npm pack, once per package, unpacked into a temporary folder."""

    def __init__(self, work: Path, integrity: dict[str, str]):
        self.work, self.integrity, self.unpacked = work, integrity, {}

    def get(self, name: str, version: str) -> Path:
        key = f"{name}@{version}"
        if key not in self.unpacked:
            name_on_disk = run("npm", "pack", key, f"--registry={REGISTRY}", "--silent",
                               cwd=self.work).strip().splitlines()[-1]
            tarball = self.work / name_on_disk
            expected = self.integrity.get(key)
            if expected:
                algorithm, digest = expected.split("-", 1)
                actual = base64.b64encode(hashlib.new(algorithm, tarball.read_bytes()).digest()).decode()
                if actual != digest:
                    raise RuntimeError(f"{key} does not match the lockfile's {algorithm}")
            target = self.work / "x" / key.replace("/", "+")
            with tarfile.open(tarball) as archive:
                archive.extractall(target, filter="data")
            tarball.unlink()
            self.unpacked[key] = target / "package"
        return self.unpacked[key]


def map_sources(path: Path) -> list[str]:
    return json.loads(path.read_text())["sources"]


def bundled_packages(mermaid: str, packs: Tarballs, lock: dict) -> set[tuple[str, str]]:
    found: set[tuple[str, str]] = set()
    unexplained: list[str] = []
    root = packs.get("mermaid", mermaid)
    pending = [(source, "mermaid") for source in map_sources(root / "dist/mermaid.min.js.map")]
    parser_files: set[str] = set()
    webpack_owner_needed = False

    while pending:
        source, origin = pending.pop()
        match = PNPM_PATH.search(source)
        if match:
            # The folder is name@version, then _peer@version or _patch_hash=...
            folder, name = match.group(1), match.group(2)
            version = folder[len(name.replace("/", "+")) + 1:].split("_", 1)[0]
            if origin == PARSER:
                version = lockfile_version(lock, match.group(2), version)
            found.add((match.group(2), version))
        elif any(pattern.search(source) for pattern in OWN_CODE):
            pass
        elif "/parser/dist/" in source and origin == "mermaid":
            parser_files.add(source.split("/parser/", 1)[1])
        elif source.startswith("webpack://LIB/"):
            webpack_owner_needed = True
            nested = re.match(r"webpack://LIB/node_modules/((?:@[^/]+/)?[^/]+)/", source)
            if nested:
                found.add((nested.group(1), ""))  # its version comes from the owner below
        else:
            unexplained.append(f"{origin}: {source}")

        if not pending and parser_files:
            manifest = json.loads(from_tag(mermaid, "packages/parser/package.json"))
            parser = packs.get(PARSER, manifest["version"])
            found.add((PARSER, manifest["version"]))
            # The bundle's parser chunks were built at the Mermaid tag, so
            # their file names need not match the published package's. When
            # they do not, every chunk map of that build of the parser counts.
            maps = [parser / f"{file}.map" for file in sorted(parser_files)]
            if not all(path.exists() for path in maps):
                folders = {path.parent for path in maps}
                maps = sorted(map_path for folder in folders for map_path in folder.glob("*.map"))
                if not maps:
                    raise RuntimeError(f"{PARSER} {manifest['version']} has no chunk maps")
            for map_file in maps:
                pending += [(source, PARSER) for source in map_sources(map_file)]
            parser_files.clear()

    if unexplained:
        raise RuntimeError("cannot attribute these bundle sources:\n  " + "\n  ".join(unexplained))
    if webpack_owner_needed:
        found |= webpack_owners(found, packs, lock)
    return found


def lockfile_version(lock: dict, name: str, published: str) -> str:
    """The version of a package inside the parser as Mermaid's tag built it:
    the published parser's own version if the lockfile has it, else the
    lockfile's only version."""
    versions = {key.rsplit("@", 1)[1] for key in lock["packages"]
                if key.rsplit("@", 1)[0] == name}
    if published in versions:
        return published
    if len(versions) == 1:
        return versions.pop()
    raise RuntimeError(f"{name}: the published {PARSER} has {published}, the lockfile {versions}")


def webpack_owners(found: set[tuple[str, str]], packs: Tarballs, lock: dict) -> set[tuple[str, str]]:
    """Resolve WEBPACK_BUNDLES: the owner at the version the lockfile gives a
    bundled package that depends on it, and each package the owner inlined at
    the newest version its own manifest allows."""
    snapshots = lock.get("snapshots") or {}
    owners: set[tuple[str, str]] = set()
    for owner, inlined in WEBPACK_BUNDLES.items():
        versions = {str(entry["dependencies"][owner]).split("(")[0]
                    for key, entry in snapshots.items()
                    if entry and owner in (entry.get("dependencies") or {})
                    and any(key.split("(")[0] == f"{name}@{version}" for name, version in found)}
        if len(versions) != 1:
            raise RuntimeError(f"no single version of {owner} in the lockfile: {versions}")
        version = versions.pop()
        owners.add((owner, version))
        manifest = json.loads((packs.get(owner, version) / "package.json").read_text())
        wanted = {**manifest.get("dependencies", {}), **manifest.get("devDependencies", {})}
        for name in inlined:
            found.discard((name, ""))
            exact = json.loads(run("npm", "view", f"{name}@{wanted[name]}", "version", "--json",
                                   f"--registry={REGISTRY}"))
            owners.add((name, exact[-1] if isinstance(exact, list) else exact))
    leftover = [name for name, version in found if not version]
    if leftover:
        raise RuntimeError(f"webpack-bundled packages with no owner in WEBPACK_BUNDLES: {leftover}")
    return owners


def notice_files(package: Path) -> tuple[str, list[tuple[str, str]]]:
    manifest = json.loads((package / "package.json").read_text())
    license_id = str(manifest.get("license") or "no license field; see its file")
    files = sorted((path.name, path.read_text(encoding="utf-8", errors="replace").strip())
                   for path in package.iterdir()
                   if path.is_file() and path.name.lower().startswith(NOTICE_PREFIXES))
    if not files:
        # Some packages (fastdom) state their license only in the README.
        for readme in sorted(package.glob("[Rr][Ee][Aa][Dd][Mm][Ee]*")):
            text = readme.read_text(encoding="utf-8", errors="replace")
            section = re.search(r"^#+\s*Licen[cs]e\s*$(.*?)(?=^#+\s|\Z)", text, re.M | re.S)
            if section and section.group(1).strip():
                files.append((f"{readme.name}, License section", section.group(1).strip()))
                break
    if not files:
        raise RuntimeError(f"{manifest['name']} ships no license file or README license section")
    return license_id, files


def main() -> int:
    if len(sys.argv) != 2 or not re.fullmatch(r"\d+\.\d+\.\d+", sys.argv[1]):
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    mermaid = sys.argv[1]
    lock = yaml.safe_load(from_tag(mermaid, "pnpm-lock.yaml"))
    integrity = {key: entry["resolution"]["integrity"]
                 for key, entry in lock["packages"].items()
                 if "integrity" in (entry.get("resolution") or {})}
    sections = []
    with tempfile.TemporaryDirectory() as temp:
        packs = Tarballs(Path(temp), integrity)
        packages = bundled_packages(mermaid, packs, lock)
        for name, version in sorted(packages):
            license_id, files = notice_files(packs.get(name, version))
            if name in EMBEDDED:
                label, url = EMBEDDED[name]
                files.append((label, fetch(url).strip()))
            sections.append((name, version, license_id, files, f"{name}@{version}" in integrity))

    rule = "-" * 77
    out = [
        f"Third-party notices for mermaid.min.js (Mermaid {mermaid})",
        "",
        "mermaid.min.js is Mermaid's single-file build. Besides Mermaid itself,",
        "under the MIT License in LICENSE beside this file, it contains the",
        "packages below, at the versions its source map names. Each package's own",
        "license files follow, unmodified. Written by bin/make-mermaid-notices.py;",
        "do not edit by hand.",
        "",
    ]
    out += [f"  {name} {version} -- {license_id}" for name, version, license_id, _, _ in sections]
    for name, version, *_ in sections:
        if name in SOURCE_OFFERS:
            out += ["", f"{name} {version} is used under the Eclipse Public License 2.0.",
                    "Its source code is available under that license at",
                    "  " + SOURCE_OFFERS[name].format(version=version)]
    for name, version, license_id, files, _ in sections:
        out += ["", rule, "", f"{name} {version} ({license_id})"]
        for label, text in files:
            out += ["", f"[{label}]", "", text]
    DEST.write_text("\n".join(out) + "\n", encoding="utf-8")
    checked = sum(1 for *_, in_lock in sections if in_lock)
    print(f"Wrote {DEST}: {len(sections)} packages; {checked} also checked against "
          f"the lockfile's SHA-512, the rest against the registry's")
    return 0


if __name__ == "__main__":
    sys.exit(main())
