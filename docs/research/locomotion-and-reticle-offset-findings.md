# Locomotion Drift & Reticle Offset — Investigation, Findings, and Fix Attempts

**Document Version:** 1.0  
**Date:** 2026-11-10  
**Branch:** `fix-baseline-yaw`  
**Game Build:** Cyberpunk 2077 2.50 (Build 3.0.88.46235)  

> [!IMPORTANT]
> **Verification Policy:**  
> Per project rules, **no implementation or fix is considered working by default**. An item is only marked **Verified Working** if explicitly confirmed in-game by the user or conclusively proven by empirical telemetry log data. All other items are explicitly labeled **Untested / Unverified** or **Refuted / Ineffective**.

---

## 1. Executive Summary & Verification Matrix

| Component / Fix Attempt | Intended Purpose | Status | Evidence / Notes |
|---|---|---|---|
| **`MonitorLocomotion` Telemetry** (Iter 14) | Instrument move heading vs camera vs body heading | **Verified Working** | Successfully logged `[LOCOMOTION_MONITOR]` data in `DetachedReticle.log`. |
| **Pillar 1: `SanitizeBaselineRot`** (Iter 15) | Strip transient yaw from `baselineRot` on unholster | **Refuted / Ineffective** | In-game logs showed `baselineRot` was already clean `(0,0,0,1)`. Bug persisted. |
| **Locomotion `locoBlend`** (Iter 16) | Attenuate $C_{\text{yaw}}$ during hipfire movement to eliminate walk drift | **Verified Working** | Telemetry at `19:01:44` showed $\Delta\text{Move\_Cam} = +0.02^\circ$ (was $+12.5^\circ$). Walk with `W` is dead straight. |
| **`isMouseMoving` Activity Gate** (Iter 16) | Prevent false `isSwinging` deadlock when moving with WASD | **Verified Working** | Unlocked `isResting` evaluation independently of frozen DirectInput mouse deltas. |
| **Pillar 4: Idle Watchdog** (Iter 16) | Re-sync pitch and clear residual when stationary | **Untested / Unverified** | Deployed in Iter 16; not yet isolated or tested independently. |
| **Socket-Relative Yaw `socketYaw`** (Iter 17) | Replace `bodyYaw` with `socketYaw = normalizeDeg(camYaw - rYaw)` to cancel $+7.68^\circ$ skeletal stance twist | **Untested / Unverified** | Deployed to `<GAME_ROOT>` at `19:06:40`. Game has not yet been executed with this build. |

---

## 2. Problem Description

During gameplay testing, two distinct but mathematically coupled issues were observed:

### Issue A: Locomotion Walk Drift (+x° Off Camera Gaze)
- **Symptom:** When unholstered and pressing `W` to walk forward, the player character did not move straight along the camera crosshair/gaze ($T_1$). Instead, the character drifted noticeably to the left (between $+9.5^\circ$ and $+12.5^\circ$ off-angle).
- **Impact:** Player could not walk straight towards a target while looking through the reticle without constantly counter-steering with the mouse or `D`.

### Issue B: Gun Reticle T3 Stuck Off-Center
- **Symptom:** The physical gun reticle T3 appeared visibly stuck to the left of the center diamond T1 when idle/resting, rather than settling in the center.
- **Impact:** Steady-state visual reticle misalignment in hipfire posture; convergence trim failed to bring T3 back to center.

---

## 3. Detailed Chronology of Investigations & Fix Attempts

