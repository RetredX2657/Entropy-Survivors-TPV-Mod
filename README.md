# Entropy Survivors – Third-Person View (FrogCam)

A third-person camera mod for **Entropy Survivors**. It replaces the fixed top-down camera with a chase cam behind your frog and its mech, so you ride along with them.

- Mouse look. The frog aims where the camera points, using the game's own aiming.
- WASD moves relative to the camera.
- **F5** switches between third person and the original top-down view.
- **F6** cycles the camera distance: near (almost first person), mid and far.
- Hold **Left Ctrl** to free the mouse pointer and click hub pop-ups. A hint at the top of the screen shows these keys when FrogCam switches on.
- Single-player only. It switches itself off in co-op.

> **Made with AI.** FrogCam's code was written by an AI coding agent (Claude, in Claude Code), directed and play-tested in the game by a human player. See [Credits](#credits).

> **Status: alpha.** Tested on one PC through the hub and full rounds. Please report anything that looks or feels wrong on the [Issues](https://github.com/RetredX2657/Entropy-Survivors-TPV-Mod/issues) page.

## Install (easy way)

1. Download **`FrogCam-vX.Y.Z-with-UE4SS.zip`** from the [latest release](https://github.com/RetredX2657/Entropy-Survivors-TPV-Mod/releases/latest). It includes the UE4SS mod loader, already set up.
2. In Steam, right-click **Entropy Survivors → Manage → Browse local files**, then open `EntropySurvivors\Binaries\Win64`. That's the folder with `EntropySurvivors-Win64-Shipping.exe` in it.
3. Copy everything from the zip into that folder.
4. Start the game. A hint at the top of the screen shows the keys.

**Uninstall:** delete `dwmapi.dll` and the `ue4ss` folder from `Win64`.

## Install (if you already use UE4SS)

Download **`FrogCam-vX.Y.Z-mod-only.zip`**, copy its `FrogCam` folder into `Win64\ue4ss\Mods\`, and add `FrogCam : 1` to `Mods\mods.txt` **above** the `; Built-in keybinds` line. If there is a `Mods\mods.json`, also add `{ "mod_name": "FrogCam", "mod_enabled": true }` to it.

Your UE4SS build needs to support Unreal Engine 5.4. FrogCam is tested with UE4SS experimental-latest, `UE4SS_v3.0.1-1161-g6eb3d9bc`.

**Uninstall:** delete `ue4ss\Mods\FrogCam` and its line in `mods.txt` / `mods.json`.

## Controls

| Key | Action |
|-----|--------|
| Mouse | Look and aim |
| WASD | Move, relative to the camera |
| F5 | Third person on/off |
| F6 | Camera distance: near (almost first person) / mid / far |
| Hold Left Ctrl | Free the mouse pointer, for clicking hub pop-ups like "Change Class → Open Menu". The camera holds still. Change the key with `frogcam freekey <key>` |

## Settings

Settings are saved in `Mods\FrogCam\FrogCam.cfg`. You can also change them while playing from the UE4SS console (the `~` key, enabled by UE4SS's ConsoleEnablerMod):

```
frogcam                 list all settings
frogcam fov 85          set one value (saved immediately)
frogcam reset           restore defaults
frogcam toggle          same as F5
frogcam reload          reload the script without restarting the game
```

| Name | Default | Meaning |
|------|---------|---------|
| `dist` | 700 | Camera distance behind the frog |
| `height` | 300 | Height of the point the camera orbits. Higher lets you look up a little further |
| `shoulder` | 0 | Sideways offset (+ = right) |
| `fov` | 75 | Field of view |
| `sens` | 0.12 | Mouse sensitivity (degrees per pixel) |
| `invert` | 0 | 1 = invert mouse Y |
| `pmin` / `pmax` | -60 / 30 | Camera pitch limits. Looking up also stops just above level (see Known limitations) |
| `retcenter` | 1 | 1 = reticle always drawn mid-screen, 0 = drawn where the game's cursor really is (useful for debugging aim) |
| `retlow` | 0.9 | Safety limit: the lowest the hidden cursor may go on screen before the camera stops tilting up |
| `aimmin` / `aimmax` | 250 / 3000 | Closest / farthest aim point ahead of the frog. The reticle stays mid-screen and looking higher aims farther out |
| `aimz` | 182 | Height of the game's aim plane (the frog's gun height) above the hero's centre. Only change this if the frog aims backwards at some camera angles |
| `hpmove` | 1 | 1 = show the health bar at a fixed spot on screen, 0 = where the game puts it (on the HUD ring under the mech) |
| `hpx` / `hpy` | 0.25 / 0.85 | Health bar screen position as a fraction of width / height (0,0 = top left) |
| `hint` | 1 | 1 = show the key hint (free-pointer key / F5 / F6) for a few seconds when FrogCam switches on |
| `freekey` | LeftControl | Key to hold for a free mouse pointer, as an Unreal key name: `LeftControl`, `Tab`, `B`, `MiddleMouseButton`, ... (Alt is the game's alternate dodge) |
| `debug` | 0 | 1 = write a status line to `FrogCam.log` every second, for troubleshooting. The log starts fresh at each game launch |

## How it works

- **View:** FrogCam spawns its own camera and makes it the view target. The game's tracking camera keeps running behind the scenes, so enemy spawning and off-screen logic that depend on it still behave normally.
- **Aim:** the game aims the frog at the mouse cursor, meeting it with a flat plane at the frog's gun height. Its crosshair reticle *is* that cursor. Each frame, FrogCam moves the cursor to a point on that plane straight ahead of the frog, where the screen centre meets it whenever possible. It also shifts the reticle widget so it is always drawn mid-screen, while the real cursor sits wherever the game needs it to aim where you look.
- **Movement:** nothing extra is needed. The game already moves relative to whatever camera is active, so once FrogCam's camera takes over, W walks where you look.

## Known limitations

- The game was built to be seen from above. Expect missing geometry, see-through effects and UI elements that are positioned for the top-down view.
- **Looking up stops just above level** (about +7° at the default distance, more with F6 near, less with far). The game aims through the mouse cursor at a plane at the frog's gun height, and that only works while the camera is above the gun. A camera below it makes the frog aim backwards. Raising `height` or lowering `dist` (F6 near) gives a little more room.
- It's a bullet hell, and enemies behind you are hard to see. Raise `dist` or press F6 if you get swarmed.
- Gamepad isn't supported yet.

## Development

- `FrogCam/Scripts/main.lua`: loads the mod and sets up hooks and the console command.
- `FrogCam/Scripts/frogcam.lua`: all camera, aim and movement logic. Reload it in game with `frogcam reload`.
- `tools/FrogCamProbe`: a read-only diagnostic mod. Press F7 in game to log the player, camera and spring-arm setup to `FrogCamProbe.log`.
- `tools/build-release.ps1`: builds both release zips into `dist/`. The bundled UE4SS build is kept in `third_party/`, which is not in git, and downloaded there if missing.
- `tools/link-dev.ps1`: links this repo's `FrogCam` folder into the game's Mods folder, so your edits are live. To remove the link, run `rmdir "<Mods>\FrogCam"` in cmd. Don't delete it recursively from Explorer or PowerShell 5.1, which can follow the link and delete the repo's files.

## Credits

Built with an AI coding agent (Claude Code, by Anthropic), which did the game research and wrote the code. RetredX2657 directed the design and play-tested every change in the game.

[RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) (MIT) is the mod loader FrogCam runs on. The with-UE4SS download bundles it unmodified, with its license, and only its mod list is set up.

The approach (polling keys on the game thread, mouse look by re-centring the cursor, the reloadable script layout) is modelled on [AscentFPS](https://github.com/dimap/ascent-fps) by dimap (MIT), a first-person mod for The Ascent.

## License

MIT. See [LICENSE](LICENSE).
