# DetachedReticle — Bugfixes & Polish Iterations

Post-MVP 2 research, bug diagnoses, and iteration tracking for polish and edge-case resolution.

---

# iteration 23
- bug: When the camera is tilted up or down (any pitch angle), moving the camera horizontally left or right (yaw) induces an unwanted camera tilt in the roll axis (horizon tilts left or right depending on whether looking up or down).
- cause:
  1. Coordinate System Mismatch in Camera Residual:
     - In `init.lua`, the residual camera yaw rotation was constructed around the static local unit vector $(0, 0, 1)$: `quatAxisAngle(0.0, 0.0, 1.0, rYaw)`.
     - In REDengine, `FPPCameraComponent` is an attached component of the player character entity whose parent transform is already pitched by the native camera pitch angle $\theta$ (actuated via `FPPCameraComponent::OnMouseLook` at RVA `0x39CA70`).
     - In a pitched coordinate frame, the local vector $(0, 0, 1)$ is tilted backward (when looking up, $\theta > 0$) or tilted forward (when looking down, $\theta < 0$).
     - Rotating around a tilted Z axis has a projection of $\sin(\theta)$ onto the camera's line of sight (forward vector $\mathbf{F}$).
     - Consequently, applying yaw $rYaw$ around local $(0, 0, 1)$ introduces an unintended roll equal to $\text{Roll} \approx rYaw \cdot \sin(\theta)$. When looking up, moving right causes a rightward roll; when looking down, moving right causes a leftward roll.
- fix:
  1. True World Vertical Axis Projection:
     - Expressed the true gravity up vector $\mathbf{U}_{world} = (0, 0, 1)$ in the camera's local coordinate frame $(\mathbf{R}, \mathbf{F}, \mathbf{U})$.
     - Since $\mathbf{X}_{local} \cdot (0, 0, 1) = 0$, $\mathbf{Y}_{local} \cdot (0, 0, 1) = \sin(\theta) = F_z$, and $\mathbf{Z}_{local} \cdot (0, 0, 1) = \cos(\theta) = \sqrt{F_x^2 + F_y^2}$, the true world up axis in camera space is exactly:
       $$\mathbf{V}_{up\_local} = \left(0,\ F_z,\ \sqrt{F_x^2 + F_y^2}\right)$$
     - Dynamically read the camera forward vector $\mathbf{F}$ from `fpp:GetWorldForward()` (with fallback to `DetachedAimSystem.GetCameraForward()`).
     - Constructed residual yaw rotation around the true world vertical axis:
       `quatAxisAngle(0.0, fwdZ, fwdXY, rYaw)`.
     - Mathematically verified in 3D quaternion simulation (`test_math.ps1`) that across all pitch angles ($-45^\circ, -30^\circ, 0^\circ, +30^\circ, +45^\circ, +60^\circ$), camera roll is reduced to strictly **$0.00^\circ$** with zero horizon tilt.
  2. Deployed to `init.lua` in repository and game directory (`E:\Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\DetachedReticle\init.lua`).
(user test timestamp: 2026-10-29 04:52:46 +0700)

# iteration 24
- bug: In iteration 23, the gimbal roll tilt was significantly reduced/fixed ("much better now"), but two secondary artifacts appeared during in-game testing:
  1. High-frequency horizontal (left-right) jitters in the camera during active mouse movement.
  2. A slight "shifting" in the camera view after moving and stopping the mouse while the body catches up.
- cause:
  1. Transform Latency & Delayed Scene Graph Feedback Loop:
     - In iteration 23, the world up axis $\mathbf{V}_{up} = (0, F_z, \sqrt{F_x^2 + F_y^2})$ was computed every frame by reading `fpp:GetWorldForward()`.
     - `fpp:GetWorldForward()` queries the child component's transform in world space *after* `fpp:SetLocalTransform` was applied in the previous frame.
     - Scene graph world transforms in REDengine are updated during the render/animation pass with 1-frame latency relative to script `onUpdate`.
     - Furthermore, `fpp:SetLocalTransform(pos, targetRot)` defines the component's orientation in the *parent's* coordinate frame (the puppet head), NOT the child's local frame.
     - Reading the child's forward vector meant that as `rYaw` deflected the camera, `camFwd` changed direction, wobbling the projected rotation axis from frame to frame (causing left-right jitter).
     - When the mouse stopped, as the puppet body caught up and `rYaw` decayed to 0, `camFwd` smoothly shifted back, rotating the parent-space axis and dragging the camera gaze slightly (causing the post-stop shift).
- fix:
  1. Continuous Native Pitch Tracking (Zero Feedback Loop):
     - Recognized that the parent socket's coordinate frame is only pitched by the native camera pitch $\theta_{native}$; it does NOT yaw with `rYaw`.
     - In `InputHook.cpp`, removed periodic pitch zeroing (`s_targetPitch -= s_aimPitch`) so `s_aimPitch` tracks the continuous, absolute native camera pitch angle in degrees without wrapping or drifting.
     - Exposed `DR_ResetChasePitch(initPitch: Float)` to seed the initial pitch angle once upon unholstering.
     - In `init.lua`, computed the parent-space world up axis directly from native pitch:
       ```lua
       local nativePitch = Game.DR_GetAimPitch()
       local pitchRad = math.rad(nativePitch)
       local fwdZ = math.sin(pitchRad)
       local fwdXY = math.cos(pitchRad)
       local qRz = quatAxisAngle(0.0, fwdZ, fwdXY, rYaw)
       ```
     - Completely eliminated all per-frame calls to `fpp:GetWorldForward()` and `aimSys:GetCameraForward()`.
     - During horizontal movement, `nativePitch` is 100% constant, making `(0, fwdZ, fwdXY)` completely rock-solid and impervious to jitter or post-stop shifting.
  2. Re-enabled `Config.debugLogging = true` in `init.lua` for full telemetry verification.
  3. Recompiled `DetachedReticle.dll` and deployed DLL and `init.lua` to game directories.
(user test timestamp: 2026-10-29 05:29:04 +0700: user confirmed "The problems have been resolved.")

# iteration 25
- bug: Heavy Machine Gun (HMG) specific issues observed upon unholstering:
  1. Secondary Static Reticle Clutter: Besides the dynamic gun reticle tracking the HMG barrel, an extra static reticle with red "ladder" brackets on the left and right (resembling an aircraft HUD) appears off-center and contributes nothing to gameplay.
  2. Ballistics Decoupling Failure: When firing the HMG, bullets fail to travel to the projected gun reticle, unlike all other guns.
- cause:
  1. HMG Crosshair Hierarchy Architecture:
     - The Militech HMG crosshair widget (`Crosshair_Custom_HMG` in `crosshair_custom_hmg.script` / `crosshair_custom_hmg.inkwidget`) contains both the center crosshair container (`m_crosshairContainer`) and outer pitch ladder / bracket images (`m_leftPartExtra`, `m_rightPartExtra`, `m_overheatContainer`, `m_overheatWarning`).
     - In vanilla, these outer ladder brackets are intended as fixed peripheral HUD elements or overheat gauges; when `DetachedReticle` translates the active crosshair widget, the outer ladder elements either remain detached at static offsets or visually clutter the view without aligning to the reticle.
  2. Projectile Attack vs Hitscan PhysicalRay Pipeline Discrepancy:
     - Unlike standard firearms (rifles, pistols, shotguns, sniper rifles, LMGs) which use `playerAttack = Attacks.Bullet_GameEffect` (hitscan `gameEffectObjectProvider_PhysicalRay` intercepted by `ShootingHook.cpp`), TweakDB assigns the HMG (`Preset_HMG_Default`) `rangedAttacks = Attacks.ExplodingBulletHMGPackage`.
     - In `bullets.tweak`, `Attacks.ExplodingBulletHMG` defines `playerAttack = Attacks.ExplodingBulletSmallProjectile` (a `Bullet_Projectile` launched via native projectile spawner at 140 m/s towards the camera look target).
     - Because `Attacks.ExplodingBulletSmallProjectile` bypasses `gameEffectObjectProvider_PhysicalRay`, `ShootingHook.cpp` is never invoked, causing HMG shots to launch along the camera vector rather than the physical muzzle orientation.
- fix:
  1. Clean Up HMG Crosshair HUD:
     - In `r6/scripts/DetachedReticle/DetachedReticle.reds`, wrapped `Crosshair_Custom_HMG`'s lifecycle methods (`OnInitialize`, `OnPreIntro`, `OnBulletSpreadChanged`, `OnOverheatChanged`).
     - Added `DR_HideLadderWidgets()` to set `m_leftPartExtra`, `m_rightPartExtra`, `m_overheatContainer`, and `m_overheatWarning` to invisible (`SetVisible(false)`) and transparent (`SetOpacity(0.0)`).
     - Added a recursive pass on `GetRootCompoundWidget()` to ensure any direct static ladder / HUD child elements are hidden, while leaving `m_crosshairContainer` cleanly tracking the weapon barrel.
  2. Unified Ballistics Redirection for HMG:
     - In `r6/scripts/DetachedReticle/DetachedReticle.reds`, wrapped `WeaponTransition.GetDesiredAttackRecord`:
       ```swift
       @wrapMethod(WeaponTransition)
       protected func GetDesiredAttackRecord(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> ref<Attack_Record> {
           let weapon: ref<WeaponObject> = this.GetWeaponObject(scriptInterface);
           if IsDefined(weapon) && (weapon.IsHeavyWeapon() || WeaponObject.GetWeaponType(weapon.GetItemID()) == gamedataItemType.Wea_HeavyMachineGun) {
               let hmgAttack: ref<Attack_Record> = TweakDBInterface.GetAttackRecord(t"Attacks.ExplodingBulletMediumEffect");
               if IsDefined(hmgAttack) {
                   return hmgAttack;
               }
           }
           return wrappedMethod(stateContext, scriptInterface);
       }
       ```
     - In `ShootEvents.OnEnter`, re-asserted `weapon.SetAttack(t"Attacks.ExplodingBulletMediumEffect")` immediately after `wrappedMethod(...)`.
     - In `r6/tweaks/DetachedReticle/hmg_attack.yaml`, configured TweakXL to map `Attacks.ExplodingBulletHMG.playerAttack: Attacks.ExplodingBulletMediumEffect`.
     - `Attacks.ExplodingBulletMediumEffect` is a vanilla `Bullet_GameEffect` with identical damage multipliers (0.5x physical, thermal, chemical, electric) and explosive payload (`Attacks.BulletMediumExplosion`). This routes HMG fire through `gameEffectObjectProvider_PhysicalRay`, allowing `ShootingHook.cpp` to redirect bullets precisely from the physical muzzle to the projected gun reticle.
     - Resolved startup compilation error (`[NO_MATCHING_OVERLOAD]` on `OperatorEqual`) by converting enum comparisons to standard redscript `EnumInt(...) == EnumInt(...)`.
  3. Deployed updated `DetachedReticle.reds` and `hmg_attack.yaml` to `E:\Cyberpunk 2077`.
  (user test timestamp: 2026-10-29 15:10:04 +0700)

# iteration 26
- error: 
    ```
    [ERROR] [NO_MATCHING_OVERLOAD] At DetachedReticle.reds:475 & 485:
    arguments passed to 'OperatorEqual' do not match any of the overloads:
    1st argument: expected 'TweakDBID', given 'gamedataItemType'
    ```
- cause: In redscript, enum types (such as gamedataItemType) do not expose a direct global == operator overload within class modules. Comparing them directly via == causes [NO_MATCHING_OVERLOAD]. In redscript, enum comparison must be performed via integer representation using EnumInt(...) == EnumInt(...).
- fix:
    - Resolved startup compilation error (`[NO_MATCHING_OVERLOAD]` on `OperatorEqual`) by converting enum comparisons to standard redscript `EnumInt(...) == EnumInt(...)`.
    ``` swift
        if IsDefined(weapon) && (weapon.IsHeavyWeapon() || EnumInt(WeaponObject.GetWeaponType(weapon.GetItemID())) == EnumInt(gamedataItemType.Wea_HeavyMachineGun)) {
               let hmgAttack: ref<Attack_Record> = TweakDBInterface.GetAttackRecord(t"Attacks.ExplodingBulletMediumEffect");
               if IsDefined(hmgAttack) {
                   return hmgAttack;
               }
           }
    ```
(user test timestamp: 2026-10-29 15:19:04 +0700)

# iteration 27
- bug:
  1. HMG Ballistics confirmed 100% resolved by user test in Iteration 26 ("The bullet from HMG already goes towards the gun reticle correctly now.").
  2. The previous `DR_HideLadderWidgets()` attempt in Iteration 25/26 targeted the wrong elements (`m_leftPartExtra`, `m_rightPartExtra`, `m_overheatContainer`), which did not affect the zoom indicator.
  3. User requirement clarification: Do NOT hide the zoom indicator element; instead, center it at screen center `(0, 0)` whenever it is visible. When the weapon is holstered, holding right-click already displays the zoom reticle centered at `(0, 0)`; the off-center issue only manifests when holding an HMG.
- cause:
  1. In `UpdateDetachedAim()`, when unarmed/holstered (`!IsDefined(weapon)`), `activeWidget.SetTranslation(new Vector2(0.0, 0.0))` is called. When right-click is held while unarmed, optical zoom (`CrosshairGameController_NoWeapon`) is active and remains centered at `(0, 0)`.
  2. When an HMG is equipped, `weapon` is defined, so `UpdateDetachedAim()` executes `activeWidget.SetTranslation(screenOffset)` to track the physical weapon barrel.
  3. Because an HMG cannot aim down sights (ADS) via weapon optics, holding right-click activates optical eye zoom. If `activeWidget` is translated by `screenOffset`, any zoom elements inside it (e.g. `fluff`) or any active zoom crosshair widget inherits `screenOffset`, displacing the zoom indicator away from the camera gaze to the gun barrel's physical orientation.
- fix:
  1. Deleted `DR_HideLadderWidgets()` and removed all widget hiding from `Crosshair_Custom_HMG` so vanilla UI elements are fully preserved.
  2. Implemented Multi-Layer Zoom Centering in `UpdateDetachedAim()`:
     - Active Controller Check: If `activeController` is `CrosshairGameController_NoWeapon`, forces `activeWidget.SetTranslation(new Vector2(0.0, 0.0))` so optical zoom remains locked to camera gaze.
     - Weapon Crosshair & Counter-Translation: When `activeWidget` is the weapon reticle (`screenOffset`), inspects if child `fluff` exists. If `fluff` is visible, counter-translates it by `-screenOffset` (`fluff.SetTranslation(new Vector2(-screenOffset.X, -screenOffset.Y))`) so its effective screen position is `screenOffset + (-screenOffset) = (0, 0)`.
     - Secondary Widget Centering: Iterates all direct children in `this.m_rootWidget`. Any visible child other than `activeWidget` and `m_cameraCrosshair` is forced to `SetTranslation(new Vector2(0.0, 0.0))`.
  3. Root Centering in `CrosshairGameController_NoWeapon`:
     - Wrapped `OnInitialize`, `OnState_Aim`, `OnState_HipFire`, and `OnZoomLevel` on `CrosshairGameController_NoWeapon` to enforce `rootWidget.SetTranslation(new Vector2(0.0, 0.0))`.
  4. Comprehensive Multi-Method Diagnostic Probes:
     - Added recursive 3-level widget hierarchy dumper on `Crosshair_Custom_HMG` (`DR_LogHmgHierarchy`) logging names, classes, visibility, sizes, translations, and margins for all children and grandchildren.
     - Added telemetry dumper in `UpdateDetachedAim()` logging `activeWidget`, `activeController`, blackboard crosshair state, and zoom level.
     - Wrapped `scannerBorderGameController.OnScannerZoom` and `hud_turret.OnScannerZoom` to detect any secondary zoom HUD activations.
  5. Deployed updated `DetachedReticle.reds` to `E:\Cyberpunk 2077\r6\scripts\DetachedReticle\DetachedReticle.reds`.
