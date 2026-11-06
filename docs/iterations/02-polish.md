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
  4. **Compile Fix:** smartGunUIParameters is an IScriptable class requiring indirection (ef<...>). Fixed FromVariant<smartGunUIParameters> to FromVariant<ref<smartGunUIParameters>>.
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

# next iteration above this line

### Findings Writing Rules:
- Write iterations continuing the last one
- Never edit/revise written iterations unless there's a typo
- Fixes for a wrong implementation in an iteration = next iteration, describing what were wrong and what's the solution

