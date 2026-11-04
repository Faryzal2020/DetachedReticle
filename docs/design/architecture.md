# Architecture — DetachedReticle

**Game build:** 2.50 (Build 3.0.88.46235)
**Merged from:** `mvp.md` (the three-tier model and the MVP 2 status) and `research/native-architecture.md` (build and layout). Both originals are in `archive/superseded/`. This file describes the design as it stands on `testing` @ `569ff34`. For the evidence behind each piece, see [../FINDINGS.md](../FINDINGS.md).

---

## 1. Goal

The camera follows only the mouse and never wobbles. The aiming direction (the body and the upper-body rig) is detached from the camera but follows it with an adjustable lag. Bullets leave the physical barrel and land at the **gun** reticle, not at the camera reticle.

This works by decoupling the camera from the weapon. It is not a third-person mode.

## 2. The tiers

| Tier | Component | Role | Driven by |
|---|---|---|---|
| **T1** | Camera reticle (center diamond) | Intended aim point | Raw mouse, instant |
| **T2A** | Aiming anchor | Smoothed chase of T1 | Chase curve in the native hook (`ProcessMouseAim`) |
| **T2B** | Physical body heading | `T2B = T2A − C + W` | C = barrel-offset compensation (from `init.lua`), W = recoil transferred from the camera |
| **T3** | Gun reticle (floating crosshair) | Where the barrel points, `T2B + O` | Vanilla animation, sway and recoil follow T2B |

Because T3 is tied to T2B by vanilla animation, the mod never moves the gun mesh itself. It moves T2B by feeding the native look integrator a smoothed delta.

### Per-frame math (native, `src/Hooks/InputHook.cpp`)

```
dMouse, dRecoil   = split of the integrator delta at 0x51D462
T  += dMouse                                   (Tier 1, clamped to ±85° pitch)
A  += chaseStep(T − A, dt)                     (Tier 2A; Option A power law or Model A braking)
C  += clamp((Ctarget − C)·(1 − e^(−rate·dt)))  (Tier 2B compensation, ±10°)
W  += leash(dRecoil)                           (recoil kick, hold, then drift-cancelled recovery)
out = dA − dC + dW                             → written into the integrator (body yaw [rcx+9Ch], pitch xmm7)
R   = (T − A) + C − W − predNextDBody          → read by init.lua, applied to the camera
```

`dt` is smoothed (`0.75·prev + 0.25·dt`) before the chase and compensation filters. The camera ends up at `T2B + R = T` in world space.

### Camera residual (CET, `init.lua`)

```
qYaw   = axisAngle((0, sin θ, cos θ), R.yaw)    θ = DR_GetT2BPitch()   (gravity-up in the parent frame)
qPitch = axisAngle(X, R.pitch)
fpp:SetLocalTransform(pos, qYaw * qPitch * baselineRot)   baselineRot captured once at activation
```

## 3. Components

| Layer | File | Job |
|---|---|---|
| Native (RED4ext) | `src/Main.cpp` | Plugin entry; registers the `DR_*` / `SetMuzzleAimState` RTTI functions |
| | `src/Hooks/InputHook.cpp/.hpp` | Chase, Tier 2B, recoil state; patch at `0x51D462` |
| | `src/Hooks/MouseLookRelay.asm` | MASM relay: saves volatile registers, reads the split stack slots, calls `OnNativeMouseAim` |
| | `src/Hooks/ShootingHook.cpp/.hpp` | PhysicalRay callsite patches at `0x9507B7` / `0x9507EC`; muzzle origin; spread rotation |
| | `src/Hooks/AnimationHook.cpp/.hpp` | Standby no-op (has no job yet) |
| CET (Lua) | `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua` | Activation gating, pitch seed, Tier 2B target and trim, camera residual write, config/NativeSettings/ImGui UI, file logging |
| redscript | `r6/scripts/DetachedReticle/DetachedReticle.reds` | `module DetachedReticle`; `DetachedAimSystem`; dual reticle (`gameuiCrosshairContainerController` wraps, `ProjectWorldToScreen`); muzzle state feed; smart / HMG / NoWeapon crosshair handling |
| | `r6/scripts/DetachedReticle/NativeBridge.reds` | `native func` declarations for the DLL exports |
| TweakXL | `r6/tweaks/DetachedReticle/hmg_attack.yaml` | HMG `playerAttack` → `Attacks.ExplodingBulletMediumEffect` (hitscan) |

### Activation (CET)

- `isArmed = weapon and not weapon:IsMelee() and not isDual` (`init.lua:486`). The README also says vehicles and scanning fall back to vanilla, but the activation code doesn't check either one. That fallback is unconfirmed.
- `shouldBeActive = enabled and fpp and (isArmed or settling)`.
- On activation:
  - seed pitch from `CameraSystem.GetActiveCameraForward()`
  - capture `baselineRot`
  - call `DR_SetSmoothing(..., true)`
- On deactivation, wait until the residual, C and W are all under 0.10°. Then restore `baselineRot` and the original `headingLocked` / sensitivity values, and switch to passthrough. Passthrough is byte-for-byte vanilla.

## 4. Per-weapon handling

| Class | Chase | Tier 2B gate | Gun reticle | Ray hook | Notes |
|---|---|---|---|---|---|
| Regular firearms | on | 2.5° / 4.0° / ±2° | on | on | Shotgun spread rotated into the barrel frame |
| HMG (`IsHeavyWeapon`) | on | 8.5° / 12° / ±8.5° | on | on (remapped to hitscan) | Trim kept across zoom 4↔8 flips |
| LMG (`Wea_LightMachineGun`) | on | 8.5° / 12° / ±8.5° | on | on | REC#6, untested |
| Smart | on | off | off (vanilla crosshair centered) | off | Open bug: see FINDINGS §7 |
| Melee, unarmed, dual wield | off | — | — | — | Vanilla (`init.lua:486`, `DetachedReticle.reds:322`) |
| Vehicle, scanning | ? | — | — | — | The README claims vanilla, but no explicit gate exists. Unconfirmed. |

## 5. Build

- **Toolchain:** MSVC v143 (VS 2022), C++20, CMake ≥ 3.22, MASM (`ASM_MASM`).
- **SDK:** `RED4ext.SDK` pinned to commit `5246e659d783e5834cc08a90e56c8932c9ed3449` (`CMakeLists.txt`). No MinHook: every patch is a hand-written callsite patch.
- **Build commands:**
  ```powershell
  cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
  cmake --build build --config Release
  ```
- **Output:** `build/Release/DetachedReticle.dll`. Copy it to `red4ext/plugins/DetachedReticle/`, where it is tracked.
- **Known pitfall:** clear the lowercase `https_proxy` / `http_proxy` when the uppercase pair is also set. Otherwise MSBuild fails with "Item has already been added".