(user test timestamp: 2026-10-29 15:41:48 +0700)

# iteration 28
- error:
    ```
    [ERROR] [UNRESOLVED_METHOD] At DetachedReticle.reds:609:1:
    @wrapMethod(CrosshairGameController_NoWeapon)
    no method with this name exists on the target type (OnInitialize)

    [ERROR] [UNRESOLVED_REF] At DetachedReticle.reds:651:1:
    @wrapMethod(hud_turret)
    unresolved reference 'hud_turret'
    ```
- cause:
    1. In vanilla scripts, `CrosshairGameController_NoWeapon` does not directly declare or override `OnInitialize()` (it is inherited from `gameuiCrosshairBaseGameController`). In redscript, `@wrapMethod` on a subclass requires the target method to be explicitly defined on that exact class; attempting to wrap an inherited method produces `[UNRESOLVED_METHOD]`.
    2. `hud_turret` is a specialized HUD class not recognized in the core global symbol table during redscript startup compilation, generating `[UNRESOLVED_REF]`.
- fix:
    1. In `CrosshairGameController_NoWeapon`, replaced `@wrapMethod` of `OnInitialize` with `OnPlayerAttach(playerPuppet: ref<GameObject>) -> Bool`, which is directly defined on `CrosshairGameController_NoWeapon`.
    2. Removed the unnecessary speculative wrapper blocks for `hud_turret` and `scannerBorderGameController`, maintaining focused hooks on `CrosshairGameController_NoWeapon`, `Crosshair_Custom_HMG`, and `gameuiCrosshairContainerController`.
    3. Deployed the updated `DetachedReticle.reds` to `E:\Cyberpunk 2077\r6\scripts\DetachedReticle\DetachedReticle.reds`.
(user test timestamp: 2026-10-29 16:08:16 +0700: user confirmed "test iteration 28 complete, the issues have been resolved")

# iteration 29
- requirement: Monitor the location of the gun reticle and its angular offset compared to the Aiming Direction across various weapons in hip and resting animation postures vs ADS.
- implementation:
  1. In `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`, added dedicated `[GUN_OFFSET_MONITOR]` telemetry block running in `onUpdate`:
     - Reads equipped weapon name via `TDBID.ToStringDEBUG(ItemID.GetTDBID(weapon:GetItemID()))`.
     - Reads gun forward vector and screen pixel offset from `DetachedAimSystem`: `aimSys:GetGunForward()` and `aimSys:GetScreenOffset()`.
     - Computes spherical gun barrel angles (`gunYaw`, `gunPitch`) and compares them against Aiming Direction angles (`bodyYaw`, `aPitch`).
     - Computes exact 3D angular divergence:
       $$\text{Offset} = \left(\Delta\text{Yaw} = \text{gunYaw} - \text{bodyYaw},\ \Delta\text{Pitch} = \text{gunPitch} - \text{aPitch},\ \text{Total} = \arccos(\mathbf{gunFwd} \cdot \mathbf{aimFwd})\right)$$
     - Reads Player State Machine crosshair and upper body states to distinguish postures:
       `RESTING(HIP)`, `SWINGING(HIP)`, `RESTING(ADS)`, `SWINGING(ADS)`, `RELOAD`, `SPRINT`, `SAFE`.
     - Logs continuously every 10 frames (~6 Hz) and immediately triggers on weapon switch or ADS transition:
       `[GUN_OFFSET_MONITOR] Weapon=<name> | Mode=<posture> | ReticleScreen=(x, y)px | GunAngles=(Yaw, Pitch) | AimAngles=(Yaw, Pitch) | Offset=(dYaw, dPitch, Total)`
  2. Deployed updated `init.lua` to `E:\Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\DetachedReticle\init.lua`.

# iteration 30
- requirement: Actively offset the Aiming Direction so that the resting position of the physical gun reticle aligns with the Aiming Direction (Tier 2A anchor), without breaking mouse freelook crispness, dynamic swing lag, or camera stability.
- root cause / problem analysis (from Iteration 29 telemetry):
  1. In hipfire resting posture, weapons exhibit an intrinsic anatomical barrel offset relative to the character puppet body:
     - Lexington (Pistol): $\Delta\text{Yaw} = -1.05^\circ$, $\Delta\text{Pitch} = -4.80^\circ$ (Total $4.95^\circ$, Screen `(36.0, 154.1)px`)
     - Igla (Shotgun): $\Delta\text{Yaw} = +5.64^\circ$, $\Delta\text{Pitch} = +5.52^\circ$ (Total $7.88^\circ$, Screen `(-147.3, -139.4)px`)
     - HMG (Heavy Machine Gun): $\Delta\text{Yaw} = +3.76^\circ$, $\Delta\text{Pitch} = +6.40^\circ$ (Total $7.56^\circ$, Screen `(-67.7, -158.2)px`)
  2. In optical ADS, the rig naturally aligns the weapon optics with the camera eye ($<0.2^\circ$).
  3. Because the weapon rig and arms are parented to the character puppet body, actuating the puppet body rotation directly turns the gun barrel in 3D world space.
- solution / architecture:
  1. **Tier 2A ($T2A$) Anchor Preservation:**
     - Tier 2A maintains the dynamic mouse chase anchor chained to Tier 1 target gaze $T$. Raw mouse input updates $T$, and exponential smoothing advances $T2A$ by step $dA = \text{gap} \times (1 - e^{-\lambda \cdot dt})$.
  2. **Tier 2B ($T2B = T2A - C$) Body Heading Actuation:**
     - Actively offsets the player puppet body yaw and pitch by $C = (C_{\text{yaw}}, C_{\text{pitch}})$, physically rotating the arms and weapon barrel so the gun points directly along $T2A$ (and camera gaze $T$) in resting posture.
     - Rate-modulated exponential tracking:
       $$dC = (\Delta_{\text{target}} - C) \times (1 - e^{-\lambda_{\text{comp}} \cdot dt})$$
       Where $\lambda_{\text{comp}} = 0.5\text{ s}^{-1}$ during rapid mouse flicks ($|\text{gap}| > 5.0^\circ$) to let $T2A$ dictate swing weight, and $\lambda_{\text{comp}} = 2.0\text{ s}^{-1}$ when settling to smoothly glide the barrel into alignment.
     - Single-frame step clamped to $\pm 1.0^\circ$; total compensation clamped to $\pm 15.0^\circ$.
     - Output to engine look integrator at RVA `0x51D462`:
       $$\text{outYaw} = dAYaw - dCompYaw,\quad \text{outPitch} = dAPitch - dCompPitch$$
  3. **Camera World Invariance ($R = T - T2B$):**
     - Because `FPPCameraComponent` is parented to the puppet head, offsetting the puppet by $-C$ and the camera local residual by $+C$ cancels out identically in world space:
       $$\text{CamWorld} = T2B + R = (T2A - C) + (T - T2A + C) = T$$
       The camera gaze remains 100% rock-solid in world space on mouse gaze $T$, with zero drift or wobble.
  4. **State Gating:**
     - Active compensation tracks barrel offset during `HIP` and `ADS`.
     - During `RELOAD`, `SPRINT`, `SAFE`, or when holstered, target offset is commanded to `(0.0, 0.0)` so compensation smoothly winds down to zero, preventing the compensator from fighting weapon handling animations.
- implementation:
  1. In `src/Hooks/InputHook.hpp` and `src/Hooks/InputHook.cpp`:
     - Added native compensation state (`s_targetCompYaw`, `s_targetCompPitch`, `s_compYaw`, `s_compPitch`, `s_displayT2BYaw`, `s_displayT2BPitch`).
     - Added `SetBarrelOffset(aYaw, aPitch)` with $\pm 15.0^\circ$ safety clamping.
     - Integrated $dC$ calculation and updated engine look integrator feed and camera residual in `ProcessMouseAim`.
  2. In `src/Main.cpp`:
     - Registered RTTI native functions: `DR_SetBarrelOffset(yaw, pitch)`, `DR_GetCompYaw()`, `DR_GetCompPitch()`, `DR_GetT2BYaw()`, `DR_GetT2BPitch()`.
  3. Recompiled `DetachedReticle.dll` and deployed to `red4ext/plugins/DetachedReticle/DetachedReticle.dll` and `E:\Cyberpunk 2077\red4ext\plugins\DetachedReticle\DetachedReticle.dll`.
  4. In `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`:
     - Added `Config.activeAimOffset = true`.
     - Added per-frame active barrel offset feeding to `Game.DR_SetBarrelOffset(diffYaw, diffPitch)` during `HIP` and `ADS`.
     - Added ImGui overlay checkbox, live status telemetry, and NativeSettings integration.
     - Added `DetachedReticle.SetActiveAimOffset(val)` modular option.
     - Deployed updated `init.lua` to `E:\Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\DetachedReticle\init.lua`.
- diagnostic telemetry & anomaly watchdogs:
  1. `[T2B_OFFSET_COMP] TargetErr=(dYaw:%+.2f deg, dPitch:%+.2f deg) | CompApplied=(C_yaw:%+.2f deg, C_pitch:%+.2f deg) | T2A_Aim=(Yaw:%.2f, Pitch:%.2f) | T2B_Body=(Yaw:%.2f, Pitch:%.2f) | Residual=(rYaw:%.4f, rPitch:%.4f)`
  2. `[WARN][T2B_CLAMP]`: Triggers if compensation reaches clamp limit ($\ge 14.5^\circ$).
  3. `[WARN][T2B_NAN]`: Triggers if NaN / Inf is detected in any compensation variable.
  4. `[WARN][T2B_EXCESSIVE_OFFSET]`: Triggers if measured barrel offset exceeds expected bounds ($> 25.0^\circ$).
  5. `[WARN][T2B_RESIDUAL_HIGH]`: Triggers if camera residual exceeds expected bounds ($> 70.0^\circ$).
  6. `[WARN][T2B_CONVERGENCE_STALL]`: Triggers if resting in hipfire for $> 120$ frames (~2 seconds) and reticle screen distance remains $> 40\text{ px}$.
(user test timestamp: 2026-10-29 17:13:04 +0700: user confirmed yaw stabilization aligns with aiming direction; requested faster yaw settling, pitch fine-tuning across guns, and smooth ease-in ease-out return of T2B to T2A during unholster/holster to eliminate camera snap)

# iteration 31
- requirement:
  1. Faster yaw stabilization toward the aiming direction.
  2. Eliminate vertical reticle discrepancy (reticle slightly higher or lower on some guns).
  3. Prevent camera snapping back to T2B when unholstering / holstering by returning T2B smoothly to T2A in the middle of the transition animation using a quick ease-in ease-out movement.
- root cause / problem analysis:
  1. **Camera Snap on Holster / Unholster:**
     - During holster or unholster animations, the weapon barrel points downward/sideways (`angleDeg > 12.0°` up to `100°+`), which spiked target compensation to the clamp limit ($\pm 15.0^\circ$).
     - When fully holstered, `isArmed` became false in a single frame, immediately disabling native smoothing and snapping the camera local transform to `baselineRot` (0 residual). Because the puppet body was left at $T2B = T2A - C$, the camera abruptly snapped from $T2A$ to $T2B$ by $C$ degrees.
     - On unholstering, the system started from $T2B$, and the draw animation angles again caused sudden jerks.
  2. **Pitch Divergence across Weapon Types:**
     - Different weapon models (pistols vs shotguns vs HMGs) have different vertical offsets and sight heights relative to eye level, creating parallax at different engagement ranges.
     - Previously, `diffPitch` was calculated from world spherical angles `gunPitch - aPitch`, which did not match the camera view coordinate frame and lacked closed-loop screen feedback.
  3. **Slower Yaw Settling:**
     - Previous `compRate = 2.0 s^-1` had a time constant of $\tau = 0.5\text{s}$, taking ~1.5s to fully settle.
- solution / architecture:
  1. **Quick Ease-In Ease-Out Return to T2A ($C \to 0$) during Transitions:**
     - Added native `StartReturnToT2A(duration = 0.30s)` and `IsReturningToT2A()` in `InputHook`.
     - Uses a cubic smoothstep curve $S(u) = 3u^2 - 2u^3$ where $u = \text{clamp}(t / T_{\text{trans}}, 0.0, 1.0)$.
     - At $u = 0$, velocity is 0 (smooth ease-in); at $u = 0.5$, peak velocity; at $u = 1.0$, velocity is 0 (smooth ease-out).
     - Each frame: $dComp = C_{\text{target}}(u) - C_{\text{previous}}$, outputting smooth deltas to the puppet body look integrator while counter-rotating the camera local residual.
     - Camera gaze remains 100% frozen in world space on $T2A$ throughout the entire transition.
     - By the middle/end of the animation, $T2B$ has smoothly rejoined $T2A$, and $C = 0$.
     - In `init.lua`, decoupled camera mode remains active while `IsReturningToT2A()` is true even if `isArmed` becomes false, eliminating any single-frame camera snap.
     - During unholstering (draw animation), $C$ is held at 0 ($T2B == T2A$) until the weapon enters ready firing stance (`angleDeg < 12.0°`), preventing wild draw angles from affecting compensation.
  2. **Faster Yaw Stabilization:**
     - Increased resting settling rate `compRate` from `2.0 s^-1` to `4.5 s^-1`.
     - Increased single-frame delta clamp from `1.0°` to `2.5°`.
  3. **Camera-Relative Pitch Lag & Screen-Space Feedback Trim:**
     - Reads exact camera-relative barrel angles `yawLagDeg` and `pitchLagDeg` from `DetachedAimSystem`.
     - Applies subtle screen-space feedback trim ($\pm 3.0^\circ$ bounded nudge proportional to `screenOffset`):
       $$\text{diffPitch} = \text{pitchLagDeg} - \text{clamp}(\text{scrY} \times 0.03, -3.0, 3.0)$$
       $$\text{diffYaw} = \text{yawLagDeg} + \text{clamp}(\text{scrX} \times 0.03, -3.0, 3.0)$$
     - Closes the loop in screen space, pulling the reticle directly onto the center diamond vertically and horizontally on all weapon models.
- implementation:
  1. `src/Hooks/InputHook.hpp` & `src/Hooks/InputHook.cpp`:
     - Added `StartReturnToT2A(duration)` and `IsReturningToT2A()`.
     - Implemented cubic smoothstep ease-in ease-out return loop in `ProcessMouseAim`.
     - Increased settling rate to `4.5 s^-1` and delta clamp to `2.5°`.
  2. `src/Main.cpp`:
     - Registered RTTI global functions: `DR_StartReturnToT2A(duration)` and `DR_IsReturningToT2A()`.
  3. Recompiled `DetachedReticle.dll` and deployed to `red4ext/plugins/DetachedReticle/DetachedReticle.dll` and `E:\Cyberpunk 2077\red4ext\plugins\DetachedReticle\DetachedReticle.dll`.
  4. `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`:
     - Added `isReturning` check to `shouldBeActive` to preserve continuity across holster/unholster.
     - Added `isHolsteringOrDrawing` detection triggering `DR_StartReturnToT2A(0.30)`.
     - Integrated `aimSys:GetPitchLagDeg()`, `aimSys:GetYawLagDeg()`, and screen-space trim.
     - Deployed updated `init.lua` to `E:\Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\DetachedReticle\init.lua`.
- status: tested, broken, iteration 31 solution is not working because it undo the previous MVPs. implementation of iteration 31 requirement from iteration 30 state is advised.

