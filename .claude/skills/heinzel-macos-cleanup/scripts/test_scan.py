"""Tests for scan.py. Run: python3 -m unittest discover -s <this dir>."""

import os
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import scan


def app_entry(path, bid, nested=(), groups=(), libs=(), team=""):
    """`nested` holds the app's own nested ids, `libs` those of its libraries."""
    return {
        "path": path,
        "id": bid,
        "ids": {bid, *nested, *libs},
        "own_ids": {bid, *nested},
        "names": {Path(path).stem.lower()},
        "team": team,
        "groups": set(groups),
    }


def own(bid, nested=(), groups=()):
    return app_entry("/Applications/X.app", bid, nested, groups)


INV = scan.Inventory(
    bundle_ids={
        "com.tapbots.pastebot2mac",
        "com.microsoft.teams2",
        "com.microsoft.autoupdate2",
        "com.flyingmeat.acorn8",
        "com.sindresorhus.dato",
        "com.sindresorhus.dato.widgets",
        "com.brave.browser",
        "com.electron.dockerdesktop",
        "io.github.someone.tool",
        "com.openai.chat",
        "org.swift.swiftpm",
        "com.apple.safari",
        "com.google.firebase.messaging",
    },
    names={
        "pastebot",
        "microsoft teams",
        "acorn",
        "dato",
        "brave browser",
        "game center helper",
    },
    app_names={
        "pastebot",
        "microsoft teams",
        "acorn",
        "dato",
        "brave browser",
        "firefox",
    },
    team_ids={"9JTH7AWHE6", "UBF8T346G9"},
    tools={"ngrok", "mix"},
    apple_daemons={"tipsd", "homeenergyd"},
    # Only an app's own ids name a vendor. Firebase is a nested framework.
    apps=[
        own("com.tapbots.pastebot2mac"),
        own("com.openai.chat"),
        own("org.swift.swiftpm"),
        own("com.apple.safari"),
        own("com.electron.dockerdesktop"),
        own("com.microsoft.word", groups=["ubf8t346g9.ms"]),
        own("com.viscosityvpn.viscosity", ["com.sparklabs.viscosity.networkextension"]),
        own("com.wipr.mac", groups=["group.wipr2.rules"]),
    ],
)


def cls(name):
    return scan.classify_name(name, INV)[0]