### Phase 1: Iteration 14 — Locomotion Telemetry & Engine Fact Discovery
- **Action:** Created `MonitorLocomotion` watchdog in [`init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua) to compute and log:
  $$\text{moveHeading} = \text{atan2}(-v_x, v_y), \quad \text{camYaw} = \text{CameraSystem forward}, \quad \text{bodyYaw} = \text{player:GetWorldYaw()}$$
  $$\Delta\text{Move\_Cam} = \text{normalize}(\text{moveHeading} - \text{camYaw}), \quad \Delta\text{Move\_Body} = \text{normalize}(\text{moveHeading} - \text{bodyYaw})$$
- **Verified Engine Fact (`locomotionTransitions.script:3938`):**  
  Cyberpunk 2077's native character controller evaluates movement world direction as:
  $$\vec{d}_{\text{world}} = \text{RotByAngleXY}(\text{GetOwnerForward}(), -\text{GetInputHeading}())$$
  Where `GetOwnerForward()` is the puppet body forward (`bodyYaw`).
- **Empirical Measurement:**  
  When pressing `W` with an unholstered weapon, $\Delta\text{Move\_Body} \approx 0.02^\circ$, while $\Delta\text{Move\_Cam} = +12.51^\circ$. This proved that **locomotion physically follows the puppet body heading, not the camera gaze**.
- **Status:** **Verified Working** (Telemetry instrumentation confirmed the physics mechanism).

---

### Phase 2: Iteration 15 — Pillar 1 (Baseline Camera Rotation Sanitization)
- **Hypothesis:** During sprint-holster transitions (`Det:8`), `fpp:GetLocalOrientation()` might have been captured while twisted by $-12.6^\circ$, baking a permanent rotation into `baselineRot`.
- **Implementation:** Added `SanitizeBaselineRot(rawRot)` to force local `yaw = 0.0` upon capturing `baselineRot`.
- **In-Game Test Results:**  
  - User tested in-game and reported that **the walking drift was still present**.
  - Telemetry (`DetachedReticle.log`, lines 90890–90952) confirmed: `localRot` at activation was already `(0, 0, 0, 1)`. `[BASELINE_SANITIZE]` was never triggered.
- **Status:** **Tested — Refuted / Ineffective**.

---

### Phase 3: Iteration 16 — Locomotion Straight-Walk Alignment & Mouse Activity Gate
- **Telemetry Analysis (`DetachedReticle.log` lines 90890–90952):**
  1. *Locomotion Drift Cause:* In hipfire, active Tier 2B barrel offset compensation $C_{\text{yaw}}$ turned the body by $-C_{\text{yaw}}$ relative to camera gaze ($T_{2B} = T_{2A} - C$). Because the engine moves along `bodyYaw`, pressing `W` walked at an angle of $-C_{\text{yaw}}$ relative to the camera gaze.
  2. *Reticle Stuck Cause:* The native look integrator at RVA `0x51D462` runs **only upon DirectInput mouse events**. When moving with `W` without mouse movement, DirectInput deltas ceased, freezing the native chase gap. This locked `isSwinging = (rawGapYaw > 0.50)` permanently `true`, blocking `isResting` and preventing integral screen trim (`trimYaw`) from ever running.
- **Implementation:**
  1. Added camera-delta windowing to detect true mouse motion (`isMouseMoving`), breaking the frozen `isSwinging` deadlock.
  2. Implemented **Locomotion Straight-Walk Alignment**:
     ```lua
     if not isADS then
         local speed2D = DetachedReticle.lastSpeed2D or 0.0
         if speed2D > 0.3 then
             local locoBlend = math.max(0.0, 1.0 - math.min(1.0, (speed2D - 0.3) / 0.7))
             targetYaw = targetYaw * locoBlend
         end
     end
     ```
     When walking in hipfire, $C_{\text{yaw}}$ smoothly blends to 0, rotating the puppet body to align with camera gaze.
- **In-Game Test Results (`DetachedReticle.log` lines 90955–91343, `18:58`–`19:05`):**
  - **Locomotion Walk Drift:** **TESTED — VERIFIED WORKING BY LOGS.**  
    Lines 90965–90973 show that while walking at 1.80 m/s with `W`:
    $$\Delta\text{Move\_Cam} = +0.02^\circ, \quad \Delta\text{Move\_Body} = +0.04^\circ, \quad C_{\text{yaw}} = 0.00^\circ$$
    Drift reduced from $+12.5^\circ$ to $+0.02^\circ$. Walking forward with `W` followed the camera gaze dead straight.
  - **Reticle T3 Centering:** **TESTED — FAILED / UNRESOLVED.**  
    User reported T3 was still visibly stuck on the left.  
    Lines 91338–91342 confirmed steady-state lockup:
    ```
    [WARN][IDLE_RETICLE_OFF_CENTER] Weapon=Items.MalorianArms_Coda | Duration=22.5s | ReticleScreen=(199.7, 13.8)px | TargetErr=(dYaw:+9.19, dPitch:-0.48)deg | CompApplied=(C_yaw:+8.44, C_pitch:-0.20)deg | ReadyW=0.90 (Gate:[8.5, 12.0] Clamp:8.5)
    ```

---

### Phase 4: Root Cause Discovery — Skeletal Coordinate Frame Mismatch
Why did `TargetErr` read `dYaw = +9.19 deg` on a handgun whose physical barrel offset is only $\approx +1.49^\circ$?

1. **The Code in `init.lua`:**
   ```lua
   diffYaw = normalizeDeg(gunYaw - bodyYaw)
   ```
2. **The Coordinate Frame Conflict:**
   - `bodyYaw = player:GetWorldYaw()` measures the orientation of the **ground capsule collider** at the feet.
   - In first-person idle posture, V's upper body skeleton / torso has an **anatomical $+7.68^\circ$ twist** relative to the feet capsule.
   - The weapon is attached to the upper torso/arms via the weapon rig.
3. **The Consequence:**
   - Measuring `gunYaw - bodyYaw` measured:
     $$\text{diffYaw} = \text{BarrelOffset} (+1.49^\circ) + \text{TorsoStanceTwist} (+7.68^\circ) = +9.17^\circ \approx +9.19^\circ$$
   - Because $+9.19^\circ$ exceeded the ready stance gate limit ($\text{maxReady} = 8.5^\circ$), `readyWeight` fell to `0.90`, clamping `targetYaw` at $8.5^\circ$ and driving $C_{\text{yaw}} = +8.44^\circ$.
   - This $8.44^\circ$ over-compensation deflected the body and camera counter-rotation, projecting T3 ~200 pixels off-center to the left.
4. **Contrast with Pitch:**
   - Pitch was already computed relative to the camera socket: `diffPitch = gunPitch - socketPitch` where `socketPitch = camPitch - rPitch`. Pitch centered cleanly ($\text{dPitch} = -0.48^\circ$). Only Yaw was corrupted by mixing the feet capsule coordinate frame with the upper torso.

---

### Phase 5: Iteration 17 — Socket-Relative Yaw Compensation (`socketYaw`)
- **Fix Implemented in `init.lua`:**
  ```lua
  local socketYaw = 0.0
  if hasCamFwd then
      socketPitch = camPitch - (DetachedReticle.lastWrittenRPitch or 0.0)
      socketYaw = normalizeDeg(camYaw - rYaw)
  else
      pcall(function() socketPitch = Game.DR_GetT2BPitch() end)
      pcall(function() socketYaw = Game.DR_GetT2BYaw() end)
  end
  ...
  diffYaw = normalizeDeg(gunYaw - socketYaw)
  diffPitch = gunPitch - socketPitch
  ```
- **Architectural Rationale:**
  Because both the camera socket (`fpp`) and the weapon are mounted to the upper torso/head rig, computing `gunYaw - socketYaw` cancels out the $+7.68^\circ$ skeletal stance twist.
  This restores `diffYaw` to the true physical barrel offset:
  - Malorian Handgun: $\approx +1.49^\circ$ (well within $\text{maxReady} = 8.5^\circ$, `readyWeight` = 1.00)
  - Shotguns (Testera, Igla): $\approx +5.8^\circ$
  - Heavy weapons (HMG, Defender): $\approx +6.5^\circ$
- **Deployment Status:**
  - Deployed to `E:\Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\DetachedReticle\init.lua` on `2026-11-10 19:06:40 +0700`.
  - File hash verified: `81845D5B9835BAB95323EA9CF794D55C8F99A3563AC2197B9CC79119E14364A8`.
- **Verification Status:**  
  **UNTESTED / UNVERIFIED.**  
  As of 19:25:00, no game run has occurred since deployment (latest log is from `19:05:43`). This fix awaits in-game testing to verify whether T3 centers cleanly onto T1.

---

## 4. Verification Checkpoints for Next In-Game Test

When running the game with the Iteration 17 build, verify the following:

1. **Visual Reticle Alignment:**
   - Equip Malorian (or any handgun/rifle) in ready hipfire.
   - Stand still without moving the mouse.
   - Check if the physical gun reticle (T3) sits directly inside the camera center diamond (T1).
2. **Telemetry Log Verification (`DetachedReticle.log`):**
   - Confirm `[T2B_OFFSET_COMP]` reports:
     - `TargetErr.dYaw` $\approx +1.0^\circ$ to $+2.0^\circ$ (instead of $+9.19^\circ$).
     - `ReadyW = 1.00` (instead of `0.90`).
     - `ReticleScreen` $\approx (0.0, 0.0)\text{px}$ (instead of $(199.7, 13.8)\text{px}$).
     - `[WARN][IDLE_RETICLE_OFF_CENTER]` does not appear.
3. **Locomotion Straight-Walk Verification:**
   - Press and hold `W` to walk forward while looking at a distant reference point.
   - Confirm character walks dead-straight towards the gaze target without sideways drift.

