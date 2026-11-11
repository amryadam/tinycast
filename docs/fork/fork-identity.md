# Feature: fork-identity

The fork builds as its own app, with its own bundle id, link scheme, name and signing identity.
This keeps it side by side with the installed Tinycast, stops upstream releases from replacing it, and lets macOS remember its permissions across rebuilds.
It changes no upstream file.

## Contents

- [Design](#design)
- [Files](#files)
- [Using it](#using-it)
- [What changes for you](#what-changes-for-you)
- [Not done](#not-done)
- [Removing it](#removing-it)

## Design

| Setting | Value | Why |
|---|---|---|
| Bundle id | `com.amryadam.tinycast` | Your own reverse-DNS name. Upstream's `ReleaseChannel` treats any id it does not know as a development build that never updates itself. |
| Link scheme | `tinycast-amryadam` | So a link never lands in whichever Tinycast macOS picks. |
| App name | `Tinycast Amr` | Installs beside `Tinycast.app` without replacing it. |
| Signing identity | `Tinycast Self-Signed` | The name `project.yml` and `docs/signing.md` already expect, so Xcode builds work too. |

The overrides are passed on the `xcodebuild` command line, the way upstream's release workflow does it for its Beta app.
Settings, clipboard history, snippets and the config folder are keyed by bundle id, so the fork has its own and never touches the installed app's.

## Files

| File | Change | Purpose | Conflict risk |
|---|---|---|---|
| `Scripts/fork-signing-identity.sh` | New | Creates the `Tinycast Self-Signed` identity in the login keychain, once. The user runs it. | None |
| `Scripts/fork-build.sh` | New | Builds the fork with the overrides above and checks the result. | None |
| `docs/fork/fork-identity.md` | New | This file. | None |

## Using it

```shell
./Scripts/fork-signing-identity.sh   # once; read it first, it imports a private key
./Scripts/fork-build.sh              # Release, about ten minutes the first time
./Scripts/fork-build.sh Debug        # a Debug build instead
```

Overrides: `FORK_BUNDLE_ID`, `FORK_URL_SCHEME`, `FORK_APP_NAME`, `FORK_BUILD_DIR`.
The app lands in `~/Library/Caches/tinycast-fork/DerivedData/Build/Products/Release/Tinycast Amr.app`.

## What changes for you

- The fork starts with empty settings, clipboard history, snippets and quicklinks, because they are stored per bundle id. The Backup feature can import settings from the installed app.
- Accessibility, Full Disk Access and the other permissions must be granted to `Tinycast Amr` once. The stable identity keeps them across rebuilds.
- Two Tinycast copies share the machine's global hotkeys, so quit the installed one or give the fork different shortcuts.
- Raycast-extension deep links accept only upstream's schemes, so a link that uses `tinycast-amryadam` is untested.

## Not done

| Item | Note |
|---|---|
| Running the signing script | It changes the user's keychain, so the user runs it. |
| A signed Release build | Not run, because it needs the identity. An unsigned Debug build with the same overrides produced bundle id `com.amryadam.tinycast`, name `Tinycast Amr`, scheme `tinycast-amryadam` and dictation helper id `com.amryadam.tinycast.dictation`. |
| Installing into `/Applications` | The script prints the path and stops, so nothing is copied for you. |

## Removing it

1. Delete the two scripts and this file.
2. Delete `Tinycast Self-Signed` in Keychain Access, under My Certificates, if nothing else uses it.
3. Delete `~/Library/Caches/tinycast-fork`.
