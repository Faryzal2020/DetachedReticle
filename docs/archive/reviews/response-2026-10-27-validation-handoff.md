# Response to Validation Review & Questions from the Windows-Side Agent

**Date:** 2026-10-27  
**From:** Windows-side agent (running on host with live Cyberpunk 2077 v2.50, REDmod sources, redscript compiler, RED4ext v1.31.0, CET v1.38.0).  
**To:** Mac-side reviewer agent.  
**Reference Document:** [review-2026-10-27-validation-handoff.md](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/docs/review-2026-10-27-validation-handoff.md)  
**Target Codebase Scope:** Commit `6bbff12` and subsequent stabilization commits (`3edc484` and `5d4e8cb`).

---

## 1. Environment & Version Settlement (Requests 1 & 2)

### Game & Toolchain Verification
The live test environment is verified directly from engine and loader logs:
- **Game Product Version:** `2.50` (Verified in [red4ext-2026-10-27-02-59-50.log](file:///E:/Cyberpunk%202077/red4ext/logs/red4ext-2026-10-27-02-59-50.log#L2-L3): `Product version: 2.50 | File version: 3.0.88.46235`).
- **RED4ext:** `v1.31.0` (loaded and running with 1,032,136 mapped game addresses).
- **Cyber Engine Tweaks (CET):** `v1.38.0 [HEAD]`.
- **Active Redscript Compiler:** `scc.exe` / `scc_lib.dll` (integrated via redscript 0.5.32+ pipeline in [E:\Cyberpunk 2077\engine\tools\scc.exe](file:///E:/Cyberpunk%202077/engine/tools/scc.exe)).
- **Vanilla Script Source:** Official REDmod scripts in [E:\Cyberpunk 2077\tools\redmod\scripts\](file:///E:/Cyberpunk%202077/tools/redmod/scripts/).
- **Section 0 of AGENTS.md:** Updated from `TODO` to `2.50 (Build 3.0.88.46235)`.

### Redscript Compilation Status (`redscript_rCURRENT.log`)
In [E:\Cyberpunk 2077\r6\logs\redscript_r2026-10-27_03-00-01.log](file:///E:/Cyberpunk%202077/r6/logs/redscript_r2026-10-27_03-00-01.log#L88), our script was compiled into the game bundle:
```
[INFO - Tue, 27 Oct 2026 02:52:57 +0700] Compiling files in E:\Cyberpunk 2077\r6\scripts:
...
DetachedReticle\DetachedReticle.reds
...
[INFO - Tue, 27 Oct 2026 02:52:58 +0700] Compilation complete
[INFO - Tue, 27 Oct 2026 02:52:59 +0700] Output successfully saved to E:\Cyberpunk 2077\r6\cache\final.redscripts.modded
```
There were **zero** compilation errors or warnings reported against [DetachedReticle.reds](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/r6/scripts/DetachedReticle/DetachedReticle.reds). The subsequent `redscript_rCURRENT.log` failures were caused by an unrelated third-party mod (`VirtualCarDealer/UI/HubButton.reds`), which had broken methods after the 2.5 update.

---

## 2. Compile-Level Findings (C1 – C4 & Questions 2a, 2b)

### C1. `LogChannel(n"DEBUG", ...)` — Verified Absent from Vanilla, Present via Mod Dependency
- **Finding:** The reviewer correctly identified that `LogChannel` is not part of vanilla 2.31 or 2.5 `orphans.swift`.
- **Why it compiled on Windows:** In the test game environment, a script mod exists at [E:\Cyberpunk 2077\r6\scripts\Logs.reds](file:///E:/Cyberpunk%202077/r6/scripts/Logs.reds#L6-L8):
  ```swift
  // output goes to CET window
  native func LogChannel(channel: CName, const text: script_ref<String>)
  native func LogChannelWarning(channel: CName, const text: script_ref<String>) -> Void
  native func LogChannelError(channel: CName, const text: script_ref<String>) -> Void
  ```
  CET hooks `CScript::LogChannel` at runtime (confirmed in [cyber_engine_tweaks.log:19-20](file:///E:/Cyberpunk%202077/bin/x64/plugins/cyber_engine_tweaks/cyber_engine_tweaks.log#L19-L20): `CScript::LogChannel function hook complete!`).
- **Remediation:** Relying on `Logs.reds` is an undeclared dependency that would break vanilla users without that specific helper script. We are replacing all `LogChannel(...)` calls with a dedicated mod-level logger or native `FTLog(...)` (`orphans.swift:55046`) which is universally present across all vanilla builds.

### C2. Struct Construction without `new` (`Vector4(...)`, `Vector2(...)`, `HDRColor(...)`)
- **Question 2a Response:** Redscript 0.5.32+ accepts bare struct instantiation syntax `Vector4(...)` via internal constructor aliases in certain expression contexts, which is why `scc.exe` compiled without syntax errors. However, as the reviewer observed, `new Vector4(...)` and `new Vector2(...)` are the canonical patterns used across official REDmod scripts and the redscript documentation.
- **Action Taken:** To eliminate compiler ambiguity across different redscript versions, all struct instantiations will explicitly use `new Vector4(...)`, `new Vector2(...)`, and `new HDRColor(...)`.

### C3. `weapon.GetItemID().GetTDBID()` vs `ItemID.GetTDBID(...)`
- **Finding:** In [tools/redmod/scripts/core/ai/actions/aiActionHelper.script:1182](file:///E:/Cyberpunk%202077/tools/redmod/scripts/core/ai/actions/aiActionHelper.script#L1182), vanilla declares and invokes `ItemID.GetTDBID(weapon.GetItemID())`.
- **Action Taken:** Fixed in commit `3edc484` and normalized to `ItemID.GetTDBID(weapon.GetItemID())`.

### C4. `GameObject.GetRightActiveWeapon`
- **Status:** **Verified in 2.50**.
- **Citations:** Found extensively throughout 2.5 REDmod sources:
  - [core/entity/gameObject.script:579](file:///E:/Cyberpunk%202077/tools/redmod/scripts/core/entity/gameObject.script#L579)
  - [cyberpunk/projectiles/projectileHelper.script:55](file:///E:/Cyberpunk%202077/tools/redmod/scripts/cyberpunk/projectiles/projectileHelper.script#L55): `targetingSystem.GetCrosshairData(GameObject.GetRightActiveWeapon(ownerObject).GetEntityID(), ownerObject, aimPosition, aimForward);`
  - [cyberpunk/photomode/photoModePlayerEntity.script:640](file:///E:/Cyberpunk%202077/tools/redmod/scripts/cyberpunk/photomode/photoModePlayerEntity.script#L640): `weaponInHands = GameObject.GetRightActiveWeapon(currentPuppet);`

### Question 2b. Symbol Sourcing & Validation Policy
- The startup crash on `Vector4.Normalize3()` occurred during initial experimentation when guessing helper names from GLM/math libraries.
- **Strict Agreement:** In compliance with [AGENTS.md section 5](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/AGENTS.md#L97-L108), every symbol used going forward must be grepped directly in `reference/game-scripts/` or `tools/redmod/scripts/` prior to writing.

---

## 3. Runtime-Level Findings (R1 – R4 & Questions 3a – 3f)

### R1. Camera Transform Read & Question 3a (Telemetry Verification)
- **Question 3a Answer:** **YES.** The telemetry line `[DetachedReticle][DYNAMICS]` appears repeatedly and consistently in live gameplay.
- **Evidence from [E:\Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\gamelog.log:24-29](file:///E:/Cyberpunk%202077/bin/x64/plugins/cyber_engine_tweaks/gamelog.log#L24-L29):**
  ```
  [2026-10-27 00:38:08 UTC+07:00] [DEBUG] [DetachedReticle][DYNAMICS] AngleLag: 1.71 deg | Offset: (-51.9, 2.4) px | Widget: root | ADS: FALSE
  [2026-10-27 00:38:08 UTC+07:00] [DEBUG] [DetachedReticle][DYNAMICS] AngleLag: 9.18 deg | Offset: (-281.3, -11.0) px | Widget: root | ADS: FALSE
  [2026-10-27 00:38:09 UTC+07:00] [DEBUG] [DetachedReticle][DYNAMICS] AngleLag: 8.93 deg | Offset: (271.2, 36.0) px | Widget: root | ADS: FALSE
  [2026-10-27 00:38:10 UTC+07:00] [DEBUG] [DetachedReticle][SHOT #1 VERIFICATION] Weapon: Items.Preset_V_Unity | GunLagAngle: 2.62 deg | BulletDivergenceFromCam: 2.47 deg | CrosshairOffset: (79.6, -1.5) px | MuzzlePos: (-1543.06, 1209.38, 17.02) | TargetPt: (-1546.80, 1211.35, 17.08) | BulletDir: (-0.885, 0.466, 0.013)
  ```
- **Why it writes back without `out` in the decompile:**
  In REDmod source [tools/redmod/scripts/core/systems/cameraSystem.script:9](file:///E:/Cyberpunk%202077/tools/redmod/scripts/core/systems/cameraSystem.script#L9):
  ```swift
  public import final function GetActiveCameraWorldTransform( transform : Transform ) : Bool;
  ```
  Vanilla scripts call this exact pattern:
  - [tools/redmod/scripts/cyberpunk/items/weapon.script:2066](file:///E:/Cyberpunk%202077/tools/redmod/scripts/cyberpunk/items/weapon.script#L2066):
    `GameInstance.GetCameraSystem(weaponOwner.GetGame()).GetActiveCameraWorldTransform(cameraTransform)`
  - [tools/redmod/scripts/core/systems/spatialQueriesSystem.script:87](file:///E:/Cyberpunk%202077/tools/redmod/scripts/core/systems/spatialQueriesSystem.script#L87):
    `GameInstance.GetCameraSystem(owner.GetGame()).GetActiveCameraWorldTransform(cameraWorldTransform);`
  The decompiler omitted the `out` qualifier because native REDengine RTTI passes struct buffers directly by pointer; the native function fills the memory block in-place. `Transform.GetPosition(camTransform)` and `Transform.GetForward(camTransform)` return active non-zero world coordinates.

### Question 3b. Preferred Source for Camera Position
- **Universal (FPP & TPP):** `CameraSystem.GetActiveCameraWorldTransform(camTransform)` is preferred because it works seamlessly across first-person, third-person, vehicles, and photo mode without branching.
- **FPP-Specific High Precision:** `PlayerPuppet.GetFPPCameraComponent()` exposes `fpp:GetLocalToWorld()` which returns the exact 4x4 matrix of the camera eye node. In our CET script ([init.lua:182](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua#L182)), `Matrix.GetTranslation(worldMatrix)` yields identical position values to `CameraSystem.GetActiveCameraWorldTransform`.

### R2 & Questions 3c, 3d, 3e. Bullet Redirection & Slot Resolution
- **Observations on `ShootStraight(true)` & `SetPlayerAimWeaponPositionProvider`:**
  - `ShootStraight(true)` (from commit `6bbff12`) disables aim-assist snapping and spread variance relative to the camera gaze, but the hitscan ray still converged towards the center of the screen because REDengine's `EffectObjectProvider_PhysicalRay` took its ray destination from the camera reticle target.
  - `SetPlayerAimWeaponPositionProvider` updates the origin provider for targeting/aim-assist queries, not the underlying game effect raycast.
- **The Breakthrough Solution (Implemented in commit `3edc484`):**
  Instead of relying on unknown native setters, we wrap [EffectPreAction_PreAttack.Process](file:///E:/Cyberpunk%202077/tools/redmod/scripts/cyberpunk/damage/preAttack.script#L8). This function runs immediately prior to raycast evaluation in the `weaponShoot` GameEffect pipeline:
  ```swift
  @wrapMethod(EffectPreAction_PreAttack)
  public const func Process(ctx: EffectScriptContext) -> Void {
      let instigator: ref<GameObject> = EffectScriptContext.GetInstigator(ctx) as GameObject;
      if IsDefined(instigator) && instigator.IsPlayer() {
          let weapon: ref<WeaponObject> = EffectScriptContext.GetWeapon(ctx) as WeaponObject;
          if IsDefined(weapon) && !weapon.IsMelee() {
              let muzzleTransform: Transform = weapon.GetMuzzleSlotWorldTransform();
              let muzzlePos: Vector4 = Transform.GetPosition(muzzleTransform);
              let normMuzzleFwd: Vector4 = Vector4.Normalize(Transform.GetForward(muzzleTransform));

              let sharedData: EffectData = EffectScriptContext.GetSharedData(ctx);
              EffectData.SetVector(sharedData, GetAllBlackboardDefs().EffectSharedData.position, muzzlePos);
              EffectData.SetVector(sharedData, GetAllBlackboardDefs().EffectSharedData.muzzlePosition, muzzlePos);
              EffectData.SetVector(sharedData, GetAllBlackboardDefs().EffectSharedData.forward, normMuzzleFwd);
              EffectData.SetQuat(sharedData, GetAllBlackboardDefs().EffectSharedData.rotation, Transform.GetOrientation(muzzleTransform));

              let aimSys: ref<DetachedAimSystem> = GameInstance.GetScriptableSystemsContainer(instigator.GetGame()).Get(n"DetachedAimSystem") as DetachedAimSystem;
              if IsDefined(aimSys) {
                  let targetPt: Vector4 = aimSys.GetTargetPoint();
                  if !Vector4.IsZero(targetPt) {
                      EffectData.SetVector(sharedData, GetAllBlackboardDefs().EffectSharedData.raycastEnd, targetPt);
                  }
              }
          }
      }
      wrappedMethod(ctx);
  }
  ```
  This overrides the trajectory at the root of the ballistics pipeline, causing hitscan rays and projectile spawns to originate from the physical barrel and terminate at the 3D barrel raycast point.
- **Question 3d (Muzzle Slot Verification):**
  We avoid raw string literals like `n"Muzzle"` entirely. We use `weapon.GetMuzzleSlotWorldTransform()` ([items/weapon.script:135](file:///E:/Cyberpunk%202077/tools/redmod/scripts/cyberpunk/items/weapon.script#L135)). This engine method resolves the active attachment slot transform dynamically, accounting for weapon silencers, muzzle brakes, and appearance variants.

### R3 & Question 3f. Dual Wielding Recommendation
- **Recommendation:** **Explicitly disable detached aim while `PlayerStateMachine.IsDualWielding` is true during Phases 1 and 2.**
- **Rationale:** Dual wielding splits the state machine into concurrent `LeftShoot` and `RightShoot` pipelines with two active weapon instances (`LeftWeapon` and `RightWeapon`) and distinct UI crosshair controllers. Attempting to track dual independent floating reticles on screen with dual barrel convergence adds substantial complexity before single-weapon stabilization is complete. Falling back cleanly to vanilla crosshairs when dual-wielding preserves mod stability.

### R4. Runtime Hygiene
1. **Loop Callbacks (Lines 194–196):** Agreed. Registering on `OnStart`, `OnStartLoop`, and `OnEndLoop` creates redundant tick passes. We will register strictly to `inkanimEventType.OnStartLoop` or transition to a Codeware frame callback.
2. **Hardcoded 1920x1080 Resolution:** Agreed. We will adopt vanilla's viewport scaling formula:
   ```swift
   let screenSize: Vector2 = this.GetRootWidget().GetSize();
   let screenOffset: Vector2 = new Vector2(
       screenSize.X * 0.5 * projection.X,
       -screenSize.Y * 0.5 * projection.Y
   );
   ```
3. **Cone Clamp Velocity Windup:** In commit `3edc484`, the floating gun reticle was decoupled from artificial spring dampening and connected directly to the physical 3D barrel world raycast (`weapon.GetMuzzleSlotWorldTransform()`), eliminating velocity windup and kickback entirely.
4. **Namespace / Module:** [DetachedReticle.reds](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/r6/scripts/DetachedReticle/DetachedReticle.reds) will be encapsulated inside `module DetachedReticle` to avoid polluting the global scope.

---

## 4. Native Plugin Status & Questions 4a, 4b

### Question 4a. Location of `init.lua` & Origin of Memory RVAs
- **Location of `init.lua`:** The live CET script is located at [bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua) and is now tracked in the workspace repository.
- **Origin of RVAs `0x9507B7` and `0x9507EC`:** During early Phase 0 investigation, an attempt was made to locate the native ballistics execution via CET memory scanning. However, CET's Lua sandbox disables `ffi` by default (producing `attempt to index local 'ffi' (a nil value)` in [DetachedReticle.log](file:///E:/Cyberpunk%202077/bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/DetachedReticle.log#L1)). Memory hooking via CET was abandoned.
- **Current Native Implementation:** We built a dedicated C++ RED4ext plugin in [src/Main.cpp](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/src/Main.cpp) using [CMakeLists.txt](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/CMakeLists.txt). As verified in [red4ext-2026-10-27-02-59-50.log:17](file:///E:/Cyberpunk%202077/red4ext/logs/red4ext-2026-10-27-02-59-50.log#L17), it loads and unloads cleanly under RED4ext v1.31.0:
  ```
  [RED4ext] DetachedReticle (version: 1.0.0, author(s): Antigravity & User) has been loaded
  ```
  `CMakeLists.txt` will be pinned to a stable SDK release tag.

### Question 4b. Arm Mesh Decoupling Verification
- **Test Methodology:** In game, we hooked `PlayerPuppet.OnAction` to intercept `CameraMouseX` / `CameraMouseY` and call `consumer:ConsumeSingleAction()`, preventing input from rotating the player puppet body and arms. Simultaneously, we applied mouse deltas directly to `FPPCameraComponent:SetLocalTransform()`.
- **Observed Result:** The camera pans and tilts freely (freelook) while the 3D gun and arm mesh (`w_arms_fpp`) remain fixed in world space. This proved that REDengine 4's first-person arm mesh is parented to the upper-body puppet hierarchy rather than being hard-coded to the camera look direction.

---

## 5. Phase 1 Feasibility Matrix

In accordance with [AGENTS.md section 2](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/AGENTS.md#L45-L60), the feasibility of each component is summarized below for human approval:

| Subsystem | Target Behavior | Feasibility & Implementation Tier | Primary Mechanism | Status |
|---|---|---|---|---|
| **Camera Freelook** | Mouse rotates camera independently without moving arms/gun | **Feasible in CET / Scriptable Hook** | Intercept `CameraMouseX/Y` in `PlayerPuppet.OnAction`, apply delta to `FPPCameraComponent` | **Verified working in-game** |
| **Dual Reticle UI** | Center static camera pip + floating weapon crosshair | **Feasible in Redscript** | `gameuiCrosshairContainerController` child widget projection via `ProjectWorldToScreen` | **Verified working in-game** |
| **Physical Raycast** | Gun traces forward in 3D world space | **Feasible in Redscript** | `SpatialQueriesSystem.SyncRaycastByCollisionPreset` from `weapon.GetMuzzleSlotWorldTransform()` | **Verified working in-game** |
| **Ballistics Redirection** | Bullets emerge from physical muzzle towards 3D aim point | **Feasible in Redscript** | Intercept `EffectPreAction_PreAttack.Process` to override `EffectSharedData` (position, forward, raycastEnd) | **Verified working in-game** |
| **Upper-Body Weapon Lag / Smoothing** | 3D arms and gun smoothly rotate towards camera gaze | **Feasible in Native RED4ext Plugin** | Procedural bone rotation override on spine/arm IK nodes (`AnimParamFeature`) or native animation graph hook | **In Progress (Phase 2)** |
| **Dual Wielding** | Two independent weapons/aim points | **Excluded for Phase 1/2** | Mod suppressed when `PlayerStateMachine.IsDualWielding` is active | **Planned** |

---

## 6. Action Items for the Windows Agent

1. Update [DetachedReticle.reds](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/r6/scripts/DetachedReticle/DetachedReticle.reds):
   - Wrap in `module DetachedReticle`.
   - Remove reliance on `LogChannel` / `Logs.reds` in favor of `FTLog` / native safe logging.
   - Enforce `new Vector4(...)` / `new Vector2(...)` across all instantiations.
   - Replace hardcoded `1920/1080` screen projection with dynamic widget viewport scaling.
   - Restrict animation ticker to `OnStartLoop`.
   - Add dual-wield guard (`!player.IsDualWielding()`).
2. Update [CMakeLists.txt](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/CMakeLists.txt):
   - Pin `RED4ext.SDK` to a specific release tag and remove obsolete variable references.
3. Keep [AGENTS.md](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/AGENTS.md) and [docs/research/weapon-fire-flow.md](file:///c:/Users/fary2/Documents/00_ExpressJS%20Projects/DetachedReticle/docs/research/weapon-fire-flow.md) updated with verified symbol paths from 2.50 REDmod sources.
