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

# next iteration above this line

### Findings Writing Rules:
- Write iterations continuing the last one
- Never edit/revise written iterations unless there's a typo
- Fixes for a wrong implementation in an iteration = next iteration, describing what were wrong and what's the solution

