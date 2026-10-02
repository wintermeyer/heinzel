# Locations

`scan.py` lists the top level of each folder below.

## Per user (`~/Library`)

| Folder                    | Holds                                     |
|---------------------------|-------------------------------------------|
| `Application Support`     | App data, often in a folder named after   |
|                           | the app or vendor                         |
| `Application Scripts`     | Script folders of sandboxed apps and      |
|                           | extensions, mostly empty                  |
| `Caches`                  | Caches                                    |
| `Containers`              | Sandbox data per bundle id                |
| `Group Containers`        | Data shared between an app and its        |
|                           | extensions, often with Team ID prefix     |
| `Preferences`             | `<bundle id>.plist`                       |
| `Saved Application State` | Window state                              |
| `HTTPStorages`, `WebKit`, | Web data of apps with embedded browsers   |
| `Cookies`                 |                                           |
| `LaunchAgents`            | launchd jobs of the user                  |
| `Logs`                    | Logs                                      |
| `Internet Plug-Ins`,      | Plug-ins, usually empty today             |
| `PreferencePanes`,        |                                           |
| `QuickLook`,              |                                           |
| `Screen Savers`           |                                           |

## System (`/Library`)

| Folder                  | Holds                                       |
|-------------------------|---------------------------------------------|
| `LaunchDaemons`         | launchd jobs that run as root               |
| `LaunchAgents`          | launchd jobs for every user                 |
| `PrivilegedHelperTools` | Root helpers of apps, started by a          |
|                         | LaunchDaemon                                |
| `Application Support`   | Shared data and updaters                    |
| `Audio/Plug-Ins/HAL`    | Audio drivers                               |
| `Extensions`            | Kernel extensions                           |
| `Preferences`, `Caches`,| Same as per user                            |
| `Logs`                  |                                             |

Two kinds keep running after their app is gone: launchd jobs
with helpers, and drivers or extensions. Look at them first.

Not a folder, but also a leftover: installer receipts.
`pkgutil --pkgs` lists them. They take no space.

System extensions live in a database, not in `/Library`:

    systemextensionsctl list

## Manual probes without the Command Line Tools

When `/usr/bin/python3` is not usable, run these read-only probes
and classify by hand with `classification.md`.

Installed bundle ids:

    mdfind "kMDItemContentType == 'com.apple.application-bundle'" \
      | while IFS= read -r app; do
          defaults read "$app/Contents/Info" CFBundleIdentifier
        done 2>/dev/null | sort -u

Team IDs of installed apps:

    for app in /Applications/*.app; do
      codesign -dv "$app" 2>&1 | grep TeamIdentifier
    done | sort -u

Entries per folder, largest first:

    du -sh ~/Library/"Application Support"/* | sort -h | tail -30

launchd jobs whose program is missing. launchd prefers `Program`
over `ProgramArguments`. A bare command name goes through `PATH`:

    for p in ~/Library/LaunchAgents/*.plist \
             /Library/LaunchAgents/*.plist \
             /Library/LaunchDaemons/*.plist; do
      prog=$(plutil -extract Program raw "$p" 2>/dev/null \
        || plutil -extract ProgramArguments.0 raw "$p" 2>/dev/null)
      case "$prog" in
        /*) [ -e "$prog" ] || echo "$p: $prog" ;;
        ?*) command -v "$prog" > /dev/null || echo "$p: $prog" ;;
      esac
    done
