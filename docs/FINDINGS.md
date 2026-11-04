# DetachedReticle — Key Findings

One-file digest of what the project has established so far. It is compiled from the iteration logs, the research notes and review rounds 1 to 9. It replaces none of them; every claim names its source so you can check the detail.

- **Compiled:** 2026-11-04, from `testing` @ `569ff34` ("stable checkpoint").
- **Game build:** Cyberpunk 2077 2.50 (Build 3.0.88.46235). Every RVA and field offset below is specific to this build.
- **Labels** (AGENTS.md §5):
  - **verified**: seen in the 2.5 script dump (`reference/game-scripts/`).
  - **empirical**: measured in game or in a disassembly by the Windows agent. The Mac reviewer can't check these.
  - **inferred**: reasoned from the evidence, not yet tested.
  - **unknown**: not known at all.
- **Source shorthand:** `MVP#n` = [iterations/01-mvp.md](iterations/01-mvp.md), `POL#n` = [iterations/02-polish.md](iterations/02-polish.md), `REC#n` = [iterations/03-recoil.md](iterations/03-recoil.md), `R<n>` = review round *n* (in [reviews/](reviews/) or [archive/reviews/](archive/reviews/)).

---

## 1. Status at a glance

| Area | State | Source |
|---|---|---|
| MVP 1: pure freelook, bullets leave the barrel | Done, owner-confirmed 2026-10-28 | MVP#8 |
| MVP 2: body and weapon chase the camera with lag, camera never wobbles | Done, owner-confirmed 2026-10-29 | MVP#22, R5 |
| Gimbal roll fix, Tier 2B barrel compensation, holster/draw continuity | Done | POL#23–#32 |
| Trim sign fix, resting-pose jolt, HMG roll | Done (regular guns confirmed "less jittery") | POL#33–#36 |
| Chase curve: Option A power law (default), Model A braking zone (option) | Implemented | [design/chase-smoothing.md](design/chase-smoothing.md) |
| Recoil moved from the camera to Tier 2, drift-free recovery, rubber leash | Implemented; leash confirmed working | REC#1–#5 |
| LMG hip-cradle compensation | Deployed, **untested** | REC#6 |
| Smart weapons: regular reticle shown, no lock-on | **Open.** Iteration 37 is deployed; the bisection is still waiting to run | POL#37, R9 |

---

## 2. The model

Three tiers. The full write-up is in [design/architecture.md](design/architecture.md).