class ClassifyName(unittest.TestCase):
    def test_exact_bundle_id_is_installed(self):
        self.assertEqual(cls("com.tapbots.Pastebot2Mac"), "installed")

    def test_plist_suffix_is_ignored(self):
        self.assertEqual(cls("com.tapbots.Pastebot2Mac.plist"), "installed")

    def test_extension_of_installed_app_is_installed(self):
        self.assertEqual(cls("com.sindresorhus.Dato.Widgets.Share"), "installed")

    def test_same_vendor_other_app_is_vendor_not_installed(self):
        # Ivory is gone, Pastebot from the same vendor is installed.
        self.assertEqual(cls("com.tapbots.Ivory"), "vendor")
        self.assertEqual(cls("group.com.tapbots.Ivory"), "vendor")

    def test_vendor_of_nested_framework_is_no_vendor(self):
        # Firebase is nested. Chrome is gone.
        self.assertEqual(cls("com.google.Chrome"), "orphan")

    def test_vendor_of_own_extension_is_vendor(self):
        # Viscosity ships its network extension under its old vendor id.
        self.assertEqual(cls("com.sparklabs.ViscosityHelper"), "vendor")

    def test_generic_prefix_is_no_vendor(self):
        # Electron apps default to com.electron.<name>.
        self.assertEqual(cls("com.electron.brain.fm"), "orphan")
        self.assertEqual(cls("io.github.mshibanami.RedirectWeb"), "orphan")

    def test_similar_bundle_id_is_not_installed(self):
        # Teams classic left com.microsoft.teams, Teams 2 is installed.
        self.assertNotEqual(cls("com.microsoft.teams"), "installed")

    def test_older_major_version_is_not_installed(self):
        self.assertNotEqual(cls("com.flyingmeat.Acorn7.QLPreview"), "installed")

    def test_unknown_vendor_is_orphan(self):
        self.assertEqual(cls("com.flexibits.fantastical2.mac"), "orphan")
        self.assertEqual(cls("group.com.jonny.mona.widget-content"), "orphan")

    def test_team_prefix_of_installed_app_is_installed(self):
        self.assertEqual(cls("9JTH7AWHE6.com.tapbots.Pastebot2Mac"), "installed")

    def test_team_prefix_of_installed_team_other_app_is_vendor(self):
        self.assertEqual(cls("9JTH7AWHE6.com.tapbots.Ivory"), "vendor")

    def test_team_prefix_of_installed_team_without_bundle_id_is_vendor(self):
        self.assertEqual(cls("UBF8T346G9.Office"), "vendor")
        self.assertEqual(cls("UBF8T346G9.OfficeWordWidget"), "vendor")

    def test_app_group_of_installed_app_is_installed(self):
        # Office declares UBF8T346G9.ms in its application-groups entitlement.
        self.assertEqual(cls("UBF8T346G9.ms"), "installed")
        self.assertEqual(cls("group.wipr2.rules"), "installed")

    def test_team_prefix_of_unknown_team_is_orphan(self):
        self.assertEqual(cls("85C27NK92C.com.flexibits.fantastical2.mac"), "orphan")
        self.assertEqual(cls("TC3Q7MAJXF.com.adguard.mac"), "orphan")
        self.assertEqual(cls("X5AZV975AG.shared"), "orphan")

    def test_apple_prefixes(self):
        for n in (
            "com.apple.Safari",
            "group.com.apple.notes",
            "243LU875E5.groups.com.apple.podcasts",
            "systemgroup.com.apple.icloud.searchpartyd.sharedsettings.plist",
            "group.is.workflow.shortcuts",
            "org.cups.PrintingPrefs.plist",
        ):
            with self.subTest(n):
                self.assertEqual(cls(n), "apple")

    def test_apple_data_without_prefix(self):
        for n in ("coreMLCache", "GeoServices", "CloudDocs", "CallHistoryDB"):
            with self.subTest(n):
                self.assertEqual(cls(n), "apple")

    def test_developer_caches(self):
        for n in ("ms-playwright", "pip", "virtualenv", "org.webkit.Playwright"):
            with self.subTest(n):
                self.assertEqual(cls(n), "cache")

    def test_plain_name_of_installed_app(self):
        self.assertEqual(cls("Acorn"), "installed")
        self.assertEqual(cls("Microsoft Teams"), "installed")

    def test_plain_name_of_installed_tool(self):
        self.assertEqual(cls("ngrok"), "installed")

    def test_folder_named_after_installed_app_is_vendor(self):
        # Brave keeps its profile in BraveSoftware. Office is installed, Edge is not.
        self.assertEqual(cls("BraveSoftware"), "vendor")
        self.assertEqual(cls("Microsoft Edge Beta"), "vendor")

    def test_folder_named_after_bundle_id_vendor_is_vendor(self):
        # ChatGPT (com.openai.chat) keeps its data in OpenAI.
        self.assertEqual(cls("OpenAI"), "vendor")

    def test_folder_named_after_own_extension_vendor_is_vendor(self):
        self.assertEqual(cls("SparkLabs"), "vendor")

    def test_bundle_id_vendor_must_match_the_whole_name(self):
        self.assertEqual(cls("swift-test"), "unclear")

    def test_generic_and_apple_vendors_name_no_folder(self):
        self.assertEqual(cls("Electron"), "unclear")
        self.assertEqual(cls("Apple"), "unclear")

    def test_vendor_of_nested_framework_names_no_folder(self):
        self.assertEqual(cls("Google"), "unclear")

    def test_apple_daemon_style_names(self):
        for n in ("homeenergyd", "tipsd", "SiriTTSService", "SiriEntityCache"):
            with self.subTest(n):
                self.assertEqual(cls(n), "apple")

    def test_lowercase_name_is_not_apple_by_shape(self):
        self.assertEqual(cls("discord"), "unclear")

    def test_first_word_of_nested_bundle_is_ignored(self):
        self.assertEqual(cls("GameKit"), "unclear")

    def test_unknown_plain_name_is_unclear(self):
        # Could be a removed app or an Apple daemon. A person decides.
        self.assertEqual(cls("SuperDuper!"), "unclear")
        self.assertEqual(cls("Arc"), "unclear")


