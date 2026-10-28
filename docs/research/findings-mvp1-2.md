- "Vector4.Normalize3()" causes crash at startup; wrong method name
- require("ffi") causes crash

#iteration 1
- error: Redscript failed to parse and compile ShootEvents.OnEnter on startup.
- error cause: 
  - Line 396 declared `protected export function OnEnter(...)`: redscript syntax does not have `export` and uses `func`, not `function`.
  - Lines 541 & 573 used empty argument syntax `, , true` in `TriggerSingleBroadcast`, which is illegal syntax in redscript.
  - Lines 493 & 494 passed references directly to `EffectData.SetVariant` without `ToVariant(...)`.
  - Line 467 used `new Vector4(...)`, but `Vector4` is a struct (value type), not a class.
  - Lines 542 & 582 used non-existent `Equals(...)` helper on enums instead of `==`.
- fix:
  - Changed method signature to `protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void`.
  - Declared `emptyInvestigateData: stimInvestigateData` and passed it to `TriggerSingleBroadcast` calls.
  - Wrapped `attackObj` and `statMods` with `ToVariant(...)` in `EffectData.SetVariant`.
  - Replaced `new Vector4(...)` with `Vector4(...)`.
  - Replaced `Equals(...)` with `==`.
(user test timestamp: 2026-10-27 22:15:12 +0700)

#iteration 2
- error: `[NO_MATCHING_OVERLOAD] At r6\scripts\DetachedReticle\DetachedReticle.reds:424:21: muzzleFxScale = statsSystem.GetStatValue(weapon.GetEntityID(), ...); arguments passed to 'GetStatValue' do not match any of the overloads: 1st argument: expected 'StatsObjectID', given 'EntityID'`
- error cause: Redscript is strictly typed and does not implicitly coerce `EntityID` to `StatsObjectID` when invoking `StatsSystem.GetStatValue` or `StatPoolsSystem.GetStatPoolValue`.
- fix: Wrapped all entity ID parameters with `Cast<StatsObjectID>(...)` across lines 424, 428, 538, 550, 581, and 583.
(user test timestamp: 2026-10-27 22:21:39 +0700)

#iteration 3
- error: `[NO_MATCHING_OVERLOAD] At r6\scripts\DetachedReticle\DetachedReticle.reds:484:13: gameEffectAttack.GetStatModList(statMods); arguments passed to 'GetStatModList' do not match any of the overloads: 1st argument: expected '[ref<gameStatModifierData>]', given '[gameStatModifierData]'`
- error cause: `gameStatModifierData` is an engine class type, so redscript arrays of this type require the explicit reference wrapper `array<ref<gameStatModifierData>>`.
- fix: Changed `let statMods: array<gameStatModifierData>;` to `let statMods: array<ref<gameStatModifierData>>;` on line 483.
(user test timestamp: 2026-10-27 22:29:17 +0700)

#iteration 4
- error: `[NO_MATCHING_OVERLOAD] At r6\scripts\DetachedReticle\DetachedReticle.reds:543:16: if WeaponObject.GetWeaponType(weapon.GetItemID()) == gamedataItemType.Wea_SniperRifle; arguments passed to 'OperatorEqual' do not match any of the overloads: 1st argument: expected 'TweakDBID', given 'gamedataItemType' ...`
- error cause: Redscript does not provide direct `==` operator overloads for game enums (`gamedataItemType`, `gamedataWeaponEvolution`); it requires the built-in intrinsic `Equals(enumA, enumB)`.
- fix: Replaced `==` with `Equals(...)` on lines 543 and 583.
(user test timestamp: 2026-10-27 22:35:50 +0700)
(startup compilation crash fixed, iteration reset)

