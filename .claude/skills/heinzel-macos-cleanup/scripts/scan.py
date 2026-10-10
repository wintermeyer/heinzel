#!/usr/bin/python3
"""Read-only scan for leftovers of uninstalled macOS apps.

Runs with the Python 3.9 from the Command Line Tools and needs only the
standard library. It never deletes, moves or writes anything.

    scan.py orphans         entries of apps that are no longer installed
    scan.py app <name|id>   everything that belongs to one installed app

Output is JSON on stdout. See ../references/classification.md.
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from functools import cached_property
from pathlib import Path

HOME = Path.home()

LOCATIONS = [
    HOME / "Library" / d
    for d in (
        "Application Scripts",
        "Application Support",
        "Caches",
        "Containers",
        "Cookies",
        "Group Containers",
        "HTTPStorages",
        "Internet Plug-Ins",
        "LaunchAgents",
        "Logs",
        "PreferencePanes",
        "Preferences",
        "QuickLook",
        "Saved Application State",
        "Screen Savers",
        "WebKit",
    )
] + [
    Path("/Library") / d
    for d in (
        "Application Support",
        "Audio/Plug-Ins/HAL",
        "Caches",
        "Extensions",
        "Internet Plug-Ins",
        "LaunchAgents",
        "LaunchDaemons",
        "Logs",
        "PreferencePanes",
        "Preferences",
        "PrivilegedHelperTools",
        "QuickLook",
        "Screen Savers",
    )
]

APP_DIRS = [
    Path("/Applications"),
    HOME / "Applications",
    Path("/System/Applications"),
    Path("/Library/Application Support"),
]

CONTAINER_METADATA = ".com.apple.containermanagerd.metadata.plist"
APP_GROUPS = "com.apple.security.application-groups"

# Bundle folders not worth descending into for nested bundle ids.
SKIP_DIRS = {"Developer", "Headers", "Modules", "_CodeSignature"}

BUNDLE_SUFFIXES = {
    ".appex",
    ".bundle",
    ".component",
    ".driver",
    ".kext",
    ".plugin",
    ".prefPane",
    ".qlgenerator",
    ".saver",
}

# Libraries nested in an app. Their bundle ids do not name a vendor.
LIBRARY_SUFFIXES = (".framework", ".bundle")

NAME_SUFFIXES = (".plist", ".savedState", ".binarycookies", ".lockfile")

GROUP_PREFIXES = ("systemgroup.", "groups.", "group.")
APPLE_PREFIXES = ("com.apple.", "is.workflow.", "org.cups.")

# Apple data without a com.apple prefix. Unlisted names stay "unclear".
APPLE_NAMES = {
    "addressbook",
    "amsdatamigratortool",
    "animoji",
    "appplaceholdersyncd",
    "arfilecache",
    "askpermissiond",
    "baseband",
    "byhost",
    "callhistorydb",
    "callhistorytransactions",
    "clipboardappicons",
    "clouddocs",
    "contextstoreagent",
    "coremlcache",
    "coresimulator",
    "databases",
    "destinationd",
    "diagnosticreports",
    "diagnostics_agent",
    "differentialprivacy",
    "directoryservice",
    "features_config",
    "geoservices",
    "icdd",
    "ilifemediabrowser",
    "intelligenceflow",
    "knowledge",
    "livefsd",
    "locationaccessstored",
    "lsmimagecache",
    "mbuseragent",
    "mobilesync",
    "opendirectory",
    "passkit",
    "privacypreservingmeasurement",
    "replayd",
    "scopedbookmarkagent",
    "sesstorage",
    "ssu",
    "stickersd",
    "storedownloadd",
    "systemconfiguration",
    "tokenbucketratelimiter",
    "trickplay",
    "tv",
    "tvapp_bag",
    "xccov",
    "xsan",
}

APPLE_NAME_PREFIXES = ("siri",)

# Bundle id prefixes shared by unrelated apps.
GENERIC_VENDORS = {"com.electron", "com.github", "io.github"}

# Caches of developer tools. Safe to delete, rebuilt on demand.
CACHE_NAMES = {
    "bun",
    "go-build",
    "hex",
    "mix",
    "node-gyp",
    "phx-esbuild",
    "pip",
    "pipx",
    "pnpm",
    "puccinialin",
    "pypoetry",
    "rustler_precompiled",
    "typescript",
    "uv",
    "virtualenv",
    "yarn",
}

TEAM_RE = re.compile(r"^([A-Z0-9]{10})\.(.+)$")
UUID_RE = re.compile(r"^[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}$", re.IGNORECASE)
RDNS_RE = re.compile(r"^[a-z0-9-]+(\.[a-z0-9_-]+){2,}$")
SYSTEM_PREFIXES = ("/System/", "/usr/", "/bin/", "/sbin/", "/opt/homebrew/")
WORKERS = 8


@dataclass
class Inventory:
    bundle_ids: set[str] = field(default_factory=set)
    names: set[str] = field(default_factory=set)
    team_ids: set[str] = field(default_factory=set)
    tools: set[str] = field(default_factory=set)
    app_names: set[str] = field(default_factory=set)
    apple_daemons: set[str] = field(default_factory=set)
    apps: list[dict] = field(default_factory=list)

    # Computed once, after collect_inventory() filled the fields.
    @cached_property
    def own_ids(self) -> set[str]:
        return {b for a in self.apps for b in a["own_ids"]}

    @cached_property
    def vendors(self) -> set[str]:
        return {vendor_prefix(b) for b in self.own_ids if "." in b} - GENERIC_VENDORS

    @cached_property
    def vendor_labels(self) -> set[str]:
        return {vendor_label(b) for b in self.own_ids} - {""}

    @cached_property
    def app_groups(self) -> set[str]:
        return {g for a in self.apps for g in a["groups"]}

    @cached_property
    def first_words(self) -> set[str]:
        return {w for w in map(first_word, self.app_names) if w}

    @cached_property
    def squashed_names(self) -> list[tuple[str, str]]:
        return [(n, squash(n)) for n in self.names]


def squash(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", s.lower())


def first_word(name: str) -> str:
    parts = name.split()
    word = squash(parts[0]) if parts else ""
    return word if len(word) >= 4 else ""


def vendor_prefix(bid: str) -> str:
    return ".".join(bid.split(".")[:2])


def vendor_label(bid: str) -> str:
    """Return the squashed vendor of a bundle id: org.mozilla.firefox → mozilla.

    Vendor folders like Mozilla or OpenAI carry this name.
    """
    parts = bid.split(".")
    if len(parts) < 3 or bid.startswith(APPLE_PREFIXES):
        return ""
    if vendor_prefix(bid) in GENERIC_VENDORS:
        return ""
    label = squash(parts[1])
    return label if len(label) >= 4 else ""


def strip_suffix(name: str) -> str:
    for suffix in NAME_SUFFIXES:
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return name


def strip_group(name: str) -> str:
    for prefix in GROUP_PREFIXES:
        if name.startswith(prefix):
            return name[len(prefix) :]
    return name


def split_id(name: str) -> tuple[str, str]:
    """Return (team id, lowercase bundle id) of a Library entry name.

    Handles TEAM.group.id as well as group.TEAM.id.
    """
    base = strip_group(strip_suffix(name))
    m = TEAM_RE.match(base)
    if not m:
        return "", base.lower()
    return m.group(1), strip_group(m.group(2)).lower()


def owned_by(bid: str, ids: set[str]) -> bool:
    parts = bid.split(".")
    return any(".".join(parts[:i]) in ids for i in range(len(parts), 1, -1))


def apple_reason(low: str, bid: str, daemons: set[str] = frozenset()) -> str:
    if bid.startswith(APPLE_PREFIXES):
        return "Apple prefix"
    if low in APPLE_NAMES or low.startswith(APPLE_NAME_PREFIXES):
        return "known Apple data"
    if low in daemons:
        return "name of an Apple launchd job"
    return ""


def classify_name(name: str, inv: Inventory) -> tuple[str, str]:
    low = strip_suffix(name).lower()
    team, bid = split_id(name)
    reason = apple_reason(low, bid, inv.apple_daemons)
    if reason:
        return "apple", reason
    if low in inv.app_groups:
        return "installed", "app group of an installed app"
    if "playwright" in low or low in CACHE_NAMES:
        return "cache", "developer tool cache"

    if RDNS_RE.match(bid):
        if owned_by(bid, inv.bundle_ids):
            return "installed", "bundle id of an installed app"
        if team and team in inv.team_ids:
            return "vendor", f"team {team} has another app installed"
        vendor = vendor_prefix(bid)
        if vendor in inv.vendors:
            return "vendor", f"{vendor} has another app installed"
        return "orphan", "no installed app with this bundle id"
    if team:
        if team in inv.team_ids:
            return "vendor", f"team {team} has an app installed"
        return "orphan", f"no installed app from team {team}"

    norm = squash(low)
    if low in inv.tools:
        return "installed", "command or Homebrew package"
    for n, sn in inv.squashed_names:
        if sn == norm or (
            len(norm) >= 5 and len(sn) >= 5 and (sn in norm or norm in sn)
        ):
            return "installed", f"matches app name {n!r}"
    if norm in inv.vendor_labels:
        return "vendor", f"vendor {norm!r} has an app installed"
    for w in inv.first_words:
        if w in norm:
            return "vendor", f"shares the word {w!r} with an installed app"
    return "unclear", "name matches no installed app"


def parse_plist(data: bytes) -> dict:
    try:
        plist = plistlib.loads(data)
    except (plistlib.InvalidFileException, ValueError):
        return {}
    return plist if isinstance(plist, dict) else {}


def read_plist(path: Path) -> dict:
    try:
        return parse_plist(path.read_bytes())
    except OSError:
        return {}


def launchd_program(path: Path) -> str:
    data = read_plist(path)
    program = data.get("Program")
    args = data.get("ProgramArguments")
    if not program and isinstance(args, list) and args:
        program = args[0]
    return program if isinstance(program, str) else ""


def is_launchd_plist(path: Path) -> bool:
    return path.parent.name in ("LaunchAgents", "LaunchDaemons") and (
        path.suffix == ".plist"
    )


def classify_entry(path: Path, inv: Inventory, containers: Path) -> tuple[str, str]:
    name = path.name
    parent = path.parent.name
    if path.is_symlink() and not path.exists():
        return "orphan", "symlink to a missing target"

    if is_launchd_plist(path):
        program = launchd_program(path)
        if program and not os.path.isabs(program):
            # launchd resolves a bare name through PATH.
            if shutil.which(program):
                return "custom", f"own job, command {program}"
            return "unclear", f"command not on PATH: {program}"
        if program:
            if not os.path.exists(program):
                return "orphan", f"program missing: {program}"
            if ".app/" in program:
                return "installed", f"program inside {program.split('.app/')[0]}.app"
            if program.startswith(SYSTEM_PREFIXES):
                return "installed", f"program in {program}"
            if not program.startswith("/Library/"):
                return "custom", f"own job, program {program}"

    if UUID_RE.match(name):
        if parent == "Containers":
            ident = read_plist(path / CONTAINER_METADATA).get("MCMMetadataIdentifier")
            if isinstance(ident, str):
                return classify_name(ident, inv)
        elif parent == "Application Scripts" and not (containers / name).exists():
            return "orphan", "UUID folder without a container"
        return "unclear", "UUID folder"

    if path.suffix in BUNDLE_SUFFIXES:
        bid = read_plist(path / "Contents" / "Info.plist").get("CFBundleIdentifier")
        if isinstance(bid, str):
            return classify_name(bid, inv)

    return classify_name(name, inv)


def app_matches(
    path: Path,
    app_ids: set[str],
    app_names: set[str],
    taken: set[str] = frozenset(),
    label: str = "",
    shared: set[str] = frozenset(),
    groups: set[str] = frozenset(),
    loose: set[str] = frozenset(),
    loose_ids: set[str] = frozenset(),
) -> str:
    """Return "exact", "name" or "" for an entry and one app.

    `label` is the app's vendor label. `taken` holds first words and
    vendor labels of other apps, `shared` their app groups. `groups`
    holds the app groups that count as exact. `loose` and `loose_ids`
    hold the groups and bundle ids that need a confirmation.
    """
    low = strip_suffix(path.name).lower()
    _, bid = split_id(path.name)
    if apple_reason(low, bid) or low in shared:
        return ""
    if owned_by(bid, app_ids) or low in groups:
        return "exact"
    if low in loose or owned_by(bid, loose_ids):
        return "name"
    norm = squash(low)
    if label and norm == label and norm not in taken:
        return "name"
    for n in app_names:
        if squash(n) == norm:
            return "name"
        w = first_word(n)
        if w and w not in taken and w in norm:
            return "name"
    return ""


# --- probes (macOS only) -------------------------------------------------


def proc(cmd: list[str], timeout: int = 60) -> subprocess.CompletedProcess | None:
    try:
        return subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, check=False
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def run(cmd: list[str], timeout: int = 60) -> str:
    r = proc(cmd, timeout)
    return r.stdout + r.stderr if r else ""


def app_roots() -> set[Path]:
    found = run(["mdfind", "kMDItemContentType == 'com.apple.application-bundle'"])
    roots = {Path(p) for p in found.splitlines() if p.endswith(".app")}
    for base in APP_DIRS:
        for dirpath, dirnames, _ in os.walk(base):
            depth = len(Path(dirpath).relative_to(base).parts)
            for d in list(dirnames):
                if d.endswith((".app", ".prefPane")):
                    roots.add(Path(dirpath) / d)
                    dirnames.remove(d)
            if depth >= 2:
                dirnames.clear()
    return {r for r in roots if r.is_dir()}


def bundle_infos(root: Path):
    """Yield (folder, Info.plist) for the app and every nested bundle."""
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        if "Info.plist" in filenames:
            yield Path(dirpath), read_plist(Path(dirpath) / "Info.plist")


def signature(path: Path) -> tuple[str, set[str]]:
    """Return the Team ID and the lowercase app groups of a signed bundle."""
    # -v writes the Team ID to stderr, --entitlements the plist to stdout.
    r = proc(["codesign", "-dv", "--entitlements", "-", "--xml", str(path)])
    if r and r.returncode:
        # An older codesign without --xml refuses the whole call.
        r = proc(["codesign", "-dv", str(path)])
    if not r:
        return "", set()
    m = re.search(r"TeamIdentifier=([A-Z0-9]{10})", r.stderr)
    groups = parse_plist(r.stdout.encode()).get(APP_GROUPS)
    if not isinstance(groups, list):
        groups = []
    return m.group(1) if m else "", {g.lower() for g in groups if isinstance(g, str)}


def bundle_names(info: dict) -> set[str]:
    values = (info.get(k) for k in ("CFBundleName", "CFBundleDisplayName"))
    return {v.lower() for v in values if isinstance(v, str) and len(v) > 2}


def describe_app(root: Path) -> dict:
    """Bundle ids and names of an app. Nested names stay apart."""
    top: dict = {}
    ids, own, libs, nested = set(), set(), set(), set()
    for folder, info in bundle_infos(root):
        bid = info.get("CFBundleIdentifier")
        if isinstance(bid, str):
            bid = bid.lower()
            ids.add(bid)
            parts = folder.relative_to(root).parts
            is_lib = any(p.endswith(LIBRARY_SUFFIXES) for p in parts)
            (libs if is_lib else own).add(bid)
        if folder == root / "Contents":
            top = info
        else:
            nested |= bundle_names(info)
    team, groups = signature(root)
    main = top.get("CFBundleIdentifier")
    main = main.lower() if isinstance(main, str) else ""
    # A library under the app's own vendor prefix is part of the app.
    vendor = vendor_prefix(main)
    adopted = set()
    if "." in main and vendor not in GENERIC_VENDORS:
        adopted = {b for b in libs if vendor_prefix(b) == vendor} - own
    return {
        "path": str(root),
        "id": main,
        "ids": ids,
        "own_ids": own | adopted,
        "adopted_ids": adopted,
        "names": {root.stem.lower()} | bundle_names(top),
        "nested_names": nested,
        "team": team,
        "groups": groups,
    }


def collect_inventory() -> Inventory:
    inv = Inventory()
    # codesign dominates the runtime. It runs in parallel.
    with ThreadPoolExecutor(WORKERS) as pool:
        apps = list(pool.map(describe_app, sorted(app_roots())))
    for app in apps:
        root = Path(app["path"])
        inv.bundle_ids |= app["ids"]
        inv.names |= app["names"] | app["nested_names"]
        if app["team"]:
            inv.app_names.add(root.stem.lower())
            inv.team_ids.add(app["team"])
        inv.apps.append(app)

    for d in ("/System/Library/LaunchAgents", "/System/Library/LaunchDaemons"):
        for n in os.listdir(d):
            if n.startswith("com.apple.") and n.endswith(".plist"):
                inv.apple_daemons.add(strip_suffix(n).split(".")[-1].lower())

    brew = shutil.which("brew")
    if brew:
        inv.tools |= set(run([brew, "list", "-1"]).lower().split())
    for d in os.environ.get("PATH", "").split(":"):
        try:
            inv.tools |= {n.lower() for n in os.listdir(d)}
        except OSError:
            pass
    return inv


def size_of(path: Path) -> int:
    if path.is_symlink():
        return 0
    out = run(["du", "-sk", str(path)]).split()
    return int(out[0]) * 1024 if out and out[0].isdigit() else 0


def entries(unreadable: list[str]):
    for loc in LOCATIONS:
        try:
            names = sorted(os.listdir(loc))
        except FileNotFoundError:
            continue
        except OSError:
            unreadable.append(str(loc))
            continue
        for n in names:
            if not n.startswith("."):
                yield loc / n


def add_sizes(found: list[dict]) -> None:
    with ThreadPoolExecutor(WORKERS) as pool:
        sizes = pool.map(lambda e: size_of(Path(e["path"])), found)
        for e, size in zip(found, sizes):
            e["bytes"] = size


def receipts() -> list[str]:
    out = run(["pkgutil", "--pkgs"]).split()
    return [p for p in out if not p.startswith("com.apple.")]


def scan_orphans(inv: Inventory, show_all: bool) -> dict:
    containers = HOME / "Library" / "Containers"
    unreadable: list[str] = []
    found = []
    for path in entries(unreadable):
        try:
            path.lstat()  # Python 3.12+ hides this error in exists()
            c, reason = classify_entry(path, inv, containers)
        except OSError:
            unreadable.append(str(path))
            continue
        if show_all or c not in ("apple", "installed"):
            found.append({"path": str(path), "class": c, "reason": reason})
    add_sizes([e for e in found if e["class"] != "apple"])
    pkgs = [
        {"id": p, "class": "orphan"}
        for p in receipts()
        if classify_name(p, inv)[0] == "orphan"
    ]
    return {"entries": found, "receipts": pkgs, "unreadable": unreadable}


def is_running(app: str) -> bool:
    # pgrep takes a POSIX ERE. re.escape() would also escape "-",
    # which ERE leaves undefined.
    pattern = re.sub(r"([.^$*+?()\[\]{}|\\])", r"\\\1", app + "/Contents/MacOS/")
    r = proc(["pgrep", "-f", pattern])
    return r is not None and r.returncode == 0


def scan_app(inv: Inventory, query: str) -> dict:
    q = query.lower().removesuffix(".app")
    targets = [
        a
        for a in inv.apps
        if a["path"] == query.rstrip("/") or q in a["ids"] or q in a["names"]
    ]
    if not targets:
        return {"error": f"no installed app matches {query!r}"}
    if len(targets) > 1:
        return {
            "error": f"{query!r} matches several apps, pass one path",
            "candidates": sorted(a["path"] for a in targets),
        }
    target = targets[0]
    app_path, names = target["path"], target["names"]
    others = [a for a in inv.apps if a is not target]
    # Library ids belong to every app that embeds the library. That holds
    # for an adopted one too while another installed app owns it: gone when
    # it is the other app's own, to confirm when both adopted it.
    theirs = {b for a in others for b in a["own_ids"]}
    contested = target["adopted_ids"] & theirs
    ids = target["own_ids"] - contested
    loose_ids = contested - {b for a in others for b in a["own_ids"] - a["adopted_ids"]}
    taken = {first_word(n) for a in others for n in a["names"]}
    taken |= {vendor_label(b) for b in theirs}
    shared = {g for a in others for g in a["groups"]}
    # Nested bundles of the team's other apps may declare the same groups.
    # An empty team counts as a different team.
    team = target["team"]
    team_apps = bool(team) and any(a["team"] == team for a in others)
    # Only the Team ID prefix closes a group to the apps of other teams.
    mine = set() if team_apps else target["groups"]
    groups = {g for g in mine if team and g.startswith(f"{team.lower()}.")}
    loose = mine - groups
    label = vendor_label(target["id"])

    unreadable: list[str] = []
    found = [{"path": app_path, "match": "exact"}]
    for path in entries(unreadable):
        if str(path) == app_path:
            continue
        m = app_matches(
            path, ids, names, taken, label, shared, groups, loose, loose_ids
        )
        program = launchd_program(path) if is_launchd_plist(path) else ""
        if not m and program.startswith(app_path + "/"):
            m = "exact"
        if m:
            found.append({"path": str(path), "match": m})
    add_sizes(found)
    pkgs = [p for p in receipts() if owned_by(p.lower(), ids)]
    return {
        "apps": [app_path],
        "ids": sorted(ids),
        "running": [app_path] if is_running(app_path) else [],
        "entries": found,
        "receipts": pkgs,
        "unreadable": unreadable,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="mode", required=True)
    orphans = sub.add_parser("orphans", help="leftovers of removed apps")
    orphans.add_argument("--all", action="store_true", help="include apple/installed")
    app = sub.add_parser("app", help="everything of one installed app")
    app.add_argument("query", help="app name or bundle id")
    args = parser.parse_args()

    if sys.platform != "darwin":
        parser.error("macOS only")
    if os.geteuid() == 0:
        # root's home is /var/root, so the scan would miss the user's Library.
        parser.error("run as the user whose apps to scan, not as root")
    inv = collect_inventory()
    if args.mode == "orphans":
        result = scan_orphans(inv, args.all)
    else:
        result = scan_app(inv, args.query)
    result["inventory"] = {
        "apps": len(inv.apps),
        "bundle_ids": len(inv.bundle_ids),
        "team_ids": len(inv.team_ids),
    }
    json.dump(result, sys.stdout, indent=1, sort_keys=True)
    print()
    return 1 if "error" in result else 0


if __name__ == "__main__":
    sys.exit(main())