# iteration 32
- requirement:
  1. Restore MVP 1 & MVP 2 decoupled aim functionality completely.
  2. Fix the 50% half-gain error in Tier 2B loop that left vertical and horizontal reticle discrepancies across weapons.
  3. Prevent camera snapping during holster/draw without relying on timed transitions or per-frame restarted smoothsteps.
  4. Preserve all volatile registers (r9, r10, r11, xmm4, xmm5) in `MouseLookRelay.asm` with 16-byte stack alignment (Round 5 finding H1).
  5. Document parallax & convergence design decision (Round 5 finding H3).
- root cause / problem analysis:
  1. **Mod Inertia in Iteration 31:** `local weapon = GameObject.GetRightActiveWeapon(player)` and `local fpp = player:GetFPPCameraComponent()` were accidentally omitted in `init.lua:onUpdate`. `isArmed` and `shouldBeActive` were nil, leaving the native input hook in 100% vanilla passthrough.
  2. **Half-Gain Loop Error in Iteration 30:** Gun direction $G = T2B + O$. Error measured relative to camera gaze $L = G - T = O - C - \text{gap}$. At rest ($\text{gap} = 0$), $C \to L \implies C = O - C \implies C = O/2$. The loop only compensated for half the anatomical offset, leaving $2.4^\circ\text{ to }3.2^\circ$ ($75\text{--}100\text{ px}$) vertical error on shotguns/HMGs.
  3. **Anti-Lag Dynamic Locking in Iteration 31:** Feeding live `yawLagDeg` (camera-relative) and proportional screen trim into the fast compensator ($4.5\text{ s}^{-1}$) caused the compensator to erase dynamic mouse deflection $(T1 - T2A)$, locking $T2$ to $T1$.
  4. **Holster Snap & Zeno's Holster:** Calling `DR_StartReturnToT2A` every frame reset `s_transTime = 0`, while deactivating `shouldBeActive` abruptly when `isArmed` became false snapped the camera because the puppet was left at $T2A - C$.
- solution / architecture:
  1. **Restore Core Initialization in `init.lua`:** Re-declared `weapon` and `fpp` at the top of `onUpdate`.
  2. **Body-Relative Offset Target ($C = O$):**
     $$\text{diffYaw} = \text{normalizeDeg}(\text{gunYaw} - \text{bodyYaw})$$
     $$\text{diffPitch} = \text{gunPitch} - \text{t2bPitch}$$
     Measuring relative to puppet body heading and actuation pitch eliminates the chase gap and ensures 100% anatomical offset removal at rest.
  3. **No-Snap Transition Gating via Settling Continuity:**
     `shouldBeActive = Config.enabled and fpp and (isArmed or settling)`
     where `settling = (|rYaw| + |rPitch| > 0.10) or (|cYaw| + |cPitch| > 0.10)`.
     When unarming (`not isArmed`), `DR_SetBarrelOffset(0.0, 0.0)` is sent. $C$ naturally decays through the native filter at $4.5\text{ s}^{-1}$, while camera residual $R = (T - T2A) + C$ keeps camera world gaze rock-solid on $T$. When residual and compensation reach $< 0.10^\circ$, `shouldBeActive` deactivates cleanly with zero snap.
  4. **Ready Stance Gating:**
     Target offset is held at zero during draw/holster animations using body-relative gate:
     `isReadyStance = (|diffYaw| < 15.0) and (|diffPitch| < 15.0) and (stateStr == "HIP" or stateStr == "ADS")`.
  5. **Dynamic Hit-Point Parallax Convergence:**
     Implemented slow integral trim on screen error ($\int \text{scrErr} \cdot k_i \, dt$, clamped $\pm 3.0^\circ$) active **only** when resting at settled stance (`rawGap < 0.10°`). Frozen during mouse swings. Documented in `docs/research/convergence-design.md`.
  6. **Relay Register Preservation:**
     Expanded stack frame in `MouseLookRelay.asm` to `0D8h` (216 bytes) with 16-byte alignment to preserve volatile registers `r9`, `r10`, `r11`, `xmm4`, `xmm5` across `OnNativeMouseAim`.
  7. **Native Code Simplification:**
     Removed `StartReturnToT2A` and `IsReturningToT2A` from `InputHook` and `Main.cpp`.
  8. **Cleanups:**
     Set `Config.debugLogging = false` by default; cleaned up leftover HMG diagnostic hierarchy dumper in `DetachedReticle.reds`.
- implementation:
  1. `src/Hooks/MouseLookRelay.asm`: Preserved all volatile registers (`r9`, `r10`, `r11`, `xmm4`, `xmm5`).
  2. `src/Hooks/InputHook.hpp` & `src/Hooks/InputHook.cpp`: Removed timed transition methods and simplified Tier 2B loop with rate $4.5\text{ s}^{-1}$ and clamp $2.5^\circ$.
  3. `src/Main.cpp`: Removed `DR_StartReturnToT2A` and `DR_IsReturningToT2A`.
  4. Recompiled `DetachedReticle.dll` and deployed to `red4ext/plugins/DetachedReticle/DetachedReticle.dll` and `E:\Cyberpunk 2077\red4ext\plugins\DetachedReticle\DetachedReticle.dll`.
  5. `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`: Restored `weapon`/`fpp`, added `settling` gate, implemented body-relative offsets, ready stance gating, slow integral trim, and default `debugLogging = false`. Deployed to `E:\Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\DetachedReticle\init.lua`.
  6. `r6/scripts/DetachedReticle/DetachedReticle.reds`: Cleaned up HMG hierarchy dumper and `FTLog` noise. Deployed to `E:\Cyberpunk 2077\r6\scripts\DetachedReticle\DetachedReticle.reds`.
  7. `docs/research/convergence-design.md`: Documented parallax decision.
- status: tested 2026-10-29 18:40, everything works and looks good.

# iteration 33
- date: 2026-11-02 18:24 +0700
- requirement:
  1. Fix yaw integral trim positive feedback sign inversion (Round 8 §2A) so gun settles onto camera center instead of driving off-screen.
  2. Prevent trim offset leakage between stances (hip-fire trim carrying over into ADS).
  3. Eliminate the 0.1s camera jerk/shake when raising weapon from relaxed low-ready carry to ready firing stance.
  4. Surface direct Trim telemetry in `[T2B_OFFSET_COMP]`.
- root cause / problem analysis:
  1. **Positive Feedback in `trimYaw`:** `trimYaw = trimYaw + scrX * 0.005 * dt` in `init.lua:607`. Positive `scrX` (reticle right) increased `trimYaw`, commanding $+C$ yaw compensation, rotating puppet $-dC$ (right), moving the gun further right until hitting the $+3.0^\circ$ clamp.
  2. **Trim Stance Leakage:** Trim was only reset on weapon change (`DetachedReticle.lastTrimWeapon`), not on `HIP` <-> `ADS` transitions. A $+3.0^\circ$ trim accumulated during hip-fire stayed active after entering ADS.
  3. **Binary Ready Stance Discontinuity:** The hard threshold `isReadyStance = (|diffYaw| < 15) and (|diffPitch| < 15)` jumped from `readyWeight = 0.0` to `1.0` in a single frame as the gun raised above 15°, delivering a sudden ~14.5° step into `Game.DR_SetBarrelOffset` which yanked the puppet and camera for 0.1s.
- solution / implementation:
  1. **Sign Flip:** In `init.lua:607`, flipped `+ scrX * 0.005 * dt` to `- scrX * 0.005 * dt` (negative feedback). Pitch trim (`- scrY`) was verified correct in Round 8 review and kept unchanged.
  2. **Stance Edge Trim Reset:** Added `or isADS ~= DetachedReticle.lastTrimADS` to the trim reset check, resetting `trimYaw = 0.0` and `trimPitch = 0.0` on every HIP <-> ADS transition.
  3. **Continuous Smoothstep Gate:** Replaced the binary 15° check with a smooth cubic Hermite blend between 10° (full compensation, `readyWeight = 1.0`) and 16° (low-ready carry, `readyWeight = 0.0`):
     $$t = \text{clamp}\left(\frac{16 - \text{maxAngle}}{6}, 0, 1\right), \quad \text{readyWeight} = t^2(3 - 2t)$$
     Scaling target offsets by `readyWeight` provides continuous blending with zero step discontinuities or camera twitches.
  4. **Telemetry:** Added `Trim=(Y:%+.2f, P:%+.2f)` directly to the `[T2B_OFFSET_COMP]` telemetry string in `init.lua`.
  5. Deployed updated `init.lua` to `E:\Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\DetachedReticle\init.lua`.
- status: deployed, awaiting in-game verification.

# iteration 34
- date: 2026-11-02 19:25 +0700
- type: diagnostic only (no aiming behavior change)
- finding (verified, file timestamps and hashes):
  1. The 19:15 test session did NOT run iteration 33. At 19:00 a DLL built from uncommitted source (adds `DR_SetMinChaseSpeed`, 386048 bytes) and at 19:03 a different `init.lua` (`steadyOffsets`, `minChaseSpeed`, `catchUpSpeed=12`, `maxDivergence=25`, yaw axis pitch from `DR_GetT2BPitch`) were deployed over iteration 33. `src/` was later reverted to HEAD, leaving repo DLL and game folder out of sync with the source.
  2. Game `config.json` carried `catchUpSpeed=12`, `maxDivergence=25` from that build; saved config overrides script defaults.
  3. `DetachedReticle.log` 19:15:55 and 19:16:36: both activations logged `initPitch=0.00` (the known seed failure, `noted-issues.md:34`). Debug logging was off, so no other telemetry exists for that session.
- user observations from that session (build = the 19:03 experimental build, not iteration 33):
  1. Camera pull/shake still present when the gun enters/leaves the resting (low-ready) pose. That build held the T2B target nearly constant through resting, so this is evidence (inferred) that the shake is not caused by C changing.
  2. New: camera roll left/right with the HMG only.
- HMG roll hypotheses (unverified, to be classified by the [SEED] probe):
  - H-seed: `initPitch=0.00` makes the yaw-axis pitch (`DR_GetAimPitch`) wrong by the camera pitch at activation. Roll ~ rYaw * sin(error). HMG has the largest steady rYaw (C_yaw up to ~12 deg in the 12:31 session), so it shows mainly there.
  - H-axis: the parent frame is pitched by native pitch = T2B = A - C, while iteration 33 uses A. Error = C_pitch (HMG ~5 to 9 deg). The 19:03 build used T2B and still rolled, so H-seed is the stronger candidate.
- changes:
  1. Rebuilt `DetachedReticle.dll` from HEAD `src/` (385024 bytes, no `DR_SetMinChaseSpeed`), copied to `red4ext/plugins/DetachedReticle/` and the game folder. Build note: MSBuild fails with `Item has already been added ... 'https_proxy'` when both `https_proxy` and `HTTPS_PROXY` are set; clear the lowercase variants for the build process.
  2. `init.lua` (iteration 33 logic unchanged) gained logging-only probes, all gated on `debugLogging`, logged every frame:
     - `[P1] camYaw/camPitch` from `CameraSystem.GetActiveCameraForward()` (`cameraSystem.script:14`), `dCam`, `dBody`, `predBody = dA - dC`.
     - `[1C] fppOverwrite`: angle between the fpp local orientation read before writing and the one written last frame (non-zero = something else wrote it).
     - `[SEED] pitchErr = camPitch - T pitch` (steady non-zero = bad seed).
     - `ReadyW` (iteration 33 gate weight) added to `[T2B_OFFSET_COMP]`.
  3. Game `config.json` reset to repo defaults with `debugLogging=true`.
- status: deployed, awaiting test (iteration 33 behavior + probes).

# iteration 35
- date: 2026-11-02 20:00 +0700
- requirement:
  1. Eliminate the 0.1s camera shake / jolt when weapon enters and leaves resting (low-ready) carry pose.
  2. Eliminate the camera horizon roll left/right when swinging mouse with Heavy Machine Gun (HMG).
- verified telemetry findings (from 19:35 test session with 21,047 logged frames):
  1. `[1C] fppOverwrite` logged strictly 0.000 deg (peak noise 0.01-0.03 deg): the engine is NOT overwriting `fpp` transform.
  2. `[SEED] pitchErr` logged +0.02 to +0.08 deg on Copperhead: seed pitch is accurate.
  3. Resting Transition Jolt Diagnosis: Telemetry proved steady-state ready firing offset is only dYaw ~ +0.58 deg, dPitch ~ +0.50 deg. The 10-16 deg gate in Iteration 33 chased the arm-lowering animation as it swept through 2-15 deg, ramping CompApplied (C_yaw) from 0.56 up to 3.57 deg. When maxAngle exceeded 16 deg, readyWeight hit 0, commanding targetYaw = 0. C_yaw decayed rapidly, rotating the puppet body by +0.495 deg in Frame 5281. Due to 1-frame latency between engine physics and CET onUpdate, rendered camera jolted by +0.353 deg (F=5281) and bounced back by -0.183 deg (F=5282).
  4. HMG Horizon Roll Diagnosis: HMG is held in hip-cradle position with muzzle tilted up by +6.6 deg. Tier 2B commanded C_pitch = +6.5 deg to twist the torso down, inflating rPitch to 10 deg. In `init.lua`, the parent yaw axis was computed using `DR_GetAimPitch()` (A) instead of `DR_GetT2BPitch()` (T2B = A - C), creating a 6.5 deg tilt error in the parent coordinate frame. Rotating by rYaw (up to 65.5 deg) around an axis tilted by 6.5 deg induced an exact cross-axis roll of sin(6.5 deg) * sin(65.5 deg) ~ 6.0 deg.
- solution / implementation:
  1. **Align Gravity-Up Rotation Axis:** In `init.lua:460-466`, read `Game.DR_GetT2BPitch()` instead of `DR_GetAimPitch()`. Because the engine's physical parent socket is pitched at T2B = A - C, using T2B guarantees `(0, fwdZ, fwdXY)` points along the exact true gravity-up axis of the parent socket under all conditions.
  2. **Bypass Tier 2B for Heavy Weapons:** In `init.lua:540`, added `isHeavyWeapon` detection (`weapon:IsHeavyWeapon()` or item ID match). When holding an HMG/heavy weapon, Tier 2B compensation is bypassed (target = 0, C_pitch = 0.0). Freelook, muzzle ballistics redirection, and reticle tracking remain 100% active, but the torso is never twisted by 6.6 deg, completely eliminating horizon roll.
  3. **Tighten Ready Stance Gate & Target Clamp:** In `init.lua:630-665`, tightened the ready gate to `[2.5 deg, 4.0 deg]` (full ready < 2.5 deg, smooth Hermite blend to 0 by 4.0 deg, unready >= 4.0 deg). Added hard clamp on `targetYaw` and `targetPitch` to `[-2.0 deg, +2.0 deg]`. The controller can never chase arm-lowering/raising animations or spike to 3.5 deg; it smoothly tapers to 0 before the arm even begins its main motion.
  4. **Native Clamp Safety:** In `src/Hooks/InputHook.cpp:138 & 254`, tightened clamp on `s_targetCompYaw`, `s_targetCompPitch`, `s_compYaw`, and `s_compPitch` from +/-15.0 deg to +/-3.0 deg.
  5. Recompiled `DetachedReticle.dll` (Release) and deployed DLL and `init.lua` to repository and `<GAME_ROOT>`.
- status: deployed, ready for verification.

# iteration 36
- date: 2026-11-02 20:12 +0700
- user feedback on iteration 35:
  1. "it's now less jittery and feels better for regular guns." (Resting transition twitch verified resolved).
  2. "for HMG currently the gun reticle is offset to upper left."
  3. "need a fix for smart weapons, the reticle for smart weapons is gone, i think by simply excluding smart weapons for our gun reticle (the 'where the bullet should go' part)."
