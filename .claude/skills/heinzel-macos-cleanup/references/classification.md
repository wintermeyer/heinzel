# Classification

`scan.py` compares every entry in the scanned locations with the
installed apps. It collects the bundle ids of each app and of all
nested bundles (helpers, extensions, XPC services in frameworks),
the Team ID and the app groups from `codesign`, Homebrew packages
and the commands on `PATH`.

## Classes

- `apple`: Apple prefix, known Apple data, or the name of an
  Apple launchd job. Never touch.
- `installed`: belongs to an installed app, command or Homebrew
  package. Never touch.
- `orphan`: no installed app with this bundle id, Team ID or
  program. Verify, then propose.
- `vendor`: same vendor or Team ID as an installed app, but not
  its bundle id. Verify the owner first.
- `cache`: cache of a developer tool. Offer separately.
- `custom`: launchd job that runs the user's own program. Only on
  explicit request.
- `unclear`: plain name that matches nothing. Research one by
  one.

`orphans` hides `apple` and `installed`. Pass `--all` to see them.

In the uninstall mode each entry carries `match`: `exact` for the
app's bundle ids and app groups, `name` for folders named after
the app or its vendor. Propose `exact` entries as a group. List
`name` entries separately and confirm each.

## Verify before proposing

For an `orphan` or `vendor` entry, all of these must come back
empty for the bundle id or label:

    mdfind "kMDItemCFBundleIdentifier == '<bundle id>'"
    pluginkit -mA | grep -i '<bundle id>'
    launchctl list | grep -i '<label>'
    systemextensionsctl list | grep -i '<bundle id>'
    pgrep -fl '<app or helper name>'

A `vendor` entry needs one more answer: which installed app uses
it? Check in this order:

1. A launchd plist whose `Program` or `ProgramArguments` points
   at the entry. `plutil -p <plist>` shows it.
2. The Team ID of a helper against the installed apps:
   `codesign -dv <path> 2>&1 | grep TeamIdentifier`.
3. The vendor's documentation for the app that ships the helper.

If an installed app uses the entry, it stays.

## Traps behind the rules

Each trap came up on a real machine.

- **Group containers carry a Team ID prefix.**
  `85C27NK92C.com.flexibits.fantastical2.mac` belongs to
  `com.flexibits.fantastical2.mac`. Some put `group.` first:
  `group.245B4P8J7P.com.staysorted.Sorted.3`.
- **Group containers are named after app groups.** Office uses
  `UBF8T346G9.Office` and `UBF8T346G9.ms`, Wipr uses
  `group.wipr2.rules`. None of them is a bundle id. The scanner
  reads `com.apple.security.application-groups` from the
  entitlements of each app. A listed group is `installed`. Only
  the app itself is read, not its nested bundles. The uninstall
  mode skips a group another installed app declares. A group is
  `exact` when no other installed app has the same Team ID. An
  app without a Team ID shares its team with no other app. Only
  apps of one team can share a group prefixed with that Team ID.
  Nested helpers may declare such a group unread. Wipr's groups
  are `exact`. Word's groups are not while Excel or AutoUpdate
  is installed.
- **The same vendor is not the same app.** Pastebot 3
  (`com.tapbots.Pastebot3Mac`) is installed. The containers of
  Ivory and of Pastebot 2 are still leftovers. The scanner
  reports them as `vendor`, not `installed`.
- **Libraries do not name a vendor.** Ids inside a `.framework`
  or `.bundle` do not count. All other nested ids do. A library
  id counts when it shares the two-part prefix of the app's main
  id, unless that prefix is generic like `com.electron`.
  GoogleUpdater ships `com.google.Keystone` in a `.bundle`, so
  Keystone counts as its own. Firebase brings `com.google.*` ids
  to other apps, but `com.google.Chrome` stays an `orphan`.
  Viscosity ships a `com.sparklabs.*` system extension, so
  `com.sparklabs.ViscosityHelper` is `vendor`. The uninstall mode
  ignores other library ids as well: a Sparkle id is no `exact`
  match for one app.
- **A similar bundle id is not the same app.** Teams classic
  left `com.microsoft.teams`. The installed Teams is
  `com.microsoft.teams2`.
- **An older major version is a leftover.** Acorn 8 is
  installed, `com.flyingmeat.Acorn7.*` is not.
- **Helpers of installed apps have their own ids.** Office uses
  `com.microsoft.autoupdate.helper` and
  `com.microsoft.office.licensingV2.helper`. Viscosity uses
  `com.sparklabs.ViscosityHelper`. TimeMachineEditor uses
  `com.tclementdev.timemachineeditor.scheduler`. All show up as
  `vendor`. All must stay.
- **Vendor folders use the company name.** Firefox keeps data in
  `Mozilla` and `Firefox`. Brave keeps its profiles in
  `BraveSoftware`. ChatGPT uses `OpenAI`. These hold profiles
  with passwords and bookmarks. A folder named like the second
  label of an app's own bundle id is `vendor`: `Mozilla` matches
  `org.mozilla.firefox`. The whole name must match. Nested
  frameworks do not count: Firebase brings `com.google.*` ids,
  but `Google` holds Chrome's profiles.
- **A vendor folder can serve several apps.** The firefoxpwa
  runtime nests `org.mozilla.*` helpers. The uninstall mode skips
  a vendor folder that any id of another installed app names.
- **Apple data often has no Apple prefix.** `coreMLCache` can
  hold several GB. `GeoServices`, `CloudDocs` and `CallHistoryDB`
  are Apple data too. So are daemon folders like `tipsd`, and
  Shortcuts (`group.is.workflow.*`) and CUPS (`org.cups.*`).
  `ParrotAudioPlugin.driver` is Apple's; the scanner reads the
  bundle id of driver and plug-in bundles for this reason.
- **Developer caches belong to tools.** `ms-playwright`, `pip`,
  `mix` and `puccinialin` can hold GB. Deleting them is safe.
  Tools download them again on the next run.
- **Own launchd jobs look like leftovers.**
  `com.user.restart_exchangesyncd.plist` ran a script in
  `~/.local/bin`. The scanner marks jobs with a program outside
  an app bundle as `custom`.
- **UUID folders in Application Scripts.** Empty folders named
  by UUID without a matching container are leftovers of removed
  extensions. Elsewhere, a UUID name says nothing.
- **Dead symlinks.** Clop linked `ClopCLI` to a folder that was
  already gone. `removal.md` covers how to remove and check them.
- **Several apps can share a name.** PWAsForFirefox keeps a
  second `Firefox.app` in `~/Library/Application Support`. The
  uninstall mode stops and lists both paths.
