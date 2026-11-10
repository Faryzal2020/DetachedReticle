# Recoil Decoupling & Tier 2 Transfer — Iterative Implementation & Findings

**Target Game Version:** Cyberpunk 2077 `2.50 (Build 3.0.88.46235)`  
**Branch:** `recoil-modifying`  
**Intent:** Free Tier 1 (Camera view & center reticle) from weapon recoil effects and transfer/apply weapon recoil (Kick $\to$ Hold $\to$ Recovery) exclusively to Tier 2 (physical weapon barrel & gun reticle).

---

# iteration 1
- date: 2026-11-03 20:30 +0700
- status: untested (deployed to repo and `<GAME_ROOT>`, awaiting in-game test)
- target_goal:
  1. Split pure player look input (`dMouseYaw`, `dMousePitch`) from procedural weapon recoil/sway (`dRecoilYaw`, `dRecoilPitch`) at the existing RVA `0x51D462` hook site without requiring a second binary hook.
  2. Keep Tier 1 ($T$, camera gaze and center cyan pip) 100% free of native look-integrator recoil deltas (`dRecoil`).
  3. Transfer native weapon recoil ($\vec{W} = (W_{\text{yaw}}, W_{\text{pitch}})$) onto Tier 2 ($\text{T2B} = A - C + \vec{W}$) so the gun barrel and gun reticle climb during firing, pause during `RecoilHoldDuration`, and recover back to the camera reticle over `RecoilRecoveryTime` without fighting the Tier 2A mouse-chase filter ($A$) or Tier 2B active barrel offset compensation ($C$).
  4. Verify via telemetry probes whether any secondary skeletal camera animation (`'RightShoot'` / `AnimFeature_CameraRecoil`) shakes the rendered world camera independently of `sub_51CFA8`.
- verified binary & architectural basis:
  1. Disassembly of `sub_51CFA8` (`Cyberpunk2077.exe` RVAs `0x51CFA8`–`0x51D51F`) confirmed the stack frame layout at the RVA `0x51D462` hook callsite:
     - Prologue (`0x51CFA8`–`0x51CFCB`): `mov rax, rsp`, 5 register pushes (`28h` bytes), `lea rbp, [rax-68h]`, `sub rsp, 140h` (`caller_rsp = rbp - 100h`).
     - Inside `MouseLookRelay` after pushing the 8-byte return address and executing `sub rsp, 0D8h`: `caller_rsp = rsp + 0E0h`.
     - At `0x51D3DF`–`0x51D3F4`:
       - `[rbp - 78h]` holds pure `dMouseYaw` (float).
       - `[rbp - 7Ch]` holds pure `dMousePitch` (float).
       - `[caller_rsp + 48h]` = `[rsp + 128h]` holds native `dRecoilYaw` (float, written by `sub_DA86E8` $\to$ `sub_648844` at `0x51D273`).
       - `[caller_rsp + 44h]` = `[rsp + 124h]` holds native `dRecoilPitch` (float, written by `sub_DA86E8` $\to$ `sub_648844` at `0x51D273`).
  2. Separating $A$ (Tier 2A mouse chase) from $\vec{W}$ (Tier 2 recoil offset) prevents the chase filter (`ProcessMouseAim` Step 5) from prematurely pulling recoil back during `RecoilHoldDuration` and prevents double-recovery undershoot when the native recoil state machine unwinds $\vec{W} \to 0$.