#iteration 5
- error: Bullet still travels toward the camera crosshair instead of the gun reticle; no shot or telemetry entries appear in on-disk log files.
- error cause:
  1. Log Visibility: `r6\logs\redscript_rCURRENT.log` is strictly an offline AST compilation log (it closes before the 3D game world loads). `red4ext\logs\` only logs plugin load events. `FTLog(...)` in REDengine retail builds routes to kernel/ETW debug traces (`OutputDebugString`), not to files on disk. CET's `print(...)` outputs solely to the interactive in-game console (`~`), not to disk.
  2. Ballistics Pipeline: In `ShootEvents.OnEnter`, calling `scriptInterface.PushAnimationEvent(n"RightShoot")` and `WeaponObject.TriggerWeaponEffects` triggers REDengine's native animation track event callback. This natively evaluates the active camera transform and fires the engine's primary camera-centered raycast (`EffectObjectProvider_PhysicalRay`), bypassing or firing alongside any script-dispatched attack.
  3. Decoupling Activation: `isDecoupledActive` relies on `aimSys.IsDetachedActive()`, which is set only when `gameuiCrosshairContainerController.UpdateDetachedAim()` is actively ticking. If the UI container has not ticked or is delayed, the weapon falls back to vanilla camera-driven firing.
- fix:
  1. File Logging: Added dedicated file logger in `init.lua` appending to `plugins/cyber_engine_tweaks/mods/DetachedReticle/DetachedReticle.log` and `scripting.log` via `io.open(...)`. Added input listener for `RangedAttack` / `mouse_left` to log all trigger presses. Added telemetry bridge polling `DetachedAimSystem` in CET `onUpdate` to record exact shot numbers, muzzle coordinates, divergence angle, and barrel direction to disk.
  2. Activation Decoupling: In `ShootEvents.OnEnter`, removed the dependency on `aimSys.IsDetachedActive()`; `isDecoupledActive` now activates directly whenever an armed player holds a non-melee weapon (`IsDefined(player) && !GameObject.IsDualWielding(player) && IsDefined(weapon) && !weapon.IsMelee()`).
  3. Straight Shooting Enforcement: Added native `weapon.ShootStraight(true)` calls in both CET `onUpdate` and redscript `ShootEvents.OnEnter` / `UpdateDetachedAim` to disable REDengine's native camera convergence.
(user test timestamp: 2026-10-27 22:35:25 +0700)

#iteration 6
- error: In-game logs confirmed pure freelook divergence of 47.84 deg and muzzle forward vector calculation, but the visual bullet still shot toward the camera reticle instead of the barrel direction.
- error cause:
  1. `Attack_GameEffect` runs compiled native `EffectObjectProvider_PhysicalRay`, which ignores script blackboard orientation overrides and queries the player camera gaze.
  2. `WeaponObject.TriggerWeaponEffects(weapon, gamedataFxAction.Shoot, effectBlackboard)` was still executing unconditionally in `ShootEvents.OnEnter`. In REDengine, this native function explicitly generates the first-person visual bullet tracer beam converging to the camera crosshair.
- fix:
  1. Replaced `gameEffectAttack.StartAttack()` with native `weapon.AI_ShootForwards(scriptInterface.executionOwner, ammoCost, projParams, projectilesPerShot, charge, muzzlePos, normMuzzleFwd)` which explicitly forces the engine to fire the shot along `normMuzzleFwd` from `muzzlePos`.
  2. Suppressed `WeaponObject.TriggerWeaponEffects(..., Shoot)` when `isDecoupledActive` is true, preventing the native camera-converging tracer from being generated.
(user test timestamp: 2026-10-27 23:15:08 +0700)

#iteration 7
- error: User confirmed in live tests that bullets still shoot toward the camera reticle instead of the gun reticle/barrel orientation, despite telemetry logs proving up to 47.29 deg of pure freelook divergence across 14 shots.
- error cause:
  1. In `ShootEvents.OnEnter`, `scriptInterface.PushAnimationEvent(n"RightShoot")` was still executing. In REDengine's first-person player animation graph, the `RightShoot` event contains an animation-track callback that natively triggers the active weapon attack. Because `ReadyEvents.OnUpdate` keeps `weapon.SetAttack(attackID)` bound to vanilla `Bullet_GameEffect`, this animation event triggers a native camera-bound raycast.
  2. `weapon.AI_ShootForwards` was called without `AIWeapon.SetAttackBasedOnTimeDilation`, which is required to bind attack data for the forward shoot query on player puppets.
  3. Testing a single vector in isolation without suppressing the animation track left uncertainty regarding which subsystem (animation event vs effect provider vs targeting system) produced the visible tracer.
- fix:
  1. Implemented a comprehensive multi-approach ballistic experimental matrix ("spreading the net"):
     - Experiment A (Anim Event Suppression): Suppress `scriptInterface.PushAnimationEvent(n"RightShoot")` to verify if the camera bullet originates solely from the animation graph.
     - Experiment B (Proper AI_ShootForwards): Bind `AIWeapon.SetAttackBasedOnTimeDilation` and fire `weapon.AI_ShootForwards` along `normMuzzleFwd` with anim event suppressed.
     - Experiment C (Direct EffectSystem Dispatch): Invoke `EffectSystem.CreateEffectStatic(n"weaponShoot", n"player_ray", ...)` explicitly overriding `EffectSharedData.position` and `EffectSharedData.forward` with physical muzzle vectors.
     - Experiment D (Continuous Attack Vector): Call `weapon.StartContinuousAttack(muzzlePos, normMuzzleFwd)` / `PrepareContinuousAttack`.
  2. Implemented round-robin cycling and CET hotkey/console mode selection with dedicated on-disk logging to `DetachedReticle.log`, outputting the exact experiment mode, vector inputs, and branch execution for every single shot.
(user test timestamp: 2026-10-28 00:02:40 +0700)

#iteration 8
- error: All multi-mode ballistics experiments (Modes 1 through 6) still resulted in bullets hitting the camera reticle. Modes 1 to 5 did not animate the gun housing (recoil slide suppressed), while Mode 6 did. Crucially, in Mode 1—where all attack dispatches, animation events, and effect spawners were completely suppressed in `ShootEvents.OnEnter`—a bullet still fired natively and hit the camera reticle.
- error cause:
  1. REDengine's Ranged Weapon State Machine does not fire the hitscan bullet from `ShootEvents.OnEnter`. When the player pulls the trigger (`mouse_left`), the state machine executes `SemiAutoEvents.OnEnter` -> `SetupStandardShootingSequence` -> `StartShootingSequence`, which natively executes `GetWeaponObject(scriptInterface).SetTriggerDown(true)`. `ShootEvents.OnEnter` only handles cosmetic recoil animation (`PushAnimationEvent`), stamina deduction, audio, and ammo tracking.
  2. `WeaponObject::SetTriggerDown(true)` natively dispatches the active attack bound during `ReadyEvents.OnUpdate` (`weapon.SetAttack(attackID)`). In REDengine 4, firearms evaluate their combat ray via the native C++ class `gameEffectObjectProvider_PhysicalRay::Execute`.
  3. Inside `PhysicalRay::Execute`, the engine evaluates `inputPosition` and `inputForward` from the player's active camera gaze at verified callsites RVA `0x9507B7` and RVA `0x9507EC` (both calling the input evaluator at RVA `0x474BCC`). Because this evaluation occurs entirely in native C++ engine code, redscript and CET cannot intercept or redirect the ray.
- fix:
  1. Implement native callsite hooking in `src/Hooks/ShootingHook.cpp` inside `DetachedReticle.dll` (RED4ext native plugin):
     - Patch callsite RVA `0x9507B7` (`CALL 0x474BCC`) to redirect the ray origin to `muzzlePosition`.
     - Patch callsite RVA `0x9507EC` (`CALL 0x474BCC`) to redirect the ray direction to `muzzleForward`.
     - Validate player ownership via effect shared data (`playerOwnedWeapon == true`) and distance gating to avoid affecting environmental probes or NPCs.
     - Update effect blackboard shared data (`position` and `forward`) so downstream impact executors (`gameEffectExecutor_BulletImpact`, damage calculation, and decal spawners) register the physical hit along the gun barrel orientation.
  2. Register native RTTI global function `SetMuzzleAimState(muzzlePos: Vector4, muzzleFwd: Vector4, isDecoupled: Bool)` in `DetachedReticle.dll`, continuously fed by `gameuiCrosshairContainerController.UpdateDetachedAim()` and `ShootEvents.OnEnter` in redscript.
  3. Re-enable `PushAnimationEvent(n"RightShoot")` in redscript so normal weapon recoil slide animation functions seamlessly.
(user test timestamp: 2026-10-28 01:46:19 +0700)

(Note: at this point the first MVP has been achieved, the player can move the camera freely with gun unholstered, while left mouse click will make the gun shoots at the point of where the gun is pointing at)

#iteration 9
- error: Shotgun bullet spread becomes one (all pellets collapse into a single trajectory point without spread).
- error cause:
  1. In `Hooked_WaPhysicalRayForward` (`ShootingHook.cpp`), the hook previously discarded the evaluated ray direction `out` (which contains the engine-evaluated spread cone offset for each individual shotgun pellet) and unconditionally overwrote `out` with the identical static muzzle forward vector `s_muzzleFwd` for every ray. Consequently, all 8–12 shotgun pellets were forced into the exact same trajectory line.
  2. In `DetachedReticle.reds` and `init.lua`, `weapon.ShootStraight(true)` was previously called during earlier troubleshooting. `ShootStraight(true)` natively disables weapon spread and pellet dispersion in REDengine.
- fix:
  1. Removed `weapon.ShootStraight(true)` from `DetachedReticle.reds` and `init.lua` so natural weapon spread dispersion and shotgun pellet distribution remain fully active.
  2. Implemented frame-relative spread vector rotation (`RotateVectorFrame`) in `ShootingHook.cpp`. Instead of clobbering the pellet's angular spread, the hook extracts the relative angular deviation between the vanilla ray and camera forward, and rotates that spread cone around the physical barrel forward direction using unit quaternion rotation ($q = \text{Normalize}(1 + \vec{c} \cdot \vec{b}, \vec{c} \times \vec{b})$).
  3. Extended `SetMuzzleAimState` native RTTI global binding to pass `camFwd` alongside `muzzlePos` and `muzzleFwd`, ensuring mathematically exact rotation of the spread cone from camera space into barrel space for shotguns and all weapons.
(user test timestamp: 2026-10-28 02:30:19 +0700)

#iteration 10
- requirement:
  1. Catch-up speed must be modular and adjustable via options, allowing advanced algorithms to be plugged in dynamically.
  2. Zero deadzone by default (any mouse movement immediately turns the body / aiming direction).
  3. Deadzone, catch-up speed, max divergence, and algorithm selection must all be configurable via options.
  4. Chained Aiming Direction: Camera reticle (mouse-controlled) chains the Aiming Direction (body heading & upper-body rig) smoothly toward the camera view, while the Gun Reticle (physical weapon barrel) naturally follows the Aiming Direction via vanilla skeletal animations, weapon sway, and recoil.
- implementation:
  1. Modular Algorithms Architecture: Created `Algorithms` table in `init.lua` with pluggable smoothing functions:
     - `exponential`: Standard framerate-independent exponential approach ($1 - e^{-\lambda \cdot dt}$).
     - `linear`: Constant angular rate-limited rotation ($\text{speed} \times 15.0^\circ/\text{s}$).
     - `spring`: Critically damped smooth damp approximation preventing overshoot.
     - `power`: Progressive power-curve acceleration ($(\theta/\theta_{\text{max}})^{1.5}$) for responsive wide swings.
     - Registered extensible API: `DetachedReticle.RegisterAlgorithm(name, fn)` for runtime script registration.
  2. Zero Deadzone: Default `deadzone = 0.0^\circ`, ensuring instant body response upon any mouse movement. Fully configurable from $0.0^\circ$ to $30.0^\circ$.
  3. Comprehensive Options Interfaces:
     - Persistent file storage: `config.json` auto-loaded on startup and auto-saved on edits.
     - Native Settings UI: Registered in-game menu tab `/detachedReticle` with live sliders and selectors under Pause Menu -> Settings -> Mods.
     - CET ImGui Overlay UI: Live popup window in CET overlay (`onDraw`) with sliders, algorithm radio buttons, and status monitors.
     - CET Console API: `DetachedReticle.SetCatchUpSpeed(val)`, `DetachedReticle.SetDeadzone(val)`, `DetachedReticle.SetMaxDivergence(val)`, `DetachedReticle.SetSmoothingMode(mode)`, `DetachedReticle.GetOptions()`.
  4. Camera Reticle Stability: During the catch-up rotation step where the player puppet's world yaw advances by $\delta$, the camera's local offset decrements by $-\delta$. As a result, the camera view remains rock-solid in world space on the player's intended target, while the character body and weapon smoothly swivel into alignment.
  (user test timestamp: 2026-10-28 03:00:19 +0700)

#iteration 11
- error: Camera was actively being pulled back towards the aiming direction / center when moving the mouse, fighting the player's look input instead of the aiming direction rotating toward the camera.
- error cause:
  1. In `init.lua`, `player:GetWorldYaw()` was called inside a `pcall`; `GetWorldYaw` does not exist on `PlayerPuppet` in REDengine, causing `teleFac:Teleport(...)` to silently fail and never be invoked to rotate the player puppet.
  2. Because the puppet body never turned, `freeYaw = freeYaw - yawStep` decayed the camera's local angle back to zero every frame, actively dragging the camera freelook away from the player's intended aim point.
- fix:
  1. Isolated Camera Freelook: `intendedWorldYaw`, `freeYaw`, and `freePitch` are now strictly and exclusively driven by raw mouse input (`rawMouseX`, `rawMouseY`). Under no circumstances does catch-up, decay, spring, or clamp touch or alter `freeYaw` or `intendedWorldYaw`.
  2. Valid Body Orientation API: Used valid REDengine API `Vector4.Heading(player:GetWorldForward())` / `math.atan2(fwd.y, fwd.x)` to measure current body yaw and rotate the player puppet towards `intendedWorldYaw` via `TeleportationFacility.Teleport`.
  3. Stationary Camera in World Space: Set `fpp:SetLocalTransform` relative yaw to `normalizeDeg(intendedWorldYaw - currentBodyYaw)`. The camera in world space remains 100% stationary on the mouse aim point while the character body and weapon swivel smoothly into alignment.
  4. Outward Divergence Clamp: Clamped max divergence by pulling the body along rather than pulling the camera back.
(user test timestamp: 2026-10-28 03:23:19 +0700)

#iteration 12
- error: The camera rotates ~90 degrees to the left and tilts (rolls) to the left when gun is unholstered, with severe shaking left-to-right every frame.
- error cause:
  1. Angle Convention Mismatch: `init.lua` measured body yaw as `math.deg(math.atan2(fwd.y, fwd.x))` (cartesian 0° at +X, 90° at +Y), but wrote heading via `Teleport(player, pos, EulerAngles.new(0, 0, yaw))` where engine forward is +Y (0°). Teleporting shifted the body by 90°, producing cyclical divergence and per-frame shaking.
  2. Gimbal Roll in Compound Transform: `Rx(-entryPitch) * Rz(yaw) * Rx(entryPitch + freePitch) * baselineRot` rotates around an axis tilted by entry pitch, introducing camera roll proportional to `sin(entryPitch) * yaw`.
  3. Pitch Divergence Affecting Yaw: Pitch was included in `divergenceMag`, causing vertical mouse looks to yank body yaw via Teleport.
  4. Architectural Limits of Teleportation: `PlayerPuppet` in REDengine has no world pitch (cannot pitch the body). `Teleport` also disrupts character controller locomotion, physics velocity integration, and footstep timing.
- fix (architectural pivot):
  - Transition from Teleportation to "Chase the Mouse" input smoothing (Round 4 design). Feed smoothed deltas to vanilla's native input integrator so body yaw and arm pitch are handled natively and seamlessly by REDengine, while the camera receives the residual offset.
(user test timestamp: 2026-10-28 23:40:44 +0700)

#iteration 13
- test: Round 4 Probes L1 (raw mouse routing observation) and L3 (script-side camera yaw lock test).
- results:
  1. Mouse X (Yaw) Routing (S1 Yaw: Confirmed): Across frames F=10 to F=8233, mouse X input (`rawX`) directly turns `bodyYaw` with an exact linear sensitivity ratio of `0.0500 deg / count` (e.g., `rawX = -7.0` -> `ΔbodyYaw = +0.3500°`, `rawX = 63.0` -> `ΔbodyYaw = -3.1500°`). During pure yaw turning, `camLocalYaw` remains at `0.0000` and `camWorldYaw` matches `bodyYaw` with zero offset.
  2. Mouse Y (Pitch) Routing (S1 Pitch: Branch F2): `camLocalPitch` remained strictly `0.0000` throughout the entire test despite `rawY` reaching +12.0 and -10.0. This confirms Branch F2: pitch is NOT integrated into the component's script-accessible local orientation quaternion; it is stored inside `FPPCameraComponent`'s native C++ pitch accumulator (`ResetPitch()`).
  3. Camera Component Persistence (S2: Refuted): In Probe L3, multiplying `qRz` onto `fpp:GetLocalOrientation()` compounded across frames, spinning the camera 360°. This refutes S2: vanilla does NOT clobber or reset `fpp:GetLocalOrientation()` every frame. Component local orientation is persistent state. Script-driven offsets must be computed from a fixed baseline socket transform or handled natively.
- fix:
  1. Route A Native RTTI Probing (`DetachedReticle.dll`): Added `InputHook` subsystem with `ProbeRTTI()` running in `PostRegisterTypes`. Probes `gameFPPCameraComponent`, `FPPCameraComponent`, `CameraComponent`, `entCameraComponent`, and `PlayerPuppet`. For every class, dumps properties (name, type, offset) and functions (name, `regIndex`, native status, handler RVA, and disassembles `CALL rel32` destination target RVAs). Full report saved to `red4ext/plugins/DetachedReticle/rtti_probe.log`.
  2. Native Scripting Bridge: Registered global functions in `Main.cpp`:
     - `DR_SetSmoothing(lambda: Float, mode: Int32, maxDiv: Float, deadzone: Float, enabled: Bool)`
     - State getters: `DR_GetTargetYaw()`, `DR_GetTargetPitch()`, `DR_GetAimYaw()`, `DR_GetAimPitch()`, `DR_GetResidualYaw()`, `DR_GetResidualPitch()`
     - `DR_DrainEvents() -> String`
  3. Script Event Drain: Added native event draining in `init.lua` onUpdate to capture `[N0]` and `[N1]` probe events directly into `DetachedReticle.log`.
  4. DLL Rebuild: Compiled `DetachedReticle.dll` with MSVC 19.38 / Ninja and deployed to `E:\Cyberpunk 2077\red4ext\plugins\DetachedReticle\DetachedReticle.dll`.
(user test timestamp: 2026-10-29 00:48:04 +0700)

#iteration 14
- error:
  1. In Probe L3, moving the mouse caused continuous, runaway camera spinning in the direction of the movement (like a mouse joystick axis with persistent deflection). When the mouse stopped, the camera kept spinning continuously until mouse was moved opposite.
  2. `rtti_probe.log` file was not created on disk because the relative path in the DLL evaluated relative to `<GAME_ROOT>\bin\x64`, where the `red4ext/plugins/...` folder hierarchy does not exist.
- error cause:
  1. Compounding Transform Spin (S2 Refuted): `init.lua` re-read `localRot = fpp:GetLocalOrientation()` every frame and multiplied `targetRot = quatMultiply(qRz, localRot)`. Because camera component local orientation is stateful and persistent across frames in REDengine, multiplying `qRz` onto the *already rotated* orientation re-integrated the angular offset every single frame (e.g. -8.37° per frame), turning a static position offset into continuous angular velocity.
  2. Relative Working Directory: Cyberpunk2077.exe working directory is `bin\x64`. `std::ofstream("red4ext/...")` failed because `red4ext` is at the game root, not under `bin\x64`.
- fix:
  1. Non-Compounding Camera Lock: Updated `init.lua` to capture `baselineRot = fpp:GetLocalOrientation()` ONCE when locked. Each frame, the camera transform is computed as `targetRot = quatMultiply(qRz, baselineRot)`. When the mouse stops, the camera offset remains fixed and does not compound.
  2. Transform Cleanup on Exit: Added restore logic in `init.lua` on holster, deactivate, and probe mode change to restore `fpp:SetLocalTransform` back to `baselineRot`, preventing residual rotation leaks.
  3. Guaranteed Probe Log Path: Updated `InputHook.cpp` to write `rtti_probe.log` directly into `plugins/cyber_engine_tweaks/mods/DetachedReticle/rtti_probe.log` (guaranteed writeable directory).
  4. DLL & Script Deployed: Recompiled `DetachedReticle.dll` and deployed both DLL and `init.lua` to game directories.
(user test timestamp: 2026-10-29 00:59:35 +0700)

#iteration 15
- test: Round 4 Probe L3 (camera world-lock test with baseline orientation) and Route A RTTI probe.
- results:
  1. Camera World-Lock (S3: Confirmed): Camera world yaw remained rock-solid on heading `41.7454°` with `err = -0.0085°` across all frames (F=3449 to F=3505), completely eliminating continuous spin.
  2. Decoupling Verified (S6: Confirmed): Moving the mouse turned the character body and arms horizontally and tilted arms vertically, while the camera remained fixed on its world heading. Proves that the upper-body/weapon rig tracks the body and native pitch accumulator, completely independent of the camera component transform.
  3. Route A RTTI Dump Successfully Extracted (`rtti_probe.log`):
     - `gameFPPCameraComponent` size: `0x510`, parent: `gameCameraComponent`.
     - Key Properties:
       - `pitchMin`: offset `0x3e0` (Float)
       - `pitchMax`: offset `0x3e4` (Float)
       - `yawMaxLeft`: offset `0x3e8` (Float)
       - `yawMaxRight`: offset `0x3ec` (Float)
       - `headingLocked`: offset `0x3f6` (Bool)
       - `sensitivityMultX`: offset `0x498` (Float)
       - `sensitivityMultY`: offset `0x49c` (Float)
     - Member Functions: `ResetPitch` (regIdx 13284), `ResetCurrentGameplayInput` (regIdx 13285), `SceneDisableBlendingToStaticPosition` (regIdx 13286).
- fix:
  1. Route A Disassembly & Scanner Fixes (`DetachedReticle.dll`):
     - Expanded `TryGetHandler` regIndex bound from 8,192 to 65,536 so `ResetPitch` (regIdx 13284) and `ResetCurrentGameplayInput` (regIdx 13285) are evaluated and their machine code bytes are logged.
     - Added `ScanSensitivityMultAccess` to scan `.text` in `Cyberpunk2077.exe` for references to `sensitivityMultX` (offset `0x498`) and `sensitivityMultY` (offset `0x49c`) to locate the native input integrator callsites.
  2. Implemented Probe L4 (Chase Decoupled Aim Prototype):
     - Raw mouse input moves the Camera Aim Target ($T$) instantly via `0.0500 deg/count`, driving `fpp:SetLocalTransform` relative to immutable baseline, while the character body and weapon ($A$) stay on body heading.
  3. Recompiled and deployed `DetachedReticle.dll` and `init.lua` to game directories.
(user test timestamp: 2026-10-29 01:13:22 +0700)

#iteration 16
- test: Round 4 Probe L4 in-game telemetry analysis and Route A `.text` disassembly scan inspection.
- results:
  1. Vanilla Concurrency in Probe L4: In-game telemetry (`DetachedReticle.log:4216-4590`) revealed that horizontal mouse input (`rawX`) updated both `intendedTargetYaw` and vanilla `bodyYaw` at the identical rate (`0.0500 deg/count`), causing `divergence` to remain locked at `-1.1999°`. The body turned synchronously with the camera target because vanilla mouse integration was concurrently active on the body.
  2. Native Mouse Integrator Call Location (Scan Hits #294 & #295): The native `.text` scanner located the exact instruction block where REDengine integrates mouse deltas into camera and body orientation in `Cyberpunk2077.exe`:
     - RVA `0x2463D0E`: `movss xmm0, dword ptr [rax+0x8]` (raw mouse X delta)
     - RVA `0x2463D13`: `mulss xmm0, dword ptr [rdi+0x498]` (scales yaw by `FPPCameraComponent.sensitivityMultX`)
     - RVA `0x2463D1B`: `movss xmm1, dword ptr [rax+0x4]` (raw mouse Y delta)
     - RVA `0x2463D20`: `mulss xmm1, dword ptr [rdi+0x49C]` (scales pitch by `FPPCameraComponent.sensitivityMultY`)
     - RVA `0x2463D28`: `subss xmm9, xmm0` (subtracts yaw delta into native body yaw accumulator `xmm9`)
     - RVA `0x2463D35`: `subss xmm10, xmm1` (subtracts pitch delta into native pitch accumulator `xmm10`)
     - Register `rdi` holds `gameFPPCameraComponent*`.
  3. Native Gating Mechanism (S7 Confirmed): Properties `sensitivityMultX` (offset `0x498`) and `sensitivityMultY` (offset `0x49C`) directly scale mouse deflection before accumulation. When set to `0.0`, vanilla body yaw and arm pitch turning from mouse is completely halted without altering locomotion physics.
- fix:
  1. Native Sensitivity Controls (`DetachedReticle.dll`):
     - Added native RTTI functions `DR_SetSensitivityMult(fpp, multX, multY)`, `DR_GetSensitivityMultX(fpp)`, and `DR_GetSensitivityMultY(fpp)`.
     - Directly reads and writes `float` offsets `0x498` and `0x49C` on `gameFPPCameraComponent`, bypassing any script property restriction.
  2. Decoupled Aim Sensitivity Gating (`init.lua`):
     - In Probe L4: reads and logs `sensitivityMultX` and `sensitivityMultY` baseline values.
     - When decoupled mode is active: sets `sensitivityMultX = 0.0` (and `sensitivityMultY = 0.0`), freezing vanilla mouse-to-body coupling so moving the mouse updates camera look target $T$ while body/weapon heading $A$ remains independent.
     - Restores original sensitivity multipliers on holster, deactivate, or mode change.
  3. DLL & Script Deployed: Recompiled `DetachedReticle.dll` and deployed DLL and `init.lua` to game directories.

(user test timestamp: 2026-10-29 01:37:04 +0700)

#iteration 17
- test: Round 4 Probe L4 sensitivity multiplier gating and pitch decoupling verification.
- results:
  1. Pitch Decoupling Confirmed: Setting `sensitivityMultY = 0.0` on `gameFPPCameraComponent` completely prevented the weapon/arms and upper body from pitching ("aiming direction stays level"). The camera pitched independently while the weapon remained level, proving pitch decoupling is natively controlled via offset `0x49C`.
  2. Pitch Sign Inversion: Moving the mouse UP tilted the camera DOWN due to negative mouse count convention in the quaternion pitch offset.
  3. Native Heading Lock Bypass Discovered (RVA `0x0039CAFE`): When moving mouse horizontally, `bodyYaw` still rotated because player puppet yaw turning is governed by the heading lock gate at RVA `0x0039CAFE`:
     - RVA `0x0039CAFE`: `80 BF F6 03 00 00 00` -> `cmp byte ptr [rdi+0x3F6], 0`
     - RVA `0x0039CB08`: `0F 85 17 01 00 00` -> `jne 0x0039CC25` (jumps over the entire mouse yaw integrator block when heading is locked)
     - Offset `0x3F6` on `gameFPPCameraComponent` is `headingLocked` (Bool). Setting `headingLocked = true` natively freezes player puppet body yaw rotation from mouse input.
- fix:
  1. Pitch Sign Inversion Fix (`init.lua`): Changed mouse pitch integration to `+ (rawY * 0.0500)` so moving mouse UP tilts the camera UP.
  2. Native Heading Lock Control (`DetachedReticle.dll`):
     - Added native RTTI functions `DR_SetHeadingLocked(fpp, locked)` and `DR_GetHeadingLocked(fpp)`.
     - Directly reads and writes `bool` byte at offset `0x3F6` on `gameFPPCameraComponent`.
  3. Decoupled Free-Aim Prototype Integration (`init.lua`):
     - In Probe L4: enables `headingLocked = true` and zeroes `sensitivityMultY = 0.0`, completely decoupling both yaw and pitch from the weapon and character body.
     - Moving the mouse steers camera look target $T$ freely across both axes.
     - Restores original `headingLocked` and sensitivities on holster, deactivate, or exit.
  4. DLL & Script Deployed: Recompiled `DetachedReticle.dll` and deployed DLL and `init.lua` to game directories.
(user test timestamp: 2026-10-29 01:50:20 +0700)

#iteration 18
- test: Round 4 Probe L4 full decoupling verification (heading lock + pitch sensitivity freeze + live ballistics shot).
- results:
  1. Complete Body Yaw Freeze (S8 Confirmed): Telemetry in `DetachedReticle.log:F=920-F=975` showed `bodyYaw` held rock-solid at `42.1221°` with zero drift across all frames while horizontal mouse inputs were actively firing (`rawX = 1.0`). `headingLocked = true` completely decoupled mouse turning from the character puppet entity.
  2. Independent Pitch Look: Camera pitch traversed smoothly from `-11.6000°` to `+20.1000°` while the weapon and character body remained level in the aiming direction.
  3. Live Decoupled Ballistics Fired (Record #11): At frame 975, a shot was fired during active decoupled aim. The native `ShootingHook` intercepted the PhysicalRay, evaluated origin at the weapon muzzle `(-1543.90, 1211.08, 17.02)`, and launched the bullet along the barrel vector `(-0.666, 0.744, -0.055)` with an angle of `23.30°` from the camera view direction. Decoupled aim and physical muzzle ballistics are fully validated simultaneously.
  4. Missing Chase Dynamics: User confirmed that with L4 selected, the camera freelook and ballistics were decoupled, but the character body remained statically frozen in place with no dynamic smooth chase, because `headingLocked = true` held the puppet completely still without a chase integrator.
- fix:
  1. Universal Look Integration Funnel Discovered (RVA `0x39CB63`):
     - Disassembled `Cyberpunk2077.exe` around RVAs `0x39CB00` - `0x39CC30` and `0x2463C40` - `0x2463D40`.
     - Proved that regardless of which branch is taken (`0x39CB47` fast path or `0x2463C78` / `0x2463D13` look path), all look input paths converge at RVA `0x39CB63` before calling orientation update `0x39CD44`.
     - At RVA `0x39CB63`, register `rdi` holds `gameFPPCameraComponent*`, register `xmm9` holds the final yaw delta, and `xmm10` holds the final pitch delta.
  2. Native Mouse Look Relay Hook (`MouseLookRelay.asm` & `InputHook.cpp`):
     - Implemented near-callsite patch at RVA `0x39CB63` replacing 11 displaced bytes (`mov rdx, [rdi+50h]; mov rax, [rdx+0B8h]`) with a 5-byte `CALL <relay>` and 6 NOPs.
     - Written in MASM (`ml64.exe`) to guarantee 16-byte stack alignment, full volatile register preservation (`rax, rcx, rdx, r8-r11, xmm0-xmm1`), execution of displaced instructions, and clean return.
     - In `InputHook::ProcessMouseAim`:
       - When decoupled mode is active: advances target $T$ with mouse deltas, evaluates smoothed chase delta $dA = (T - A) \times (1 - \exp(-\lambda \cdot dt))$ with deadzone and max divergence clamping, updates aiming direction $A$, and outputs $dA$ into `xmm9` (yaw) and `xmm10` (pitch).
       - Stores camera residuals $R_{yaw} = T_{yaw} - A_{yaw}$ and $R_{pitch} = T_{pitch} - A_{pitch}$.
       - When decoupled mode is OFF: passes raw deltas directly (100% vanilla passthrough).
  3. Script Integration (`init.lua`):
     - Probe L4 enables native smoothing via `Game.DR_SetSmoothing(catchUpSpeed, 0, maxDiv, deadzone, true)` and keeps `headingLocked = false` so REDengine applies $dA$ to rotate the body and arms.
     - In `onUpdate`: reads native residuals via `Game.DR_GetResidualYaw()` and `Game.DR_GetResidualPitch()`, and applies them to camera local orientation via `fpp:SetLocalTransform`.
     - Resets camera and disables native smoothing on unequip or mode switch.
  4. Built and Deployed: Compiled `DetachedReticle.dll` using CMake (Ninja toolchain) and deployed DLL and `init.lua` to game directories.
(user test timestamp: 2026-10-29 01:57:05 +0700)

#iteration 19
- test: In-game verification of Native Dynamic Smooth Chase via Probe L4 (Look Funnel Hook at RVA `0x39CB63`).
- results:
  1. Instant Camera Response: User confirmed "camera responds instantly with mouse, no lag".
  2. Dynamic Smooth Chase Validated (Vertical Axis): User confirmed "the weapon, hands, and player body smoothly swings and catch up to where i'm looking, but the 'weight' only visible and looks proper on vertical movements." In-game telemetry (`DetachedReticle.log:F=4989-F=5100`) verified `rPitch` climbing smoothly up to `+4.48°` under mouse deflection and decaying smoothly to `0.0°` (`4.48 -> 1.00 -> 0.75 -> 0.11 -> 0.0`) when mouse stopped.
  3. Horizontal Look Funnel Branch Bypass Identified: On horizontal movements, aiming direction remained 1:1 with camera movement (`rYaw = 0.0000` constantly in log). Disassembly at RVA `0x39CB32` (`ucomiss xmm11, xmm6`) revealed horizontal deflection triggers a branch jump to `0x2463C4E`, which evaluates deflection and re-enters downstream at `0x39CB65` (offset +2 into our 5-byte `CALL` at `0x39CB63`), completely skipping yaw interception.
- fix:
  1. Universal Mouse Look Entry Hook Discovered (RVA `0x39CA70`):
     - Traced mouse look to the root function entry point `gameFPPCameraComponent::OnMouseLook` at RVA `0x39CA70`.
     - Inputs: `rcx = gameFPPCameraComponent*`, `xmm2 = rawYaw` float delta, `xmm3 = rawPitch` float delta before ANY branch conditions, deflection thresholds, or deflection splits execute.
     - Displaced 11 bytes: `48 8B C4 48 89 58 08 48 89 78 10` (`mov rax, rsp; mov [rax+8], rbx; mov [rax+10h], rdi`).
  2. 5-byte JMP Trampoline Relay (`MouseLookRelay.asm`):
     - Uses 5-byte `JMP rel32` (`0xE9`) instead of `CALL` to prevent stack alignment corruption at the function prologue.
     - MASM relay allocates 16-byte aligned stack frame (`sub rsp, 88h`), preserves all volatile registers (`rax, rcx, rdx, r8-r11, xmm0-xmm1`), spills `xmm2` and `xmm3`, calls `OnNativeMouseAim(rcx, &yawDelta, &pitchDelta)`, restores updated deltas into `xmm2` and `xmm3`, executes the 11 displaced bytes, and jumps via 64-bit indirect `jmp [g_lookReturnAddr]` to `s_exeBase + 0x39CA7B`.
  3. Symmetric Filter & Camera Yaw Inversion (`InputHook.cpp` & `init.lua`):
     - Both `xmm2` (yaw) and `xmm3` (pitch) are symmetrically filtered by the exponential chase integrator in `ProcessMouseAim`.
     - In `init.lua`, inverted `rYaw` in `quatAxisAngle(0, 0, 1, -rYaw)` so screen-space mouse right (+X delta) maps to negative Z rotation (right) in Cyberpunk's coordinate convention.
     - Set default `probeMode = "L4"` in `init.lua`.
  4. Compiled and Deployed: Rebuilt `DetachedReticle.dll` with Ninja and deployed DLL and `init.lua` to game directories.
(user test timestamp: 2026-10-29 02:25:12 +0700)

#iteration 20
- test: In-game verification of universal mouse look entry hook at RVA `0x39CA70` for symmetric horizontal and vertical smooth chase and physical weight.
- results:
  1. Vertical Movement Preserved: Vertical movement remained smooth with proper weight and inertia as in iteration 19.
  2. Gun Moved Ahead of Camera Horizontally: User reported that moving mouse to the right made the gun/hand move ahead to the right first rather than lagging behind, followed by an oscillating drift back to center when stopping.
  3. Zero-Yaw Entry Point Root Cause Discovered: Disassembly of the 4 engine call sites calling RVA `0x39CA70` (`0x51D488`, `0x7E6F1C`, `0x2AD2A53`, `0x2E3A0C2`) revealed that call site `0x51D488` explicitly zeroes `xmm2` via `0F 57 D2` (`xorps xmm2, xmm2`). Raw mouse X delta is NOT passed into function entry `0x39CA70`; it is read internally at RVA `0x2463D0E` and subtracted directly into accumulator `xmm9`. Consequently, `xmm2` at function entry was always `0.0000`, explaining why `rYaw` remained `0.0000` in telemetry.
  4. Camera Quaternion Sign Inversion: The `-rYaw` change in `init.lua` flipped camera rotation to the left when moving right, creating the appearance of the gun moving ahead of the gaze.
- fix:
  1. True Universal Look Funnel Call Discovered (RVA `0x39CBE3`):
     - Traced execution from `0x2463D3B` back into `sub_39CA70` at `0x39CB64`. All look pathways converge at RVA `0x39CBE3` on a 5-byte `CALL`:
       - `0x39CBE3`: `E8 74 01 00 00` -> `call 0x39CD5C` (`ApplyOrientationDeltas`).
       - Next instruction at `0x39CBE8`: `4C 8D 9C 24 20 01 00 00` (`lea r11, [rsp+120h]`).
     - Right before `0x39CBE3`:
       - `rcx` = `gameFPPCameraComponent*`
       - `xmm2` = `xmm9` (**Complete combined yaw delta, including Mouse X**)
       - `xmm3` = `xmm10` (**Complete combined pitch delta, including Mouse Y**)
  2. Clean 5-Byte Tail-Call MASM Trampoline (`MouseLookRelay.asm` & `InputHook.cpp`):
     - Patches exact 5-byte call at RVA `0x39CBE3` (`E8 <rel32>`), replacing `call 0x39CD5C` with `call MouseLookRelay`. Zero NOPs, zero displaced instructions.
     - `MouseLookRelay` allocates 16-byte aligned stack, preserves registers, spills `xmm2` and `xmm3`, calls `OnNativeMouseAim(rcx, &yaw, &pitch)`, restores updated chase deltas into `xmm2` and `xmm3`, restores registers, and tail-calls via 64-bit indirect `jmp [g_origTargetAddr]` directly into `s_exeBase + 0x39CD5C`.
     - `0x39CD5C` returns directly to `0x39CBE8`, leaving stack layout 100% transparent.
  3. Sign Correction (`init.lua`):
     - Changed `qRz` back to `quatAxisAngle(0.0, 0.0, 1.0, rYaw)` (positive angle = left, negative angle = right, matching negative mouse delta convention).
     - Added `s_displayTargetYaw` and `s_displayAimYaw` to report accurate non-zero telemetry in `DetachedReticle.log`.
  4. Built and Deployed: Rebuilt `DetachedReticle.dll` and deployed DLL and `init.lua` to game directories.
(user test timestamp: 2026-10-29 03:20:27 +0700)

#iteration 21
- test: In-game verification of true look funnel call hook at RVA `0x39CBE3` (`call 0x39CD5C`) for symmetric horizontal and vertical smooth chase and physical weight.
- results:
  1. Instant Camera and Gun Horizontal Turning: User reported "when moving mouse left/right, the camera turn instantly, but the gun/hand also turn instantly, doesn't smoothly lag behind."
  2. Telemetry and Component Scope Root Cause Discovered:
     - Disassembly of `sub_39CD5C` revealed it directly mutates `FPPCameraComponent` local orientation state.
     - However, in first-person gameplay, the player puppet entity's world yaw (which rotates the player body, upper torso, arms, and weapon rig) is NOT driven by `FPPCameraComponent`'s local yaw.
     - Disassembly of caller `0x51D488` revealed it explicitly zeroes `xmm2` via `0F 57 D2` (`xorps xmm2, xmm2`) before calling `FPPCameraComponent::OnMouseLook` (`0x39CA70`).
     - Tracing backwards into the caller function `sub_51D380`, at RVA `0x51D462`:
       `F3 0F 11 B1 9C 00 00 00` (`movss dword ptr [rcx+9Ch], xmm6`)
       `rcx` is the player puppet orientation accumulator object.
       `xmm6` is the raw Mouse X yaw delta (post-sensitivity)!
       It writes raw mouse yaw directly into `[rcx+9Ch]`, bypassing `FPPCameraComponent` completely.
       Then at `0x51D48B`:
       `movaps xmm3, xmm7` (Camera Pitch Delta)
       `call 0x39CA70` (`FPPCameraComponent::OnMouseLook`).
     - Modifying `FPPCameraComponent` deltas at `0x39CBE3` only influenced camera orientation, while puppet body yaw was being updated upstream at `0x51D462` without smoothing.
- fix:
  1. Relocate native look interceptor to RVA `0x51D462` (`movss dword ptr [rcx+9Ch], xmm6`), where both puppet body yaw (`xmm6`) and camera pitch (`xmm7`) originate simultaneously from mouse input.

#iteration 22
- test: In-game verification of the Primary Gameplay Look Integrator Hook at RVA `0x51D462` (`movss [rcx+9Ch], xmm6`).
- results:
  1. Instant Freelook: Mouse gaze moves the camera reticle instantly with zero input lag, crisp response, and no wobble or unwanted drift.
  2. Symmetrical Physical Weight & Smooth Chase: When moving the mouse, the weapon, hands, and player puppet body smoothly lag behind and chase the camera gaze with realistic inertia on both horizontal (yaw) and vertical (pitch) axes.
  3. Seamless Convergence: When mouse movement stops, the character body and weapon settle smoothly onto the camera reticle without overshoot or oscillation.
  4. Physical Muzzle Ballistics Intact: Bullets originate physically at the weapon barrel muzzle in 3D world space and fire along the barrel vector, fully decoupled from the camera gaze direction.
  5. Dual Reticle Harmony: Camera center diamond indicates intended gaze, while the projected weapon crosshair tracks the physical barrel orientation.
  6. Milestone Verdict: User confirmed: *"it works perfectly now, MVP 2 is done."*
- fix:
  1. Production Release of Native Decoupled Aim System (v2.0.0):
     - RVA `0x51D462` established as authoritative native look integrator callsite in `Cyberpunk2077.exe` 2.50.
     - Hook verified using 8-byte near-call relay (`E8 <rel32>` + 3 NOPs) to `MouseLookRelay.asm`.
     - Preserves all registers, computes chase deltas via exponential decay model, feeds smoothed `xmm6` into puppet yaw accumulator `[rcx+9Ch]`, and feeds smoothed `xmm7` into camera pitch `xmm3` at `0x51D48B`.
     - Residuals ($R_{yaw} = T_{yaw} - A_{yaw}$, $R_{pitch} = T_{pitch} - A_{pitch}$) applied to `FPPCameraComponent` via CET `init.lua` for instantaneous freelook.
  2. Cleaned production files: Removed all temporary probe modes (`L1`, `L3`, `L4`) and probe selectors from CET script and UI. Defaulted to clean production settings with master toggle and modular sliders.
(user test timestamp: 2026-10-29 04:16:55 +0700)

---

## Assumptions Ledger

| # | Assumption | Status | Evidence |
|---|---|---|---|
| A1 | `ShootEvents.OnEnter` is where the bullet is fired, so suppressing its calls stops the camera ray | **Refuted** (iteration 8) | Mode 1 suppressed everything in `OnEnter` and the bullet still fired. The ray comes from native `SetTriggerDown` to `gameEffectObjectProvider_PhysicalRay`. |
| A2 | `EffectPreAction_PreAttack.Process` overrides of `position`/`forward`/`raycastEnd` redirect the ray | **Refuted** (iterations 5 to 7) | Blackboard writes did not move the hitscan ray. |
| A3 | `weapon.ShootStraight(true)` redirects along the barrel | **Refuted**, and harmful | Disables spread (iteration 9). Removed. |
| A4 | `AI_ShootForwards`, `StartContinuousAttack`, `CreateEffectStatic(n"weaponShoot")` from script fire along a given vector for the player | **Refuted** (iterations 6 to 8) | All modes hit the camera reticle. |
| A5 | `TriggerWeaponEffects(..., Shoot)` generates the camera-converging tracer | **Refuted** | Suppressing it did not change where the bullet hit (iteration 8). |
| A6 | Native callsite patch of the PhysicalRay input evaluator redirects origin and direction | **Confirmed empirically** by owner (iteration 8) | Build-specific RVAs; hook checks `E8` and call target before patching. |
| A7 | `GetWorldYaw` does not exist on `PlayerPuppet` | **Refuted** | `core/entity/entity.script:26`, `PlayerPuppet` inherits `Entity.GetWorldYaw()`. |
| A8 | `math.atan2(fwd.y, fwd.x)` equals engine yaw | **Refuted** (iteration 12) | Engine forward is +Y, cartesian atan2 is 90° out of phase. |
| A9 | `EulerAngles.new(0, 0, yaw)` sets yaw | **Confirmed** | CET `BasicTypes.h`: `EulerAngles(roll, pitch, yaw)`. |
| A10 | `Rx(-p) * Rz(yaw) * Rx(p + free) * baseline` is a pure yaw plus pitch | **Refuted** | Introduces roll proportional to `sin(p) * yaw`. |
| A11 | Per-frame `TeleportationFacility.Teleport` is a viable way to rotate the player body | **Refuted as viable design** | Causes locomotion, physics, and footstep issues; cannot actuate pitch. |
| A12 | The anim graph makes the gun follow the camera pitch set through `SetLocalTransform` | **Refuted** (MVP 1) | The gun stayed fixed while the camera pitched via script. |
| A13 | `redscript_rCURRENT.log` and `FTLog` can show runtime telemetry | **Refuted** (iteration 5) | File logging via CET `io.open` and native hook's `ofstream` is what works. |
| A14 | Bare `Vector4(...)` and `EulerAngles` struct construction compile on redscript 0.5.32 | **Confirmed** | Redscript 0.5.32 handles struct construction without `new`. |
| S1 (Yaw) | Mouse X is integrated directly into player puppet body yaw | **Confirmed** (iteration 13) | Linear constant 0.0500 deg/count; camLocalYaw remains 0. |
| S1 (Pitch) | Mouse Y is integrated into camera component local orientation quaternion | **Refuted** (iteration 13) | camLocalPitch remains 0.0000; pitch lives in native accumulator (Branch F2). |
| S2 | Vanilla rewrites camera component local orientation every frame | **Refuted** (iteration 13) | Component local orientation is stateful and persistent; relative multiplies compound. |
| S3 | Script-side camera write can hold still in world space from immutable baseline | **Confirmed** (iteration 14) | err = -0.0085° across all frames (F=3449 to F=3505) without any drift or spin. |
| S6 | Upper-body and arms follow body yaw and native pitch, decoupled from camera component | **Confirmed** (iteration 14) | Mouse moved hand/arms horizontally and tilted vertically while camera remained locked. |
| S7 | Mouse integration into body yaw and pitch accumulator is gated by `sensitivityMultX` (0x498) and `sensitivityMultY` (0x49C) at RVA 0x2463D13 | **Confirmed** (iteration 15) | Scan hits #294/#295 in Cyberpunk2077.exe: `mulss xmm0, [rdi+498h]`, `mulss xmm1, [rdi+49Ch]`, subtracted into accumulators xmm9 & xmm10. |
| S8 | Player puppet body yaw rotation from mouse input is gated by `headingLocked` (offset 0x3F6) at RVA 0x0039CAFE | **Confirmed** (iteration 16) | `cmp byte ptr [rdi+3F6h], 0; jne 0x0039CC25` bypasses yaw integration when true. |
| S9 | Horizontal look branch at RVA 0x39CB32 bypasses mid-pipeline funnel hook at 0x39CB63 | **Confirmed** (iteration 19) | `rYaw` stayed `0.0000` while `rPitch` varied `-7.4°` to `+4.48°` because horizontal deflection jumps to `0x2463C4E` and re-enters at `0x39CB65`. |
| S10 | Function entry at RVA 0x39CA70 receives raw mouse X in `xmm2` | **Refuted** (iteration 20) | Caller at RVA `0x51D488` zeroes `xmm2` via `xorps xmm2, xmm2`; mouse X is read internally at `0x2463D0E` into accumulator `xmm9`. |
| S11 | Exact 5-byte callsite at RVA `0x39CBE3` (`call 0x39CD5C`) is the universal orientation applicator | **Refuted for body yaw** (iteration 21) | `0x39CD5C` only rotates `FPPCameraComponent`; body yaw is updated upstream at `0x51D462`. |
| S12 | Primary gameplay look integrator at RVA `0x51D462` (`movss [rcx+9Ch], xmm6`) feeds puppet yaw while `0x51D48B` feeds camera pitch | **Confirmed** (iteration 22) | Intercepting `xmm6` (yaw) and `xmm7` (pitch) at `0x51D462` achieves fully symmetric smooth chase and decoupled ballistics. |




