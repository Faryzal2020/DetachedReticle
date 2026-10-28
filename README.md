# DetachedReticle

**DetachedReticle** decouples Cyberpunk 2077's camera look from the physical weapon orientation, allowing independent camera aiming while bullets originate from and travel along the weapon barrel's physical orientation.

## Requirements

- **Cyberpunk 2077:** Version 2.50 (Build 3.0.88.46235) exactly. *(Native callsite RVAs in `DetachedReticle.dll` are build-specific; if loaded on an untested game build, the plugin safely refuses to patch and logs a warning in `red4ext/logs/DetachedReticle.log`).*
- [RED4ext](https://github.com/WopsS/RED4ext): 1.25.0 or later (Required for native ballistics interception and RTTI bridge).
- [redscript](https://github.com/jac3km4/redscript): 0.5.32 or later.
- [Cyber Engine Tweaks (CET)](https://www.nexusmods.com/cyberpunk2077/mods/107): 1.38.0 or later.
- [Native Settings UI](https://www.nexusmods.com/cyberpunk2077/mods/3518): Optional (provides in-game configuration menu under Settings -> Mods).

## Build Provenance

- **Binary:** `red4ext/plugins/DetachedReticle/DetachedReticle.dll`
- **Game Build:** Cyberpunk 2077 2.50 (Build 3.0.88.46235)
- **Compiler:** MSVC 19.38+ (Visual Studio 2022 / C++20)
- **SDK Dependency:** [RED4ext.SDK](https://github.com/WopsS/RED4ext.SDK) commit `5246e659d783e5834cc08a90e56c8932c9ed3449`
- **Plugin Author:** `Antigravity & User`

## Architecture & Features

1. **Dual Reticle System:**
   - **Camera Reticle (Center Diamond):** Indicates the intended aim point driven instantly by mouse input.
   - **Gun Reticle (Floating Crosshair):** Represents where the weapon barrel is physically pointing in 3D world space.
2. **Physical Barrel Ballistics:** Fired bullets originate at the weapon's muzzle transform and travel along the physical barrel vector via native C++ callsite hooks (`PhysicalRay::Execute` origin @ RVA `0x9507B7` and forward @ RVA `0x9507EC`). Shotgun pellet spread and dispersion cones are preserved and rotated into barrel space.
3. **Chained Aiming Model ("Chase the Mouse"):**
   - The camera target moves instantly with mouse input.
   - Mouse deltas are smoothed and fed to vanilla's native input integrator, so character body yaw, arm pitch, sway, and recoil track naturally.
   - The residual offset is applied to the camera, holding the view rock-solid on target while the body and weapon swivel into alignment.
4. **Clean Fallbacks:** Melee weapons, unarmed states, vehicles, and scanning automatically revert to 100% vanilla behavior.

## Installation & Deployment

Copy `bin/`, `r6/`, and `red4ext/` directly into your Cyberpunk 2077 root directory:

```
<GAME_ROOT>/
├── bin/x64/plugins/cyber_engine_tweaks/mods/
│   └── DetachedReticle/
│       ├── init.lua
│       └── config.json
├── r6/scripts/
│   └── DetachedReticle/
│       ├── DetachedReticle.reds
│       └── NativeBridge.reds
└── red4ext/plugins/
    └── DetachedReticle/
        └── DetachedReticle.dll
```

## Logging & Diagnostics

Diagnostics and telemetry are written to:
- `<GAME_ROOT>/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/DetachedReticle.log` (CET script diagnostics and shot logs).
- `<GAME_ROOT>/red4ext/logs/DetachedReticle.log` (RED4ext native plugin initialization and callsite patch status).

