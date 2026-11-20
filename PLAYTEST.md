# Noctis Live V5 — Playtest build

This branch is a playtest-ready snapshot of the existing V5 prototype. It does not replace `main`.

## Requirements

- Windows 10/11
- Godot **4.6 or newer** (the V5 project was validated by its development report with Godot 4.6.2 and 4.7.2)
- Extract the repository archive completely before launching. Do not run the game from inside the ZIP.

The project uses the Godot Compatibility renderer. No export template or separate installer is required to run it from the editor.

## Start

1. Download the branch ZIP from GitHub and extract it to a normal folder.
2. Install Godot 4.6.x or 4.7.x.
3. Either:
   - set the Windows environment variable `GODOT_EXE` to the full path of your Godot executable and double-click `Play.cmd`; or
   - open `project.godot` in Godot and press **F5**.
4. The first resource import may take several minutes. Let it finish before launching again.

`Play.cmd` checks for a local Godot executable and then for `godot.exe` in PATH. It no longer depends on the developer's machine-specific Steam or work-folder paths.

## Before testing saves

The game stores user data separately from the project, under:

`%APPDATA%/Godot/app_userdata/Йедамар — Дорога через Лиору/`

If you already have V2–V5 saves, make a copy of the `saves` folder before testing this branch. Do not delete your existing saves to troubleshoot a launch problem.

## First play session

- Start or continue the game and check that the window identifies itself as V5.
- Use **Esc** for pause and save options.
- **F5** writes to manual save slot 1; use the in-game save menu if you want another slot.
- **L** opens the life and settlement panels; **I** inventory; **C** crafting; **B** building; **M** map; **J** journal.
- The README contains the full controls, gameplay systems, and known scope limitations.

## Important scope notes

This is a local single-player prototype, not a finished game. The playable area is approximately 3.17 × 2 km. Network multiplayer, the full 250 km continent, unrestricted room/floor construction, and several systems from the design documents are not implemented. See `README.md` and `VALIDATION.md` for the documented scope and the original development test report.

The validation figures in `VALIDATION.md` are the project's recorded development results; this branch has not been independently run on another machine as part of its preparation.
