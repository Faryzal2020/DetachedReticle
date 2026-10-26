# DetachedReticle

**DetachedReticle** decouples Cyberpunk 2077's camera freelook from the physical weapon orientation, introducing realistic angular inertia, delay, and weight to weapon aiming with true-to-crosshair ballistics.

## Core Architecture

- **Camera Freelook:** The mouse freely controls camera rotation and freelook view. A subtle, centered **Camera Crosshair** marks the intended aim point.
- **Weighted Gun Crosshair:** The active game crosshair (including spread, charge, and ammo UI) is physically decoupled from the camera view center. It moves across the screen governed by a 2nd-order angular spring-damper model simulating weight, mass, and delay.
- **Dynamic Ballistic Redirection:** Bullets do not shoot from the screen center; native hitscan traces (`PhysicalRay::Execute`) and projectile vectors are dynamically redirected from the weapon's physical muzzle directly through the world target point that the Gun Crosshair is aimed at.

## Requirements

- [redscript](https://github.com/jac3km4/redscript) (0.5.x or newer)
- [Cyber Engine Tweaks (CET)](https://www.nexusmods.com/cyberpunk2077/mods/107) (for native hitscan raycast interception)
- [RED4ext](https://github.com/WopsS/RED4ext)
- Cyberpunk 2077 (v2.1x)

## Installation & Deployment

Deploy the mod by copying `r6/` and `bin/` into your game root directory:

```
<GAME_ROOT>/
├── bin/x64/plugins/cyber_engine_tweaks/mods/
│   └── DetachedReticle/
│       └── init.lua
└── r6/scripts/
    └── DetachedReticle/
        └── DetachedReticle.reds
```

## Diagnostic Verification & Logs

In accordance with our strict verification policy, every execution generates diagnostic proof in the logs:

1. **Redscript Telemetry (`r6/logs/redscript_rCURRENT.log` / redscript console):**
   - Telemetry logs angle lag ($\theta^\circ$), screen translation offset $(X, Y)\text{ px}$, and active widget name.
   - On every shot fired, logs the exact muzzle position, target point, and calculated bullet divergence from camera center.
2. **CET Log (`bin/x64/plugins/cyber_engine_tweaks/cyber_engine_tweaks.log`):**
   - Verifies native memory allocation and hook installation at RVAs `0x9507B7` and `0x9507EC`.
   - On every trigger pull, logs:
     - `[SHOT VERIFICATION #N INTERCEPTED BY NATIVE HOOK]`
     - Muzzle origin $(X, Y, Z)$
     - Target point $(X, Y, Z)$
     - Bullet forward vector vs Camera forward vector
     - Divergence angle ($\text{deg}$) verifying off-center bullet redirection.
