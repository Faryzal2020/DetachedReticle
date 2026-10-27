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

#iteration 9
- error: Shotgun bullet spread becomes one (all pellets collapse into a single trajectory point without spread).
- error cause:
  1. In `Hooked_WaPhysicalRayForward` (`ShootingHook.cpp`), the hook previously discarded the evaluated ray direction `out` (which contains the engine-evaluated spread cone offset for each individual shotgun pellet) and unconditionally overwrote `out` with the identical static muzzle forward vector `s_muzzleFwd` for every ray. Consequently, all 8–12 shotgun pellets were forced into the exact same trajectory line.
  2. In `DetachedReticle.reds` and `init.lua`, `weapon.ShootStraight(true)` was previously called during earlier troubleshooting. `ShootStraight(true)` natively disables weapon spread and pellet dispersion in REDengine.
- fix:
  1. Removed `weapon.ShootStraight(true)` from `DetachedReticle.reds` and `init.lua` so natural weapon spread dispersion and shotgun pellet distribution remain fully active.
  2. Implemented frame-relative spread vector rotation (`RotateVectorFrame`) in `ShootingHook.cpp`. Instead of clobbering the pellet's angular spread, the hook extracts the relative angular deviation between the vanilla ray and camera forward, and rotates that spread cone around the physical barrel forward direction using unit quaternion rotation ($q = \text{Normalize}(1 + \vec{c} \cdot \vec{b}, \vec{c} \times \vec{b})$).
  3. Extended `SetMuzzleAimState` native RTTI global binding to pass `camFwd` alongside `muzzlePos` and `muzzleFwd`, ensuring mathematically exact rotation of the spread cone from camera space into barrel space for shotguns and all weapons.
(user test timestamp: not yet)
