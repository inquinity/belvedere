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
contains, in four layers:

1. Packages in the bundle's source map. mermaid@VERSION is fetched with
   `npm pack` and the `sources` of dist/mermaid.min.js.map are read; each
   package path there names a package and the version built in. Code from
   Mermaid's own parser package is followed into that package's chunk maps
   (the published copy's: the bundle's parser was built at the Mermaid tag,
   so its versions are taken from Mermaid's lockfile, which pinned it).
2. Packages a dependency had already bundled before Mermaid's build. A map
   names such a dependency once, under its own name, so INLINED lists what
   each one carries (vscode-uri, roughjs, venn.js).
3. Code compiled into a package from another project, which no package
   manifest records (EMBEDDED: Guava and GWT's runtime inside ELK, JamaJS
   code in layout-base, a Babel helper in DOMPurify).
4. A check: every runtime dependency of every package found must itself be
   found, or be in NOT_BUNDLED with the reason it is absent. A package that
   ships a prebuilt file can still inline a build-time dependency this check
   cannot see; layer 2 is where such packages are recorded when found.

Map sources the script cannot attribute stop it, and so does a dependency
that is neither found nor explained. Each package is fetched at its version
with `npm pack` (npm checks the registry's checksum) and, where Mermaid's
pnpm-lock.yaml at the mermaid@VERSION tag has it, also checked against the
lockfile's SHA-512. Nothing from a package is run.

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
# Mermaid's own code, and webpack's generated module runtime, need no notice.
OWN_CODE = (re.compile(r"^(\.\./)+src/"), re.compile(r"^webpack://LIB/webpack/"))
# The one package known to ship a webpack build whose sources reach the map
# as webpack://LIB/...; a second such package would be misattributed, so
# webpack sources are only accepted while this names exactly one owner.
WEBPACK_OWNER = "vscode-uri"
# Packages that ship a prebuilt file with other packages inside it.
INLINED = {
    "vscode-uri": ("path-browserify",),
    "roughjs": ("hachure-fill", "path-data-parser", "points-on-curve", "points-on-path"),
    "@upsetjs/venn.js": ("fmin",),
}
# Runtime dependencies of bundled packages that are not in the bundle.
NOT_BUNDLED = {
    "@chevrotain/types": "type declarations only",
    "@types/trusted-types": "type declarations only",
    "delaunator": "only d3-delaunay's own source is in the map",
    "rw": "used by d3-dsv's command-line tools only",
    "commander": "command-line tools only (d3-dsv, KaTeX)",
    "iconv-lite": "used by d3-dsv's command-line tools only",
    "argparse": "used by js-yaml's command-line tool only",
    "strictdom": "a fastdom development extension, not in the map",
    "vscode-languageserver": "langium's language-server side, not in the parser chunks",
    "mlly": "Node-only code in @iconify/utils, not in the map",
    "debug": "Node-only code in @iconify/utils, not in the map",
    "globals": "Node-only code in @iconify/utils, not in the map",
    "kolorist": "Node-only code in @iconify/utils, not in the map",
    "local-pkg": "Node-only code in @iconify/utils, not in the map",
    "@antfu/install-pkg": "Node-only code in @iconify/utils, not in the map",
    "@antfu/utils": "Node-only code in @iconify/utils, not in the map",
    "@iconify/types": "type declarations only",
    "contour_plot": "fmin's demo visualisations only, which venn.js does not take",
}
# Where the source is, for components whose license asks binary
# distributors to say so.
SOURCE_OFFERS = {"elkjs": "https://github.com/kieler/elkjs/tree/{version}"}
# Code compiled into a package from another project: a label, and where its
# notice comes from ("url:..." fetched, "file:path:N" the first N lines of a
# file in the package).
EMBEDDED = {
    "dompurify": [
        ("Babel regenerator-runtime helper, built into DOMPurify's dist; "
         "MIT License, Copyright (c) 2014-present, Facebook, Inc.",
         "url:https://raw.githubusercontent.com/babel/babel/v7.28.0/packages/babel-helpers/LICENSE"),
    ],
    "layout-base": [
        ("Singular value decomposition code adapted from JamaJS "
         "(https://github.com/dragonfly-ai/JamaJS), under the Apache License 2.0; "
         "from layout-base's src/util/SVD.js",
         "file:src/util/SVD.js:214"),
    ],
    "elkjs": [
        ("Google Guava, compiled into elk.bundled.js by GWT; "
         "Copyright (C) The Guava Authors, Apache License 2.0",
         "url:https://raw.githubusercontent.com/google/guava/master/LICENSE"),
        ("GWT's Java runtime emulation, compiled into elk.bundled.js; "
         "Copyright Google Inc. and the GWT authors, Apache License 2.0",
         "url:https://raw.githubusercontent.com/gwtproject/gwt/main/distro-source/core/src/COPYING"),
    ],
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

    def manifest(self, name: str, version: str) -> dict:
        return json.loads((self.get(name, version) / "package.json").read_text())


def map_sources(path: Path) -> list[str]:
    return json.loads(path.read_text())["sources"]


def lockfile_versions(lock: dict, name: str) -> set[str]:
    return {key.rsplit("@", 1)[1] for key in lock["packages"] if key.rsplit("@", 1)[0] == name}


def lockfile_version(lock: dict, name: str, published: str) -> str:
    """The version of a package inside the parser as Mermaid's tag built it:
    the published parser's own version if the lockfile has it, else the
    lockfile's only version."""
    versions = lockfile_versions(lock, name)
    if published in versions:
        return published
    if len(versions) == 1:
        return versions.pop()
    raise RuntimeError(f"{name}: the published {PARSER} has {published}, the lockfile {versions}")


def mapped_packages(mermaid: str, packs: Tarballs, lock: dict) -> tuple[set[tuple[str, str]], bool]:
    """Layer 1. Returns the packages and whether webpack sources were seen."""
    found: set[tuple[str, str]] = set()
    unexplained: list[str] = []
    root = packs.get("mermaid", mermaid)
    pending = [(source, "mermaid") for source in map_sources(root / "dist/mermaid.min.js.map")]
    parser_files: set[str] = set()
    webpack_seen = False

    while pending:
        source, origin = pending.pop()
        match = PNPM_PATH.search(source)
        if match:
            # The folder is name@version, then _peer@version or _patch_hash=...
            folder, name = match.group(1), match.group(2)
            version = folder[len(name.replace("/", "+")) + 1:].split("_", 1)[0]
            if origin == PARSER:
                version = lockfile_version(lock, name, version)
            found.add((name, version))
        elif any(pattern.search(source) for pattern in OWN_CODE):
            pass
        elif "/parser/dist/" in source and origin == "mermaid":
            parser_files.add(source.split("/parser/", 1)[1])
        elif source.startswith("webpack://LIB/"):
            nested = re.match(r"webpack://LIB/node_modules/((?:@[^/]+/)?[^/]+)/", source)
            if nested and nested.group(1) not in INLINED.get(WEBPACK_OWNER, ()):
                unexplained.append(f"{origin}: {source} (not in INLINED[{WEBPACK_OWNER!r}])")
            webpack_seen = True
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
    return found, webpack_seen


def owner_version(lock: dict, owner: str, found: set[tuple[str, str]]) -> str:
    """The lockfile version of `owner` that a found package depends on."""
    snapshots = lock.get("snapshots") or {}
    versions = {str(entry["dependencies"][owner]).split("(")[0]
                for key, entry in snapshots.items()
                if entry and owner in (entry.get("dependencies") or {})
                and any(key.split("(")[0] == f"{name}@{version}" for name, version in found)}
    if len(versions) != 1:
        raise RuntimeError(f"no single version of {owner} in the lockfile: {versions}")
    return versions.pop()


def inlined_packages(found: set[tuple[str, str]], webpack_seen: bool,
                     packs: Tarballs, lock: dict) -> set[tuple[str, str]]:
    """Layer 2: what INLINED owners carry, at the version their own manifest
    asked for (the newest the registry has in that range)."""
    names = {name: version for name, version in found}
    if webpack_seen and WEBPACK_OWNER not in names:
        names[WEBPACK_OWNER] = owner_version(lock, WEBPACK_OWNER, found)
    added: set[tuple[str, str]] = set()
    if WEBPACK_OWNER in names:
        added.add((WEBPACK_OWNER, names[WEBPACK_OWNER]))
    for owner, inlined in INLINED.items():
        if owner not in names:
            continue
        manifest = packs.manifest(owner, names[owner])
        wanted = {**manifest.get("devDependencies", {}), **manifest.get("dependencies", {})}
        for name in inlined:
            if name not in wanted:
                raise RuntimeError(f"{owner} {names[owner]} no longer depends on {name}")
            spec = urllib.parse.unquote(wanted[name])
            # A Yarn patch of a published version: patch:fmin@npm:0.0.4#...
            patched = re.match(r"patch:.+?@npm:([^#]+)#", spec)
            if patched:
                spec = patched.group(1)
            exact = json.loads(run("npm", "view", f"{name}@{spec}", "version", "--json",
                                   f"--registry={REGISTRY}"))
            added.add((name, exact[-1] if isinstance(exact, list) else exact))
    return added


def check_dependencies(found: set[tuple[str, str]], packs: Tarballs) -> None:
    """Layer 4: every runtime dependency is found or explained."""
    names = {name for name, _ in found}
    unexplained = []
    for name, version in sorted(found):
        manifest = packs.manifest(name, version)
        for dependency in {**manifest.get("dependencies", {}),
                           **manifest.get("optionalDependencies", {})}:
            if dependency not in names and dependency not in NOT_BUNDLED \
                    and not dependency.startswith("@types/"):
                unexplained.append(f"{name} {version} depends on {dependency}")
    if unexplained:
        raise RuntimeError("dependencies neither bundled nor in NOT_BUNDLED:\n  "
                           + "\n  ".join(unexplained))


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


def embedded_notice(package: Path, source: str) -> str:
    kind, _, rest = source.partition(":")
    if kind == "url":
        return fetch(rest).strip()
    path, _, lines = rest.rpartition(":")
    if not (package / path).exists():
        return ""  # this version of the package does not carry that code
    text = (package / path).read_text(encoding="utf-8").splitlines()[: int(lines)]
    return "\n".join(text).strip()


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
        found, webpack_seen = mapped_packages(mermaid, packs, lock)
        found |= inlined_packages(found, webpack_seen, packs, lock)
        check_dependencies(found, packs)
        for name, version in sorted(found):
            package = packs.get(name, version)
            license_id, files = notice_files(package)
            for label, source in EMBEDDED.get(name, []):
                notice = embedded_notice(package, source)
                if notice:
                    files.append((label, notice))
            sections.append((name, version, license_id, files, f"{name}@{version}" in integrity))

    rule = "-" * 77
    out = [
        f"Third-party notices for mermaid.min.js (Mermaid {mermaid})",
        "",
        "mermaid.min.js is Mermaid's single-file build. Besides Mermaid itself,",
        "under the MIT License in LICENSE beside this file, it contains the",
        "packages below, as found from its source maps and from what those",
        "packages are known to carry inside them. Each package's license files",
        "follow, unmodified, with notices for code compiled into a package from",
        "another project after them. Written by bin/make-mermaid-notices.py; do",
        "not edit by hand.",
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
          f"the lockfile's SHA-512, the rest against the registry's only")
    return 0


if __name__ == "__main__":
    sys.exit(main())