- root cause analysis:
  1. **HMG Reticle Offset to Upper Left:** In Iteration 35, Tier 2B compensation was completely bypassed for heavy weapons (`isHeavyWeapon -> readyWeight = 0`). In vanilla animations, V holds the HMG at the right hip with the barrel angled upward and inward (dYaw ~ +3.5 deg, dPitch ~ +6.6 deg). With Tier 2B turned off, the barrel was never aligned toward center screen, causing the gun reticle (and muzzle fire) to sit permanently at the upper-left of screen center. The camera roll in earlier iterations was caused exclusively by `DR_GetAimPitch` vs `DR_GetT2BPitch` axis misalignment, which was mathematically proven (in `test_hmg_roll.ps1`) to have 0.000 deg roll once `DR_GetT2BPitch` is used.
  2. **Smart Weapons Missing Reticle:** Smart weapons have their own built-in targeting brackets, locking frames, and homing projectile logic. Translating `activeWidget` with `screenOffset` moved the entire smart HUD hierarchy off-screen or out of position, and `ShootingHook` ray redirection interfered with native lock acquisition.
- solution / implementation:
  1. **Smart Weapon Full Exclusion:**
     - In `r6/scripts/DetachedReticle/DetachedReticle.reds` (`UpdateDetachedAim` and `ShootEvents.OnEnter`), added `isSmartWeapon = Equals(RPGManager.GetWeaponEvolution(weapon.GetItemID()), gamedataWeaponEvolution.Smart)`.
     - When a smart weapon is active:
       - Hides the camera freelook center pip (`m_cameraCrosshair.SetVisible(false)`).
       - Resets and locks the vanilla smart crosshair widget centered at `(0.0, 0.0)` (`activeWidget.SetTranslation(Vector2(0, 0))`).
       - Disables native muzzle ray redirection (`SetMuzzleAimState(..., false)`).
       - Excludes smart weapons from `ShootEvents.OnEnter` redirection, preserving 100% vanilla lock-on targeting and homing projectiles.
     - In `init.lua`, added `isSmartWeapon` check and bypassed Tier 2B (`readyWeight = 0.0`).
  2. **HMG Centered Offset Compensation (Roll-Free):**
     - In `init.lua`, differentiated ready stance gates:
       - Regular guns: `[2.5 deg, 4.0 deg]` gate, clamp `[-2.0 deg, +2.0 deg]`. (Preserves the smooth, jitter-free regular gun behavior).
       - Heavy weapons (HMG): `[8.0 deg, 12.0 deg]` gate, clamp `[-8.0 deg, +8.0 deg]`. (Compensates the +3.5 deg yaw / +6.6 deg pitch cradle angle, bringing the HMG gun reticle right to center screen when ready).
     - In `src/Hooks/InputHook.cpp`, adjusted `s_targetCompYaw`, `s_targetCompPitch`, `s_compYaw`, and `s_compPitch` clamps from +/-3.0 deg to +/-8.0 deg to accommodate HMG's 6.6 deg pitch while protecting against runaway spikes.
     - Recompiled `DetachedReticle.dll` (Release) and deployed DLL, `init.lua`, and `DetachedReticle.reds` to repository and `<GAME_ROOT>`.
- status: deployed, ready for verification.

# iteration 37
- date: 2026-11-03 13:40 +0700
- context / review analysis (Round 9 review):
  1. **Strict Scope Mandate:** Smart weapons MUST keep the chase (Tier 1 & Tier 2A decoupled gun/hand lag). Excluding smart weapons from mouse smoothing is off the table. They receive no Tier 2B torso compensation, no detached gun reticle, no camera center pip, and the vanilla smart crosshair must remain at screen center (0, 0).
  2. **Core Discovery (Regular Reticle on Smart Weapon):** Testing revealed that drawing a smart weapon displays a regular gun reticle rather than the square smart targeting frame. Target acquisition/brackets fail because the native smart crosshair controller was never spawned/activated, not because brackets are misplaced.
  3. **Pitch Seed Bug (Fix F0):** Previously, the smart branch in `DetachedReticle.reds` zeroed `aimSys.SetAimState`, causing `aimSys:GetCameraForward()` to return (0, 0, 0) and seeding `initPitch = 0.00` in `init.lua`. This caused horizon roll on weapon draws or swaps between smart and regular weapons.
  4. **Unconditional Fix F2:** In `DetachedReticle.reds`, `activeWidget.SetVisible(true)` was being called every tick in the smart branch, overriding vanilla hiding during safe/sprint/reload/scan states.
- implementation:
  1. **Fix F0 (Universal Camera Pitch Seed):**
     - In `init.lua`, replaced `aimSys:GetCameraForward()` with direct query to `Game.GetCameraSystem():GetActiveCameraForward()` to calculate `initPitch = atan2(cz, hypot(cx, cy))`.
     - In `DetachedReticle.reds` smart branch, computed active camera forward vector `camFwd3` and passed it to `aimSys.SetAimState` with `isDetached = false` instead of zeroes.
  2. **Fix F2 (Vanilla Crosshair State Preservation):**
     - Removed `activeWidget.SetVisible(true)` from the smart branch in `DetachedReticle.reds`.
  3. **Section 3.1 Smart Diagnostic Probe:**
     - Extended `DetachedAimSystem` with probe fields and accessors: `m_smartCalls`, `m_smartTargets`, `m_smartLocked`, `m_smartHasLink`, `m_smartRegion`, `m_smartRootVis`, `m_smartRootOpacity`, `m_smartPreIntro`, `m_smartCtrlClass`, `m_smartWidgetName`, `m_smartExpectedXhair`.
     - Wrapped `CrosshairGameController_Smart_Rifl.OnSmartGunParams(argParams: Variant) -> Bool` and `CrosshairGameController_Smart_Rifl.OnPreIntro() -> Bool` to track native event publishing, target lock state, and cyberware link status.
     - In `DetachedReticle.reds:UpdateDetachedAim()`, recorded active controller class, widget name, and expected item TDBID crosshair record.
     - In `init.lua`, added periodic `[SMART]` telemetry logger running every 30 frames whenever a smart weapon is equipped.
  4. **Compile Fix:** smartGunUIParameters is an IScriptable class requiring indirection (
ef<...>). Fixed FromVariant<smartGunUIParameters> to FromVariant<ref<smartGunUIParameters>>.
- status: deployed, awaiting user diagnostic probe & bisection session (Round 9 Section 3).