| Tier | What | Driven by |
|---|---|---|
| T1, camera reticle | Where the player looks | Raw mouse, instant |
| T2A, aiming anchor | Smoothed chase of T1 | Native hook, chase curve |
| T2B, physical body heading | `T2B = T2A − C + W` | C = barrel-offset compensation, W = recoil |
| T3, gun reticle | Where the barrel points (`T2B + O`, O = the gun's resting offset) | Vanilla animation follows T2B |

The camera is held on T1 by writing the residual `R = (T − A) + C − W − predNextDBody` to the `FPPCameraComponent` local transform. That gives `camera world = T2B + R = T` (POL#30, REC#1, REC#4).

The idea that made MVP 2 work: **don't rotate the body, rotate the mouse.** Feed vanilla's own look integrator a smoothed delta, and vanilla moves the body, arms, sway and recoil exactly as before, as if the player had a slower hand (R4).

---

## 3. Engine facts

### 3.1 Firing pipeline

- **The bullet is not fired from `ShootEvents.OnEnter`.** It comes from native `SetTriggerDown(true)`, called from `StartShootingSequence`. That dispatches the attack bound by `SetAttack` into `gameEffectObjectProvider_PhysicalRay::Execute`. Suppressing everything in `OnEnter` still fired a bullet at the camera reticle. **empirical** (MVP#8)
- **`PhysicalRay::Execute` reads the ray origin and direction from the camera** at callsites RVA `0x9507B7` (origin) and `0x9507EC` (forward). Both call the input evaluator at `0x474BCC`. Patching those two callsites in the DLL (`ShootingHook.cpp`) is the only thing that moved hitscan rays. **empirical** (MVP#8)
- **Shotgun spread** comes in on the evaluated forward vector. Keep it by rotating each pellet's offset from the camera frame into the barrel frame with `q = normalize(1 + c·b, c × b)`. Replacing the vector with the muzzle forward collapses the pellets onto one line. **empirical** (MVP#9)
- **The muzzle transform is script-readable** through `WeaponObject.GetMuzzleSlotWorldTransform()`, and it follows attachments. **verified** (`weapon.swift:135`; [research/weapon-fire-flow.md](research/weapon-fire-flow.md) §5)
- **Hitscan and projectile weapons are split in TweakDB:**
  - hitscan: `Attack_GameEffect` / `Bullet_GameEffect`, `effectName = "weaponShoot"`, `effectTag = "player_ray"`
  - projectile: `Attack_Projectile` / `Bullet_Projectile`

  Projectiles bypass `PhysicalRay`, so the ray hook never sees them. **verified + empirical** (weapon-fire-flow §6, POL#25)
- **The HMG is a projectile weapon.** `Preset_HMG_Default` → `Attacks.ExplodingBulletHMGPackage` → `playerAttack = Attacks.ExplodingBulletSmallProjectile`, a 140 m/s projectile. Remapping it to `Attacks.ExplodingBulletMediumEffect` (hitscan, same damage multipliers and explosion) routes it through the hook. That is a gameplay change. **empirical** (POL#25–#27)

### 3.2 Mouse look, body and camera

- **Mouse X turns the puppet body yaw** at 0.0500 °/count, while `camLocalYaw` stays at 0. **Mouse Y is not stored in the camera component's local quaternion.** It lives in a native accumulator. **empirical** (MVP#13)
- **The camera component's local orientation persists** between frames. Vanilla doesn't rewrite it, so a per-frame `local = q * GetLocalOrientation()` compounds into a spin. Offsets must be applied to a baseline captured once. **empirical** (MVP#13–#14)
- **The arms and gun follow the engine's input state, not the camera component.** A script camera write can world-lock the view (err −0.0085°) while the rig keeps moving. **empirical** (MVP#15, S3/S6)
- **There is exactly one site that carries both look deltas:**
  - RVA `0x51D462`, `movss [rcx+9Ch], xmm6`: `xmm6` = body-yaw delta, `xmm7` = pitch delta. The pitch is passed on as `xmm3` at `0x51D48B` into `FPPCameraComponent::OnMouseLook` (`0x39CA70`).
  - The enclosing function is `sub_51CFA8` (MVP#21 calls it `sub_51D380`).
  - **empirical** (MVP#21–#22, REC#1)
- **Rejected hook sites** (each was tried; see §7):
  - `0x39CB63`: a horizontal branch at `0x39CB32` jumps around it.
  - `0x39CA70` entry: the caller at `0x51D488` zeroes `xmm2` with `xorps`.
  - `0x39CBE3` (`call 0x39CD5C`): this call only rotates the camera component.
- **`gameFPPCameraComponent` fields** (size `0x510`): `pitchMin 0x3E0`, `pitchMax 0x3E4`, `yawMaxLeft 0x3E8`, `yawMaxRight 0x3EC`, `headingLocked 0x3F6`, `sensitivityMultX 0x498`, `sensitivityMultY 0x49C`.
  - `sensitivityMult*` scale the deltas at `0x2463D13` / `0x2463D20`.
  - `headingLocked` gates body yaw at `0x39CAFE`.
  - **empirical** (MVP#15–#17)
- **The camera lags the body by one frame in the scene graph.** The hook writes the body yaw for frame *k* before CET writes that frame's residual, so `camYaw_k = bodyYaw_k + rYaw_{k−1}`. With no compensation, the camera drifts toward the catching-up gun and shakes. Two fixes are in: the residual subtracts the predicted next body step, and `dt` is smoothed (`0.75·prev + 0.25·dt`). **empirical** (REC#4)
- **The engine does not overwrite `fpp`** between script ticks. The `[1C] fppOverwrite` probe read 0.000°. **empirical** (POL#35, refutes the theory in R8 1C)

### 3.3 Conventions

- **Engine yaw:** forward is +Y, and positive yaw is to the left. `GetWorldYaw`, `Vector4.Heading`, `Transform.GetYaw` and `EulerAngles.Yaw` all share this convention. `atan2(fwd.y, fwd.x)` is 90° out of phase with it. **verified** (R3 §1a: `entity.swift:48`, `vector.swift:110`)
- **CET constructor argument orders:** `EulerAngles.new(roll, pitch, yaw)`, `Quaternion.new(i, j, k, r)`. **verified** (CET `BasicTypes.h`)
- **Gravity-up axis for the residual yaw:** in the camera's parent frame it is `(0, sin θ, cos θ)`, where θ is the **T2B** pitch (`DR_GetT2BPitch`). Using A's pitch puts a tilt of C into the axis. That caused about 6° of HMG roll. Reading `fpp:GetWorldForward()` for the axis feeds back the previous frame's result and jitters. **empirical** (POL#23, #24, #35)
- **Screen axes:** `scrX > 0` means the gun reticle is right of center, `scrY > 0` means below. Screen +X maps to −yaw and screen +Y to −pitch, so both trim updates carry the same sign (`−scr·k`). **verified by reading** (R8 2A)
- **PSM states:**
  - `gamePSMCrosshairStates`: Default 0, Safe 1, Aim 4, Reload 5, Sprint 7, HipFire 8.
  - `gamePSMUpperBodyStates`: SwitchItems 1, Reload 3, Aim 6.
  - **verified** (`orphans.swift:6728`, `:6657`; R5 §6)
- **HMG zoom behaves differently:** the HMG has no upper-body Aim state (upper body is never 6). Firing while zoomed flips `crosshairState` from 4 to 8. **empirical** (REC#4)

### 3.4 Recoil internals

- **Recoil is mixed into the same look delta.** At the `0x51D462` hook, `xmm6/xmm7` = pure mouse + native recoil, with zero split error over every logged frame. Inside the relay:
  - pure mouse yaw/pitch: `[rsp+128h]` / `[rsp+124h]`
  - recoil yaw/pitch: `[rbp−78h]` / `[rbp−7Ch]`, written by the weapon recoil subsystem (`[r10+350h]` on `rdi+0B8h`)

  **empirical** (REC#1–#2; the first attempt had the two pairs swapped)
- **Native recovery doesn't return to zero.** After `RecoilHoldDuration` (~0.08 s), the engine recovers over `RecoilRecoveryTime` (~0.18 s) toward a random drift point of radius 0.6–0.9° × min(1, |W_peak| / 3°). The stats involved are `RecoilDriftRandomRangeMin 0.6`, `RecoilDriftRandomRangeMax 0.9` and `RecoilMagForFullDrift 3` in every ranged base. **empirical + vanilla tweak** (REC#3)
- **Recoil can climb up to 30°** (`BaseStats.RecoilMaxLength = 30`). That's why the leash exists. (REC#5)

### 3.5 UI and crosshair

- **A second reticle is feasible in script.** Project the gun's hit point with `ProjectWorldToScreen()`, then translate a widget under `gameuiCrosshairContainerController`, as vanilla does in `crosshairController_DriverCombat_PowerWeapon`. **verified** (weapon-fire-flow §7)
- **HMG zoom indicator:** keep it at screen center by counter-translating the `fluff` child and centering `CrosshairGameController_NoWeapon`. Don't hide the ladder widgets. **empirical** (POL#27–#28)
- **Smart crosshair** (`CrosshairGameController_Smart_Rifl`): it draws only what the engine publishes on `UI_ActiveWeaponData.SmartGunParams`. Target acquisition and locking are native. Which crosshair is spawned is decided natively from `Item_Record.Crosshair()`; no script swaps crosshairs. **verified** (R7, R9 §1–1b)

### 3.6 Weapon classes

- **`WeaponObject.IsHeavyWeapon()` is true only for the HMG** (`Wea_HeavyMachineGun`), not for LMGs (`Wea_LightMachineGun`: Defender, MA70 HB). **empirical** (REC#6)
- **Resting hip barrel offsets O, body-relative (yaw, pitch):**

  | Weapon | Offset | Source |
  |---|---|---|
  | Lexington | (−1.05°, −4.80°) | POL#30 |
  | Igla | (+5.64°, +5.52°) | POL#30 |
  | HMG | (+3.5 to 3.8°, +6.4 to 6.6°) | POL#30, POL#36 |
  | LMG Defender | (+6.37°, +7.07°) | REC#6 |
  | Copperhead (ready) | (+0.58°, +0.50°) | POL#35 |

  In optical ADS the offset is under 0.2°.
- **Muzzle parallax:** the muzzle sits 0.2 to 0.4 m from the eye. That is 6 to 10° of parallax at 2 m, about 1° at 15 m and under 0.3° at 50 m. **geometry** ([design/convergence.md](design/convergence.md))

### 3.7 Runtime and tooling

- **Logging that reaches disk:** CET `io.open` in `init.lua`, and the DLL's `ofstream`. `FTLog` and `redscript_rCURRENT.log` do not show runtime telemetry. The compile log closes before gameplay. **empirical** (MVP#5)
- **Relative paths:** the game's working directory is `bin\x64`, so relative paths in the DLL resolve from there. **empirical** (MVP#14)
- **CET:**
  - `ffi` is unavailable (`require("ffi")` crashes).
  - `Observe` must be called inside `onInit`.
  - There are no session start/end events.

  **empirical** ([research/noted-issues.md](research/noted-issues.md))
- **Lua:** `0.0 or x` evaluates to `0.0`, because 0 is truthy. That bug zeroed Tier 2B mid-burst. **empirical** (REC#4)
- **Build:** MSBuild fails when both `https_proxy` and `HTTPS_PROXY` are set. Clear the lowercase pair. **empirical** (POL#34)

---

## 4. Native hook and API map (2.50 only)

| RVA | Patch | Purpose |
|---|---|---|
| `0x51D462` | 8-byte near call (`E8 rel32` + 3 NOPs) to `MouseLookRelay.asm` | Look integrator. Feeds the smoothed body yaw `[rcx+9Ch]` and pitch, and splits mouse from recoil. The relay saves every volatile register (r8–r11, xmm0–xmm5) in a `0D8h`, 16-byte-aligned frame (POL#32). |
| `0x9507B7` | Callsite patch of `call 0x474BCC` | Hitscan ray origin → muzzle |
| `0x9507EC` | Callsite patch of `call 0x474BCC` | Hitscan ray forward → barrel, spread rotated |

**Script ↔ native functions**, registered in `src/Main.cpp`:

- `SetMuzzleAimState(muzzlePos, muzzleFwd, camFwd, isDecoupled)`
- `DR_SetSmoothing(lambda, mode, maxDiv, deadzone, enabled)`
- `DR_SetExpParams`, `DR_SetBrakeParams`
- `DR_SetBarrelOffset(yaw, pitch)`
- `DR_SetRecoilLeashParams`
- `DR_SetHeadingLocked`, `DR_SetSensitivityMult`
- Getters: `DR_GetTargetYaw/Pitch`, `DR_GetAimYaw/Pitch`, `DR_GetResidualYaw/Pitch`, `DR_GetCompYaw/Pitch`, `DR_GetT2BYaw/Pitch`, `DR_GetRecoilYaw/Pitch`, `DR_GetSplitErrYaw/Pitch`, `DR_DrainEvents`

The patches check the bytes before writing and refuse to patch on any other build.

---

## 5. Design decisions in force

| Decision | Value / rule | Why | Source |
|---|---|---|---|
| Body actuator | Smoothed mouse delta into the native integrator. Never `Teleport`. | Teleport breaks locomotion and physics, and can't pitch. | MVP#12, R4 |
| Chase curve (default) | Option A power law `dG/dt = −k·G^p`, k = 22, p = 0.60, closed form | No distance branches; frame-rate independent; settles in 4 frames; tames flicks | [design/chase-smoothing.md](design/chase-smoothing.md) |
| Chase curve (option) | Model A braking: 360°/s cruise, smoothstep inside 2° | Distinct cruise feel | same |
| Max divergence / deadzone | 65° (advances A, never T) / 0° | Camera is never pulled | MVP#10–#11 |
| Tier 2B target | Body-relative `C = O` (`gunYaw − bodyYaw`, `gunPitch − t2bPitch`) | A camera-relative target converges to O/2 (half-gain bug) | POL#32, R5 §2 |
| Tier 2B rates | settled 12 s⁻¹, moving 4 s⁻¹, max 240 °/s, min 6 °/s, gap threshold 3° | Snappy settling without eating the swing | `init.lua` Config |
| Ready-stance gate | Smoothstep. Regular guns: full below 2.5°, zero by 4.0°, target clamp ±2°. HMG and LMG: 8.5° / 12° / ±8.5°. Native clamp ±10°. | A hard 15° cutoff jolted the camera; a wide gate chased the arm-lowering animation | POL#33, #35, #36, REC#6 |
| Parallax | Converge on the hit point with a slow integral trim: ki 0.005 °/(px·s), clamp ±3°, frozen while `rawGap ≥ 0.10°`, negative feedback on both axes | Centers at any range once settled | [design/convergence.md](design/convergence.md), POL#33 |
| Trim and stored targets reset | Reset on weapon change and on HIP↔ADS. The HMG keeps them across 4↔8 crosshair flips. | Trim leaking between stances; zoomed HMG stall | POL#33, REC#4, REC#6 |
| Tier 2B freeze | Hold the last settled target while recoiling or swinging (gap > 0.5°) | Stops swing and recoil from corrupting C | REC#1, REC#4 |
| Deactivation | `shouldBeActive = enabled and fpp and (isArmed or settling)`, where `settling = |R| + |C| (+ |W|) > 0.10` | No camera snap on holster | POL#32, R5 §4c |
| Activation pitch seed | `CameraSystem.GetActiveCameraForward()`, not `aimSys` | `aimSys` reads 0 while holstered or on smart weapons, which caused roll after a draw | POL#37 (F0) |
| Recoil | W goes to Tier 2 only. Recovery runs straight to (0, 0), scaled to cancel the drift. Leash `g = 1 − (r/7°)^1.5` keeps 50% of the tangential jitter. | Camera free of recoil; no random rest point | REC#1–#5 |
| Exclusions | Melee, unarmed and dual wielding (`GameObject.IsDualWielding`) fall back to vanilla (`init.lua:486`). The README also lists vehicles and scanning, but the activation code has no explicit gate for them (unconfirmed). | Scope | README, R1 |
| Smart weapons | Keep the chase (T1 → T2A). No Tier 2B, no gun reticle, no camera pip, ray hook off. Vanilla smart crosshair stays at center. | Owner decision 2026-11-03 | R9 §0 |

---

## 6. Refuted approaches (don't retry)

The complete list is [research/noted-issues.md](research/noted-issues.md); the assumptions ledger is in [iterations/01-mvp.md](iterations/01-mvp.md). Grouped summary:

- **Redirecting shots from script.** None of these moved the bullet:
  - `EffectPreAction_PreAttack.Process` blackboard writes
  - `ShootStraight(true)` (it also kills spread)
  - `AI_ShootForwards`, `StartContinuousAttack`, `CreateEffectStatic(n"weaponShoot")`
  - suppressing `TriggerWeaponEffects` or `PushAnimationEvent`

  The PhysicalRay callsite patch is the only path that works. (MVP#5–#8)
- **Turning the body from script:**
  - Per-frame `Teleport`.
  - Setting pitch through `fpp:SetLocalTransform` (the rig ignores it).
  - Folding pitch into the yaw divergence.

  (MVP#11–#12)
- **Composing the camera:**
  - `Rx(−p)·Rz(y)·Rx(p+f)` rolls the horizon.
  - Yaw about a local (0, 0, 1) inside a pitched frame rolls by about yaw·sin(pitch).
  - Multiplying onto `GetLocalOrientation()` every frame spins the camera.
  - Inverting `rYaw` makes the gun move ahead of the camera.

  (MVP#12, #14, #20, POL#23)
- **Pitch seeding:**
  - Re-seeding every frame (`DR_ResetChasePitch`) wipes the residual.
  - Seeding from `aimSys:GetCameraForward()` gives 0.

  (noted-issues, R8 §4)
- **Tier 2B control:**
  - Measuring camera-relative gives half gain.
  - Feeding live lag into the fast compensator erases the chase.
  - A smoothstep restarted every frame never decays ("Zeno's holster").
  - A binary 15° gate jolts.
  - Bypassing Tier 2B for the HMG leaves its reticle off to the upper left.

  (POL#31–#36)
- **Integral trim:** `+scrX` on yaw is positive feedback and runs into the clamp. (POL#33, R8 2A)
- **Recoil:**
  - Swapped stack slots sent the mouse into W.
  - Trusting native recovery leaves a random 0.6–0.9° rest point plus a ~1 s bleed.

  (REC#2–#3)
- **Process:** iteration 31 deleted the `local weapon`/`local fpp` lines and made the whole mod inert while it still looked installed. Re-check the activation log after every big edit. (POL#32, R5 §1)

---

## 7. Open issues and untested hypotheses

1. **Smart weapons**:
   - Symptom: a regular reticle where the square smart reticle should be, and no lock-on.
   - What's in: iteration 37 shipped the F0 seed fix, F2 (no forced `SetVisible`) and the `[SMART]` probe.
   - What's pending: the R9 §3 bisection (steps 0 to 4) and the probe readout. No fix should go in before that session.
   - Ranked causes (R9 §1b), all **inferred**: (1) the weapon's `crosshair` flat or another mod; (2) the Smart Link state; (3) this mod's container wraps or added canvas.
2. **LMG compensation** (REC#6) has not been tested in game.
3. **WASD jitter** (R8 Issue 1):
   - Origin unclear: the locomotion turn (1A) is unverified and the R8 P2 hook-count probe has no recorded result.
   - It is likely mitigated by REC#4's one-frame lead compensation. **inferred**; not separately confirmed.
4. **The gun trace uses only `n"World Static"`** (`DetachedReticle.reds:417, :574`). On NPCs and other dynamic objects the reticle and trim target the wall behind. This affects the display only, not the ballistics. (R8 2C)
5. **Close range (< ~5 m):** the ±3° trim can't close the parallax. This is by design; revisit if it bothers players.
6. **Never reported:**
   - impact test on tech (charged) and non-HMG projectile weapons (R2 Request C)
   - spread under ADS and tech charge (R3 Q3)
   - gamepad right stick (R2 Request E)
   - TPP camera (an AGENTS.md §1 requirement; no TPP test on record)
   - the byte dump of `0x51D46A–0x51D490` confirming no flags dependency (R5 H1)
7. **Release hygiene still open:**
   - The HMG redirect is still triple: TweakXL `hmg_attack.yaml` + `GetDesiredAttackRecord` wrap + `SetAttack` re-assert (R5 H4).
   - `config.json` is tracked and rewritten on every slider change (R5 H6).
   - `AnimationHook` is a standby no-op (R3 C9).
   - README has to state the HMG gameplay change and the TweakXL dependency (R5 H3).

---

## 8. Where things live

See [README.md](README.md) for the folder map and the old-path → new-path table.
