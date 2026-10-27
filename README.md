# DetachedReticle

**DetachedReticle** decouples Cyberpunk 2077's camera look from the physical weapon orientation, allowing independent camera freelook while aiming and true physical barrel-directed ballistics.

## Minimum Requirements

- **Cyberpunk 2077:** 2.50 minimum (Build 3.0.88.46235)
- [Cyber Engine Tweaks (CET)](https://www.nexusmods.com/cyberpunk2077/mods/107): 1.38.0 or later
- [redscript](https://github.com/jac3km4/redscript): 0.5.32 or later
- *(Note: RED4ext is not required for the Phase 1 MVP; native plugin sources under `src/` are reserved for Phase 2 procedural body/arm animation.)*

## MVP Features & Architecture

This release establishes the baseline proof-of-concept detachment between camera view and weapon ballistics:

1. **Independent Camera Freelook:** Moving the mouse rotates the first-person camera view only. The player's body and weapon model remain fixed in world space.
2. **Dual Reticle UI:**
   - **Camera Reticle (Center Pip):** A subtle static diamond pip at screen center marks where the camera is looking.
   - **Gun Reticle (Dynamic Floating Crosshair):** The active weapon crosshair is projected onto the screen from the physical 3D weapon barrel raycast in world space.
3. **Physical Barrel Ballistics:** Fired bullets leave the weapon's physical muzzle and travel along the 3D barrel orientation towards the Gun Reticle's impact point, not along the camera gaze.
4. **Clean Fallbacks:** Unarmed and dual-wielding states seamlessly revert to vanilla controls and crosshairs.

> [!NOTE]
> **Known MVP Scope / Gap:** While an armed ranged weapon is held, the player cannot rotate their body facing (camera turns freely, arms and body stay locked). Upper-body procedural tracking, spring smoothing, and convergence are scheduled for Phase 2.

## Installation & Deployment

Deploy the mod by copying `bin/` and `r6/` directly into your Cyberpunk 2077 root directory:

```
<GAME_ROOT>/
├── bin/x64/plugins/cyber_engine_tweaks/mods/
│   └── DetachedReticle/
│       └── init.lua
└── r6/scripts/
    └── DetachedReticle/
        └── DetachedReticle.reds
```

## Telemetry & Verification Logs

When active, the mod emits diagnostics via vanilla engine logging (`FTLog`):

- **Reticle Dynamics:** Logs angular divergence between camera look and weapon barrel, along with projected screen pixel offsets:
  `[DetachedReticle][DYNAMICS] Divergence: X.XX deg (Yaw: ... | Pitch: ...) | Offset: (X, Y) px`
- **Shot Redirection:** Logs atomic physical barrel origin and orientation at the exact instant of pre-attack processing:
  `[DetachedReticle] Redirected shot to physical barrel: MuzzlePos=(X, Y, Z) | MuzzleFwd=(X, Y, Z)`
- **Shot Telemetry:** Logs execution data per shot pull:
  `[DetachedReticle][SHOT #N EXECUTED] Weapon: Items.Preset_... | GunDivergence: X.XX deg | CrosshairOffset: ...`
