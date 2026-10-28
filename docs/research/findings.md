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