- changes_made:
  1. [`src/Hooks/MouseLookRelay.asm`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/MouseLookRelay.asm#L36-L61):
     - Reads `[rsp+128h]` (`dRecoilYaw`), `[rsp+124h]` (`dRecoilPitch`), `[rbp-78h]` (`dMouseYaw`), and `[rbp-7Ch]` (`dMousePitch`) into stack scratch slots `[rsp+0C8h..0D4h]` and passes `lea r9, [rsp+0C8h]` (`aSplitProbe`) as the 4th argument to `OnNativeMouseAim`.
  2. [`src/Hooks/InputHook.hpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.hpp#L27-L133) & [`src/Hooks/InputHook.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.cpp#L119-L416):
     - Computes pure look input `dInputYaw = aRawYaw - dRecoilYaw` and `dInputPitch = aRawPitch - dRecoilPitch`.
     - Advances Tier 1 target $T$ (`s_targetYaw`, `s_targetPitch`) exclusively by `(dInputYaw, dInputPitch)`.
     - Accumulates native recoil deltas into `s_recoilYaw` / `s_recoilPitch` ($\vec{W}$), with a `0.35s` post-idle orphan bleed (using `s_compSpeedSettled`) to smoothly clear any unrecovered drift if reload/weapon-swap aborts native recovery.
     - Updates physical socket output to `outYaw = dAYaw - dCompYaw + effDRecoilYaw` and `outPitch = dAPitch - dCompPitch + effDRecoilPitch` ($\text{T2B} = A - C + \vec{W}$).
     - Updates camera residual to `s_residualYaw = (s_targetYaw - s_aimYaw) + s_compYaw - s_recoilYaw` and `s_residualPitch = (s_targetPitch - s_aimPitch) + s_compPitch - s_recoilPitch` so $\text{T2B} + R \equiv T$.
     - Updates `s_displayT2BYaw` and `s_displayT2BPitch` to include `+ s_recoilYaw` / `+ s_recoilPitch` so the gravity-up yaw projection axis in `init.lua` matches the physical socket pitch during recoil.
  3. [`src/Main.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Main.cpp#L142-L437):
     - Registered RTTI native functions `DR_GetRecoilYaw`, `DR_GetRecoilPitch`, `DR_GetLastDeltaRecoilYaw`, `DR_GetLastDeltaRecoilPitch`, `DR_GetSplitErrYaw`, and `DR_GetSplitErrPitch`.
  4. [`bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua#L450-L960):
     - Added `wYaw` / `wPitch` check to `settling` (`|wYaw| + |wPitch| > 0.05`) and defined `isRecoiling = (|wYaw| + |wPitch| > 0.02)`.
     - Protected Tier 2B (`DR_SetBarrelOffset` and `trimYaw`/`trimPitch`) from fighting recoil by gating `isResting` on `not isRecoiling` and holding `targetYaw`/`targetPitch` at `lastSettledCompTargetYaw`/`Pitch` while `isRecoiling` is true.
     - Added `[RECOIL] W=(...) dRec=(...) splitErr=(...)` telemetry to `[F=...]` per-frame logs, `[GUN_OFFSET_MONITOR]`, `[T2B_OFFSET_COMP]`, `[BALLISTICS RECORD]`, and the CET ImGui status overlay.
- expected_outcome:
  1. **Probe P-R1 (`splitErr`):** When moving the mouse and firing (without gamepad stick input), `splitErr=(+0.00000,+0.00000)`. When firing hands-off, `dRec` is positive during Kick, `0` during Hold, and negative during Recovery, while `tPitch` does not change.
  2. **Probe P-R2 (Tier 1 Camera Stability):** During hands-off full-auto firing, `tPitch` stays constant; `pitchErr = camPitch - tPitch` measures whether any secondary skeletal camera bone animation shakes the rendered camera (`0.000 deg` = completely rock-solid camera; transient spikes = skeletal camera bone shake).
  3. **Probe P-R3 (Tier 2 Gun Reticle Climb & Recovery):** During hands-off firing, `W=(wYaw, wPitch)` climbs with each shot, the Gun Reticle (`ReticleScreen`) climbs away from the stationary center Camera Reticle, bullets impact at the climbing Gun Reticle, and upon stopping fire, `W` and `ReticleScreen` smoothly recover back to `(0, 0)` over the weapon's native recovery time.
  4. **Probe P-R4 (Simultaneous Mouse Tracking + Recoil):** Moving the mouse while firing in full-auto moves the center Camera Reticle smoothly while the Gun Reticle both trails along the mouse path and kicks upward from recoil, recovering onto the new mouse aim point when firing stops.
- test_procedure:
  1. Launch game, enable **Verbose Debug Logging** in the CET Detached Reticle window (or `config.json`), and equip a regular ranged weapon (e.g. Lexington or Copperhead).
  2. **Test A (Hands-Off Single Shot & Full-Auto Burst):** Stand still without touching the mouse, fire 1 single shot, pause 1 second, then fire a 10–15 round full-auto burst and wait 1 second after stopping.
  3. **Test B (Mouse Panning + Full-Auto Spray):** Sweep the mouse horizontally/diagonally while firing a full-auto burst, then stop firing and hold the mouse still for 1 second.
  4. Inspect `DetachedReticle.log` for `[RECOIL]`, `[P1]`, `[SEED]`, and `[GUN_OFFSET_MONITOR]` lines.

# iteration 2
- date: 2026-11-03 20:47 +0700
- status: untested (deployed to repo and `<GAME_ROOT>`, awaiting in-game test)
- previous_iteration_results (Iteration 1 Playtest & Telemetry Analysis):
  1. **User Observation:** Moving the mouse did not move the camera (Tier 1), but moved the gun reticle / weapon (Tier 2) instead!
  2. **Log Telemetry (`DetachedReticle.log` `20:41:27`–`20:42:02`, `F=1670`–`F=3204`):**
     - When moving the mouse without firing (`F=1795`–`F=1966`), `dRec` and `W` received all the mouse movement deltas (`F=1850`: `W=(-20.220,-6.300) dRec=(-3.2400,-1.0800)`, `F=1857`: `W=(-45.000,-1.620) dRec=(-3.9000,+0.5400)`), while `tPitch` stayed frozen at `-6.4918°` and `camYaw` (`-4.77°`) / `camPitch` (`-6.59°`) remained rock-solid in world space!
     - Then, `0.35s` after mouse movement stopped (`F=1967`–`F=2029`), the idle bleed smoothly decayed `W` from `(-16.620,+5.220)` back to `(+0.000,+0.000)` while `camYaw` (`-4.75°`) and `camPitch` (`-6.61°`) never budged.
     - **Probe P-R1 (`splitErr`) Verified 100%:** Across the entire session (`F=1670`–`F=3204`), `splitErr=(+0.00000,+0.00000)` on every single frame, proving that `[rbp-78h] + [rsp+128h] == xmm6` and `[rbp-7Ch] + [rsp+124h] == xmm7` with zero residual error.
     - **Tier 1 Counter-Rotation (`R = (T - A) + C - W`) Verified 100%:** Even when `W` was deflected by up to `45°` in yaw and `14.7°` in pitch (`F=1819`), `fpp:SetLocalTransform` counter-rotated the camera so Tier 1 remained completely motionless in world space while Tier 2 moved across the screen and returned smoothly when `W` decayed to `0`.
  3. **Root Cause Identified in `sub_51CFA8` (`Cyberpunk2077.exe` RVAs `0x51D310`–`0x51D3F4`):**
     - The two stack pairs in `MouseLookRelay.asm` were swapped!
     - Disassembly of `0x51D32D`–`0x51D3B8` shows:
       - `0x51D32D`–`0x51D352`: queries `CameraMouseX` and stores pure **`dMouseYaw`** into **`[caller_rsp + 48h]` (`[rsp + 128h]` inside `MouseLookRelay`)**.
       - `0x51D35E`–`0x51D385`: queries `CameraMouseY` and stores pure **`dMousePitch`** into **`[caller_rsp + 44h]` (`[rsp + 124h]` inside `MouseLookRelay`)**.
       - `0x51D388`–`0x51D3B0`: calls `[r10 + 350h]` on the weapon recoil subsystem (`rdi + 0B8h`) with `lea r8, [rbp - 80h]`, which writes **`dRecoilPitch`** into **`[rbp - 7Ch]`** and **`dRecoilYaw`** into **`[rbp - 78h]`**!
- target_goal:
  1. Swap the two stack slot pairs in [`src/Hooks/MouseLookRelay.asm`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/MouseLookRelay.asm#L40-L54) so `[rbp-78h]`/`[rbp-7Ch]` are passed as `dRecoilYaw`/`dRecoilPitch` (`aSplitProbe[0..1]`) and `[rsp+128h]`/`[rsp+124h]` are passed as `dMouseYaw`/`dMousePitch` (`aSplitProbe[2..3]`).
  2. Increase `s_recoilIdleTimer` threshold in [`src/Hooks/InputHook.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.cpp#L368-L370) from `0.35f` to `0.50f` so slow-firing weapons with long `RecoilHoldDuration` complete their native recovery naturally before any orphan residual bleed engages.
- changes_made:
  1. [`src/Hooks/MouseLookRelay.asm`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/MouseLookRelay.asm#L40-L54):
     - Loaded `[rbp-78h]` (`dRecoilYaw`) into `[rsp+0C8h]` and `[rbp-7Ch]` (`dRecoilPitch`) into `[rsp+0CCh]`.
     - Loaded `[rsp+128h]` (`dMouseYaw`) into `[rsp+0D0h]` and `[rsp+124h]` (`dMousePitch`) into `[rsp+0D4h]`.
  2. [`src/Hooks/InputHook.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.cpp#L368-L370):
     - Adjusted post-idle orphan bleed delay from `0.35f` to `0.50f`.
- expected_outcome:
  1. Moving the mouse moves Tier 1 (Camera view & center reticle) immediately while Tier 2 chases it smoothly with `W=(+0.000,+0.000)` and `dRec=(+0.0000,+0.0000)`.
  2. Firing a weapon produces non-zero `dRec` and `W`, causing Tier 2 (gun barrel and gun reticle) to kick upward, hold, and recover back to Tier 1 while Tier 1 remains stationary when hands-off or tracks pure mouse input when moving the mouse.
- test_procedure:
  1. Launch game and verify normal mouse look moves the camera (Tier 1) while `W` stays `(0, 0)`.
  2. **Test A (Hands-Off Single Shot & Full-Auto Burst):** Stand still without touching the mouse, fire 1 single shot, pause 1 second, then fire a 10–15 round full-auto burst and wait 1 second after stopping.
  3. **Test B (Mouse Panning + Full-Auto Spray):** Sweep the mouse while firing a full-auto burst, then stop firing and hold the mouse still for 1 second.

# iteration 3
- date: 2026-11-03 21:23 +0700
- status: untested (deployed to repo and `<GAME_ROOT>`, awaiting in-game test)
- previous_iteration_results (Iteration 2 Playtest & Telemetry Analysis):
  1. **User Observation:** Moving the mouse moves Tier 1 (`T`, camera) now, and recoil applies to Tier 2 (`T2`, gun reticle and weapon barrel). However, after every recoil or burst fire, Tier 2 returns not to the center (`(0, 0)`), but to a random point around the reticle and sits there before returning to the center after ~1 second.
  2. **Log Telemetry (`DetachedReticle.log` `21:08:22`–`21:08:55`, `F=3156`–`F=5171`):**
     - **Verified Working:**
       - Mouse look moves Tier 1 immediately while `W=(+0.000,+0.000)` when not firing.
       - `splitErr=(+0.00000,+0.00000)` across all frames (`F=3156`–`F=5171`).
       - During hands-off bursts (`#31–#34` at `F=4155`–`F=4186`, `#35–#40` at `F=4296`–`F=4350`, `#41–#45` at `F=4470`–`F=4509`), `tPitch` stays completely locked at `-14.1388°` while `W` climbs (`W=(-0.050,+4.196)` at `F=4509`, `ReticleScreen=(1.2,-124.3)px`) and shots follow the climbing gun reticle (`[BALLISTICS RECORD #31–#45]`).
     - **Verified Root Cause of Random Post-Burst Offset & 1-Second Delay:**
       - Every ranged weapon base in vanilla TweakDB (e.g. [`base_rifle_assault.tweak`](file:///E:/Cyberpunk%202077/tools/redmod/tweaks/base/gameplay/static_data/database/items/weapons/ranged/bases/base_rifle_assault.tweak#L300-L314)) defines **`RecoilDrift`**:
         - `BaseStats.RecoilDriftRandomRangeMin = 0.6f`
         - `BaseStats.RecoilDriftRandomRangeMax = 0.9f`
         - `BaseStats.RecoilMagForFullDrift = 3.f`
       - When native recovery begins after `RecoilHoldDuration`, the engine does **not** recover toward `(0, 0)`. Instead, it picks a random 2D point $\vec{D}_{\text{drift}} = (D_{\text{yaw}}, D_{\text{pitch}})$ on a circle of radius $r \in [0.6^\circ, 0.9^\circ] \times \min(1, |\vec{W}_{\text{peak}}| / 3^\circ)$ and interpolates along $-(\vec{W}_{\text{peak}} - \vec{D}_{\text{drift}})$ over `RecoilRecoveryTime` (`0.18s`, 17 frames):
         - **Burst #29–#30 (`F=3740`–`F=3777`):** $\vec{W}_{\text{peak}} = (+0.010^\circ, +1.346^\circ)$. Native recovery (`F=3760`–`F=3777`) moved along $(-0.371^\circ, -1.313^\circ)$ (`dRecYaw/dRecPitch = 0.282` every frame) and stopped at $\vec{D}_{\text{drift}} = (-0.361^\circ, +0.033^\circ)$ ($|\vec{D}_{\text{drift}}| = 0.362^\circ$).
         - **Burst #31–#34 (`F=4155`–`F=4211`):** $\vec{W}_{\text{peak}} = (+0.008^\circ, +3.087^\circ)$. Native recovery (`F=4195`–`F=4211`) moved along $(-0.545^\circ, -2.525^\circ)$ and stopped at $\vec{D}_{\text{drift}} = (-0.537^\circ, +0.562^\circ)$ ($|\vec{D}_{\text{drift}}| = 0.777^\circ \in [0.6^\circ, 0.9^\circ]$, `ReticleScreen=(15.4,-12.6)px`).
         - **Burst #41–#45 (`F=4470`–`F=4534`):** $\vec{W}_{\text{peak}} = (-0.050^\circ, +4.196^\circ)$. Native recovery (`F=4518`–`F=4534`) moved along $(-0.671^\circ, -3.853^\circ)$ (`dRecYaw/dRecPitch = 0.174` every frame) and stopped at $\vec{D}_{\text{drift}} = (-0.721^\circ, +0.343^\circ)$ ($|\vec{D}_{\text{drift}}| = 0.798^\circ \in [0.6^\circ, 0.9^\circ]$, `ReticleScreen=(20.8,-6.1)px`).
       - Once native recovery stopped at $\vec{D}_{\text{drift}}$ (`dRec = (0, 0)` at `F=4535`), `s_recoilIdleTimer` waited **`0.50s`** (`F=4535`–`F=4580`) while `W` sat parked at `(-0.721°, +0.343°)`, and then took another **`0.45s`** (`F=4581`–`F=4620`) to exponentially bleed `W` back to `(0, 0)` (`0.50s + 0.45s = 0.95s` total!).
- target_goal:
  1. Eliminate `RecoilDrift` during Tier 2 recovery so that after `RecoilHoldDuration`, Tier 2 recovers in a straight line directly from $\vec{W}_{\text{peak}}$ to `(0, 0)` (center reticle) over `RecoilRecoveryTime`, without veering off to $\vec{D}_{\text{drift}}$ and without any post-recovery pause.
- changes_made:
  1. [`src/Hooks/InputHook.hpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.hpp#L94-L104) & [`src/Hooks/InputHook.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.cpp#L359-L465):
     - Added phase-aware recoil state (`s_recoilPeakYaw`, `s_recoilPeakPitch`, `s_recoilDriftPitch`, `s_recoilRecovering`).
     - During **Kick** (`dRecoilPitch > 1e-5f`), accumulate `(dRecoilYaw, dRecoilPitch)` directly and record $\vec{W}_{\text{peak}} = (\text{s\_recoilYaw}, \text{s\_recoilPitch})$.
     - During **Hold** (`|dRecoil| <= 1e-5f` while `!s_recoilRecovering`), hold $\vec{W}$ steady for `RecoilHoldDuration`.
     - During **Native Recovery** (`dRecoilPitch < -1e-5f`), set `s_recoilRecovering = true`. On the first recovery frame, compute `s_recoilDriftPitch` from the native recovery ray slope $m = \text{dRecoilYaw}/\text{dRecoilPitch}$ and the `RecoilDrift` radius (`0.75° * min(1, |W_peak| / 3.0°)`), then scale each native recovery step by $W_{\text{peak,pitch}} / (W_{\text{peak,pitch}} - D_{\text{drift,pitch}})$ and steer yaw radially along `s_recoilYaw * (effDRecoilPitch / s_recoilPitch)` directly toward `(0, 0)`.
     - Once `s_recoilRecovering` is true, if native `dRecoilPitch` drops to `0` with any tiny residual left, finish the remaining fraction immediately at native recovery speed (`W_peak / 0.18s`) with **zero** idle wait (`s_recoilIdleTimer` is only used when `!s_recoilRecovering`, e.g., if a reload aborts recovery before it starts).
- expected_outcome:
  1. During firing, Tier 2 climbs along the weapon's recoil pattern while Tier 1 remains unaffected by recoil.
  2. After firing stops and `RecoilHoldDuration` (`~0.08s`) elapses, Tier 2 recovers in a single smooth motion directly back to `(0, 0)` (center reticle) over `RecoilRecoveryTime` (`~0.18s`), with no random sideways/upward stop point and no 1-second delay.
- test_procedure:
  1. Launch game and fire single shots, short bursts (3–5 rounds), and longer full-auto bursts both hands-off and while moving the mouse.
  2. Verify visually and in `DetachedReticle.log` that Tier 2 returns directly to the center reticle after each shot/burst without stopping at a random point around the reticle.

# iteration 4
- date: 2026-11-03 22:00 +0700
- status: untested (deployed to repo and `<GAME_ROOT>`, awaiting in-game test)
- previous_iteration_results (Iteration 3 Playtest & Telemetry Analysis):
  1. **User Observations:**
     - **Issue A (HMG Zoomed Recoil Recovery Stall at Top-Left):** Recoil recovery works much better for regular rifles like the Copperhead, but for the HMG when shooting while zoomed in (holding right-click), after shooting stops, the gun reticle sits at the top-left of the center reticle before moving to the center less than a second later. This does not happen when shooting the HMG unzoomed.
     - **Issue B (Horizontal Mouse Pan Camera Shake / Pull Toward Gun):** When using the Copperhead or other guns in an unholstered position and not firing, after moving the mouse horizontally and stopping, while the gun/hand is catching up, the camera shakes sideways with a slight movement toward where the gun is coming from.
  2. **Log Telemetry (`DetachedReticle.log` `21:37:01`–`21:39:49`, `BALLISTICS RECORD #61–#140`, `F=18751`–`F=19742`, and `gamelog.log` lines 11315–11366):**
     - **Verified Root Cause of Issue A (HMG Zoomed Top-Left Stall):**
       - In `gamelog.log` (`21:38:08`–`21:38:14`, `Ctrl: Crosshair_Custom_HMG`) and `DetachedReticle.log` (`BALLISTICS RECORD #114–#125`):
         - Before firing while holding right-click (`#114`): `State: 4` (`Aim`), `Zoom: 1.50`, `Divergence = 0.40 deg`, `RecoilW = (+0.00, +0.00)`.
         - When firing starts while holding right-click (`#115–#122`): `PlayerStateMachine.Crosshair` (`crosshairState`) transitions from `4` (`Aim`) to **`8` (`HipFire`)** (`State: 8 | Zoom: -1`).
         - For regular rifles (`Copperhead`), holding right-click sets `upperBodyState = 6` (`Aim`), so `isADS = (crosshairState == 4 or upperBodyState == 6)` remains `true` throughout firing. For Heavy Machine Guns (`Preset_HMG_Default`), `upperBodyState` is never `6` (HMG has no iron-sight upper-body state; right-click only applies optical zoom in the hip-cradle posture). Thus, when `crosshairState` changes from `4` to `8` on the first zoomed HMG shot, `isADS` flips from `true` to `false` while `isRecoiling == true`.
         - In [`init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua#L829-L836), `isADS ~= DetachedReticle.lastTrimADS` triggered mid-burst and reset `DetachedReticle.lastSettledCompTargetYaw = 0.0` and `DetachedReticle.lastSettledCompTargetPitch = 0.0`.
         - Immediately below at lines 853–855, `if isRecoiling then targetYaw = DetachedReticle.lastSettledCompTargetYaw or targetYaw` evaluated `0.0 or targetYaw` (which is `0.0` in Lua because `0.0` is truthy), passing `Game.DR_SetBarrelOffset(0.0, 0.0)` throughout the entire burst!
         - Consequently, Tier 2B barrel compensation $\vec{C}$ decayed to `(0, 0)` during firing. When firing stopped and `RecoilW` reached `(-0.00, +0.03)` at `#123` (`21:38:09`), the HMG barrel was sitting at its uncompensated hip-cradle anatomical angle (`+3.4°` left yaw, `+5.9°` up pitch = `7.11 deg`, screen `(-94.5, -167.7) px` **top-left**), and then over the next `~0.4s` (`#123` $\to$ `#124` `1.98 deg` $\to$ `#125` `0.56 deg`) Tier 2B filtered $\vec{C}$ from `(0, 0)` back to `(+3.4°, +5.9°)` at `s_compSpeedSettled = 12.0`.
     - **Verified Root Cause of Issue B (Horizontal Pan Camera Shake & Drift Toward Gun):**
       - In `DetachedReticle.log` (`F=19690`–`F=19742`, horizontal pan left stopping at `F=19690` with `T_world = -78.941°`, and `F=19139`–`F=19174`, horizontal pan right stopping at `F=19139` with `T_world = -160.35°`):
         - On every frame $k$ during horizontal catch-up, the rendered world camera yaw (`[P1] camYaw`) obeys:
           $$\text{camYaw}_k = \text{bodyYaw}_k + \text{rYaw}_{k-1} = T_{\text{world}} + \text{dBody}_k$$
           because `MouseLookRelay` in `InputHook.cpp` updates the puppet's `bodyYaw` (`[rcx+9Ch]`) for frame $k$, and the engine evaluates the scene-graph camera world transform (`bodyYaw_k + fppLocalYaw`) **before** CET's `onUpdate` writes frame $k$'s `s_residualYaw` (`rYaw_k`) via `fpp:SetLocalTransform` (which takes effect on frame $k+1$).
         - Because $\text{camYaw}_k = T_{\text{world}} + \text{dBody}_k$:
           1. **Drift toward the catching-up gun:** At `F=19691` (right when the left pan stops and the gun is catching up from the right with `dBody = +3.209°`/frame), `camYaw` is `-75.702°` (`T_world + 3.239°`). As the gun catches up and `dBody` decays from `+3.209°` to `0°` (`F=19691`–`F=19739`), `camYaw` drifts backward by **`-3.24°` (`-75.702°` $\to$ `-79.002°`) toward where the gun is coming from**.
           2. **Sideways camera shake:** Because raw wall-clock `dt` between `MouseLookRelay` calls fluctuates frame-to-frame, `dBody` jumps (`+1.946°` at `F=19690` $\to$ `+3.209°` at `F=19691` $\to$ `+2.029°` at `F=19692` $\to$ `+2.223°` at `F=19693`), shaking `camYaw` left and right by **`dCam = +1.289°, -1.179°, +0.194°`** on consecutive frames!
           3. **Post-swing Tier 2B tail pull:** During a `50°` horizontal swing (`SWINGING`), upper-body turn-lag animation twists `diffYaw` to `-1.19°`, pulling `cYaw` (`s_compYaw`) away from its settled value and causing `cYaw` to drift from `-0.38°` back to `+0.70°` (`F=19720`–`F=19742`) after the swing ends.
- target_goal:
  1. Preserve Tier 2B barrel compensation $\vec{C}$ across zoomed HMG bursts so that when `RecoilW` finishes recovering to `(0, 0)`, the HMG reticle is already at the center reticle without stalling at the top-left.
  2. Eliminate the 1-frame scene-graph `bodyYaw` lead, `dt` timing jitter, and mid-swing Tier 2B target corruption during horizontal mouse pans so `camYaw` stays locked at $T_{\text{world}}$ with zero sideways shake and zero drift toward the catching-up gun.
- changes_made:
  1. [`bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua#L828-L870):
     - Decoupled weapon-change resets from `isADS` transitions: `lastSettledCompTargetYaw` and `lastSettledCompTargetPitch` are only reset when `weaponName ~= DetachedReticle.lastTrimWeapon` (never zeroed when `crosshairState` toggles `4 <-> 8` during zoomed HMG firing), and `trimYaw`/`trimPitch` are not reset on `isADS` changes for `isHeavyWeapon`.
     - Added `isSwinging = (rawGapYaw > 0.50) or (rawGapPitch > 0.50)` and locked `targetYaw, targetPitch` to `lastSettledCompTargetYaw, lastSettledCompTargetPitch` whenever `isRecoiling or isSwinging or (readyWeight < 0.999 and hasSettledComp and (stateStr == "HIP" or stateStr == "ADS"))`, updating `lastSettledCompTargetYaw/Pitch` only when genuinely settled (`not isRecoiling and not isSwinging and readyWeight >= 0.999`).
  2. [`src/Hooks/InputHook.hpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.hpp#L130-L135) & [`src/Hooks/InputHook.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.cpp#L197-L505):
     - Added exponentially smoothed frame delta `s_smoothedDt` (`0.75 * s_smoothedDt + 0.25 * dt`) for the chase/compensation filters so wall-clock thread jitter cannot cause frame-to-frame velocity spikes in `dAYaw`.
     - Extracted `ComputeChaseStep` and added 1-frame scene-graph lead compensation (`predNextDBodyYaw = nextDAYaw - nextDCompYaw`) to `s_residualYaw` (`s_residualYaw = (s_targetYaw - s_aimYaw) + s_compYaw - s_recoilYaw - predNextDBodyYaw`), pre-cancelling the next frame's puppet `bodyYaw` step in the scene graph before CET's next `fpp:SetLocalTransform` is evaluated.
- expected_outcome:
  1. Firing the HMG while zoomed in (holding right-click) and releasing trigger recovers the gun reticle directly to the center reticle without stalling at the top-left for ~0.4s.
  2. Panning the mouse horizontally and stopping with an unholstered weapon keeps the camera (`camYaw`) stationary while the gun/hand catches up, without shaking sideways or drifting toward the gun.
- test_procedure:
  1. Equip HMG, hold right-click (zoomed in), fire a burst, and stop firing while still holding right-click; verify the gun reticle returns directly to center without pausing at the top-left.
  2. Equip Copperhead (unholstered, not firing), pan the mouse horizontally left and right and stop abruptly; verify the camera remains steady without shaking sideways or drifting toward the catching-up gun.

# iteration 5
- date: 2026-11-04 08:42 +0700
- status: untested (deployed to repo and `<GAME_ROOT>`, awaiting in-game test)
- previous_iteration_results (Iteration 4 Playtest & Extended Fire Design Goal):
  1. **User Observation & Design Request:**
     - Iteration 4 resolved the zoomed HMG post-burst top-left stall and horizontal pan camera shake (`d3cc8ac` merged into `testing`).
     - During extended full-auto firing (e.g., HMG or LMG belts, where vanilla `BaseStats.RecoilMaxLength = 30.0f` allows recoil to climb up to `30°`), we need a **"rubber leash" (Option A Radial Soft-Wall Attenuation)** mechanic on Tier 2 recoil pull so the gun reticle never climbs past a configurable maximum distance from the center reticle, with a new configuration section for 1–2 tunable parameters.
- target_goal:
  1. Implement **Option A Radial Soft-Wall Attenuation ("Rubber Leash")** on Tier 2 recoil accumulation $\vec{W}$ in [`InputHook::ProcessMouseAim`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.cpp) so outward recoil kicks are progressively resisted by $g_{\text{rad}}(r) = 1 - (r / R_{\text{max}})^p$ as $r = |\vec{W}| \to R_{\text{max}}$ and never exceed $R_{\text{max}}$, while preserving tangential jitter along the leash boundary so sustained HMG/LMG fire remains lively.
  2. Preserve exact native `RecoilRecoveryTime` duration when releasing the trigger after a leashed burst by tracking the unattenuated shadow native recoil (`s_nativeRecoilYaw`, `s_nativeRecoilPitch`, `s_nativeRecoilPeakYaw`, `s_nativeRecoilPeakPitch`) for the recovery span denominator.
  3. Add a new configuration section (**Tier 2 Recoil Rubber Leash**) in `Config`, NativeSettings UI, and CET ImGui overlay with two configurable parameters:
     - `recoilMaxRadius` ($R_{\text{max}}$, default `7.0` deg, `0.0` = unlimited)
     - `recoilLeashCurve` ($p$, default `1.5`, power-law resistance exponent)
- changes_made:
  1. [`src/Hooks/InputHook.hpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.hpp) & [`src/Hooks/InputHook.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.cpp):
     - Added `s_recoilMaxRadius` (default `7.0f`), `s_recoilLeashCurve` (default `1.5f`), and shadow unattenuated native recoil tracking (`s_nativeRecoilYaw`, `s_nativeRecoilPitch`, `s_nativeRecoilPeakYaw`, `s_nativeRecoilPeakPitch`) plus `SetRecoilLeashParams` / `GetRecoilMaxRadius` / `GetRecoilLeashCurve`.
     - During Kick, decomposed `(dRecoilYaw, dRecoilPitch)` into outward radial component $\Delta W_{\text{rad}}\,\hat{u}$ and tangential component $\Delta\vec{W}_{\perp}$, attenuating outward climb by $1 - (r / R_{\text{max}})^p$ and clamping $|\vec{W}| \le R_{\text{max}}$ while retaining `50%` tangential jitter at the rim.
     - During Native Recovery, scaled native recovery steps by `s_recoilPeakPitch / (s_nativeRecoilPeakPitch - s_recoilDriftPitch)` so leashed bursts still recover smoothly over the full `RecoilRecoveryTime`.
  2. [`src/Main.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Main.cpp):
     - Registered RTTI functions `DR_SetRecoilLeashParams`, `DR_GetRecoilMaxRadius`, and `DR_GetRecoilLeashCurve`.
  3. [`bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua):
     - Added `recoilMaxRadius = 7.0` and `recoilLeashCurve = 1.5` to `Config`, `LoadConfig`, `SyncRecoilLeashParams`, NativeSettings subcategory `/detachedReticle/recoilLeash` ("Tier 2 Recoil Rubber Leash"), CET ImGui section, and console setters `SetRecoilMaxRadius` / `SetRecoilLeashCurve`.
- expected_outcome:
  1. Short bursts feel natural, while extended full-auto firing (HMG / LMG) smoothly decelerates outward climb against the rubber leash and dances around the $R_{\text{max}}$ (`7.0°` default) boundary without ever escaping further away.
  2. Releasing the trigger after a sustained leashed burst recovers smoothly to the center reticle over normal `RecoilRecoveryTime`.
- test_procedure:
  1. Fire extended 30–50 round bursts with HMG / LMG / Copperhead and verify the gun reticle stays bounded within `recoilMaxRadius` while remaining lively at the boundary.
  2. Adjust **Max Recoil Leash Angle** (`recoilMaxRadius`) and **Leash Resistance Curve** (`recoilLeashCurve`) in CET overlay or NativeSettings to verify real-time responsiveness.

# iteration 6
- date: 2026-11-04 09:38 +0700
- status: untested (deployed to repo and `<GAME_ROOT>`, awaiting in-game test)
- previous_iteration_results (Iteration 5 Playtest & Log Analysis):
  1. **User Observation:**
     - Confirmed the **Option A Recoil "Rubber Leash"** (`# iteration 5`) is working in-game.
     - Reported a bug when equipping an LMG (`Items.Preset_Defender_Military`): the resting hip-position of the gun points to the top-left of screen center (`T2A -> T2B` barrel offset compensation was not moving for the LMG), whereas other regular guns worked normally.
  2. **Root Cause Verified from [`DetachedReticle.log`](file:///E:/Cyberpunk%202077/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/DetachedReticle.log#L14049-L14614) (`09:29:39`–`09:29:45`):**
     - When `Weapon=Items.Preset_Defender_Military` (`gamedataItemType.Wea_LightMachineGun`) is held at rest in hip-fire (`Mode=RESTING(HIP)`):
       - `ReticleScreen = (-153.5, -167.3) px` (pointing top-left)
       - `TargetErr = (dYaw: +6.37 deg, dPitch: +7.07 deg, Total: 9.53 deg)`
       - `ReadyW = 0.00 | CompApplied = (C_yaw: +0.00 deg, C_pitch: +0.00 deg)`
     - In [`init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua), `weapon:IsHeavyWeapon()` returns `true` only for turret HMGs (`Wea_HeavyMachineGun`), **not** for Light Machine Guns (`Wea_LightMachineGun`, such as the Constitutional Arms Defender and Midnight Arms MA70 HB).
     - Because `isHeavyWeapon` was `false` for the LMG, the Tier 2B ready-stance gate used the regular rifle thresholds (`maxReady = 2.5 deg`, `maxBlend = 4.0 deg`, `maxClamp = 2.0 deg`). Since the LMG's hip-cradle barrel offset has `maxAngle = 7.07 deg > maxBlend (4.0 deg)`, `readyWeight` evaluated to `0.00`, completely disabling Tier 2B barrel compensation (`CompApplied = 0.00 deg`) and leaving the gun barrel pointing `+6.37°` left and `+7.07°` up (top-left of center).
- target_goal:
  1. Detect Light Machine Guns (`isLMG`, via `WeaponObject.GetWeaponType(itemID)` / `RPGManager.GetItemType(itemID)` matching `Wea_LightMachineGun` and item name fallback for `Defender` / `MA70` / `LMG`) in [`init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua).
  2. Apply the heavy hip-cradle Tier 2B gate (`maxReady = 8.5 deg`, `maxBlend = 12.0 deg`, `maxClamp = 8.5 deg`) whenever `isHeavyWeapon or isLMG`, and widen the C++ barrel compensation clamp in [`InputHook::SetBarrelOffset`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.cpp) and [`InputHook::ProcessMouseAim`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.cpp) from `±8.0°` to `±10.0°` so the LMG's `+7.07°` pitch offset plus integral trim never saturates.
  3. On `HIP <-> ADS` transitions (`isADS ~= DetachedReticle.lastTrimADS`) for non-HMG weapons (`not isHeavyWeapon`, which includes LMGs since LMGs have a true iron-sight ADS posture at `0°` offset vs. `+6.4°, +7.1°` in hip-fire), reset `lastSettledCompTargetYaw` and `lastSettledCompTargetPitch` alongside `trimYaw`/`trimPitch` so Tier 2B transitions cleanly between hip-cradle and iron-sight ADS even while moving the mouse.
- changes_made:
  1. [`bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua):
     - Added `isLMG` detection via `WeaponObject.GetWeaponType(itemID)` / `RPGManager.GetItemType(itemID)` (`Wea_LightMachineGun`) and `weaponName` fallback (`Defender`, `MA70`, `LMG`, `LightMachineGun`).
     - Enabled heavy hip-cradle gate (`useHeavyCradleGate = isHeavyWeapon or isLMG`: `maxReady = 8.5`, `maxBlend = 12.0`, `maxClamp = 8.5`).
     - Reset `lastSettledCompTargetYaw = nil` and `lastSettledCompTargetPitch = nil` on `isADS ~= DetachedReticle.lastTrimADS` when `not isHeavyWeapon`.
  2. [`src/Hooks/InputHook.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.cpp):
     - Widened `s_targetCompYaw`/`s_targetCompPitch` and `s_compYaw`/`s_compPitch` clamp bounds from `[-8.0f, 8.0f]` to `[-10.0f, 10.0f]`.
- expected_outcome:
  1. Equipping an LMG (`Defender` or `MA70`) in resting hip-fire (`RESTING(HIP)`) yields `ReadyW = 1.00`, `CompApplied ≈ (+6.37°, +7.07°)`, and centers the gun reticle at `(0, 0)` instead of pointing to the top-left.
  2. Transitioning between hip-fire and ADS with an LMG smoothly aligns the reticle in both stances.
- test_procedure:
  1. Equip an LMG (e.g., Defender) in hip-fire at rest and verify the gun reticle aligns with the center camera reticle (`ReadyW = 1.00` in `DetachedReticle.log`).
  2. Aim down sights (hold right-click) and release back to hip-fire with the LMG, and fire bursts in both stances to verify smooth alignment and recoil recovery.

# iteration 7
- date: 2026-11-04 20:20 +0700
- status: untested (deployed to branch `ads-lever-arm-compensation` in repo and `<GAME_ROOT>`, awaiting in-game test)
- previous_iteration_results (Iteration 6 Playtest & User Observation):
  1. **User Observation & Problem Statement:**
     - In ADS firing, the physical 3D gun appears to pitch and rise upward significantly faster than the T3 gun reticle, causing the receiver and rear sight of the weapon to occlude the direct line of sight between the camera and T3.
     - User proposed: lower the root of the lever arm in proportion to how much the 3D gun pitches up, preventing the gun body from blocking the view between the camera root and T3.
     - User requested: verify whether verbose logging contains the 3D gun's pitch and position relative to the camera line of sight, and checkout to a new branch (`ads-lever-arm-compensation`) to proceed with implementation.
  2. **Geometric Analysis of Near-Field Lever-Arm Parallax:**
     - The puppet's arms pivot around the upper body / shoulders / spine located $\approx 0.15\text{–}0.25\text{ m}$ behind and below the first-person eye socket (`FPPCameraComponent`).
     - In ADS, the weapon receiver sits on a forward lever arm $L \approx 0.35\text{–}0.50\text{ m}$ in front of the pivot. When Tier 2 recoil pitches the upper body upward by $\theta_{\text{recoil}} = +4.5^\circ$ ($0.0785\text{ rad}$), the receiver physically translates upward by $\Delta z \approx L \sin(\theta_{\text{recoil}}) \approx +3.5\text{–}5.0\text{ cm}$.
     - Because the camera is counter-rotated at the eye socket to hold Tier 1 steady, the distant T3 target ($D \ge 20\text{ m}$) shifts by the angular barrel pitch of $+4.5^\circ$ ($139\text{ px}$ on screen).
     - However, the near-field gun receiver ($D \approx 0.30\text{ m}$ from the camera lens) subtends an apparent angular rise of $\arctan(\Delta z / 0.30\text{ m}) \approx 9.5^\circ$ ($290\text{ px}$ on screen)—more than double the rise of T3. This causes the solid receiver to climb over and block the sight-line to T3.
- target_goal:
  1. Add comprehensive 3D camera-relative gun telemetry to `DetachedAimSystem` in [`DetachedReticle.reds`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/r6/scripts/DetachedReticle/DetachedReticle.reds) and [`init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua):
     - `MuzzleRelCam=(R, F, U)m`: 3D position of the gun muzzle relative to camera-local Right, Forward, and Up axes in meters.
     - `MuzzleScreen=(mx, my)px`: 2D projected screen pixel coordinates of the physical 3D muzzle.
  2. Implement **ADS Lever-Arm Drop Compensation** in [`init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua):
     - In ADS with upward recoil ($W_{\text{pitch}} > 0$), calculate vertical compensation $h = L_{\text{drop}} \cdot \sin(W_{\text{pitch}})$, where $L_{\text{drop}} = 0.35\text{ m}$ by default.
     - Construct $\Delta\vec{p}_{\text{comp}} = (0.0,\; h \cdot fwdZ,\; h \cdot fwdXY)$ along world-up in the head socket's frame, applying it to `fpp:SetLocalTransform(targetPos, targetRot)` via non-compounding delta `dDrop = dropDist - lastDrop`.
     - Elevating the camera along world-up by $h$ is mathematically identical in the camera's local coordinate frame to lowering the lever-arm root by $h$, dropping the near-field receiver below the sight-line to T3 while having sub-pixel parallax ($< 0.1^\circ$) on distant world targets and keeping the hands 100% attached to the weapon.
  3. Provide full configuration and real-time adjustment via `Config`, CET ImGui overlay, NativeSettings, and CET console setters (`SetAdsLeverArmComp`, `SetAdsLeverArmLength`).
- changes_made:
  1. [`r6/scripts/DetachedReticle/DetachedReticle.reds`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/r6/scripts/DetachedReticle/DetachedReticle.reds):
     - Added `m_cameraPos`, `m_muzzleRelCam`, and `m_muzzleScreen` to `DetachedAimSystem` with `SetMuzzleTelemetry` and getters `GetCameraPos`, `GetMuzzleRelCam`, `GetMuzzleScreen`.
     - In `UpdateDetachedAim`, computed `toMuzzle = muzzlePos - camPos` dotted with `camRight`, `camFwd3`, `camUp`, projected `muzzlePos` to screen via `ProjectWorldToScreen`, and updated `DetachedAimSystem`.
  2. [`bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua):
     - Added `adsLeverArmComp = true` and `adsLeverArmLength = 0.35` to `Config`, `LoadConfig`, CET overlay, and NativeSettings tab `/detachedReticle/leverArm`.
     - In `fpp:SetLocalTransform`, applied non-compounding world-up offset $h = L_{\text{drop}} \sin(W_{\text{pitch}})$ during ADS recoil, smoothly restoring baseline position when recoil recovers or ADS exits.
     - In `[GUN_OFFSET_MONITOR]`, logged `MuzzleScreen=(%.1f, %.1f)px | MuzzleRelCam=(R:%+.2f, F:%.2f, U:%+.2f)m | Drop=%+.1fcm`.
- expected_outcome:
  1. During sustained ADS fire with any weapon (Defender LMG, Copperhead, etc.), the body/receiver of the gun stays lower on screen, keeping a clear visual sight-line to the T3 gun reticle and target.
  2. When releasing the trigger, camera elevation smoothly recovers to normal eye level in exact lockstep with Tier 2 recoil recovery.
  3. `DetachedReticle.log` logs the exact 3D camera-relative gun coordinates and screen pixel positions of both the muzzle and T3.
- test_procedure:
  1. Equip a rifle or LMG, enter ADS (hold right-click), fire bursts and extended auto bursts.
  2. Observe whether the gun body stays below the T3 reticle, allowing an unobstructed view of the target.
  3. Adjust `adsLeverArmLength` (e.g. from `0.20` to `0.50`) in the CET overlay to customize the vertical sight clearance.

# iteration 8
- date: 2026-11-04 22:25 +0700
- status: untested (deployed to branch `recoil-horizontal-dynamics` in repo and `<GAME_ROOT>`, awaiting in-game test)
- previous_iteration_results (Iteration 7 Design & User Request):
  1. **User Request & Design Goal:**
     - User requested adding Strength-scaled horizontal recoil dynamics (`gamedataStatType.Strength`, Body attribute $B \in [3, 20]$) to every shot's recoil kick:
       - **Low Strength ($B \approx 3$, normalized $s \to 0$):** Make horizontal recoil more randomized with an alternating / mean-reverting bias—when a shot kicks to the right, our mod adds a randomized left or right push, and on the *next* shot our mod is much more likely to kick left (while remaining randomized in both sign and strength).
       - **High Strength ($B \approx 20$, normalized $s \to 1$):** Make our mod counteract/neutralize a portion of the game's native horizontal recoil kick in the opposite direction (e.g. when native recoil kicks right by 10 units, neutralize a randomized fraction of it in the opposite direction) and gently stabilize horizontal drift toward center.
  2. **Mathematical & Architectural Design:**
     - Normalize the player's `gamedataStatType.Strength` ($B \in [3, 20]$) to $s = \text{clamp}\!\left(\frac{B - 3.0}{17.0},\; 0.0,\; 1.0\right)$.
     - When `recoilHoriStatScaling` is enabled, low-strength scatter scales with $(1 - s) \cdot K_{\text{scatter}}$ and high-strength damping scales with $s \cdot C_{\text{damping}}$. When `recoilHoriStatScaling` is disabled, both `recoilHoriScatter` and `recoilHoriDamping` act directly as manual sliders ($1 - s \to 1$, $s \to 1$).
     - **Coherent Per-Shot Impulse Window:** Because Cyberpunk 2077 interpolates a single shot's recoil kick across multiple frames (`~30–55 ms`), drawing a new random sign every frame would self-cancel via the central limit theorem. Instead, detect the onset of each new shot kick impulse (when transitioning into kick or after `s_shotKickTimer >= 0.045s` / rising `dRecoilPitch` edge) and draw per-shot random variables:
       - **Alternating / Mean-Reverting Bias (`s_currentShotRandSign`, `s_currentShotRandMag`):**
         - Compute bias $b = \text{clamp}\!\left(0.55 \cdot s_{\text{lastSign}} + 0.45 \cdot \text{clamp}(W_{\text{yaw}} / 1.5^\circ, -1.0, 1.0),\; -0.85,\; 0.85\right)$, where $s_{\text{lastSign}} \in \{-1, +1\}$ is the sign of the previous shot's net horizontal kick.
         - Probability of kicking left ($\text{sign} = -1$) is $P(\text{left}) = 0.50 + 0.35 \cdot b \in [0.20, 0.80]$. Thus, after kicking right ($s_{\text{lastSign}} = +1, W_{\text{yaw}} > 0$), the next shot has an $\approx 70\%\text{–}85\%$ chance of kicking left, while still allowing occasional double-kicks for organic randomness.
         - Draw random strength multiplier $\text{shotRandMag} \in [0.40, 1.25]$ per shot.
         - Frame kick contribution: $\Delta_{\text{rand}} = \text{shotRandSign} \cdot \text{shotRandMag} \cdot (0.35 \cdot dRecoilPitch + 0.25 \cdot |dRecoilYaw|) \cdot w_{\text{scatter}}$.
       - **High-Strength Native Horizontal Recoil Neutralization ($\Delta_{\text{comp}}$):**
         - Per shot, draw $\eta \in [0.65, 1.15]$ so each shot neutralizes a randomized fraction of native `dRecoilYaw` in the opposite direction:
           $$\Delta_{\text{comp}} = -\text{clamp}(\eta \cdot w_{\text{damping}},\; 0.0,\; 0.95) \cdot dRecoilYaw$$
         - Plus a gentle horizontal centering pull during kick:
           $$\Delta_{\text{center}} = -0.15 \cdot w_{\text{damping}} \cdot dRecoilPitch \cdot \text{clamp}(W_{\text{yaw}} / 1.5^\circ,\; -1.0,\; 1.0)$$
     - **Unmodified Shadow Native Recoil Tracking:** Keep `s_nativeRecoilYaw` and `s_nativeRecoilPitch` accumulating the **unmodified** engine deltas `(dRecoilYaw, dRecoilPitch)` so the `RecoilDrift` estimator and `RecoilRecoveryTime` span normalization remain 100% exact.
- target_goal:
  1. Implement per-shot alternating horizontal recoil randomization and high-Strength native horizontal recoil neutralization in [`src/Hooks/InputHook.hpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.hpp) and [`src/Hooks/InputHook.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.cpp).
  2. Expose RTTI bridge functions (`DR_SetRecoilHorizontalParams`, `DR_GetRecoilHoriStatScaling`, `DR_GetRecoilHoriScatter`, `DR_GetRecoilHoriDamping`, `DR_GetPlayerStrengthFactor`) in [`src/Main.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Main.cpp).
  3. Query `gamedataStatType.Strength` in [`bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua) and expose `recoilHoriStatScaling`, `recoilHoriScatter`, and `recoilHoriDamping` in `Config`, NativeSettings, CET ImGui overlay, and CET console setters.
- changes_made:
  1. [`src/Hooks/InputHook.hpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.hpp) & [`src/Hooks/InputHook.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.cpp):
     - Added `s_recoilHoriStatScaling`, `s_recoilHoriScatter`, `s_recoilHoriDamping`, `s_playerStrengthFactor`, and per-shot PRNG state (`s_shotKickTimer`, `s_prevDRecoilPitch`, `s_lastHoriPushSign`, `s_currentShotRandSign`, `s_currentShotRandMag`, `s_currentShotCompMult`).
     - In `InputHook::ProcessMouseAim`, applied $\Delta_{\text{comp}} + \Delta_{\text{rand}} + \Delta_{\text{center}}$ to `rawModifiedYaw` during the kick phase prior to the Option A Radial Soft-Wall Attenuation ("Rubber Leash").
  2. [`src/Main.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Main.cpp):
     - Registered `DR_SetRecoilHorizontalParams`, `DR_GetRecoilHoriStatScaling`, `DR_GetRecoilHoriScatter`, `DR_GetRecoilHoriDamping`, and `DR_GetPlayerStrengthFactor`.
  3. [`bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua):
     - Added `recoilHoriStatScaling = true`, `recoilHoriScatter = 1.0`, `recoilHoriDamping = 0.70` to `Config`, `LoadConfig`, NativeSettings, CET overlay, and console API.
     - Polled player's `gamedataStatType.Strength` (`StatsSystem:GetStatValue(player:GetEntityID(), gamedataStatType.Strength)`) and synced `strengthFactor` to the native hook.
- expected_outcome:
  1. At low Body/Strength ($B \approx 3\text{–}6$), shots exhibit lively, organic left-right horizontal kick where a right kick is followed with high probability ($\approx 75\%$) by a left kick of randomized strength on the next shot.
  2. At high Body/Strength ($B \approx 15\text{–}20$), native horizontal kicks are counteracted by up to $\approx 70\%\text{–}85\%$ in the opposite direction, keeping horizontal spread tight and controlled.
- test_procedure:
  1. Fire automatic bursts and compare horizontal reticle behavior across different Body/Strength stat levels (or toggle `Scale with Body/Strength Stat` and adjust `Low-Strength Horizontal Scatter` / `High-Strength Horizontal Damping` in the CET overlay).
  2. Verify in `DetachedReticle.log` that recoil recovery still returns cleanly to `(0, 0)` after bursts.

# iteration 9
- date: 2026-11-05 20:55 +0700
- status: untested (deployed to branch `testing` in repo and `<GAME_ROOT>`, awaiting in-game test)
- previous_iteration_results (Iteration 8 & LMG Pitch Diagnostic Findings):
  1. **User Observation & Problem Statement:**
     - When continuously firing the Defender LMG (Constitutional Arms Defender / MA70), the 3D gun visibly pitches up to **above 20 degrees** on screen.
     - However, in `DetachedReticle.log`, no telemetry showed the gun pointing up that much (latest logs during 51-shot and 57-shot bursts showed `RecoilW` maxing out at $\approx +5.40^\circ$ and `Divergence` at $\approx 6.78^\circ$).
  2. **Root Cause Analysis & Logging Deficiencies:**
     - In previous builds, non-verbose logging only printed `[BALLISTICS RECORD]` containing `RecoilW`, `Divergence`, and raw Cartesian `BulletDir` vectors without angle conversion or camera-relative pitch.
     - Crucially, `RecoilW` (`s_recoilPitch`) is clamped by the mod's rubber leash (`s_recoilMaxRadius = 7.0f`), whereas the game's native viewmodel & skeletal arm IK (`AnimFeature_WeaponHandlingStats` / `'RightShoot'`) can rise unhindered to `RecoilMaxLength = 30.0f`.
     - Because `[GUN_OFFSET_MONITOR]` was gated behind `debugLogging = true`, no per-shot physical angles or candidate transforms were logged in standard play.
- target_goal:
  1. Add comprehensive, non-verbose per-shot telemetry logging Camera, MuzzleSlot, WeaponRoot, HandSlot, and RecoilState transforms on **every shot**.
  2. Log all candidate 3D orientations side-by-side both in world space and relative to the camera gaze axis (`Rad2Deg(AtanF(upProj, fwdProj))`) to empirically measure the actual 3D physical gun pitch without speculative perspective theories.
- changes_made:
  1. [`r6/scripts/DetachedReticle/DetachedReticle.reds`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/r6/scripts/DetachedReticle/DetachedReticle.reds):
     - Added detailed per-shot telemetry fields and getters to `DetachedAimSystem` (`CamPitch`, `CamYaw`, `MuzWorldPitch`, `MuzRelCamPitch`, `MuzTotalDiv`, `WeapWorldPitch`, `WeapRelCamPitch`, `WeapTotalDiv`, `HandWorldPitch`, `HandRelCamPitch`, `Stance`, `WeaponName`).
     - In `ShootEvents.OnEnter`, computed camera-relative pitch/yaw/divergence for `weapon.GetMuzzleSlotWorldTransform()`, `weapon.GetWorldForward()`, and `player.GetSlotComponent().GetSlotTransform(n"RightHand")`.
     - Passed all candidate transforms into `aimSys.RecordDetailedShot(...)`.
  2. [`bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua):
     - In `onUpdate` shot detection (`shotCount > lastShotCount`), retrieved detailed telemetry and logged a concise 2-line diagnostic entry per shot via `Log(...)` (active even when `debugLogging = false`).
- expected_outcome:
  1. During any burst with the Defender LMG, every shot immediately prints 2 clean diagnostic lines:
     - Line 1: `[SHOT #N] [Weapon] [Stance] Cam=(P, Y) | RecoilW=(Y, P) | dRecP | T2B_Pitch`
     - Line 2: `MuzRelCam=(P, Y, Div) | MuzWorld=(P) | WeapRelCam=(P, Div) | WeapWorld=(P) | HandRelCam=(P)`
  2. If the physical muzzle or skeleton pitches above 20 degrees, `MuzRelCam.P` and/or `HandRelCam.P` will directly show `+20.xx deg`, conclusively identifying which transform drives the visual gun rise.
- test_procedure:
  1. Equip the Defender LMG (Constitutional Arms Defender / MA70) or Copperhead rifle.
  2. Fire a sustained automatic burst (at least 20–30 rounds).
  3. Inspect `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/DetachedReticle.log`.
  4. Verify that `[SHOT #...]` entries show the exact empirical angles of `MuzRelCam`, `WeapRelCam`, `HandRelCam`, and `RecoilW`.

# iteration 10
- date: 2026-11-05 21:25 +0700
- status: tested-pass (conclusive control experiment)
- previous_iteration_results (Iteration 9 Burst Telemetry Findings):
  1. **Empirical Measurements from LMG Continuous ADS Burst (#70–#80):**
     - `RecoilW` peaked at `+5.17°`
     - `T2B_Pitch` peaked at `+2.79°`
     - `MuzRelCam.P` peaked at `+5.88°`
     - `WeapRelCam.P` peaked at `+5.88°`
     - None of the candidate transforms ever exceeded $+6.0^\circ$!
  2. **User Observation & Diagnostic Test Proposal:**
     - The user confirmed that in the logs, no transforms reached $+20^\circ$.
     - The user proposed an empirical control experiment: deliberately add $+20^\circ$ to the weapon pitch heading when unholstered and not firing:
       - If the 3D gun visibly pitches up when unholstered and not firing, it proves the look integrator / $T2B$ heading directly controls the physical 3D pitch of the weapon.
       - If the 3D gun does not visibly pitch up (and only T3 pitches up), it proves the physical 3D weapon orientation in first person is decoupled from the look integrator.
- target_goal:
  1. Implement a controllable diagnostic test pitch offset (`s_testPitchOffset` in C++, adjustable $\pm 30^\circ$) feeding directly into the Tier 2B heading and engine look integrator at RVA `0x51D462` with camera residual counter-rotation.
  2. Expose `DR_SetTestPitchOffset` and `DR_GetTestPitchOffset` via RTTI and CET UI with quick-test buttons (`+20° Test`, `-20° Test`, `Reset 0°`) and live angle monitors.
- changes_made:
  1. [`src/Hooks/InputHook.hpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.hpp) & [`src/Hooks/InputHook.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.cpp):
     - Added `s_testPitchOffset`, `s_currentTestPitch`, `SetTestPitchOffset`, `GetTestPitchOffset`.
     - In `ProcessMouseAim`, smoothly approached `s_testPitchOffset` and added `dTestPitch` to `outPitch` (look integrator), `s_displayT2BPitch`, and subtracted from `s_residualPitch` (camera counter-rotation).
  2. [`src/Main.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Main.cpp):
     - Registered `DR_SetTestPitchOffset` and `DR_GetTestPitchOffset` with RTTI.
  3. [`red4ext/plugins/DetachedReticle/DetachedReticle.dll`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/red4ext/plugins/DetachedReticle/DetachedReticle.dll):
     - Built Release DLL using MSVC toolchain.
  4. [`bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua):
     - Added CET overlay slider (`Test Pitch Offset: [-30°..+30°]`), `[+20° Test (Gun Up)]`, `[-20° Test (Gun Down)]`, `[Reset 0°]` buttons, and live `T2B Pitch` and `Muzzle Rel Cam Pitch` readouts.
     - In `onUpdate`, logged periodic `[PITCH TEST MONITOR]` lines while test offset is active.
- expected_outcome:
  1. Clicking `[+20° Test (Gun Up)]` while unholstered and resting:
     - If the weapon 3D mesh tilts steeply upward relative to the camera gaze, $T2B$ proves to be the true driver of the weapon's physical mesh pitch.
     - If the weapon 3D mesh remains flat while T3 jumps upward, it proves the first-person mesh is not pitched by the look integrator.
- test_procedure:
  1. Equip any weapon (Defender LMG, rifle, pistol).
  2. Stand still unholstered (do not fire).
  3. Open CET overlay and click `[+20° Test (Gun Up)]`.
  4. Observe whether the physical 3D gun mesh angles upward, or if only T3 moves.
  5. Click `[Reset 0°]` to restore baseline.


# iteration 11
- date: 2026-11-05 22:20 +0700
- status: tested-fail (game crash on startup / state machine conflict)
- failure_analysis:
  1. Root Cause 1: `SyncRecoilAnimScale()` called `Game.GetScriptableSystemsContainer():Get(...)` during CET's early `onInit` hook. At the main menu, `ScriptableSystemsContainer` is null; invoking a method on it triggered an uncatchable native access violation (`0xC0000005`) that crashed the game before reaching gameplay.
  2. Root Cause 2: Wrapping `ReadyEvents.OnTick` to push `AnimFeature_WeaponHandlingStats` on every frame conflicted with REDengine's viewmodel animation tree during unholstering/state transitions.
  3. Resolution: Reverted the `ReadyEvents` wrap and CET script hooks completely. Replaced with declarative TweakXL stat modifier.

# iteration 12
- date: 2026-11-05 22:50 +0700
- status: tested-fail (refuted in-game; viewmodel shoot animation kick unaffected by TweakDB stat)
- previous_iteration_results (Iteration 11 Reversion & Diagnostic Cleanup):
  1. Crash eliminated immediately upon reverting `ReadyEvents` and `onInit` hooks; game boots stably.
  2. All temporary diagnostic instruments from Iterations 9–10 (+20° pitch test slider, overlay monitor, native RTTI test functions, detailed candidate angle calculations in `ShootEvents.OnEnter`) were cleaned from the codebase.
- target_goal:
  1. Clean up and remove all legacy diagnostic testing code across `src/`, `init.lua`, and `DetachedReticle.reds`.
  2. Eliminate the visual divergence between the 3D gun mesh and T3 reticle during sustained firing (Defender LMG) using a crash-proof, declarative TweakXL stat modification (`BaseStats.RecoilAnimation`).
- changes_made:
  1. [`src/Hooks/InputHook.hpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.hpp), [`src/Hooks/InputHook.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Hooks/InputHook.cpp), [`src/Main.cpp`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Main.cpp):
     - Restored clean baseline C++ source; removed `s_testPitchOffset`, `s_currentTestPitch`, `SetTestPitchOffset`, `GetTestPitchOffset`, and RTTI bindings.
     - Built fresh Release DLL and deployed to `red4ext/plugins/DetachedReticle/DetachedReticle.dll` and `<GAME_ROOT>`.
  2. [`bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua):
     - Removed `testPitchOffset`, `SetTestPitchOffset`, the `[PITCH TEST MONITOR]` diagnostic log block, and the test slider/buttons from the CET overlay.
  3. [`r6/scripts/DetachedReticle/DetachedReticle.reds`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/r6/scripts/DetachedReticle/DetachedReticle.reds):
     - Reverted detailed per-shot candidate angle logging; restored standard `aimSys.RecordShot(...)` in `ShootEvents.OnEnter`.
  4. [`r6/tweaks/DetachedReticle/recoil_anim.yaml`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/r6/tweaks/DetachedReticle/recoil_anim.yaml):
     - Created new TweakXL configuration appending a `Multiplier = 0.0` modifier for `BaseStats.RecoilAnimation` to `Items.Base_Lightmachinegun_Sway_Stats` and `Items.Base_Defender_Recoil_Stats`.
     - Zeroes out `animFeature.weaponRecoil` declaratively at the engine stat level.
  5. Deployed all files to `E:\Cyberpunk 2077`.
- test_results:
  1. User tested in-game with Defender LMG in ADS: "It doesn't have any effect (not any different with the previous tests)".
  2. Modifying `BaseStats.RecoilAnimation` to 0.0 via TweakDB stat modifier had no observable effect on the visual viewmodel shoot kick. In REDengine, the first-person shoot kick animation (`PushAnimationEvent('RightShoot')`) is baked into the weapon mesh animset/graph clips rather than purely governed by the `RecoilAnimation` stat.
  3. Attempting to suppress it by wrapping high-frequency script methods (`ReadyEvents.OnTick`) previously crashed the game (`0xC0000005`) or broke weapon unholster state initialization.
- resolution:
  1. Completely reverted and deleted `r6/tweaks/DetachedReticle/recoil_anim.yaml` from the repo and game directory.
  2. Ceased all attempts to eliminate procedural viewmodel shoot animation kick. The mod's decoupled aim model relies on the look integrator ($T2B$) and the T3 reticle tracks physical muzzle ballistics. The viewmodel mesh upward kick is accepted as an inherent engine visual characteristic.
  3. ADS receiver sightline occlusion is effectively addressed by vertical eye-level lever-arm drop (`adsLeverArmLength = 0.70m`), maintaining clear sightlines above the gun during sustained recoil.
  4. Saved the current tuned configuration (`adsLeverArmLength = 0.70`, radial rubber leash `7.0°`, Strength-scaling horizontal dynamics) as the official default configuration in `config.json` and `init.lua`.


# iteration 13
- date: 2026-11-07 19:15 +0700
- status: untested (deployed to branch `config-cleanup` in repo and `<GAME_ROOT>`, awaiting in-game test)
- previous_iteration_results (Iteration 12 Default Tuning & User Cleanup Request):
  1. The user requested simplifying the configuration and tuning:
     - Remove the catch-up algorithm selection UI, making Option A continuous power-law exponential smoothing permanent while retaining the alternative algorithms in the code for future reference.
     - Reduce default `adsLeverArmLength` to `0.20m` for standard weapons, while applying a dynamic `3.5x` multiplier for LMGs (`armLen = armLen * 3.5`, giving $0.20\text{m} \times 3.5 = 0.70\text{m}$ by default) so heavy weapons clear sight occlusion while regular weapons do not suffer exaggerated camera displacement.
- target_goal:
  1. Set Option A Power-Law as permanent smoothing mode; remove the algorithm selector and Model A Braking sliders from NativeSettings and CET ImGui overlay.
  2. Lower default `adsLeverArmLength` to `0.20m` in `Config` and `config.json`.
  3. Reorder `onUpdate` execution so weapon type classification (`weaponName`, `isHeavyWeapon`, `isLMG`, `isSmartWeapon`) resolves prior to the ADS lever-arm drop computation.
  4. Apply a `3.5x` scale factor to `adsLeverArmLength` whenever `isLMG` is true.
- changes_made:
  1. [`bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua):
     - In `Config`: set default `adsLeverArmLength = 0.20`.
     - In `SetupNativeSettings`: removed the `Catch-up Algorithm` selector and Model A Braking sliders (`Braking Threshold Angle`, `Max Cruise Speed`), displaying `Curve Exponent (Power-Law)` directly. Updated `Lever-Arm Drop Length` default to `0.20m` (noting `3.5x` for LMG).
     - In `onDraw`: removed the `Catch-Up Algorithm:` radio button group and the Model A braking settings branch. Directly exposed `Curve Exponent (p)` under Aiming. Updated `Lever-Arm Length` slider default and tooltip.
     - In `onUpdate`: moved weapon identification and type resolution ahead of Section 2 camera transform calculations; applied `armLen = armLen * 3.5` if `isLMG` during ADS recoil.
     - In `DetachedReticle.SetAdsLeverArmLength`: updated default fallback to `0.20`.
  2. [`bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/config.json`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/config.json):
     - Updated default `"adsLeverArmLength": 0.2`.
- expected_outcome:
  1. Catch-up algorithm runs permanently on Option A Power-Law without confusing multi-algorithm UI toggles.
  2. Regular rifles, handguns, and shotguns in ADS experience a subtle $0.20\text{m}$ eye-level lever-arm drop during recoil.
  3. LMGs (Defender, MA70) automatically receive $3.5\times$ of the configured lever-arm length ($0.70\text{m}$ default), preventing the heavy receiver from occluding the line of sight to T3.
- test_procedure:
  1. Equip a regular rifle or handgun (e.g. Copperhead, Lexington), aim down sights, and fire bursts: verify camera drop during recoil is subtle ($0.20\text{m}$) and sightline stays natural.
  2. Equip the Defender LMG, aim down sights, and fire a sustained burst: verify the camera drops higher ($0.70\text{m}$), keeping the receiver below T3.
  3. Check CET overlay and NativeSettings: verify catch-up algorithm radio buttons are gone and Curve Exponent is directly editable.

# iteration 14
- date: 2026-11-08 00:10 +0700
- status: untested (deployed to branch `testing` in repo and `<GAME_ROOT>`, awaiting in-game test)
- previous_iteration_results (Iteration 13 Cleanup & Merge):
  1. Branch `config-cleanup` merged into `testing`.
  2. Option A Power-Law made permanent default; lever-arm drop set to `0.20m` base with `3.5x` dynamic multiplier for LMGs.
- target_goal:
  1. Investigate and identify the engine variables and architecture governing the physical travel direction of the player when pressing `W` (locomotion input).
  2. Determine whether player locomotion follows the rendered camera gaze ($T_1$) or the physical puppet body heading ($T_{2B}$), especially when unholstered where Tier 2B barrel offset compensation ($C$) and recoil ($W$) deflect the puppet body relative to the camera gaze ($T_{2B} = T_{2A} - C + W$, where $rYaw = T_1 - T_{2B}$).
  3. Add a dedicated locomotion monitor (`MonitorLocomotion`), periodic log output (`[LOCOMOTION_MONITOR]`), per-frame `[LOCO]` debug log tags, and live movement telemetry in the CET ImGui overlay for in-game inspection.
- verified binary & architectural basis:
  1. **REDengine PSM Locomotion Architecture (`locomotionTransitions.script:3938`, `locomotionTransitionsLowGravity.script:662`, `defaultTransition.script:780`, `psmImports.script:147`):**
     - Movement world vector is calculated as:
       $$\vec{d} = \text{RotByAngleXY}(\text{GetOwnerForward}(), -\text{GetInputHeading}())$$
     - In vanilla first-person mode, `GetOwnerForward()` (`player:GetWorldForward()`) is identical to the camera gaze forward because the camera component is locked at local yaw `0.0`.
     - In DetachedReticle, the native look integrator steers the puppet body ($T_{2B}$), deflecting it by $-C_{\text{yaw}} + W_{\text{yaw}}$ while the camera is kept at $T_1$ via local component residual $rYaw$.
     - When unholstered, $C_{\text{yaw}}$ deflects the body (e.g. Defender LMG $+6.37^\circ$, HMG $+3.50^\circ$, Igla $+5.64^\circ$, Lexington $-1.05^\circ$).
     - If the locomotion physics controller evaluates movement relative to `GetOwnerForward()`, pressing `W` will push the character along $T_{2B}$ rather than $T_1$, resulting in an angular drift equal to $-C_{\text{yaw}}$ (or $-rYaw$).
  2. **Mathematical Divergence Metrics:**
     - World velocity: $\vec{v} = (v_x, v_y, 0) \implies \text{moveHeading} = \text{atan2}(-v_x, v_y)$.
     - Camera gaze: $\text{camYaw} = \text{atan2}(-c_x, c_y)$ from `CameraSystem.GetActiveCameraForward()`.
     - Body forward: $\text{bodyYaw} = \text{player:GetWorldYaw()}$.
     - Angular deviations:
       $$\Delta_{\text{cam}} = \text{normalize}(\text{moveHeading} - \text{camYaw})$$
       $$\Delta_{\text{body}} = \text{normalize}(\text{moveHeading} - \text{bodyYaw})$$
- changes_made:
  1. [`bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua):
     - Added `MonitorLocomotion` watchdog function (lines 624–742): samples `player:GetVelocity()`, computes `moveHeading`, `camYaw`, and `bodyYaw`, and logs `[LOCOMOTION_MONITOR]` on locomotion start, holster/unholster transition, and periodically every `0.5s` during movement.
     - Hooked `MonitorLocomotion` in `onUpdate` to run on both holstered and armed states.
     - Appended `[LOCO] spd=%.2f mH=%.2f dCam=%+.2f dBody=%+.2f` to the per-frame `[F=...]` debug log line when movement speed exceeds `0.15 m/s`.
     - Added live movement direction, speed, and divergence readouts (`vs Cam`, `vs Body`) to the CET ImGui overlay.
  2. Deployed `init.lua` to `E:\Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\DetachedReticle\init.lua`.
- expected_outcome:
  1. When standing still, `Movement: Idle / Stopped` is displayed.
  2. When moving (pressing W), `[LOCOMOTION_MONITOR]` logs the exact angles and deltas to `DetachedReticle.log`.
  3. If locomotion is camera-relative in native physics, $\Delta_{\text{cam}} \approx 0.0^\circ$ and $\Delta_{\text{body}} \approx rYaw$.
  4. If locomotion is body-relative, $\Delta_{\text{body}} \approx 0.0^\circ$ and $\Delta_{\text{cam}} \approx -rYaw$ (revealing why movement drifts when unholstered).
- test_procedure:
  1. Launch game, open CET console / Detached Reticle window.
  2. **Holstered Test:** Stand still, look at a recognizable distant landmark, press and hold `W` to walk straight ahead for 3–5 seconds. Inspect ImGui overlay and log lines for `dMove_Cam` and `dMove_Body`.
  3. **Unholstered Test:** Draw the Defender LMG (large compensation $C_{\text{yaw}} \approx +6.37^\circ$). Look at the same landmark, press and hold `W` straight ahead for 3–5 seconds without moving the mouse. Inspect `dMove_Cam` and `dMove_Body`.
  4. Compare the two tests: check whether `dMove_Cam` shifts by approximately $-6.37^\circ$ when armed with the LMG.

# iteration 15
- date: 2026-11-10 13:30 +0700
- status: untested (deployed to branch `fix-baseline-yaw` in repo and `<GAME_ROOT>`, awaiting in-game test)
- previous_iteration_results (Iteration 14 Locomotion Telemetry Analysis & Root Cause Identification):
  1. **Empirical Telemetry from User Logs (`DetachedReticle.log` Cluster 123, lines 5334–5397, `12:58:43`–`12:59:41`):**
     - User experienced a persistent walking drift: pressing `W` caused the character to walk $+12.5^\circ$ to the left of the camera crosshair (`dMove_Cam = +12.51°`), while perfectly matching the puppet body forward (`dMove_Body = +0.02°`).
     - Telemetry captured the exact genesis at `12:58:43`–`12:58:45`: during holster transition (detailed locomotion state `Det:8`), the puppet body locked at `bodyYaw = -92.90°` while the player turned the mouse from `-94.62°` to `-105.56°`, creating a $-12.66^\circ$ angular deflection between camera gaze and body.
     - When unholster finished and `Decoupled Aim ACTIVE` triggered at `12:58:45`, `DetachedReticle.baselineRot = localRot` captured `fpp:GetLocalOrientation()` while it was deflected by $-12.66^\circ$.
     - Simultaneously, native `s_residualYaw` reset to `0.0`. Every frame, camera orientation was evaluated as `targetRot = quatMultiply(qRel, baselineRot)`. With `rYaw = 0`, `targetRot` was held permanently twisted $-12.66^\circ$ relative to the puppet body.
     - For 60 seconds across 60 walk events, even with weapon settled (`CompYaw = 0.00°`), every `W` press moved along puppet forward ($+12.5^\circ$ off camera gaze).
- target_goal:
  1. Implement **Pillar 1**: sanitize baseline camera orientation on capture to enforce zero local yaw (`yaw = 0.0`).
  2. Guarantee that transient camera turns or body locks during holster/unholster animations (`Det:8`) cannot bake an angular bias into `baselineRot`.
  3. Log any deviant baseline orientation capture via `[BASELINE_SANITIZE]` for empirical validation.
- verified binary & architectural basis:
  1. In vanilla Cyberpunk 2077 first-person mode, `gameFPPCameraComponent` (`fpp`) at neutral stance has strictly zero local yaw (`yaw = 0.0`) relative to the puppet head bone; world yaw is entirely driven by the puppet body orientation (`player:GetWorldYaw()`).
  2. Any non-zero yaw in `fpp:GetLocalOrientation()` at capture is a transient artifact of an animation lock or prior residual.
  3. Forcing `yaw = 0.0` while retaining subtle pitch/roll rig offsets ($\le 2.0^\circ$) ensures that `targetRot` at rest (`rYaw = 0`) aligns the camera forward vector with the puppet body forward vector, mathematically eliminating walk drift.
- changes_made:
  1. [`bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua):
     - Added `SanitizeBaselineRot(rawRot)` helper: attempts Euler conversion via `rawRot:ToEulerAngles()` (with a pure quaternion math fallback), checks for deviant angles (`|yaw| > 0.05°` or `|pitch| > 2.0°` or `|roll| > 2.0°`), logs `[BASELINE_SANITIZE]` if deviant, enforces `cleanYaw = 0.0`, preserves rig pitch/roll if within tolerance, and constructs a clean quaternion via `quatAxisAngle` and `quatMultiply`.
     - In Section 2 initialization (`if not DetachedReticle.chaseActive`): replaced raw assignment `baselineRot = localRot or Quaternion.new(0,0,0,1)` with `baselineRot = SanitizeBaselineRot(localRot)`.
     - In Section 2 re-arm (`elseif isArmed and not DetachedReticle.wasArmed`): ensured `baselineRot` is passed through `SanitizeBaselineRot`.
  2. Deployed updated `init.lua` to `E:\Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\DetachedReticle\init.lua`.
- expected_outcome:
  1. When drawing/unholstering a weapon while simultaneously moving or panning the mouse, `SanitizeBaselineRot` detects any transient yaw offset, logs `[BASELINE_SANITIZE] Deviant local camera orientation on baseline capture: raw=(yaw=..., pitch=..., roll=...) -> sanitized (yaw forced 0.0)`, and zeroes out the local yaw.
  2. Once settled at rest (`rYaw = 0`), the camera gaze $T_1$ is strictly parallel to puppet body forward.
  3. When pressing `W`, the player travels straight along the camera crosshair (`dMove_Cam = 0.0°`), completely resolving the persistent $+12.5^\circ$ drift bug.
- test_procedure:
  1. Launch game, open CET console / Detached Reticle window with Verbose Debug Logging enabled.
  2. **Stress Test (Unholster while panning):** Holster weapon, then unholster while vigorously sweeping the mouse left and right.
  3. Stop mouse movement immediately after weapon appears, face a straight road or corridor, and press and hold `W` to walk forward for 3–5 seconds.
  4. Verify visually that character walks straight towards the crosshair, without angling to the side.
  5. Check `DetachedReticle.log` for `[BASELINE_SANITIZE]` and confirm `[LOCOMOTION_MONITOR]` reports `dCam ≈ 0.0°` (and `dCam ≈ -CompYaw` when unholstered with compensated weapons).

# iteration 16
- date: 2026-11-10 19:00 +0700
- status: untested (deployed to branch `fix-baseline-yaw` in repo and `<GAME_ROOT>`, awaiting in-game test)
- previous_iteration_results (Iteration 15 Test & Deep Root-Cause Telemetry Analysis):
  1. User tested Iteration 15 in-game and reported that the bug was still present, noting that visually T3 (gun reticle) was not centered and appeared stuck on the left of the center diamond (T1).
  2. Empirical Telemetry Analysis (`DetachedReticle.log`, lines 90890–90952, `18:22:20`–`18:24:49`):
     - `fpp:GetLocalOrientation()` at `Decoupled Aim ACTIVE` entry was already `(0, 0, 0, 1)`, confirming that `baselineRot` was clean and `[BASELINE_SANITIZE]` did not trigger.
     - However, across all tested weapons (Malorian, Dual Wielding, MilitechAnchor), telemetry revealed an exact $-9.54^\circ$ discrepancy where `dCam_Body - CompYaw = -9.54°`!
     - In `locomotionTransitions.script:3938`, Cyberpunk's physics controller moves the character via `Vector4.RotByAngleXY(playerForward, GetInputHeading())`. When pressing `W`, the player travels along `playerForward` (`BodyHeading`).
     - Telemetry captured the exact genesis at `18:22:28`: during sprint holster (`Det:8`), `camYaw` and `bodyYaw` diverged by $-9.54^\circ$.
     - When `Decoupled Aim ACTIVE` activated, `ResetChase(initPitch)` reset `s_targetYaw = 0` and `s_residualYaw = 0`. Because `0x51D462` only integrates relative mouse deltas, the initial $-9.54^\circ$ divergence was never closed.
     - Furthermore, when the mouse stopped moving to walk with `W`, DirectInput stopped sending mouse events to `0x51D462`. The native chase gap froze, locking `isSwinging = (rawGapYaw > 0.50)` permanently `true` every frame!
     - This prevented `targetYaw` from updating, locked `isResting` to `false`, prevented integral screen trim (`trimYaw`) from ever running, and left T3 visibly stuck to the left of T1 while pressing `W` walked sideways along the skewed body heading.
- target_goal:
  1. Break the false `isSwinging` deadlock by tracking camera angular deltas to determine true mouse activity (`isMouseMoving`).
  2. Ensure `isResting` is `true` when the mouse is stationary, allowing the integral screen error trim (`trimYaw`) to smoothly drive T3 to screen center.
  3. Implement **Locomotion Straight-Walk Alignment**: in hipfire, when moving (`speed2D > 0.3 m/s`), attenuate `targetYaw` via `locoBlend` towards 0 so `BodyHeading` aligns with `CamHeading`, ensuring `W` moves 100% dead straight along camera crosshair.
  4. Implement **Pillar 4 (Idle Auto-Realignment Watchdog)**: re-sync native pitch and clear stalled residual when mouse is stationary for $\ge 10$ frames.
  5. Reset `lastSettledCompTargetYaw = nil` and `trimYaw = 0.0` on activation and re-arm so no stale compensation is locked in.
- verified binary & architectural basis:
  1. `locomotionTransitions.script:3938` confirms movement vector is rotated relative to `scriptInterface.executionOwner.GetWorldForward()`. Aligning body heading with camera gaze while moving eliminates walk drift by definition.
  2. The native look integrator at `0x51D462` runs only upon DirectInput mouse events. Tracking camera deltas in Lua allows detecting mouse rest independently of frozen native look deltas.
- changes_made:
  1. [`bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua):
     - Added `isMouseMoving` detection tracking `dCamYaw` and `dCamPitch` with a 6-frame idle window.
     - Unlocked `isSwinging = isMouseMoving and ((rawGapYaw > 0.50) or (rawGapPitch > 0.50))`.
     - Defined `isResting = (not isRecoiling) and ((rawGapYaw < 0.10 and rawGapPitch < 0.10) or (not isMouseMoving))`.
     - Added `locoBlend` attenuation on `targetYaw` during hipfire movement (`speed2D > 0.3 m/s`).
     - Added Pillar 4 Idle Auto-Realignment Watchdog in Section 2 to re-sync pitch if shifted while idle.
     - Separated `dCam_Body` and `rYaw` in `[LOCOMOTION_MONITOR]` logging.
     - Initialized `lastSettledCompTargetYaw = nil` and `trimYaw = 0.0` on activation and re-arm.
  2. Deployed `init.lua` to `E:\Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\DetachedReticle\init.lua` and verified SHA256 hashes match.
- expected_outcome:
  1. When mouse is stationary, `isSwinging` is false and `isResting` is true. T3 smoothly glides to center on T1 within 1 second.
  2. When moving forward with `W`, `locoBlend` brings body heading into alignment with camera gaze, eliminating sideways walking drift.
- test_procedure:
  1. Launch game with mod active.
  2. Unholster weapon while moving or standing still.
  3. Verify T3 immediately returns to screen center diamond (T1).
  4. Press and hold `W` to walk forward, verify character walks dead straight towards the crosshair.

# next iteration above this line

### Findings Writing Rules:
- Write iterations continuing the last one
- Always write the current implementation as an untested iteration before testing
- Never edit/revise written iterations unless there's a typo
- The next iteration is always another untested iteration meant to resolve the previous iteration's test results, describing what was observed/wrong in the previous test and what solution is implemented