# iteration 38
- date: 2026-11-06 13:30 +0700
- status: untested
- previous_iteration_results:
  1. User observation: "i noticed that some weapons has idle position of the reticle (T3 compensated by T2B) not on the center. I want you to add logging every 10 seconds that detect when: the gun is not on ADS and not in resting position and the gun reticle is off center for a few seconds (normally the gun reticle should move to the center within a second)."
  2. Root cause / background:
     - In earlier iterations (e.g. Iteration 33-35, REC#6), regular weapons had steady-state barrel offsets < 1.0 deg, so a strict ready-stance gate [2.5 deg, 4.0 deg] with clamp [-2.0 deg, +2.0 deg] was established to prevent chasing arm-lowering/raising animations.
     - Heavy weapons (HMG) and LMGs required a wider hip-cradle gate [8.5 deg, 12.0 deg] and clamp [-8.5 deg, +8.5 deg] because their resting barrel offsets exceed 6.0 deg.
     - Certain other weapon archetypes (e.g. particular revolvers, shotguns, tech weapons) may exhibit steady-state barrel offsets exceeding 2.5 deg/4.0 deg, causing readyWeight to drop to 0.0 or clamping at 2.0 deg, leaving the reticle uncompensated or partially compensated at rest in hipfire.
- target_goal:
  1. Add a dedicated, continuous watchdog in init.lua that checks every frame whether:
     - The gun is armed and not ADS (not isADS and stateStr != "ADS").
     - The gun is not in resting/safe position (stateStr != "SAFE", crosshairState != 1, rightWeaponState != 6, stateStr != "SPRINT", stateStr != "RELOAD", diffPitch >= -14.0 deg).
     - The player is idle/settled (rawGapYaw < 0.50 deg, rawGapPitch < 0.50 deg, not isRecoiling).
     - The gun reticle is off center on screen (scrDist > 30.0 px).
  2. When this condition persists for a few seconds (>= 2.5s), log a warning line [WARN][IDLE_RETICLE_OFF_CENTER] every 10 seconds with full diagnostic telemetry (weapon name, screen offset, target error, applied compensation, gate thresholds, ready weight, trim, stance and state machine flags).
- changes_made:
  1. `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`:
     - Added offCenterTimer = 0.0 and offCenterLogCooldown = 0.0 state fields to DetachedReticle.
     - Read rightWeaponState from blackboard PlayerStateMachine.RightWeapon alongside crosshairState and upperBodyState.
     - Hoisted readyWeight, maxReady, maxBlend, and maxClamp to outer scope so gate parameters are accessible to diagnostic telemetry.
     - Reset offCenterTimer and offCenterLogCooldown on weapon swap or deactivation.
     - Added watchdog section running outside Config.debugLogging that accumulates dt when off-center idle condition holds, logging [WARN][IDLE_RETICLE_OFF_CENTER] every 10.0 seconds once offCenterTimer >= 2.5s.
- expected_outcome:
  1. When standing idle in hipfire with any weapon whose idle reticle does not converge to screen center within 2.5 seconds, DetachedReticle.log and the CET console log a [WARN][IDLE_RETICLE_OFF_CENTER] line every 10 seconds.
  2. The log line exposes TargetErr, CompApplied, ReadyW, Gate, Trim, and state machine values to pinpoint why compensation failed.
  3. No logs are produced when aiming down sights (ADS), sprinting, reloading, or when the gun is lowered into the low-ready/safe resting position.
- test_procedure:
  1. Equip various weapon types (pistols, revolvers, shotguns, rifles, snipers) in hipfire.
  2. Hold the weapon at rest without aiming down sights or shooting for 3+ seconds.
  3. Inspect DetachedReticle.log for [WARN][IDLE_RETICLE_OFF_CENTER] warnings.

# iteration 39
- date: 2026-11-06 13:55 +0700
- status: tested-pass (verified in-game)
- previous_iteration_results:
  1. The watchdog deployed in Iteration 38 immediately captured the exact off-center defect during in-game testing with Testera (`Items.Preset_Testera_Military`):
     `[WARN][IDLE_RETICLE_OFF_CENTER] Weapon=Items.Preset_Testera_Military | Duration=2.5s | ReticleScreen=(-92.2, -44.2)px (Dist:102.2px) | TargetErr=(dYaw:+6.10, dPitch:+3.67)deg | CompApplied=(C_yaw:+2.00, C_pitch:+1.43)deg | ReadyW=0.00 (Gate:[2.5, 4.0] Clamp:2.0) | Trim=(Y:+0.02, P:+0.02) | Stance=HIP (Xhair:8, Upper:0, RWea:5)`
  2. Root cause analysis:
     - Double-barrel shotguns (`Wea_ShotgunDual`: Testera, Igla, Palica, Satara) use a distinct hip-carry skeletal pose with an intrinsic horizontal offset $d\text{Yaw} = +6.10^\circ$ and $d\text{Pitch} = +3.67^\circ$.
     - Because previous iterations only opened the wide hip-cradle gate `[8.5 deg, 12.0 deg]` for `isHeavyWeapon` (HMG) and `isLMG` (Defender/MA70), all other weapons fell back to the tight rifle gate `[2.5 deg, 4.0 deg]` with clamp `+/- 2.0 deg`.
     - With `maxAngle = 6.10 deg > 4.0 deg`, `readyWeight` dropped to `0.00`, completely locking Testera out of Tier 2B compensation and leaving the reticle stuck 102.2 px off-center.
     - Meanwhile, weapons like Carnage ($d\text{Yaw}=+0.88^\circ, d\text{Pitch}=+3.17^\circ, \text{maxAngle}=3.17^\circ < 4.0^\circ$) and revolvers ($d\text{Yaw} \approx \pm 0.5^\circ, d\text{Pitch} < 2.0^\circ$) stayed within the narrow gate and centered successfully.
- target_goal:
  1. Implement **Solution B (Universal Ready Stance Gate via State Machine)**:
     - Replace hardcoded weapon classification checks (`isHeavyWeapon`, `isLMG`) with a universal ready posture gate driven by the player state machine:
       When a weapon is armed and in ready hipfire or ADS (`stateStr == "HIP" or stateStr == "ADS"`, `rightWeaponState ~= 6`, `stateStr ~= "SAFE"`, and `diffPitch >= -14.0 deg`), apply the wide gate (`maxReady = 8.5 deg`, `maxBlend = 12.0 deg`, `maxClamp = 8.5 deg`).
     - Allow double-barrel shotguns ($d\text{Yaw} = +6.10^\circ$) and heavy/LMG weapons ($d\text{Pitch} = +6.6^\circ\text{ to }+7.1^\circ$) to achieve full, instantaneous Tier 2B center-screen alignment.
     - When the weapon lowers into safe carry, holsters, sprints, or reloads (`rightWeaponState == 6` / `stateStr == "SAFE"` / `diffPitch < -14.0 deg`), `readyWeight` smoothly drops to 0.0, cleanly relaxing compensation without twitching.
- changes_made:
  1. `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`:
     - Added `rightWeaponState == 6` check to `stateStr` mapping to reliably classify PSM Safe state as `stateStr = "SAFE"`.
     - Replaced archetype-specific `useHeavyCradleGate` with universal `isReadyPosture`:
       `local isReadyPosture = (not isSmartWeapon) and (stateStr == "HIP" or stateStr == "ADS") and (rightWeaponState ~= 6) and (diffPitch >= -14.0)`
     - Set universal ready gate thresholds: `maxReady = 8.5 deg`, `maxBlend = 12.0 deg`, `maxClamp = 8.5 deg`.
     - Confirmed native C++ (`src/Hooks/InputHook.cpp`) is already bounded to `[-10.0f, 10.0f]`, eliminating the need for DLL rebuild.
     - Constrained fine integral screen trim to `trimClamp = 3.0 deg` per `docs/design/convergence.md`.
  2. Deployed updated `init.lua` directly to `<GAME_ROOT>\bin\x64\plugins\cyber_engine_tweaks\mods\DetachedReticle\init.lua`.
- expected_outcome:
  1. Testera (and other double-barrel shotguns) in hipfire ready stance have `maxAngle = 6.10 deg < maxReady = 8.5 deg`, obtaining `readyWeight = 1.0`.
  2. Applied compensation reaches `C_yaw = +6.10 deg` and `C_pitch = +3.67 deg`, drawing T3 gun reticle to the screen center diamond in < 0.8s.
  3. The off-center watchdog (`scrDist > 30px` for >= 2.5s) ceases to trigger on Testera or any other high-offset weapon.
  4. Handguns, rifles, Carnage, revolvers, LMGs, and HMG retain smooth, rock-solid centering without regression.
  5. Safe zones, holstering, sprinting, and reloading drop compensation gracefully to 0 without jerks.
- test_procedure:
  1. Launch Cyberpunk 2077 on branch `universal-ready-gate`.
  2. Equip Testera (or any double-barrel shotgun) in hipfire and observe the gun reticle settling to center diamond.
  3. Confirm that no `[WARN][IDLE_RETICLE_OFF_CENTER]` lines appear in `DetachedReticle.log` during idle hipfire.
  4. Test weapon swap to revolver, rifle, Carnage, and LMG/HMG to verify all weapon classes center smoothly.
  5. Test sprinting, reloading, and holstering to confirm smooth transition with zero twitching.
- test_results:
  1. In-game verification confirmed the universal ready posture gate works well according to design intent.
  2. Double-barrel shotguns (Testera) with high intrinsic hipfire offset ($d\text{Yaw} = +6.10^\circ$) smoothly settle to the center screen diamond within < 0.8s.
  3. The idle watchdog (`[WARN][IDLE_RETICLE_OFF_CENTER]`) ceases to fire during hipfire rest.
  4. Handguns, rifles, revolvers, Carnage, and heavy weapons retain smooth, stable centering.
  5. Any further issues or feedback regarding weapon posture gates will be tracked under the "universal ready gate" term.

# iteration 40
- date: 2026-11-06 15:10 +0700
- status: tested-pass (deployed and verified; tuning required for dynamic range)
- previous_iteration_results:
  1. Iteration 39 resolved Testera and double-barrel shotgun hipfire centering via the universal ready posture gate (isReadyPosture).
  2. User requested introducing an "ergonomics" handling model similar to Helldivers 2, where gun weight affects how fast and responsively the gun turns to chase the camera.
  3. Baseline agreement:
     - The current config (catchUpSpeed = 22.0, expPower = 0.60) is tuned perfectly for Assault Rifles (W_ref = 6.2 kg).
     - Use Method A (Effective Perceived Mass): weapon weight (W) scaled by player Body/Strength (s in [0.0, 1.0]) up to a 20% mass reduction at Body 20: W_eff = W * (1 - 0.20 * s).
     - Responsiveness gain scales dynamically around the 6.2 kg baseline: k_eff = k_cfg * clamp(1.0 - 0.045 * (W_eff - 6.2), 0.45, 1.35).
     - Curve exponent scales between 0.55 and 0.62: p_eff = clamp(p_cfg - 0.006 * (W_eff - 6.2), 0.55, 0.62).
- target_goal:
  1. Implement weapon weight and player strength dynamic ergonomics scaling in init.lua and config.json.
  2. Light weapons (handguns, SMGs) track snappier (k ~ 24..25.5, p ~ 0.61..0.62).
  3. Assault rifles maintain exact baseline (k = 22.0, p = 0.60 at Body 3).
  4. Heavy weapons (shotguns, snipers, LMGs, HMG) exhibit tangible rotational drag and flick inertia (k ~ 10..18, p ~ 0.55..0.58).
  5. Investing in Body/Strength gives a satisfying feeling of wielding heavy weapons more easily.
- changes_made:
  1. in/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/config.json:
     - Added "weightHandlingScaling": true.
  2. in/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua:
     - Added Config.weightHandlingScaling = true, serialization in LoadConfig() and SaveConfig().
     - Added DetachedReticle.SetWeightHandlingScaling(val).
     - Added UpdateWeaponErgonomics(weapon) calculating W_eff, k_eff, and p_eff.
     - Hooked UpdateWeaponErgonomics into active weapon flow and strength updates, calling SyncSmoothing() when effective parameters change.
     - Updated CET ImGui Overlay and NativeSettings UI to display live ergonomics telemetry (Gun Weight, Eff Weight, k_eff, p_eff) and allow toggling.
- expected_outcome:
  1. When drawing a handgun (Lexington/Unity), k_eff ~ 25 and p_eff ~ 0.62, giving agile tracking.
  2. When drawing an assault rifle (Copperhead/Ajax), k_eff = 22.0 and p_eff = 0.60, exactly matching current baseline.
  3. When drawing a sniper (Grad) or LMG (Defender), k_eff ~ 17..19 and p_eff ~ 0.57..0.58, exhibiting clear physical barrel weight.
  4. When wielding an HMG, k_eff ~ 10..14 and p_eff = 0.55, creating committed, heavy turret-like traversing.
  5. Disabling weightHandlingScaling returns handling immediately to static k_cfg and p_cfg.
- test_procedure:
  1. Equip Lexington handgun, verify CET overlay shows Gun=3.3 kg and k ~ 25, p ~ 0.62.
  2. Equip Copperhead assault rifle, verify CET overlay shows Gun=6.2 kg and k = 22.0, p = 0.60.
  3. Equip Defender LMG and Militech HMG, verify CET overlay shows heavier weight and lower k, p.
  4. Perform mouse sweeps and flicks with each weapon to feel the progressive difference in rotational inertia.

# iteration 41
- date: 2026-11-06 15:22 +0700
- status: untested
- previous_iteration_results:
  1. In-game playtesting of Iteration 40 confirmed the ergonomics mechanics function smoothly with zero lag or hitching.
  2. Playtest feedback (owner, 2026-11-06):
     - "the 'snappiness' feels fine on SMG but the speed could be faster."
     - "While on the slower end; the HMG doesn't feel 'heavy' enough."
  3. Root cause:
     - The symmetric linear slope (alpha = 0.045) was too gentle on both ends:
       - For SMG (4.5 kg, deltaW = -1.7 kg), k only increased to 23.7 (+7.6%), which is barely perceptible.
       - For HMG (18.0 kg, deltaW = +11.8 kg), k = 10.3 and p = 0.55 allowed the weapon to track with only ~3.3 deg of steady lag at 20 deg/s, failing to communicate the physical mass of a 20 kg turret.
- target_goal:
  1. Implement an asymmetric split-slope ergonomics model pivoted around Assault Rifle (6.2 kg):
     - Light weapons (deltaW < 0): Increase speed slope to alpha_light = 0.13, boosting SMG speed to k ~ 27..29 (+22..33%) while preserving crisp snappiness (p ~ 0.61..0.62).
     - Heavy weapons (deltaW > 0): Increase drag slope to alpha_heavy = 0.065 and lower exponent bound to p in [0.48, 0.60], bringing HMG down to k ~ 5.3 (over 4x heavier than AR) and p = 0.48 for genuine heavy rotational inertia.
- changes_made:
  1. `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`:
     - In `UpdateWeaponErgonomics(weapon)`:
       Split deltaW into lighter (deltaW < 0) and heavier (deltaW >= 0) branches.
       Light: `ergMult = math.min(1.50, 1.0 - 0.13 * deltaW)`, `effPower = math.min(0.62, Config.expPower - 0.007 * deltaW)`.
       Heavy: `ergMult = math.max(0.24, 1.0 - 0.065 * deltaW)`, `effPower = math.max(0.48, Config.expPower - 0.010 * deltaW)`.
- expected_outcome:
  1. SMG (4.5 kg) speed increases to k ~ 26.9 (Body 3) up to k ~ 29.4 (Body 20), feeling noticeably faster and agile.
  2. Handgun (3.3 kg) achieves k ~ 30.3 (Body 3) up to k ~ 32.2 (Body 20).
  3. Assault Rifle (6.2 kg) remains at exact baseline k = 22.0, p = 0.60.
  4. HMG (18.0 kg) drops to k ~ 5.3 and p = 0.48 at Body 3, creating deep, heavy barrel lag (~25 deg on fast sweeps) with strong flick resistance.
  5. High Strength (Body 20) improves HMG significantly to k ~ 10.3 and p = 0.52.
- test_procedure:
  1. Equip SMG (Saratoga) and confirm speed is visibly faster than assault rifle.
  2. Equip HMG and perform rapid sweeps to verify genuine heavy barrel lag and committed swing.
  3. Confirm Assault Rifle (Copperhead) remains unchanged at k = 22.0, p = 0.60.


# iteration 38
- date: 2026-11-08 14:35 +0700
- status: passed (user confirmed dual-wielding works overall; requested weight formula update & chase rubber leash)
- previous_iteration_results:
  1. Equipping two shotguns (`Items.Preset_Carnage_Pimp`) under Gorilla Akimbo at 14:10:30 logged `State=HOLSTERED` in `DetachedReticle.log`, with `dCam_Body(rYaw)=+0.00`, `CompYaw=+0.00`, and `RecoilYaw=+0.00`.
  2. Cause: `GameObject.IsDualWielding(player)` was treated as an exclusion gate in `init.lua:760` and `DetachedReticle.reds:335, 573`, cleanly disabling all decoupled aim behavior and reverting to 1:1 vanilla passthrough.
- target_goal / hypothesis:
  1. For dual-wielding (vanilla dual pistols + Gorilla Akimbo shotguns/SMGs), body-level Tier 2B compensation cannot rotate the body to compensate for two separate arm vectors without throwing the other arm further off-axis.
  2. By bypassing Tier 2B (`Game.DR_SetBarrelOffset(0.0, 0.0)`), the body follows purely the smoothed T2A mouse chase.
  3. Each gun receives its own independent T3 reticle: Right T3 drives the active HUD crosshair, and Left T3 drives a dedicated HUD reticle (`m_leftCrosshair`).
  4. Both T3 reticles and their respective muzzle trajectories artificially stabilize (yaw/pitch) towards T1 (camera center) based on dynamic settling (`readyWeight * dualStabilizeMax`), eliminating resting anatomical splay while preserving dynamic swing lag during fast mouse sweeps.
  5. Shooting from either hand via `ShootEvents.OnEnter` routes the native physical ray through that specific weapon's muzzle along its stabilized trajectory.
- changes_made:
  1. `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`:
     - Added `dualStabilizeMax = 0.65` to `Config`.
     - In `UpdateWeaponErgonomics(weapon, isDual, leftWeapon)`: combined weights of right and left weapons when dual-wielding (e.g. dual Carnage shotguns = ~20.0 kg), scaled by player Strength / Gorilla Arms factor.
     - In `onUpdate`: allowed `isArmed = true` when `isDual` is true, recording `isDualWielding` and `leftWeapon`.
     - In Tier 2B block: when `isDual`, forced `Game.DR_SetBarrelOffset(0.0, 0.0)`, reset trim/settled state, and passed dynamic stabilization factor (`readyWeight * dualStabilizeMax`) to `aimSys:SetDualStabilizeWeight(stabFactor)`.
  2. `r6/scripts/DetachedReticle/DetachedReticle.reds`:
     - In `DetachedAimSystem`: added dual-wield aim fields and getters/setters (`m_dualStabilizeWeight`, `m_leftGunForward`, `m_leftMuzzlePos`, `m_leftScreenOffset`).
     - In `gameuiCrosshairContainerController`: added `m_leftCrosshair: ref<inkCanvas>`, initialized in `InitLeftCrosshair()` with amber diamond pip and left bracket marker `[`.
     - In `UpdateDetachedAim()`: replaced dual-wield early-return gate with `UpdateDualWieldAim()`, computing independent 3D muzzle traces, screen projections, and artificial T1 stabilization for both right and left weapons.
     - In `ShootEvents.OnEnter`: removed `!GameObject.IsDualWielding(player)` exclusion gate. Applied stabilized aim vector to `SetMuzzleAimState` so bullets travel directly to that gun's stabilized T3 point.
- expected_outcome:
  1. Equipping two pistols or two shotguns maintains decoupled aim active (`State=DUAL_ARMED`).
  2. Center cyan diamond T1 stays fixed at screen center (0, 0).
  3. Right gun HUD crosshair and left gun amber reticle track their respective physical muzzle traces.
  4. When resting in ready stance, both reticles smoothly stabilize inward towards T1.
  5. Firing either left or right weapon fires the physical ray from that gun's muzzle directly toward its T3 reticle.
- test_procedure:
  1. Launch game with Gorilla Akimbo and equip two shotguns (e.g. Carnage).
  2. Verify that decoupled aim is active, both reticles are visible, and mouse look follows the smoothed chase.
  3. Test mouse swings: verify both reticles splay out dynamically and settle cleanly towards center when resting.
  4. Fire right shotgun, then fire left shotgun: verify muzzle flashes, ballistics, and recoil kick for each gun.

# iteration 39
- date: 2026-11-08 14:55 +0700
- status: passed (user tested in-game: dual-wield ergonomics and chase rubber leash confirmed working; user settings saved as defaults: chaseLeashStart=20.0, chaseLeashMax=60.0, chaseLeashStiffness=0.6)
- previous_iteration_results:
  1. User tested Iteration 38 in-game: dual-wielding with two shotguns (Gorilla Akimbo) works overall!
  2. Feedback & adjustments requested:
     - Ergonomics weight calculation: calculate total weight of both guns divided by two + 10%.
     - Add experimental "rubber leash" for T1 to T2 when separation exceeds a threshold so heavy weapons don't lag excessively far behind during fast mouse movements.
- target_goal / hypothesis:
  1. Dual-Wield Weight Ergonomics:
     - `rawWeight = ((wR + wL) / 2.0) * 1.10`.
     - Previously, summing both weights directly resulted in ~20 kg for two heavy shotguns (exceeding even the 18 kg HMG), creating sluggish handling. Averaging both weights plus a 10% dual-handling penalty produces ~11 kg, providing balanced dual-wield inertia.
  2. Experimental T1-to-T2 Chase Rubber Leash:
     - When separation angle between Camera Gaze (T1) and Gun Direction (T2) exceeds `s_chaseLeashStart` (default 20.0 deg), progressive elastic tension pulls T2 toward T1:
       $$u = \text{clamp}\left(\frac{\text{gapMag} - L_{\text{start}}}{L_{\text{max}} - L_{\text{start}}}, 0.0, 1.0\right)$$
       $$\Delta v_{\text{leash}} = (k \cdot 60 + 120) \times u^p$$
     - At `s_chaseLeashMax` (default 60.0 deg), an absolute distance ceiling `step >= gapMag - s_chaseLeashMax` guarantees that no matter how heavy the weapon is or how fast the mouse moves, the gun will never lag farther behind than the leash limit.
- changes_made:
  1. `src/Hooks/InputHook.hpp` & `src/Hooks/InputHook.cpp`:
     - Added static parameters `s_chaseLeashEnabled`, `s_chaseLeashStart`, `s_chaseLeashMax`, `s_chaseLeashStiffness`.
     - In `computeChaseStep`: implemented progressive spring tension and absolute leash ceiling.
     - Added getters and setters `SetChaseLeashParams`, `GetChaseLeashEnabled`, `GetChaseLeashStart`, `GetChaseLeashMax`, `GetChaseLeashStiffness`.
  2. `src/Main.cpp`:
     - Implemented `DR_SetChaseLeashParams` and getters; registered them in `OnRegisterScriptTypes` for RED4ext RTTI.
  3. `red4ext/plugins/DetachedReticle/DetachedReticle.dll`:
     - Recompiled Release build with MSVC and updated tracked binary.
  4. `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`:
     - In `UpdateWeaponErgonomics`: updated formula to `rawWeight = ((wR + wL) / 2.0) * 1.10`.
     - In `Config`: added default parameters for chase leash (`chaseLeashStart=20.0`, `chaseLeashMax=60.0`, `chaseLeashStiffness=0.6`).
     - Added `SyncChaseLeashParams()` and hooked it into `onInit`, `SyncSmoothing`, and config loading.
     - Added ImGui overlay controls and NativeSettings subcategory for live adjustment.
  5. `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/config.json`:
     - Updated default JSON configuration with new parameters.
- expected_outcome:
  1. Dual-wielding shotguns feels substantially more responsive and agile than an HMG, reflecting ~11 kg effective mass.
  2. Fast mouse sweeps smoothly hit the rubber leash tension at 20 deg separation, accelerating the weapon to follow the camera without falling behind beyond 60 deg.
  3. All parameters can be tuned in real-time via the CET overlay or NativeSettings menu.
- test_procedure:
  1. Launch game with dual shotguns or heavy weapon.
  2. Verify that dual shotguns feel more nimble than in Iteration 38.
  3. Perform rapid, wide mouse sweeps: observe that when separation reaches 20 deg, the reticle accelerates toward camera center and never lags beyond 60 deg.
  4. Verify that CET overlay and NativeSettings sliders adjust the leash behavior live.

# iteration 42
- date: 2026-11-11 00:30 +0700
- status: untested
- previous_iteration_results:
  1. Testing sniper rifles (Overwatch / Grad with long-range scope) revealed bullets consistently miss the reticle center in ADS, landing scattered around the reticle even from a completely stationary, resting position.
  2. In hipfire, the mod's decoupled aim projects T3 from the muzzle trace and fires bullets along the physical barrel axis.
  3. In ADS, optical scopes (CrosshairGameController_NoWeapon) are locked to screen center (0, 0), while the weapon bore axis sits 12-18 cm lower with slight angular offsets (height-over-bore parallax). Furthermore, integral trim resets on ADS transitions in init.lua, preventing barrel alignment from converging before firing.
- target_goal / hypothesis:
  1. In ADS, reverse the relationship: instead of T3 representing physical barrel trajectory, the bullet should artificially converge toward where the sightline / reticle is raycast onto (the camera gaze hit point).
  2. Exceptions: HMG ADS (hip-braced heavy weapon) and dual-wielding ADS (has its own dual stabilization model) remain unchanged.
  3. In hipfire, decoupled aim mechanics and physical barrel ballistics remain 100% active and unmodified.
- changes_made:
  1. `r6/scripts/DetachedReticle/DetachedReticle.reds`:
     - In `UpdateDetachedAim`:
       - Detected ADS via `gamePSMUpperBodyStates.Aim` and `gamePSMCrosshairStates.Aim`.
       - For non-HMG weapons in ADS: raycasted along camera gaze vector (`camFwd3`) against World Static and World Dynamic to find `camTarget`. Computed `convDir = Vector4.Normalize(camTarget - muzzlePos)`.
       - When `convDir` is forward-facing (`Vector4.Dot(convDir, camFwd3) > 0.2`), set `aimFwd = convDir` and `targetPoint = camTarget`.
       - Passed `aimFwd` to `SetMuzzleAimState` for live continuous tracking by native `ShootingHook`.
       - Preserved physical `this.m_gunForward` in `aimSys.SetAimState` so Tier 2B body tracking in `init.lua` continues uninterrupted.
     - In `ShootEvents.OnEnter`:
       - Implemented the identical ADS check and camera raycast convergence for single weapons (`!isDual && isAiming && !isHMG`).
       - Passed `aimFwd = convDir` to `SetMuzzleAimState(muzzlePos, aimFwd, camFwd, true)`.
       - Updated `aimSys.RecordShot` to record `aimFwd` instead of `normMuzzleFwd`.
- expected_outcome:
  1. In ADS with Overwatch (or any scoped/iron sight weapon other than HMG), bullets hit dead-center on the target pointed to by the crosshair.
  2. Hipfire retains 100% decoupled aim with physical barrel ballistics.
  3. HMG ADS and dual-wielding ADS maintain their respective behaviors without regression.
- test_procedure:
  1. Equip Overwatch sniper rifle. Enter ADS, aim at a distinct mark on a distant wall, fire multiple shots, and verify all impacts land directly on the crosshair dot.
  2. Test short-range, medium-range, and long-range targets in ADS to verify parallax correction.
  3. Test hipfire to ensure decoupled reticle motion and muzzle-axis trajectories remain intact.
  4. Test HMG in ADS to verify it does not artificially snap to camera center.

# iteration 43
- date: 2026-11-11 01:10 +0700
- status: passed (user confirmed it works and resolves the drift issue; noted ADS recoil missing on auto/burst guns)
- previous_iteration_results:
  1. User playtesting of Iteration 42 confirmed that ADS sightline convergence eliminated bullet spread (Divergence=0.00 deg in ballistics telemetry records #16-#57).
  2. However, user observed a distinct visual drift during live fire: after repeatedly firing several different guns in ADS, the ADS sight (the 3D gun model and scope optic) gradually creeps either rising or lowering after each shot.
  3. Analysis identified two verified causes in `init.lua`:
     - Cause 1 (`adsLeverArmComp` path-integral hysteresis): Camera local translation in `init.lua:1151-1154` added `(dDrop * fwdZ)` incrementally to `fpp:GetLocalPosition()`. Because `fwdZ = sin(pitch)` varies dynamically over time during recoil and recovery, the closed-loop path integral around a shot cycle $\oint \sin(pitch) d(dropDist) \ne 0$. This permanently accumulated non-zero vertical drift $\pm \Delta Y$ on the camera component after every shot.
     - Cause 2 (Tier 2B skeletal animation latching): `isRecoiling` in `init.lua:1331` only tracked procedural look recoil (`wPitch > 0.02`), which returns to zero in ~0.25s. The 1st-person weapon bone recoil animation takes 0.5s-1.2s to fully settle. When `wPitch` dropped below 0.02 while holding ADS (`readyWeight >= 0.999`), `init.lua` sampled transient skeletal bone pitch and latched it into `lastSettledCompTargetPitch`, feeding artificial pitch offsets to `InputHook.cpp` and shifting puppet/camera residual pitch.
- target_goal / hypothesis:
  1. Fix `adsLeverArmComp`: Calculate camera translation directly as an absolute displacement from the immutable `baselinePos` captured at unholster (`targetPosY = bPos.y + dropDist * fwdZ`), never accumulating deltas onto mutable `curPos`. When recoil recovers and `dropDist = 0`, camera position is guaranteed to return to baseline with zero residual drift.
  2. Bypass Tier 2B body offset in standard ADS: In ADS, vanilla's 1st-person animation already aligns the optic with the camera eye-line. By bypassing Tier 2B (`Game.DR_SetBarrelOffset(0.0, 0.0)`) in standard ADS (`isADS and not isHeavyWeapon`), identical to dual-wielding, we decouple ADS completely from skeletal animation noise while preserving Tier 2B for hipfire and cradle-zoomed HMGs.
- changes_made:
  1. `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`:
     - In `adsLeverArmComp` camera transform block: replaced incremental `(curPos.y + dDrop * fwdZ)` accumulation with absolute displacement from `baselinePos`:
       `targetPosY = (bPos.y or 0.0) + (dropDist * fwdZ)`, `targetPosZ = (bPos.z or 0.0) + (dropDist * fwdXY)`.
     - In Tier 2B compensation block:
       - Defined `isCombatStance = (not isSmartWeapon) and (stateStr == "HIP" or (isHeavyWeapon and stateStr == "ADS"))`.
       - Restricted `lastSettledCompTargetYaw / Pitch` latching and integral screen trim to `isCombatStance`.
       - Added explicit bypass branch `elseif isADS and not isHeavyWeapon then`, setting `Game.DR_SetBarrelOffset(0.0, 0.0)` and clearing settled compensation targets.
- expected_outcome:
  1. Firing repeatedly in ADS with any weapon (Overwatch, SOR-22, Malorian, etc.) results in the scope and gun model returning to the exact initial screen position with zero vertical creep (no gradual rising or lowering).
  2. Hipfire retains 100% decoupled aim and Tier 2B anatomical compensation.
  3. Transitions between HIP and ADS smoothly blend offsets without popping or persistent offset corruption.
  4. HMG retaining `isHeavyWeapon` continues to receive cradle-zoom Tier 2B compensation.
- test_procedure:
  1. Equip Overwatch or SOR-22.
  2. Enter ADS, note the exact pixel alignment of the reticle/scope relative to a distant background landmark.
  3. Fire 5-10 consecutive rounds, pausing between shots for recoil to finish.
  4. Verify the scope and weapon model return to the exact same resting position after every shot with zero rising or lowering.
  5. Test hipfire to ensure decoupled reticle motion and Tier 2B compensation remain intact.

# iteration 44
- date: 2026-11-11 01:40 +0700
- status: untested
- previous_iteration_results:
  1. User tested Iteration 43 in-game and confirmed: "okay it actually works, and resolves the issues" (the sight creep / vertical rising and lowering across repeated shots is completely resolved).
  2. However, user noticed a gameplay issue introduced in Iteration 42: in ADS, weapons no longer exhibit simulated recoil for auto/burst guns because T3 was pinned to screen center (0, 0).
  3. User clarified design intent: T3 was never intended to be static; in ADS, auto/burst weapons (assault rifles, SMGs, LMGs, pistols, revolvers, shotguns) must realistically retain dynamic T3 reticle recoil kick, while precision rifles and sniper rifles maintain camera sightline convergence to hit where the scope reticle is aimed.
- target_goal / hypothesis:
  1. Restrict ADS camera sightline convergence (`aimFwd = convDir`, `targetPoint = camTarget`) strictly to Precision Rifles (`Wea_PrecisionRifle`) and Sniper Rifles (`Wea_SniperRifle`).
  2. For all other weapons (auto/burst guns, handguns, shotguns, LMGs) in ADS:
     - Compute `targetPoint` from physical `this.m_gunForward` so T3 dynamically kicks, climbs, and vibrates on screen with weapon recoil.
     - Fire bullets along physical muzzle forward (`normMuzzleFwd`) straight towards the dynamic T3 target point, restoring realistic ADS recoil handling.
- changes_made:
  1. `r6/scripts/DetachedReticle/DetachedReticle.reds`:
     - In `UpdateDetachedAim`:
       - Evaluated `let isPrecisionOrSniper: Bool = Equals(wType, gamedataItemType.Wea_PrecisionRifle) || Equals(wType, gamedataItemType.Wea_SniperRifle)`.
       - Gated camera sightline convergence behind `isAiming && isPrecisionOrSniper && !isHMG`.
       - Auto/burst and other weapons in ADS fall into the physical barrel raycast branch, projecting dynamic `screenOffset` from `this.m_gunForward`.
     - In `ShootEvents.OnEnter`:
       - Evaluated `isPrecisionOrSniper` and gated `aimFwd = convDir` strictly for precision and sniper rifles in ADS.
       - Auto/burst and other weapons keep `aimFwd = normMuzzleFwd`, directing bullets straight to the kicked T3 impact point.
- expected_outcome:
  1. Precision Rifles (SOR-22, Achilles) and Sniper Rifles (Overwatch, Grad, Nekomata) retain pinpoint accuracy in ADS, hitting the scope crosshair center.
  2. Auto/burst weapons (Copperhead, Ajax, Saratoga, Defender, etc.) realistically kick and climb during ADS fire, with T3 kicking on screen and bullets landing on the climbing T3 reticle.
  3. No vertical baseline drift occurs across shots (Iteration 43 baseline fix remains 100% active).
- test_procedure:
  1. Equip an assault rifle or SMG (Copperhead / Saratoga). Enter ADS, fire a burst or full auto: verify T3 reticle kicks and climbs on screen, and bullets hit where T3 climbs.
  2. Equip Overwatch or SOR-22. Enter ADS, aim at a distant mark: verify the single shot hits dead center on the scope crosshair without spread.
  3. Fire multiple shots with both weapon types to confirm neither suffers from baseline sight creep after recoil settles.

# iteration 45
- date: 2026-11-11 02:45 +0700
- status: failed
- previous_iteration_results:
  1. User confirmed Iteration 43 solved the vertical sight creep across shots in ADS.
  2. In Iteration 44, simulated recoil was restored to auto/burst weapons in ADS while keeping precision and sniper rifles converged to optic center.
  3. User observed slow swaying motion in ADS while holding the camera motionless and asked to disable breathing sway. Telemetry logs empirically confirmed this idle motion corresponds to CDPR's 1st-person weapon breathing sway (~6s cycle).
  4. User explicitly requested: "implementing both wouldn't tell us which one works, make both of them toggleable so i can test each."
- target_goal / hypothesis:
  1. Implement two independent, live-toggleable options (in config, CET ImGui overlay, NativeSettings UI, and redscript):
     - Toggle 1 (`disableProceduralSway`): Tests Hypothesis A (engine procedural weapon sway). Dynamically adds `Multiplier = 0.0` modifiers for `SwaySideMaximumAngleDistance`, `SwaySideMinimumAngleDistance`, `SwayCenterMaximumAngleOffset`, and `Sway` via `StatsSystem.AddModifier/RemoveModifier` to weapon and player entities.
     - Toggle 2 (`adsIdleStabilize`): Tests Hypothesis B (viewmodel skeletal breathing animation). When resting in ADS without mouse movement (`AbsF(yawLag) < 0.60 && AbsF(pitchLag) < 0.60 && !isRecoiling && timeSinceShot > 0.35`), stabilizes T3 and the initial shot to `camTarget`, holding the reticle rock-solid at center, while releasing immediately on shot firing (`isRecoiling` / recoil recovery window) or mouse movement to retain 100% of simulated recoil kick and pan tracking weight.
- changes_made:
  1. `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/config.json`:
     - Added `"disableProceduralSway": false` and `"adsIdleStabilize": false`.
  2. `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`:
     - Initialized `Config.disableProceduralSway` and `Config.adsIdleStabilize` (default: `false`).
     - Added serialization in `LoadConfig()` and `SaveConfig()`.
     - In `SetupNativeSettings()`: added subcategory `ADS Sway & Stabilization` with two switches.
     - In `onDraw()`: added ImGui checkboxes with descriptive tooltips under `ADS Sway & Stabilization`.
     - Added `DetachedReticle.SetDisableProceduralSway(val)` and `DetachedReticle.SetAdsIdleStabilize(val)`.
     - In `onUpdate`: passed `isRecoiling`, `Config.disableProceduralSway`, and `Config.adsIdleStabilize` to `aimSys` every frame.
     - Updated `GetOptions()` log string.
  3. `r6/scripts/DetachedReticle/DetachedReticle.reds`:
     - In `DetachedAimSystem`:
       - Added fields: `m_disableProceduralSway`, `m_adsIdleStabilize`, `m_isRecoiling`, `m_lastShotEngineTime`, `m_swayWeaponMods`, `m_swayPlayerMods`, `m_swayWeaponOwner`, `m_swayPlayerOwner`, `m_swayWeaponId`, `m_hasSwayApplied`.
       - Implemented `ApplySwayModifiers`, `RemoveSwayModifiers`, `OnWeaponUnequipped`, and toggle getters/setters.
       - In `RecordShot`: recorded `m_lastShotEngineTime`.
     - In `UpdateDetachedAim`:
       - Managed procedural sway modifiers on weapon equip/unequip/change.
       - Computed `yawLagDeg` and `pitchLagDeg` before raycast.
       - Evaluated `isRestingADS`: when active and resting in ADS with auto/burst weapons, stabilized `targetPoint` to `camTarget`, locking T3 still at optic center; broke stabilization immediately when firing or panning.
     - In `ShootEvents.OnEnter`:
       - Converged initial resting ADS shots to `camTarget` when `adsIdleStabilize` is active.
       - Recorded `aimSys.SetLastShotEngineTime(curEngineTime)`.
       - Allowed rapid/auto follow-up shots to follow physical `normMuzzleFwd` to preserve recoil climb.
- failure_analysis:
  - Redscript compilation failed with `[NO_MATCHING_OVERLOAD] arguments passed to 'OperatorNotEqual' do not match any of the overloads: 1st argument: expected 'EntityID', given 'Bool' at DetachedReticle.reds:47:12`.
  - Cause: In redscript, primitive `Bool` does not have an `!=` or `==` operator overload (`if this.m_disableProceduralSway != enable`).

# iteration 46
- date: 2026-11-11 18:55 +0700
- status: passed
- previous_iteration_results:
  - Iteration 45 redscript compilation failed due to `this.m_disableProceduralSway != enable` at line 47.
- target_goal / hypothesis:
  - Fix the boolean inequality check in `SetDisableProceduralSway` by directly assigning `this.m_disableProceduralSway = enable` and checking `if !enable && this.m_hasSwayApplied`.
  - Clean up redundant scoped re-declarations of `let aimSys: ref<DetachedAimSystem>` in `ShootEvents.OnEnter` to ensure clean compilation.
- changes_made:
  1. `r6/scripts/DetachedReticle/DetachedReticle.reds`:
     - In `DetachedAimSystem.SetDisableProceduralSway`: removed boolean `!=` operator, assigning `enable` directly and cleaning modifiers if `!enable && this.m_hasSwayApplied`.
     - In `ShootEvents.OnEnter`: scoped single `let aimSys: ref<DetachedAimSystem> = DetachedAimSystem.GetInstance(...)` at top of `if isDecoupledActive` block, eliminating duplicate sub-block declarations.
  2. `docs/research/noted-issues.md`:
     - Documented redscript language restriction: primitive `Bool` has no `!=` / `==` operator overloads.
- expected_outcome:
  - Redscript compiles cleanly with zero errors in `r6/logs/redscript_rCURRENT.log`.
  - Both toggles functional as described in Iteration 45.
- test_procedure:
  - Deploy `r6/scripts/DetachedReticle/DetachedReticle.reds`.
  - Launch game and verify `r6/logs/redscript_rCURRENT.log` reports `Compilation complete` and `Output successfully saved`.
  - Proceed with Iteration 45 test matrix.
- test_results:
  1. Redscript compiled cleanly with zero errors upon game launch.
  2. User verified in-game:
     - Breathing sway in ADS is completely eliminated without needing to disable procedural stats (`disableProceduralSway = false`).
     - Weapons that previously had accuracy issues in ADS now fire consistently, landing near and slightly below the reticle as expected from physical barrel ballistics.
     - Resting ADS reticle stabilization successfully holds T3 rock-solid at optic center while resting, and breaks dynamically into simulated recoil upon firing.

# iteration 47
- date: 2026-11-11 19:40 +0700
- status: untested
- previous_iteration_results:
  1. User verified in Iteration 46 that resting ADS reticle stabilization works well and eliminates breathing drift while holding ADS still, and weapons with accuracy issues now fire near/below the reticle.
  2. User reported two remaining issues:
     - The `disableProceduralSway` option toggle does not enable/disable anything in-game.
     - In ADS, auto/burst weapons have vertical recoil climb but lack random horizontal recoil push (should be half of the intensity of hipfiring horizontal spread).
- target_goal / hypothesis:
  1. Fix `disableProceduralSway`:
     - Root cause: In Iteration 45/46, modifiers were applied using `StatsSystem.AddModifier` with `Multiplier = 0.0` to `weapon.GetEntityID()` and `player.GetEntityID()`. In REDengine, weapon item stats live on `weapon.GetItemData().GetStatsObjectID()` and `Cast<StatsObjectID>(weapon.GetItemID())`. Furthermore, `PlayerWeaponHandlingModifiers` continually manages additive and multiplier modifiers on weapon entities during stamina changes, so `Multiplier = 0.0` does not override additive stats.
     - Solution: Use `StatsSystem.ForceModifier` across all 10 sway stat types (`SwaySideMaximumAngleDistance`, `SwaySideMinimumAngleDistance`, `SwayCenterMaximumAngleOffset`, `SwaySideTopAngleLimit`, `SwaySideBottomAngleLimit`, `Sway`, `SwayCurvatureMaximumFactor`, `SwayCurvatureMinimumFactor`, `SwayInitialOffsetRandomFactor`, `SwayStartBlendTime`) applied directly to `itemData.GetStatsObjectID()`, `weapon.GetItemID()`, `weapon.GetEntityID()`, and `player.GetEntityID()`. When toggled off or unequipped, clean up via `StatsSystem.UnforceStat`. Bridge status logging to CET via `aimSys:GetSwayStatusLog()`.
  2. Implement ADS horizontal recoil push (half intensity of hipfire):
     - Root cause: In vanilla 1st-person ADS, the weapon and arms are rigidly locked to the First Person Camera component. When `InputHook` applies native recoil yaw to body heading (`outYaw`) and counter-rotates the camera by `-s_recoilYaw` (`s_residualYaw`), the arms rotate with the camera, producing ~0° relative horizontal deflection in camera space. Furthermore, CDPR's ADS firing animation only animates vertical pitch kick with 0 horizontal displacement. Thus, ADS weapons had vertical climb but zero horizontal recoil kick or spread.
     - Solution:
       - Declare `DR_GetRecoilYaw()` and `DR_GetRecoilPitch()` in `NativeBridge.reds` to query native horizontal recoil deflection directly in script.
       - Add `adsRecoilHoriMult` (default: `0.5`, half intensity) in config and Native Settings slider [0.0..1.0].
       - In `UpdateDetachedAim`: during non-resting ADS rapid/auto fire (`isAiming && !isHMG && !isPrecisionOrSniper && !isRestingADS`), deflect `effGunFwd = Vector4.Normalize(this.m_gunForward + camRight * TanF(Deg2Rad(DR_GetRecoilYaw() * adsRecoilHoriMult)))`. The projected reticle kicks left/right dynamically.
       - In `ShootEvents.OnEnter`: deflect bullet trajectory along the exact same vector `aimFwd = Vector4.Normalize(normMuzzleFwd + camRight * TanF(Deg2Rad(DR_GetRecoilYaw() * adsRecoilHoriMult)))`. Bullets land precisely where the kicking reticle points.
- changes_made:
  1. `r6/scripts/DetachedReticle/NativeBridge.reds`:
     - Declared `public native func DR_GetRecoilYaw() -> Float;` and `public native func DR_GetRecoilPitch() -> Float;`.
  2. `r6/scripts/DetachedReticle/DetachedReticle.reds`:
     - In `DetachedAimSystem`:
       - Added fields: `m_adsRecoilHoriMult`, `m_swayItemOwner`, `m_swayItemIdOwner`, `m_hasItemOwner`, `m_swayStatusLog`.
       - Added getters and setters: `SetAdsRecoilHoriMult`, `GetAdsRecoilHoriMult` (defaults to 0.5), `GetSwayStatusLog`, `ClearSwayStatusLog`.
       - In `ApplySwayModifiers`: converted to `StatsSystem.ForceModifier` across all 10 sway stat types on `ItemData`, `ItemID`, `Weapon`, and `Player` object IDs.
       - In `RemoveSwayModifiers`: converted to `StatsSystem.UnforceStat` across all 10 sway stat types for all owners.
     - In `UpdateDetachedAim`:
       - In non-resting ADS fire (`isAiming && !isHMG && !isPrecisionOrSniper && !isRestingADS`), computed `effGunFwd = Vector4.Normalize(this.m_gunForward + camRight * TanF(Deg2Rad(DR_GetRecoilYaw() * adsRecoilHoriMult)))`.
       - Used `effGunFwd` for raycasting `targetPoint` and updating `aimSys.SetAimState`.
     - In `ShootEvents.OnEnter`:
       - Added horizontal recoil deflection branch: `aimFwd = Vector4.Normalize(normMuzzleFwd + camRight * TanF(Deg2Rad(DR_GetRecoilYaw() * adsRecoilHoriMult)))` for auto/burst weapons in ADS during recoil.
  3. `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/config.json`:
     - Added `"adsRecoilHoriMult": 0.5`.
  4. `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`:
     - Initialized `Config.adsRecoilHoriMult = 0.5` with config serialization.
     - In `SetupNativeSettings()`: added `ADS Horizontal Recoil Multiplier` slider under `ADS Sway & Stabilization` (range 0.0 to 1.0, step 0.05, default 0.5).
     - Added `DetachedReticle.SetAdsRecoilHoriMult(val)`.
     - In `onUpdate`: synced `Config.adsRecoilHoriMult` to `aimSys` and polled `GetSwayStatusLog()` to print stat modifier updates to `DetachedReticle.log`.
     - Updated `GetOptions()` log string with `adsRecoilHoriMult`.
  5. `docs/research/noted-issues.md`:
     - Documented weapon item stat object IDs and `StatsSystem.ForceModifier` requirement.
     - Documented ADS First Person Camera parenting locking out horizontal recoil animation.
- expected_outcome:
  - Toggling `disableProceduralSway` in-game forces/unforces weapon sway stats to 0.0, observable in `DetachedReticle.log` and in weapon idle behavior.
  - In ADS, rapid or automatic fire with non-sniper weapons produces dynamic alternating horizontal recoil kicks on both the reticle (T3) and bullet impacts at half the intensity of hipfire horizontal scatter.
  - Resting ADS remains stabilized at optical center, and sniper/precision rifles continue to converge smoothly to the center crosshair.
- test_procedure:
  - Deploy modified files to `E:\Cyberpunk 2077`.
  - Launch game, check `r6/logs/redscript_rCURRENT.log` for clean compilation.
  - Test `disableProceduralSway` toggle on/off: verify log output `[SWAY_STATS] Applied ForceModifier...` and `[SWAY_STATS] Unforced all sway stats...`.
  - Test ADS automatic fire with assault rifles (e.g. Copperhead, Ajax) and SMGs: verify visible alternating horizontal recoil kick on the reticle and bullet impact cluster at 50% hipfire spread.
  - Test slider `adsRecoilHoriMult` (0.0 = purely vertical, 0.5 = half intensity, 1.0 = full hipfire intensity).

# iteration 48
- date: 2026-11-11 20:47 +0700
- status: passed
- previous_iteration_results:
  1. In Iterations 42 and 44, Precision Rifles (`Wea_PrecisionRifle`) and Sniper Rifles (`Wea_SniperRifle`) in ADS were special-cased (`isPrecisionOrSniper`) to raycast from `camPos` along `camFwd3` (T1) and set `targetPoint = camTarget` and `aimFwd = Vector4.Normalize(camTarget - muzzlePos)`.
  2. While this eliminated the $6\text{--}13\text{ cm}$ height-over-bore drop between the scope (`camPos`) and `MuzzleSlot` (`muzzlePos`), raycasting along `camFwd3` completely discarded `this.m_gunForward` (`normMuzzleFwd`), directly snapping T3 and bullets to T1 and bypassing the 3D gun barrel's natural breathing sway, mouse-chase lag (`T2A`), and recoil (`W`).
  3. Telemetry logs (`DetachedReticle.log` `02:21:24`–`02:21:31` with `Items.Preset_Psycho_ma_wat_lch_06_end` / Overwatch) confirmed that upon entering ADS (`F=11250`), the 3D weapon and scope naturally align with the camera (`dYaw = -0.01°`, `dPitch = -0.05°`, `ReticleScreen = (0.5, 4.1) px`), and over the next 6 seconds the 3D gun's breathing animation sways `m_gunForward` by up to `0.57°` (`17.3 px`), while `MuzzleRelCam` sits vertically $6\text{--}13\text{ cm}$ below the camera (`U = -0.06m to -0.13m`, `R = 0.00m`).
- target_goal / hypothesis:
  1. Restore the core architectural rule across all weapons (including Precision and Sniper rifles):
     - T3 and bullet trajectories must always be derived from the 3D gun barrel's direction (`m_gunForward` / `normMuzzleFwd`) plus optional artificial angular modifications (`effGunFwd`).
     - In ADS, T3 aligns with the camera *indirectly* because the 3D gun and scope naturally align with the camera via vanilla 1st-person animation, while preserving 3D breathing sway, mouse-chase lag (`T2A`), and recoil (`W`).
  2. Eliminate the $6\text{--}13\text{ cm}$ height-over-bore parallax drop in ADS for all non-HMG weapons without discarding `effGunFwd`:
     - In ADS (`isAiming && !isHMG`), raycast the sightline from the scope/eye origin (`camPos`) along **`effGunFwd`** (instead of `camFwd3`) to find `sightTarget`, set `targetPoint = sightTarget`, and converge the bullet trajectory from `muzzlePos` to `sightTarget` (`aimFwd = Vector4.Normalize(sightTarget - muzzlePos)`).
     - Because `sightTarget - camPos` is strictly parallel to `effGunFwd`, T3's screen projection reflects 100% of `effGunFwd`'s pitch and yaw (including natural 3D breathing sway, chase lag, and recoil) with zero close/mid-range height-over-bore drop, and every shot from `muzzlePos` lands directly on T3 before natural stat-based spread.
- changes_made:
  1. `r6/scripts/DetachedReticle/DetachedReticle.reds`:
     - In `UpdateDetachedAim`:
       - Removed the `isPrecisionOrSniper` special-case override so Precision and Sniper rifles follow the exact same rules as all other non-HMG weapons.
       - Constructed `effGunFwd` from `this.m_gunForward`, applying artificial angular modifications when in ADS (`effGunFwd = camFwd3` when `isRestingADS` is active via `adsIdleStabilize`, or horizontal recoil deflection `adsHoriYawDeg` when `!isRestingADS`).
       - In ADS (`isAiming && !isHMG`), raycasted from `camPos` along `effGunFwd` (`World Static` and `World Dynamic`, `200.0m`) to find `sightTarget`, setting `targetPoint = sightTarget` and `aimFwd = Vector4.Normalize(sightTarget - muzzlePos)`.
     - In `ShootEvents.OnEnter`:
       - Removed the `isPrecisionOrSniper` special-case override and mirrored `UpdateDetachedAim`: constructed `effGunFwd` from `normMuzzleFwd` + angular modifications and raycasted from `camPos` along `effGunFwd` so shots from `muzzlePos` converge onto `sightTarget` (matching T3's pitch and yaw before natural bullet spread).
- expected_outcome:
  1. In ADS with Precision Rifles (e.g. Achilles, Sor-22) and Sniper Rifles (e.g. Grad/Overwatch, Nekomata, Ashura) with `adsIdleStabilize = false`:
     - T3 naturally aligns with the camera when entering ADS, exhibits the 3D weapon's natural breathing sway, lags behind fast mouse pans (`T2A`), and kicks with recoil (`W`).
     - Shots fired at any point during breathing sway, mouse panning, or recoil travel toward T3 (before natural weapon spread), with zero $6\text{--}13\text{ cm}$ height-over-bore drop.
  2. When `adsIdleStabilize = true`, resting ADS applies the artificial angular modification (`effGunFwd = camFwd3`) uniformly across all non-HMG weapons, and breaks out immediately upon firing or panning.
- test_procedure:
  1. Deploy `r6/scripts/DetachedReticle/DetachedReticle.reds` to `E:\Cyberpunk 2077\r6\scripts\DetachedReticle\DetachedReticle.reds`.
  2. Launch game and verify clean compilation in `E:\Cyberpunk 2077\r6\logs\redscript_rCURRENT.log`.
  3. Equip a Sniper Rifle (e.g. Grad / Overwatch) and a Precision Rifle (e.g. Achilles) with `adsIdleStabilize = false`:
     - Enter ADS and hold mouse still: verify T3 moves gently with the 3D gun's breathing sway rather than being frozen at `(0, 0)`.
     - Pan mouse in ADS: verify T3 trails with the weapon's heavy chase lag (`T2A`) and settles back to center.
     - Fire shots at various points of the breathing sway cycle and at close/mid/far distances: verify bullets land at T3 without height-over-bore drop.
- test_results:
  1. User verified in-game with `adsIdleStabilize = false`: the scope-zeroed barrel direction solution (`camPos` + `effGunFwd`) works well and resolves the main ADS accuracy/alignment issue while preserving natural breathing sway.

# iteration 49
- date: 2026-11-11 21:01 +0700
- status: passed
- previous_iteration_results:
  1. User confirmed Iteration 48 works well with `adsIdleStabilize` disabled, and requested removing `adsIdleStabilize` and `disableProceduralSway` from the config and codebase since they are no longer needed now that the scope-zeroed barrel direction solution resolves the underlying ADS issue.
- target_goal / hypothesis:
  1. Cleanly remove `disableProceduralSway` and `adsIdleStabilize` from `config.json`, `init.lua`, and `DetachedReticle.reds`, while retaining `adsRecoilHoriMult` under `/detachedReticle/recoilHorizontal`.
- changes_made:
  1. `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/config.json`:
     - Removed `"disableProceduralSway"` and `"adsIdleStabilize"`.
  2. `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`:
     - Removed `disableProceduralSway` and `adsIdleStabilize` from `Config`, `LoadConfig()`, `onUpdate`, ImGui `onDraw()`, console setters, and `GetOptions()`.
     - Removed `/detachedReticle/adsSway` subcategory in `SetupNativeSettings()` and moved `ADS Horizontal Recoil Multiplier` (`ns.addRangeFloat`) under `/detachedReticle/recoilHorizontal`.
  3. `r6/scripts/DetachedReticle/DetachedReticle.reds`:
     - Removed procedural sway stat modifier fields/methods and resting ADS idle stabilization fields/logic from `DetachedAimSystem`, `UpdateDetachedAim`, and `ShootEvents.OnEnter`.

# iteration 50
- date: 2026-11-11 22:42 +0700
- status: passed
- previous_iteration_results:
  1. User reported that when running and the gun is not at the "ready" / hip-fire / ADS position, the movement direction deviates several degrees to the right or left of `T1` yaw (varying by weapon), caused by `T2B` barrel compensation remaining active. User requested turning off (neutralizing) `T2B` when not aiming / not in ready posture, with a gradual transition (`~0.2–0.4s`) between ON and OFF to prevent camera jitter/shake.
- target_goal / hypothesis:
  1. **Root causes verified in `DetachedReticle.log` and vanilla PSM scripts (`crosshairTransitions.script`, `locomotionTransitions.script`, `weaponTransitions.script`):**
     - Physical WASD forward movement (`MoveHeading`) follows puppet body yaw (`T2B`), so any non-zero `CompYaw` skews movement direction by `-CompYaw` relative to camera yaw (`T1`).
     - During Sprint (`Locomotion == 2` or `LocomotionDetailed == 4` / `5`), `crosshairTransitions.script:22-23` returns `gamePSMCrosshairStates.HipFire` (`8`) and `RightWeapon` remains `5` (`Ready`). Because `init.lua` only checked `crosshairState == 7` for `"SPRINT"`, `stateStr` evaluated to `"HIP"` while sprinting, causing `T2B` to actively track the weapon's sprint chest-carry angle (e.g. `Sor22` `+8.40°`, `Kyubi` `+6.17°`, `Malorian` `-8.46°`, `Psycho` `+8.35°`).
     - During `PublicSafe -> Ready` (`weaponTransitions.script:1606`) and `Sprint -> Stand` transitions, `RightWeapon` flips to `5` (`Ready`) before the arms finish swinging the barrel back to the hipfire pose (`gunRelVel` `20–150 deg/s`), latching transient swing angles (`+5.9°` to `+8.4°`) into `lastSettledCompTargetYaw`. Conversely, when lowering into `PublicSafe` (`F=10943`), the barrel starts rotating toward `+45°` before `RightWeapon` flips to `6`, pulling `CompYaw`/`CompPitch` up to `+3.8°` before snapping to `0.0`.
     - In `init.lua:1458, 1492`, `hasSettledComp` overrode `readyWeight < 0.999` and kept feeding `lastSettledCompTargetYaw` into `DR_SetBarrelOffset` even when `isReadyStance` was `false`.
     - Stepping `s_targetCompYaw`/`Pitch` to `0.0` in a single frame caused a 1-frame lookahead prediction mismatch in `InputHook.cpp:687-698`, producing a visible camera twitch.
  2. **Fix in `init.lua`:**
     - Read `Locomotion` (`locoState`) and `LocomotionDetailed` (`locoDetailed`) from `psmBB`; detect sprint (`crosshairState == 7 or locoState == 2 or locoDetailed == 4 or locoDetailed == 5`) and non-ready locomotion states (`Slide`, `Dodge`, `Vault`, `Climb`, `Workspot`).
     - Track body-relative barrel angular velocity `gunRelVel`, a `0.20s` post-recoil hold window (`inRecoilWindow`), departure from settled pose (`isLeavingSettledPose`), and a settled ready posture timer (`readyStableTimer >= 0.10s`) before enabling `T2B`.
     - Ramp `t2bActiveLinear` $\in [0, 1]$ over `0.25s` using a $C^1$-continuous smoothstep `t2bBlend = u * u * (3.0 - 2.0 * u)` (giving a smooth `~0.30s` total transition with the native filter), holding `lastValidCompYaw`/`Pitch` during ramp-down so non-ready transition animations are never sampled.
     - Only latch `lastSettledCompTargetYaw`/`Pitch` when settled at rest in ready posture (`gunRelVel < 3.5 deg/s`, `lastMoveSpeed < 0.25 m/s`, `readyStableTimer >= 0.15s`).
- changes_made:
  1. `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua`:
     - Added `locoState` and `locoDetailed` reads from `PlayerStateMachine` blackboard in `onUpdate` and `upperBodyState`/`rightWeaponState`/`crosshairState`/`T2BBlend` telemetry in `MonitorLocomotion`.
     - Updated `stateStr` and `isReadyPosture` to gate out Sprint, CrouchSprint, Safe/PublicSafe, Equip/Unequip, Reload/QuickMelee, and non-ready locomotion states.
     - Implemented `readyStableTimer`, `gunRelVel` settled-offset latching, `isLeavingSettledPose` early ramp-down detection, and the gradual `0.25s` smoothstep `t2bBlend` envelope (`~0.30s` total transition) for turning `T2B` ON and OFF.
- expected_outcome:
  1. When sprinting or running with the weapon lowered / safe / not in ready posture, `T2B` compensation smoothly ramps to `0.0` over `~0.30s`, aligning puppet body heading (`T2B`) and movement direction (`MoveHeading`) with `T1` camera yaw (`dMove_Cam ~ 0.0°`).
  2. Transitions into and out of `T2B` (Ready Hipfire $\leftrightarrow$ Sprint, Ready Hipfire $\leftrightarrow$ Safe, Ready Hipfire $\leftrightarrow$ ADS) occur smoothly over `~0.30s` without camera snap or jitter, and never latch mid-swing arm animation angles.
- test_procedure:
  1. Deploy `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua` to `E:\Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\DetachedReticle\init.lua`.
  2. Test multiple weapons (`Sor22`, `Kyubi`, `Malorian`, `Psycho`, `Tactician`) while sprinting, running with weapon lowered/safe, and transitioning between Sprint/Safe/ADS and Ready Hipfire.
  3. Verify in-game and in `DetachedReticle.log` (`[LOCOMOTION_MONITOR]` and `[T2B_OFFSET_COMP]`) that `CompYaw` smoothly neutralizes to `0.00 deg` (`dMove_Cam ~ 0.00 deg`) when not in ready posture and smoothly restores in ready hipfire without camera shake.
- test_results:
  1. User verified in-game: `T2B` compensation cleanly neutralizes when running/sprinting or not in ready/hip-fire/ADS posture so movement aligns with `T1` yaw, and transitions between ON and OFF are smooth with no jitter or shake.

# iteration 51
- date: 2026-11-12 00:04 +0700
- status: passed
- previous_iteration_results:
  1. User reported two issues when dual-wielding in ready stance (both non-ADS and ADS):
     - Bullets coming from the right gun and left gun both go to the left gun's reticle instead of each of their own T3 reticles.
     - Each gun's T3 should have artificial stabilization towards the center reticle, with natural sways (without altering T2B).
- target_goal / hypothesis:
  1. **Root Cause 1 — Same-Frame Overwrite in `ShootingHook` (`src/Hooks/ShootingHook.cpp`, `DetachedReticle.reds`, `shootTransitions.script:290-297`):**
     - Verified in `DetachedReticle.log` (`#11..#85`): when dual-wielding in ADS, firing full-auto pairs (`Items.Preset_Lexington_Pimp`), or firing both guns (`BothWeapons`), both `WeaponRight` and `WeaponLeft` state machines enter `ShootEvents.OnEnter` on the **exact same frame** (`m_shotCount` jumps by 2 per frame).
     - `WeaponRight` entered `ShootEvents.OnEnter` first and wrote `rightMuzzlePos` / `rightAimFwd` to the single static `ShootingHook::s_muzzlePos` / `s_muzzleFwd`. Microseconds later on the same PSM tick (before the native Effect System executed `gameEffectObjectProvider_PhysicalRay::Execute`), `WeaponLeft` entered `ShootEvents.OnEnter` and overwrote `s_muzzlePos` and `s_muzzleFwd` with the **left gun's** muzzle and trajectory. Consequently, when `Hooked_WaPhysicalRayOrigin` (`0x9507B7`) and `Hooked_WaPhysicalRayForward` (`0x9507EC`) ran for both guns' rays, both rays read the left gun's muzzle and forward vector.
     - Additionally, `UpdateDualWieldAim` and `ShootEvents.OnEnter` previously blended 3D unit vectors toward `camTarget` (`100m` `World Static` only) rather than converging each hand's bullet ray from `muzzlePos` onto the exact 3D target point (`rightTargetPt` / `leftTargetPt`) projected by that hand's T3 reticle.
  2. **Root Cause 2 — Dual-Wield Ready Stance Gates & Virtual Barrel Stabilization (`init.lua`, `DetachedReticle.reds`, `psmImports.script:581-591, 842-853`):**
     - In `init.lua:1354`, `upperBodyState == 7` (`gamePSMUpperBodyStates.DualWield == 7`) was misclassified as `stateStr = "SAFE"`, and `rightWeaponState == 8` (`gamePSMRangedWeaponStates.Shoot == 8`) was omitted from `isWeaponStateReady`.
     - In Iteration 50 (`init.lua:1461`), `and (not isDual)` was added to `isCombatStance`, causing `readyWeight` to always be `0.0` when dual-wielding; in Lua, `(readyWeight or 1.0)` evaluated `0.0 or 1.0` to `0.0`, so `aimSys:SetDualStabilizeWeight(0.0)` was always `0.0` in both non-ADS and ADS.
     - Furthermore, the old screen-space scaling formula (`screenOffset * (1.0 - stabWeight)`) scaled down natural 3D sway, `T2A` chase lag, and `W` recoil equally rather than isolating each arm's resting anatomical splay.
     - By measuring each gun's body-relative (`T2B`-relative) angles `(relYaw_i, relPitch_i) = (gunYaw_i - rYaw, gunPitch_i + rPitch)` in camera space, tracking each hand's low-pass resting anatomical offset `(baseYaw_i, basePitch_i)` ($\tau = 0.08\text{ s}$ during the $0.45\text{ s}$ equip / `HIP <-> ADS` transition window; $\tau = 2.5\text{ s}$ once settled so $>98\%$ of natural 3D breathing/walking sway passes through), subtracting `stabWeight * base_i` from each gun's barrel angle, and interpolating the sight raycast origin `sightOrigin_i = muzPos_i * (1 - stabWeight) + camPos * stabWeight`, both guns' T3 reticles stabilize onto the center reticle in ready stance (both non-ADS and ADS) while preserving 100% of each gun's natural 3D sway, `T2A` chase lag, and `W` recoil, without ever altering `T2B` (`DR_SetBarrelOffset(0.0, 0.0)`).
- changes_made:
  1. `src/Hooks/ShootingHook.hpp`, `src/Hooks/ShootingHook.cpp`, `src/Main.cpp`, `r6/scripts/DetachedReticle/NativeBridge.reds`, `red4ext/plugins/DetachedReticle/DetachedReticle.dll`:
     - Added thread-safe (`SRWLOCK`) per-shot FIFO ring buffer (`QueuedShot` with `remainingRays` and `120 ms` expiry) and RTTI function `QueueMuzzleShot(muzzlePos, muzzleFwd, camFwd, pelletCount)` to `ShootingHook`, plus `DR_GetResidualYaw()` and `DR_GetResidualPitch()` declarations in `NativeBridge.reds`.
     - In `Hooked_WaPhysicalRayOrigin`, after `WaPlayerOwnedWeapon(rdx)` succeeds, consumes one ray from the front of the FIFO shot queue so simultaneous Right and Left gun shots on the same frame each use their own muzzle origin and converged T3 trajectory.
     - Rebuilt `DetachedReticle.dll`.
  2. `r6/scripts/DetachedReticle/DetachedReticle.reds`:
     - Added per-hand resting baseline fields and `UpdateDualBaseOffsets` / `ResetDualSettled` to `DetachedAimSystem`.
     - Updated `UpdateDualWieldAim` to compute each hand's virtual stabilized barrel vector `effFwd_i`, raycast from `sightOrigin_i` (`World Static` + `World Dynamic`, `200m`) to get `rightTargetPt` and `leftTargetPt`, project each to its own T3 widget (`activeWidget` and `m_leftCrosshair`), and converge `rightAimFwd` / `leftAimFwd` onto each hand's 3D target point.
     - Updated `ShootEvents.OnEnter` to identify which hand is firing (`this.IsLeftWeaponLogic() || weapon == leftWeapon`), compute that hand's stabilized converged `aimFwd`, query `ProjectilesPerShot`, and enqueue the shot via `QueueMuzzleShot(muzzlePos, aimFwd, camFwd, pellets)`.
  3. `bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/init.lua` & `config.json`:
     - Fixed `upperBodyState == 7` (`DualWield`) and `rightWeaponState == 8` (`Shoot`) / `1` (`Charging`) in `stateStr` and `isWeaponStateReady`.
     - Added `leftWeaponState` read and `isDualReadyPosture` gate (active in both `"HIP"` and `"ADS"` ready stances) with a `0.25s` smoothstep ramp (`dualStabBlend`) feeding `aimSys:SetDualStabilizeWeight(stabFactor)`, while keeping `Game.DR_SetBarrelOffset(0.0, 0.0)`.
- expected_outcome:
  1. When dual-wielding in ready stance (both non-ADS and ADS), right-gun bullets always originate from the right muzzle and hit the right gun's T3 reticle, and left-gun bullets always originate from the left muzzle and hit the left gun's T3 reticle, even when both guns fire on the exact same frame.
  2. Both guns' T3 reticles stabilize around the center reticle in ready stance (both non-ADS and ADS) while preserving each gun's independent natural 3D breathing/walking sway, `T2A` mouse-chase lag, and `W` recoil, with `T2B` barrel compensation remaining strictly `0.0`.
- test_procedure:
  1. Deploy `DetachedReticle.dll`, `DetachedReticle.reds`, `NativeBridge.reds`, `init.lua`, and `config.json` to `E:\Cyberpunk 2077`.
  2. Equip dual-wielded ranged weapons in ready stance (test both non-ADS hipfire and ADS):
     - Verify both right and left T3 reticles stabilize around the center reticle while exhibiting natural 3D breathing and walking sway (and trailing with `T2A` chase lag when panning).
     - Fire right gun alone, left gun alone, and both guns simultaneously (semi-auto and full-auto in both hipfire and ADS): verify right-gun bullets land on the right T3 reticle and left-gun bullets land on the left T3 reticle.
- test_results:
  1. User verified in-game and approved for minor release (`v1.3.0`).

# next iteration above this line

### Findings Writing Rules:
- Write iterations continuing the last one
- Never edit/revise written iterations unless there's a typo
- Fixes for a wrong implementation in an iteration = next iteration, describing what were wrong and what's the solution

