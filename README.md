# The Parasites QuickStack

Portable QuickStack mod for the Windows version of **The Parasites**.

Prepared for:

- The Parasites `TP_Alpha_v_0.1.5.0.0`
- Windows
- UE4SS included

No compatibility is promised for other game versions.

## What It Does

QuickStack adds one in-game hotkey:

```text
Ctrl+F9
```

Open a storage container, then press `Ctrl+F9`. The mod moves matching inventory
stacks from your character inventory into the opened container if that container
already contains the same item type.

Example:

- Your inventory contains `Branch` and `Soda`.
- The opened container already contains `Branch`.
- Press `Ctrl+F9`.
- `Branch` stacks move into the container.
- `Soda` stays in your inventory.

The mod is designed to skip equipped weapons, tools, weapon attachments,
dedicated equipment slots, and items that do not match the opened container.

## Installation

1. Close The Parasites.
2. Back up your saves.
3. Download and extract the latest release ZIP.
4. Run `Install_QuickStack.cmd`.
5. Start the game.
6. Open a container.
7. Press `Ctrl+F9`.

Manual installation:

1. Open `COPY_TO_GAME_WIN64`.
2. Copy everything inside it into your game `Win64` folder:

```text
...\TheParasites\Binaries\Win64
```

The game `Win64` folder is the folder that contains:

```text
TheParasites-Win64-Shipping.exe
```

For a custom path, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install_QuickStack.ps1 -GameWin64 "<your game Win64 folder>"
```

## Uninstallation

Run:

```text
Uninstall_QuickStack.cmd
```

If you manually merged this mod into an existing UE4SS setup, uninstall it
manually instead:

- Remove `ue4ss\Mods\TheParasitesQuickStack`.
- Remove or disable `TheParasitesQuickStack : 1` in `ue4ss\Mods\mods.txt`.

## Existing UE4SS Installations

This package is a complete portable UE4SS setup. Installing it can replace an
existing UE4SS setup, including `mods.txt` and `UE4SS-settings.ini`.

The installer backs up existing `dwmapi.dll` and `ue4ss` files before
replacement. The backup path is written to `last_backup.txt`.

If you already use UE4SS and want to keep other mods, do a manual merge:

- Copy only `ue4ss\Mods\TheParasitesQuickStack` into your existing UE4SS `Mods`
  folder.
- Make sure the UE4SS `Keybinds` mod is installed and enabled.
- Add or keep this line in your own `ue4ss\Mods\mods.txt`:

```text
TheParasitesQuickStack : 1
```

## Log File

After the mod has loaded, it writes a small log next to the installed mod:

```text
...\ue4ss\Mods\TheParasitesQuickStack\QuickStack.log
```

## Terms

The source code is available in this repository for inspection, personal
non-commercial use, and personal non-commercial modification.

Because commercial use and hosting on other websites are prohibited, this is a
custom restricted source-available license, not an OSI-approved open-source
license.

Personal, non-commercial use only. Reuploading, mirroring, reposting,
redistribution, repackaging, publishing modified versions, hosting this mod or
its source code on other websites, paid distribution, and all commercial use are
prohibited without explicit written permission from the copyright holder.

This mod is provided as-is, with no warranty, no support obligation, and no
guarantee of compatibility with future game updates. Use at your own risk.

Read [LICENSE.md](LICENSE.md), [COPYRIGHT_AND_TERMS.txt](COPYRIGHT_AND_TERMS.txt),
and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) before using or sharing
this package.

## Third-Party Components

This package includes UE4SS / RE-UE4SS components under the MIT License. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[licenses/UE4SS-MIT-LICENSE.txt](licenses/UE4SS-MIT-LICENSE.txt).

The Parasites and Unreal Engine belong to their respective owners. This mod is
unofficial and is not affiliated with, endorsed by, sponsored by, or approved by
the developer, publisher, or rightsholder of The Parasites.