def write_plist(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(plistlib.dumps(data))


def make_bundle(path, **info):
    write_plist(path / "Contents" / "Info.plist", info)


def no_probes(locations=(), receipts=()):
    """Patch the scanned folders and the macOS probes of scan.py."""
    return mock.patch.multiple(
        scan,
        LOCATIONS=list(locations),
        receipts=lambda: list(receipts),
        size_of=lambda p: 0,
    )


class TempDir(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)


class ClassifyEntry(TempDir):
    def setUp(self):
        super().setUp()
        self.containers = self.root / "Containers"
        self.scripts = self.root / "Application Scripts"
        self.agents = self.root / "LaunchAgents"
        for d in (self.containers, self.scripts, self.agents):
            d.mkdir()

    def entry(self, path):
        return scan.classify_entry(path, INV, self.containers)[0]

    def agent(self, label, program):
        p = self.agents / f"{label}.plist"
        write_plist(p, {"Label": label, "ProgramArguments": [program]})
        return p

    def test_dangling_symlink_is_orphan(self):
        link = self.root / "ClopCLI"
        os.symlink(self.root / "gone", link)
        self.assertEqual(self.entry(link), "orphan")

    def test_symlink_to_existing_target_uses_name(self):
        target = self.root / "real"
        target.mkdir()
        link = self.root / "com.tapbots.Pastebot2Mac"
        os.symlink(target, link)
        self.assertEqual(self.entry(link), "installed")

    def test_uuid_folder_without_container_is_orphan(self):
        d = self.scripts / "009FDE6F-0233-4DE6-A87E-715B4BE3CDF2"
        d.mkdir()
        self.assertEqual(self.entry(d), "orphan")

    def test_uuid_folder_with_container_is_unclear(self):
        name = "10A7E0ED-8F1C-4784-83D5-91B23D426043"
        (self.containers / name).mkdir()
        d = self.scripts / name
        d.mkdir()
        self.assertEqual(self.entry(d), "unclear")

    def test_uuid_folder_elsewhere_is_unclear(self):
        d = self.root / "009FDE6F-0233-4DE6-A87E-715B4BE3CDF2"
        d.mkdir()
        self.assertEqual(self.entry(d), "unclear")

    def test_uuid_container_uses_metadata_identifier(self):
        d = self.containers / "2F954AF3-DAE2-4C67-BB32-1AFC26748530"
        meta = {"MCMMetadataIdentifier": "com.flexibits.fantastical2.mac"}
        write_plist(d / scan.CONTAINER_METADATA, meta)
        self.assertEqual(self.entry(d), "orphan")

    def test_driver_bundle_uses_its_bundle_id(self):
        d = self.root / "ParrotAudioPlugin.driver"
        make_bundle(d, CFBundleIdentifier="com.apple.audio.ParrotAudioPlugin")
        self.assertEqual(self.entry(d), "apple")

    def test_launch_agent_with_missing_program_is_orphan(self):
        p = self.agent("com.example.updater", str(self.root / "gone" / "updater"))
        self.assertEqual(self.entry(p), "orphan")

    def test_launch_agent_of_own_script_is_custom(self):
        script = self.root / "restart.sh"
        script.write_text("#!/bin/sh\n")
        p = self.agent("com.user.restart_exchangesyncd", str(script))
        self.assertEqual(self.entry(p), "custom")

    def test_launch_agent_with_bare_command_on_path_is_custom(self):
        # launchd resolves a bare name through PATH.
        self.assertEqual(self.entry(self.agent("com.me.job", "sh")), "custom")

    def test_launch_agent_with_unknown_bare_command_is_unclear(self):
        p = self.agent("com.me.job", "no-such-command-xyz")
        self.assertEqual(self.entry(p), "unclear")

    def test_launch_daemon_inside_existing_app_is_installed(self):
        binary = self.root / "Foo.app" / "Contents" / "MacOS" / "helper"
        binary.parent.mkdir(parents=True)
        binary.write_text("")
        p = self.agent("com.unknown.foo.helper", str(binary))
        self.assertEqual(self.entry(p), "installed")

    def test_regular_entry_uses_name(self):
        d = self.root / "85C27NK92C.com.flexibits.fantastical2.mac"
        d.mkdir()
        self.assertEqual(self.entry(d), "orphan")


class BundleInfos(TempDir):
    def test_reads_bundles_inside_frameworks(self):
        # Sparkle keeps its XPC services inside the framework.
        bundle = self.root / "Foo.app"
        xpc = bundle / "Contents/Frameworks/Sparkle.framework/XPCServices/D.xpc"
        make_bundle(bundle, CFBundleIdentifier="com.foo")
        make_bundle(xpc, CFBundleIdentifier="org.sparkle-project.Downloader")
        ids = {i["CFBundleIdentifier"] for _, i in scan.bundle_infos(bundle)}
        self.assertIn("org.sparkle-project.Downloader", ids)


class DescribeApp(TempDir):
    def test_names_come_from_the_app_not_nested_bundles(self):
        bundle = self.root / "Microsoft Teams.app"
        make_bundle(bundle, CFBundleIdentifier="com.microsoft.teams2")
        make_bundle(
            bundle / "Contents/PlugIns/K.appex",
            CFBundleIdentifier="x.k",
            CFBundleName="Knowledge",
        )
        desc = scan.describe_app(bundle)
        self.assertEqual(desc["names"], {"microsoft teams"})
        self.assertEqual(desc["id"], "com.microsoft.teams2")
        self.assertEqual(desc["ids"], {"com.microsoft.teams2", "x.k"})
        self.assertEqual(desc["nested_names"], {"knowledge"})

    def test_own_ids_skip_frameworks_and_resource_bundles(self):
        bundle = self.root / "Viscosity.app"
        make_bundle(bundle, CFBundleIdentifier="com.viscosityvpn.Viscosity")
        sysext = "Contents/Library/SystemExtensions/N.systemextension"
        make_bundle(bundle / sysext, CFBundleIdentifier="com.sparklabs.N")
        fw = bundle / "Contents/Frameworks/Sparkle.framework"
        fw_info = fw / "Versions/B/Resources/Info.plist"
        write_plist(fw_info, {"CFBundleIdentifier": "org.s"})
        make_bundle(fw / "XPCServices/D.xpc", CFBundleIdentifier="org.s.D")
        res = bundle / "Contents/Resources/Pkg_Pkg.bundle"
        make_bundle(res, CFBundleIdentifier="pkg.pkg.resources")
        desc = scan.describe_app(bundle)
        own_ids = {"com.viscosityvpn.viscosity", "com.sparklabs.n"}
        self.assertEqual(desc["own_ids"], own_ids)

    def test_team_and_app_groups_come_from_one_codesign_call(self):
        bundle = self.root / "Microsoft Word.app"
        make_bundle(bundle, CFBundleIdentifier="com.microsoft.word")
        groups = ["UBF8T346G9.Office", "UBF8T346G9.ms"]
        ent = {"com.apple.security.application-groups": groups}
        signed = subprocess.CompletedProcess(
            [], 0, plistlib.dumps(ent).decode(), "TeamIdentifier=UBF8T346G9\n"
        )
        with mock.patch.object(scan, "proc", return_value=signed) as codesign:
            desc = scan.describe_app(bundle)
        codesign.assert_called_once()
        self.assertEqual(desc["team"], "UBF8T346G9")
        self.assertEqual(desc["groups"], {"ubf8t346g9.office", "ubf8t346g9.ms"})

    def test_unsigned_app_has_no_team_and_no_groups(self):
        bundle = self.root / "Plain.app"
        make_bundle(bundle, CFBundleIdentifier="com.plain")
        unsigned = subprocess.CompletedProcess([], 1, "", "code object is not signed")
        with mock.patch.object(scan, "proc", return_value=unsigned):
            desc = scan.describe_app(bundle)
        self.assertEqual((desc["team"], desc["groups"]), ("", set()))

    def test_team_survives_a_codesign_without_xml(self):
        # An older codesign that rejects --xml still has to yield the Team ID.
        bundle = self.root / "Old.app"
        make_bundle(bundle, CFBundleIdentifier="com.old")
        refused = subprocess.CompletedProcess([], 1, "", "unrecognized option `--xml'")
        signed = subprocess.CompletedProcess([], 0, "", "TeamIdentifier=UBF8T346G9\n")
        with mock.patch.object(scan, "proc", side_effect=[refused, signed]):
            desc = scan.describe_app(bundle)
        self.assertEqual((desc["team"], desc["groups"]), ("UBF8T346G9", set()))


class ScanApp(TempDir):
    FIREFOXES = scan.Inventory(
        apps=[
            app_entry("/Applications/Firefox.app", "org.mozilla.firefox"),
            app_entry("/Users/x/Library/Application Support/pwa/Firefox.app", "pwa.rt"),
        ]
    )

    def scan_app(self, query):
        with no_probes():
            return scan.scan_app(self.FIREFOXES, query)

    def test_ambiguous_name_lists_candidates(self):
        result = self.scan_app("Firefox")
        self.assertIn("error", result)
        self.assertEqual(len(result["candidates"]), 2)

    def test_path_selects_one_app(self):
        result = self.scan_app("/Applications/Firefox.app")
        self.assertEqual(result["apps"], ["/Applications/Firefox.app"])

    def test_bundle_id_selects_one_app(self):
        result = self.scan_app("org.mozilla.firefox")
        self.assertEqual(result["apps"], ["/Applications/Firefox.app"])

    def scan_entries(self, inv, query, *names):
        loc = self.root / "Library"
        for n in names:
            (loc / n).mkdir(parents=True)
        with no_probes(locations=[loc]):
            result = scan.scan_app(inv, query)
        return [Path(e["path"]).name for e in result["entries"]]

    def test_vendor_folder_of_two_installed_apps_is_not_listed(self):
        # Thunderbird still uses Mozilla when Firefox goes.
        inv = scan.Inventory(
            apps=[
                app_entry("/Applications/Firefox.app", "org.mozilla.firefox"),
                app_entry("/Applications/Thunderbird.app", "org.mozilla.thunderbird"),
            ]
        )
        self.assertEqual(self.scan_entries(inv, "Firefox", "Mozilla"), ["Firefox.app"])

    def test_app_group_shared_with_other_app_is_not_listed(self):
        group = "group.com.vendor.app"
        inv = scan.Inventory(
            apps=[
                app_entry("/Applications/A.app", "com.vendor.app", groups=[group]),
                app_entry("/Applications/B.app", "com.vendor.appb", groups=[group]),
            ]
        )
        self.assertEqual(self.scan_entries(inv, "A", group), ["A.app"])

    def test_vendor_of_nested_framework_is_not_listed(self):
        inv = scan.Inventory(
            apps=[app_entry("/A/Foo.app", "com.foo.app", libs=["com.google.fb"])]
        )
        self.assertEqual(self.scan_entries(inv, "Foo", "Google"), ["Foo.app"])

    def test_library_id_of_the_app_is_no_exact_match(self):
        # Sparkle belongs to every app that embeds it.
        lib = "org.sparkle-project.sparkle"
        inv = scan.Inventory(apps=[app_entry("/A/Foo.app", "com.foo", libs=[lib])])
        loc = self.root / "Library"
        (loc / "org.sparkle-project.Sparkle").mkdir(parents=True)
        with no_probes(locations=[loc], receipts=[lib + ".pkg"]):
            result = scan.scan_app(inv, "Foo")
        self.assertEqual([e["match"] for e in result["entries"]], ["exact"])
        self.assertEqual(result["receipts"], [])

    def test_library_vendor_of_other_app_does_not_hide_vendor_folder(self):
        # Folder Preview embeds org.mozilla.universalchardet.
        inv = scan.Inventory(
            apps=[
                app_entry("/Applications/Firefox.app", "org.mozilla.firefox"),
                app_entry("/Applications/FP.app", "ltd.fp", libs=["org.mozilla.u"]),
            ]
        )
        found = self.scan_entries(inv, "Firefox", "Mozilla")
        self.assertEqual(found, ["Firefox.app", "Mozilla"])

    def test_app_inside_a_scanned_folder_is_listed_once(self):
        loc = self.root / "Application Support"
        bundle = loc / "Firefox.app"
        bundle.mkdir(parents=True)
        inv = scan.Inventory(apps=[app_entry(str(bundle), "pwa.rt")])
        with no_probes(locations=[loc]):
            result = scan.scan_app(inv, str(bundle))
        self.assertEqual([e["path"] for e in result["entries"]], [str(bundle)])


class IsRunning(unittest.TestCase):
    def test_regex_characters_in_path_do_not_count_as_running(self):
        self.assertFalse(scan.is_running("/nonexistent/C++ Tool.app"))

    def test_parentheses_in_path_are_matched_literally(self):
        bundle = "/tmp/Teams (work or school).app"
        cmd = ["sh", "-c", "sleep 30; :", bundle + "/Contents/MacOS/Teams"]
        child = subprocess.Popen(cmd)
        self.addCleanup(child.wait)
        self.addCleanup(child.kill)
        self.assertTrue(scan.is_running(bundle))


class ScanOrphans(TempDir):
    def test_only_orphan_receipts_are_reported(self):
        pkgs = ["com.microsoft.package.Word", "com.teamviewer.helper"]
        with no_probes(receipts=pkgs):
            result = scan.scan_orphans(INV, show_all=False)
        self.assertEqual(
            result["receipts"], [{"id": "com.teamviewer.helper", "class": "orphan"}]
        )

    def test_unreadable_entry_is_reported_not_fatal(self):
        # /Library/Caches holds entries that lstat() refuses.
        loc = self.root / "Caches"
        (loc / "com.flexibits.fantastical2.mac").mkdir(parents=True)
        loc.chmod(0o600)
        self.addCleanup(loc.chmod, 0o700)
        with no_probes(locations=[loc]):
            result = scan.scan_orphans(INV, show_all=False)
        self.assertEqual(result["entries"], [])
        self.assertEqual(
            result["unreadable"], [str(loc / "com.flexibits.fantastical2.mac")]
        )


class AppMatches(unittest.TestCase):
    BRAVE_IDS = frozenset({"com.brave.browser", "com.brave.browser.helper"})
    BRAVE_NAMES = frozenset({"brave browser"})

    def match(
        self, name, ids=BRAVE_IDS, names=BRAVE_NAMES, taken=frozenset(), label="brave"
    ):
        return scan.app_matches(Path("/x") / name, set(ids), set(names), taken, label)

    def test_bundle_id_forms_are_exact(self):
        for n in (
            "com.brave.Browser.plist",
            "com.brave.Browser.savedState",
            "com.brave.Browser.origin",
            "ABCDE12345.com.brave.Browser",
            "group.com.brave.Browser",
        ):
            with self.subTest(n):
                self.assertEqual(self.match(n), "exact")

    def test_vendor_folder_is_name_match(self):
        self.assertEqual(self.match("BraveSoftware"), "name")
        self.assertEqual(self.match("Brave Browser"), "name")

    def test_other_app_is_no_match(self):
        self.assertEqual(self.match("com.google.Chrome"), "")
        self.assertEqual(self.match("Firefox"), "")

    def test_apple_entry_never_matches(self):
        for n in ("com.apple.siriknowledged", "Knowledge"):
            with self.subTest(n):
                self.assertEqual(self.match(n, {"com.foo"}, {"knowledge"}), "")

    def test_bundle_id_vendor_folder_is_name_match(self):
        m = self.match("Mozilla", {"org.mozilla.firefox"}, {"firefox"}, label="mozilla")
        self.assertEqual(m, "name")
        m = self.match("Flexibits", {"com.flexibits.x"}, {"x"}, label="flexibits")
        self.assertEqual(m, "name")

    def test_bundle_id_vendor_shared_with_other_app_is_no_match(self):
        m = self.match(
            "Mozilla", {"org.mozilla.firefox"}, {"firefox"}, {"mozilla"}, "mozilla"
        )
        self.assertEqual(m, "")

    def test_first_word_shared_with_other_app_is_no_match(self):
        m = self.match(
            "Microsoft Word",
            {"com.microsoft.teams2"},
            {"microsoft teams"},
            {"microsoft"},
        )
        self.assertEqual(m, "")

    def test_short_first_word_is_no_match(self):
        self.assertEqual(self.match("zoomer", {"us.zoom.xos"}, {"zo"}), "")


class Main(unittest.TestCase):
    def test_root_is_refused_before_scanning(self):
        # As root, Path.home() is /var/root and the scan would look clean.
        with mock.patch.object(scan.sys, "argv", ["scan.py", "orphans"]), \
                mock.patch.object(scan.sys, "platform", "darwin"), \
                mock.patch.object(scan.os, "geteuid", return_value=0), \
                mock.patch.object(scan, "collect_inventory") as collect, \
                mock.patch("sys.stderr"):
            with self.assertRaises(SystemExit):
                scan.main()
        collect.assert_not_called()


if __name__ == "__main__":
    unittest.main()
