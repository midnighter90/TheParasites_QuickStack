# Development Log - The Parasites QuickStack

Date: 2026-05-25

This document records the relevant work used to develop, test, package, and
prepare QuickStack for publication. It intentionally avoids private names,
private paths, account identifiers, and machine-specific locations.

## Starting Point

QuickStack was created as a UE4SS/Lua mod for The Parasites
`TP_Alpha_v_0.1.5.0.0`. The goal was a hotkey that moves inventory stacks into
an open container when that container already contains the same item type.

Expected user flow:

1. Open a container.
2. Press `Ctrl+F9`.
3. Only matching stacks move into the container.
4. Non-matching items, equipment, weapons, and dedicated slots remain untouched.

## Research

1. UE4SS was selected as the technical base.
   - A Lua mod was used instead of a save editor because the feature needs to
     operate while the UI and inventory are active.
   - The UE4SS runtime was included in the release package.

2. UI and container classes were investigated.
   - Relevant widget/container class:
     - `JSIContainer_C`
   - Relevant multiplayer/inventory component:
     - `BP_JigMultiplayer_C`
   - The goal was to distinguish open storage containers from the player
     inventory and internal helper containers.

3. Container metadata was investigated.
   - Container ID.
   - Parent ID.
   - Grid size.
   - Related multiplayer component.
   - Slot and equipment containers.

4. UE4SS property access was extended.
   - Custom properties were registered for primitive container values.
   - Fallbacks were added for alternate property names.
   - Robust helper functions were added for:
     - `GetPropertyValue`.
     - direct indexing.
     - `TArray` access.
     - null-object detection.
     - address and object comparison.

## Trial And Error

QuickStack required several test phases because inventory and UI objects are
hard to identify directly while the game is running.

1. Raw container probing.
   - `FindAllOf("JSIContainer_C")` was used.
   - Container candidates were logged.
   - The goal was to separate visible storage containers from the player
     inventory and invisible helper containers.

2. Dry-run and candidate scans.
   - Search passes without item movement were added.
   - These scans printed container groups, slots, and possible matching items.
   - Risky struct reads were disabled after a crash path was identified.

3. Empty-slot and slot probes.
   - Tests checked which slots actually held item data.
   - Empty and unusable slots were filtered out.

4. Single-move tests.
   - Early tests allowed only one stack to move.
   - This made it possible to find the correct server/client sequence without
     moving many items during failed attempts.

5. Working move sequence.
   - The stable sequence was:

```text
SERVER_RequestMoveItemToAnotherComp
RemoveInventoryItemByRef
CLIENT_ItemRemoved
```

   - The server request alone was not enough.
   - Local source-inventory cleanup was needed so the UI and client state stayed
     consistent.

6. Multi-item movement with delay.
   - Moving many items in a tight loop was discarded.
   - The final full QuickStack run moves one item at a time.
   - A delay between moves gives the game and UI time to update.

7. Target-container anchor.
   - The target container is captured when a QuickStack run starts.
   - Follow-up moves re-find the same container by address, container ID, and
     multiplayer component.
   - This reduces the risk of a run switching to the wrong container while it is
     still in progress.

8. Public debug hotkeys disabled.
   - Probe and debug functions remain in the code for maintenance.
   - The public runtime exposes only `Ctrl+F9`.
   - `QUICKSTACK_DEBUG_MODE = false`.

## Final Code

The final mod code is located at:

```text
COPY_TO_GAME_WIN64/ue4ss/Mods/TheParasitesQuickStack/scripts/main.lua
```

Important pieces:

- `Ctrl+F9` hotkey.
- Container and inventory detection.
- Visible-container grouping.
- Matching by item types that already exist in the target container.
- Skip logic for:
  - equipped weapons.
  - tools.
  - weapon attachments.
  - equipment and dedicated slots.
  - non-matching item types.
- Server-first move sequence.
- Step-by-step full QuickStack with delay.
- Target-container anchor.
- Cooldown against repeated triggers.
- Move limit for safety.
- Log file next to the installed mod:

```text
ue4ss/Mods/TheParasitesQuickStack/QuickStack.log
```

## Installer And Package

QuickStack was built as a complete portable UE4SS package.

Release structure:

```text
COPY_TO_GAME_WIN64/
Install_QuickStack.cmd
Uninstall_QuickStack.cmd
scripts/Install_QuickStack.ps1
scripts/Uninstall_QuickStack.ps1
```

Installer behavior:

- asks for the The Parasites `Win64` folder.
- accepts `-GameWin64 "<path>"` as an alternative.
- verifies that `TheParasites-Win64-Shipping.exe` is present.
- blocks installation while The Parasites is running.
- backs up existing `dwmapi.dll` and `ue4ss` installations.
- writes `last_backup.txt`.
- copies the UE4SS payload.
- writes a marker so its own installation can be recognized later.

Uninstaller behavior:

- removes the installed QuickStack files.
- uses the marker to avoid blindly removing unrelated installations.
- documents the manual process for existing UE4SS setups.

## Documentation And Repository Layout

The public repository was prepared from a cleaned release-staging copy. Private
development-only notes, private machine paths, and account-specific references
are not part of the published package.

Public files:

- `README.md`
- `README_INSTALLATION.txt`
- `CHANGELOG.md`
- `CHANGELOG.txt`
- `RELEASE_NOTES_v1.0.0.md`
- `VERSION.txt`
- `PUBLISHING.md`
- `LICENSE.md`
- `COPYRIGHT_AND_TERMS.txt`
- `THIRD_PARTY_NOTICES.md`
- `THIRD_PARTY_NOTICES.txt`
- `MANIFEST_SHA256.txt`
- `.gitattributes`
- `.gitignore`

After the initial upload, the package was cleaned for public release:

- no private Windows paths in public text files.
- no local package or source path in the installer marker.
- the installer asks for the game `Win64` folder or accepts `-GameWin64`.
- debug and probe hotkeys are not part of the public user flow.

## License And Copyright Work

The terms were intentionally kept restrictive:

- personal, non-commercial use.
- no reuploading.
- no mirroring.
- no reposting.
- no repackaging.
- no paid distribution.
- no commercial use.
- no warranty.
- no support promise.
- no future compatibility guarantee.

UE4SS/RE-UE4SS remains under the MIT License and is listed in the third-party
notices with its license file.

## GitHub And Release Work

Completed steps:

1. Built the development workspace.
2. Assembled the UE4SS payload.
3. Created the Lua mod in `TheParasitesQuickStack`.
4. Ran the debug and probe phase.
5. Stabilized the final `Ctrl+F9` workflow.
6. Built the installer and uninstaller.
7. Created a cleaned public release copy.
8. Removed private paths and development-only notes from the public package.
9. Generated the manifest.
10. Built the release ZIP.
11. Extracted the ZIP and verified it against the manifest.
12. Published `main`, `v1.0.0`, and the release asset.

## Verification

Verification included:

- PowerShell syntax checks for installer and uninstaller.
- manual in-game QuickStack tests with an open container.
- single-move tests.
- full QuickStack tests with delay.
- log-output checks.
- public-package scans for private paths and account-specific references.
- manifest-hash generation and validation against the extracted ZIP.
- repository branch, tag, and release ZIP checks.

## Result

QuickStack is a portable UE4SS mod for The Parasites. The final user flow is:

1. Close The Parasites.
2. Extract the release ZIP.
3. Run `Install_QuickStack.cmd`.
4. Start the game.
5. Open a container.
6. Press `Ctrl+F9`.

The final feature moves only matching stacks, uses a tested server/client move
sequence, and tries to avoid touching equipment and non-matching items.
