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

# next iteration above this line

### Findings Writing Rules:
- Write iterations continuing the last one
- Always write the current implementation as an untested iteration before testing
- Never edit/revise written iterations unless there's a typo
- The next iteration is always another untested iteration meant to resolve the previous iteration's test results, describing what was observed/wrong in the previous test and what solution is implemented
