The Parasites QuickStack v1.0.0
Portable installation and usage

What this mod does
------------------
QuickStack adds one in-game hotkey:

  Ctrl+F9

Open a storage container, then press Ctrl+F9. The mod moves matching inventory
stacks from your character inventory into the opened container if that container
already contains the same item type.

Example:

  - Your inventory contains Branch and Soda.
  - The opened container already contains Branch.
  - Press Ctrl+F9.
  - Branch stacks are moved into the container.
  - Soda stays in your inventory.

The mod is designed to skip equipped weapons, tools, weapon attachments,
dedicated equipment slots, and items that do not match the opened container.

Important warning
-----------------
Use this mod at your own risk. Back up your saves before using any mod.

This package is provided as-is. There is no warranty, no support obligation, no
liability, and no guarantee that this mod will keep working with future versions
of The Parasites.

Read COPYRIGHT_AND_TERMS.txt before publishing, mirroring, sharing, modifying,
hosting, or using this package.

Tested target
-------------
This release was prepared for the Windows version of:

  The Parasites TP_Alpha_v_0.1.5.0.0

No compatibility is promised for other versions.

Folder included in this package
-------------------------------
COPY_TO_GAME_WIN64

This folder is the portable payload. It contains the UE4SS loader/runtime,
the required Keybinds mod, and TheParasitesQuickStack.

Game Win64 folder
-----------------
The game Win64 folder is the folder that contains:

  TheParasites-Win64-Shipping.exe

The installer asks for this folder when no -GameWin64 path is provided.

Recommended installation
------------------------
1. Close The Parasites.
2. Back up your saves.
3. Extract this package anywhere.
4. Run:

   Install_QuickStack.cmd

5. Start the game.
6. Open a container.
7. Press Ctrl+F9.

Manual portable installation
----------------------------
1. Close The Parasites.
2. Open this package folder.
3. Open COPY_TO_GAME_WIN64.
4. Copy everything inside COPY_TO_GAME_WIN64 into your game Win64 folder:

   ...\TheParasites\Binaries\Win64

5. Allow Windows to merge folders and overwrite files if you accept that.
6. Start the game and use Ctrl+F9 with a container open.

Installation with a custom game path
------------------------------------
Open PowerShell in this package folder and run:

  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install_QuickStack.ps1 -GameWin64 "<your game Win64 folder>"

Existing UE4SS installations
----------------------------
This is a complete portable UE4SS package. Installing the whole payload can
replace an existing UE4SS setup, including mods.txt and UE4SS-settings.ini.

The installer backs up existing dwmapi.dll and ue4ss files before replacement.
The backup path is written to:

  last_backup.txt

If you already use UE4SS and want to keep other UE4SS mods, do a manual merge:

  - Copy only ue4ss\Mods\TheParasitesQuickStack into your existing UE4SS Mods
    folder.
  - Make sure the UE4SS Keybinds mod is installed and enabled.
  - Add or keep this line in your own ue4ss\Mods\mods.txt:

    TheParasitesQuickStack : 1

Uninstallation
--------------
Run:

  Uninstall_QuickStack.cmd

The uninstaller removes the UE4SS files installed by this package. If a previous
backup exists, it offers to restore it.

If you manually merged this mod into an existing UE4SS setup, uninstall it
manually instead:

  - Remove ue4ss\Mods\TheParasitesQuickStack
  - Remove or disable TheParasitesQuickStack in ue4ss\Mods\mods.txt

Log file
--------
After the mod has loaded, it writes a small log next to the installed mod:

  ...\ue4ss\Mods\TheParasitesQuickStack\QuickStack.log

Hotkey
------
Ctrl+F9:

  Move inventory stacks that match item types already present in the currently
  opened container.

If nothing moves, the most common reasons are:

  - No compatible container is open.
  - The container does not already contain that item type.
  - The container has no suitable free space.
  - The item is in an equipment/dedicated slot that QuickStack intentionally
    skips.
