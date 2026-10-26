// DetachedReticle.reds
// Decoupled Aim Mod for Cyberpunk 2077
// Camera freelook with weighted/delayed gun crosshair & ballistics redirection

public class DetachedAimSystem extends ScriptableSystem {
    private let m_gunForward: Vector4;
    private let m_targetPoint: Vector4;
    private let m_cameraForward: Vector4;
    private let m_screenOffset: Vector2;
    private let m_angleLagDeg: Float;
    private let m_yawLagDeg: Float;
    private let m_pitchLagDeg: Float;
    private let m_isDetachedActive: Bool;
    private let m_shotCount: Int32;
    private let m_lastShotMuzzlePos: Vector4;
    private let m_lastShotBulletDir: Vector4;
    private let m_lastShotAngleDeg: Float;

    public func SetAimState(gunFwd: Vector4, targetPt: Vector4, camFwd: Vector4, screenOffset: Vector2, angleLagDeg: Float, yawLagDeg: Float, pitchLagDeg: Float, isDetached: Bool) -> Void {
        this.m_gunForward = gunFwd;
        this.m_targetPoint = targetPt;
        this.m_cameraForward = camFwd;
        this.m_screenOffset = screenOffset;
        this.m_angleLagDeg = angleLagDeg;
        this.m_yawLagDeg = yawLagDeg;
        this.m_pitchLagDeg = pitchLagDeg;
        this.m_isDetachedActive = isDetached;
    }

    public func RecordShot(muzzlePos: Vector4, bulletDir: Vector4, angleDeg: Float) -> Void {
        this.m_shotCount += 1;
        this.m_lastShotMuzzlePos = muzzlePos;
        this.m_lastShotBulletDir = bulletDir;
        this.m_lastShotAngleDeg = angleDeg;
    }

    public func GetGunForward() -> Vector4 { return this.m_gunForward; }
    public func GetTargetPoint() -> Vector4 { return this.m_targetPoint; }
    public func GetCameraForward() -> Vector4 { return this.m_cameraForward; }
    public func GetScreenOffset() -> Vector2 { return this.m_screenOffset; }
    public func GetAngleLagDeg() -> Float { return this.m_angleLagDeg; }
    public func GetYawLagDeg() -> Float { return this.m_yawLagDeg; }
    public func GetPitchLagDeg() -> Float { return this.m_pitchLagDeg; }
    public func IsDetachedActive() -> Bool { return this.m_isDetachedActive; }
    public func GetShotCount() -> Int32 { return this.m_shotCount; }
    public func GetLastShotMuzzlePos() -> Vector4 { return this.m_lastShotMuzzlePos; }
    public func GetLastShotBulletDir() -> Vector4 { return this.m_lastShotBulletDir; }
    public func GetLastShotAngleDeg() -> Float { return this.m_lastShotAngleDeg; }
}

@addField(gameuiCrosshairContainerController)
private let m_cameraCrosshair: ref<inkCanvas>;

@addField(gameuiCrosshairContainerController)
private let m_detachedTickProxy: ref<inkAnimProxy>;

@addField(gameuiCrosshairContainerController)
private let m_gunForward: Vector4;

@addField(gameuiCrosshairContainerController)
private let m_gunAngularVelocity: Vector4;

@addField(gameuiCrosshairContainerController)
private let m_lastEngineTime: Float;

@addField(gameuiCrosshairContainerController)
private let m_telemetryTimer: Float;

@addField(gameuiCrosshairContainerController)
private let m_detachedLoggedInit: Bool;

@addField(gameuiCrosshairContainerController)
private let m_detachedLoggedWeapon: Bool;

@wrapMethod(gameuiCrosshairContainerController)
protected cb func OnInitialize() -> Bool {
    wrappedMethod();
    this.InitCameraCrosshair();
}

@wrapMethod(gameuiCrosshairContainerController)
protected cb func OnPlayerAttach(playerGameObject: ref<GameObject>) -> Bool {
    wrappedMethod(playerGameObject);
    if !IsDefined(this.m_cameraCrosshair) {
        this.InitCameraCrosshair();
    } else if !IsDefined(this.m_detachedTickProxy) || !this.m_detachedTickProxy.IsPlaying() {
        this.StartDetachedReticleTick();
    }
}

@wrapMethod(gameuiCrosshairContainerController)
protected cb func OnWeaponSwap(value: Variant) -> Bool {
    wrappedMethod(value);
    if !IsDefined(this.m_cameraCrosshair) {
        this.InitCameraCrosshair();
    } else if !IsDefined(this.m_detachedTickProxy) || !this.m_detachedTickProxy.IsPlaying() {
        this.StartDetachedReticleTick();
    }
    this.UpdateDetachedAim();
}

@wrapMethod(gameuiCrosshairContainerController)
protected cb func OnUninitialize() -> Bool {
    this.UninitDetachedReticle();
    wrappedMethod();
}

@addMethod(gameuiCrosshairContainerController)
private func InitCameraCrosshair() -> Void {
    if !IsDefined(this.m_rootWidget) {
        this.m_rootWidget = this.GetRootWidget() as inkCanvas;
    }
    if !IsDefined(this.m_rootWidget) {
        return;
    }

    if !this.m_detachedLoggedInit {
        LogChannel(n"DEBUG", "[DetachedReticle] Initializing Camera Crosshair (Freelook Center Pip)...");
        this.m_detachedLoggedInit = true;
    }

    // Static Camera Crosshair (modded crosshair) anchored at screen center (0, 0)
    let container: ref<inkCanvas> = new inkCanvas();
    container.SetName(n"CameraCrosshairFreelookCenter");
    container.SetAnchor(inkEAnchor.Centered);
    container.SetAnchorPoint(Vector2(0.5, 0.5));
    container.SetSize(Vector2(16.0, 16.0));
    container.SetTranslation(Vector2(0.0, 0.0));
    container.SetVisible(false);

    // 1. Dark outer diamond border (12x12, 45 deg)
    let shadow: ref<inkRectangle> = new inkRectangle();
    shadow.SetName(n"CamReticleShadow");
    shadow.SetAnchor(inkEAnchor.Centered);
    shadow.SetAnchorPoint(Vector2(0.5, 0.5));
    shadow.SetSize(Vector2(12.0, 12.0));
    shadow.SetRotation(45.0);
    shadow.SetTintColor(HDRColor(0.0, 0.0, 0.0, 0.75));
    container.AddChildWidget(shadow);

    // 2. Cyan diamond (8x8, 45 deg)
    let cyanPip: ref<inkRectangle> = new inkRectangle();
    cyanPip.SetName(n"CamReticleCyan");
    cyanPip.SetAnchor(inkEAnchor.Centered);
    cyanPip.SetAnchorPoint(Vector2(0.5, 0.5));
    cyanPip.SetSize(Vector2(8.0, 8.0));
    cyanPip.SetRotation(45.0);
    cyanPip.SetTintColor(HDRColor(0.2, 0.95, 1.0, 0.90));
    container.AddChildWidget(cyanPip);

    // 3. Crisp white center dot (2x2)
    let core: ref<inkRectangle> = new inkRectangle();
    core.SetName(n"CamReticleCore");
    core.SetAnchor(inkEAnchor.Centered);
    core.SetAnchorPoint(Vector2(0.5, 0.5));
    core.SetSize(Vector2(2.0, 2.0));
    core.SetTintColor(HDRColor(1.0, 1.0, 1.0, 1.0));
    container.AddChildWidget(core);

    this.m_rootWidget.AddChildWidget(container);
    this.m_cameraCrosshair = container;

    this.StartDetachedReticleTick();
}

@addMethod(gameuiCrosshairContainerController)
private func StartDetachedReticleTick() -> Void {
    if !IsDefined(this.m_cameraCrosshair) {
        return;
    }

    if IsDefined(this.m_detachedTickProxy) {
        this.m_detachedTickProxy.UnregisterFromAllCallbacks(inkanimEventType.OnStart);
        this.m_detachedTickProxy.UnregisterFromAllCallbacks(inkanimEventType.OnStartLoop);
        this.m_detachedTickProxy.UnregisterFromAllCallbacks(inkanimEventType.OnEndLoop);
        this.m_detachedTickProxy.Stop();
        this.m_detachedTickProxy = null;
    }

    let tickInterp: ref<inkAnimTransparency> = new inkAnimTransparency();
    tickInterp.SetStartTransparency(1.0);
    tickInterp.SetEndTransparency(0.99);
    tickInterp.SetDuration(1.0 / 60.0);

    let tickAnimDef: ref<inkAnimDef> = new inkAnimDef();
    tickAnimDef.AddInterpolator(tickInterp);

    let tickOpts: inkAnimOptions;
    tickOpts.loopInfinite = true;
    tickOpts.loopType = inkanimLoopType.Cycle;

    this.m_detachedTickProxy = this.m_cameraCrosshair.PlayAnimationWithOptions(tickAnimDef, tickOpts);
    if IsDefined(this.m_detachedTickProxy) {
        this.m_detachedTickProxy.RegisterToCallback(inkanimEventType.OnStart, this, n"OnDetachedReticleTick");
        this.m_detachedTickProxy.RegisterToCallback(inkanimEventType.OnStartLoop, this, n"OnDetachedReticleTick");
        this.m_detachedTickProxy.RegisterToCallback(inkanimEventType.OnEndLoop, this, n"OnDetachedReticleTick");
    }
}

@addMethod(gameuiCrosshairContainerController)
private func UninitDetachedReticle() -> Void {
    if IsDefined(this.m_detachedTickProxy) {
        this.m_detachedTickProxy.UnregisterFromAllCallbacks(inkanimEventType.OnStart);
        this.m_detachedTickProxy.UnregisterFromAllCallbacks(inkanimEventType.OnStartLoop);
        this.m_detachedTickProxy.UnregisterFromAllCallbacks(inkanimEventType.OnEndLoop);
        this.m_detachedTickProxy.Stop();
        this.m_detachedTickProxy = null;
    }
    if IsDefined(this.m_cameraCrosshair) && IsDefined(this.m_rootWidget) {
        this.m_rootWidget.RemoveChild(this.m_cameraCrosshair);
        this.m_cameraCrosshair = null;
    }

    let activeWidget: ref<inkWidget> = this.GetActiveCrosshairWidget();
    if IsDefined(activeWidget) {
        activeWidget.SetTranslation(Vector2(0.0, 0.0));
    }
}

@addMethod(gameuiCrosshairContainerController)
protected cb func OnDetachedReticleTick(anim: ref<inkAnimProxy>) -> Bool {
    this.UpdateDetachedAim();
    return true;
}

@addMethod(gameuiCrosshairContainerController)
private func UpdateDetachedAim() -> Void {
    let player: ref<PlayerPuppet> = this.m_Player;
    if !IsDefined(player) {
        player = this.GetPlayerControlledObject() as PlayerPuppet;
    }
    if !IsDefined(player) {
        if IsDefined(this.m_cameraCrosshair) { this.m_cameraCrosshair.SetVisible(false); }
        return;
    }

    let aimSys: ref<DetachedAimSystem> = GameInstance.GetScriptableSystemsContainer(player.GetGame()).Get(n"DetachedAimSystem") as DetachedAimSystem;
    let activeWidget: ref<inkWidget> = this.GetActiveCrosshairWidget();

    let weapon: ref<WeaponObject> = GameObject.GetRightActiveWeapon(player);
    if !IsDefined(weapon) || weapon.IsMelee() {
        if IsDefined(this.m_cameraCrosshair) { this.m_cameraCrosshair.SetVisible(false); }
        if IsDefined(activeWidget) { activeWidget.SetTranslation(Vector2(0.0, 0.0)); }
        if IsDefined(aimSys) {
            aimSys.SetAimState(Vector4(0.0, 0.0, 0.0, 0.0), Vector4(0.0, 0.0, 0.0, 0.0), Vector4(0.0, 0.0, 0.0, 0.0), Vector2(0.0, 0.0), 0.0, 0.0, 0.0, false);
        }
        return;
    }

    if !this.m_detachedLoggedWeapon {
        LogChannel(n"DEBUG", "[DetachedReticle] Active ranged weapon equipped: " + TDBID.ToStringDEBUG(weapon.GetItemID().GetTDBID()) + " | Mounting detached crosshair dynamics.");
        this.m_detachedLoggedWeapon = true;
    }

    // Frame Delta Time calculation
    let currentEngineTime: Float = EngineTime.ToFloat(GameInstance.GetEngineTime(player.GetGame()));
    let dt: Float = (this.m_lastEngineTime > 0.0) ? (currentEngineTime - this.m_lastEngineTime) : (1.0 / 60.0);
    this.m_lastEngineTime = currentEngineTime;
    if dt <= 0.0001 || dt > 0.2 {
        dt = 1.0 / 60.0;
    }

    // Camera world look transform
    let camTransform: Transform;
    let camSys: ref<CameraSystem> = GameInstance.GetCameraSystem(player.GetGame());
    if !IsDefined(camSys) || !camSys.GetActiveCameraWorldTransform(camTransform) {
        return;
    }

    let camPos: Vector4 = Transform.GetPosition(camTransform);
    let camFwd: Vector4 = Transform.GetForward(camTransform);
    let camFwd3: Vector4 = Vector4.Normalize(camFwd);

    if Vector4.IsZero(camFwd3) {
        return;
    }

    // Initialize gun aim vector to camera forward if uninitialized
    if Vector4.IsZero(this.m_gunForward) {
        this.m_gunForward = camFwd3;
        this.m_gunAngularVelocity = Vector4(0.0, 0.0, 0.0, 0.0);
    }

    // Check if player is Aiming Down Sights (ADS)
    let isAiming: Bool = false;
    let psmBB: ref<IBlackboard> = this.GetPSMBlackboard(player);
    if IsDefined(psmBB) {
        let crosshairState: Int32 = psmBB.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Crosshair);
        isAiming = (crosshairState == EnumInt(gamePSMCrosshairStates.Aim));
    }

    // Weight and Delay dynamics parameters:
    // HipFire: Natural weight, delay, and generous deadzone angle
    // Aim (ADS): Stiff spring, fast follow, tight alignment cone
    let omega: Float = isAiming ? 38.0 : 13.5;
    let zeta: Float = isAiming ? 0.95 : 0.86;
    let maxAngleDeg: Float = isAiming ? 1.8 : 14.0;

    // 2nd-order spring-damper acceleration: a = (camFwd - gunFwd) * omega^2 - (vel * 2 * zeta * omega)
    let diff: Vector4 = camFwd3 - this.m_gunForward;
    let accel: Vector4 = (diff * (omega * omega)) - (this.m_gunAngularVelocity * (2.0 * zeta * omega));
    this.m_gunAngularVelocity = this.m_gunAngularVelocity + (accel * dt);
    this.m_gunForward = Vector4.Normalize(this.m_gunForward + (this.m_gunAngularVelocity * dt));

    // Clamp gun forward to maximum deadzone angle cone around camera forward
    let dot: Float = Vector4.Dot(this.m_gunForward, camFwd3);
    if dot > 1.0 { dot = 1.0; } else if dot < -1.0 { dot = -1.0; }
    let angleRad: Float = AcosF(dot);
    let angleDeg: Float = Rad2Deg(angleRad);
    let maxAngleRad: Float = Deg2Rad(maxAngleDeg);

    if angleRad > maxAngleRad && angleRad > 0.0001 {
        let ortho: Vector4 = this.m_gunForward - (camFwd3 * dot);
        let orthoLen: Float = Vector4.Length(ortho);
        if orthoLen > 0.0001 {
            let orthoUnit: Vector4 = ortho / orthoLen;
            this.m_gunForward = Vector4.Normalize((camFwd3 * CosF(maxAngleRad)) + (orthoUnit * SinF(maxAngleRad)));
            dot = CosF(maxAngleRad);
            angleDeg = maxAngleDeg;
        }
    }

    // World aim target point calculation (raycast to find actual distance for perfect convergence)
    let maxRange: Float = 100.0;
    let traceEnd: Vector4 = camPos + (this.m_gunForward * maxRange);
    let targetPoint: Vector4 = traceEnd;

    let sqs: ref<SpatialQueriesSystem> = GameInstance.GetSpatialQueriesSystem(player.GetGame());
    if IsDefined(sqs) {
        let traceStatic: TraceResult;
        if sqs.SyncRaycastByCollisionPreset(camPos, traceEnd, n"World Static", traceStatic) && TraceResult.IsValid(traceStatic) {
            targetPoint = Vector4(traceStatic.position.X, traceStatic.position.Y, traceStatic.position.Z, 1.0);
        }
    }

    // Project world aim point onto screen NDC [-1.0, 1.0]
    let projection: Vector2 = this.ProjectWorldToScreen(targetPoint);
    let screenOffset: Vector2 = Vector2(
        1920.0 * projection.X,
        -1080.0 * projection.Y
    );

    // Apply translation to the game's active vanilla crosshair
    if IsDefined(activeWidget) {
        activeWidget.SetTranslation(screenOffset);
    }

    // Ensure Camera Crosshair (freelook center) is visible
    if IsDefined(this.m_cameraCrosshair) {
        this.m_cameraCrosshair.SetVisible(true);
    }

    // Calculate relative yaw and pitch lag in camera local space
    let camRight: Vector4 = Transform.GetRight(camTransform);
    let camUp: Vector4 = Transform.GetUp(camTransform);
    let dx: Float = Vector4.Dot(this.m_gunForward, camRight);
    let dy: Float = Vector4.Dot(this.m_gunForward, camUp);
    let dz: Float = Vector4.Dot(this.m_gunForward, camFwd3);
    let yawLagDeg: Float = Rad2Deg(AtanF(dx, dz));
    let pitchLagDeg: Float = Rad2Deg(AtanF(dy, dz));

    // Update global DetachedAimSystem for CET ballistics redirection and camera deflection
    if IsDefined(aimSys) {
        aimSys.SetAimState(this.m_gunForward, targetPoint, camFwd3, screenOffset, angleDeg, yawLagDeg, pitchLagDeg, true);
    }

    // Periodic telemetry log (every 2.5 seconds or during large swings)
    this.m_telemetryTimer += dt;
    if this.m_telemetryTimer >= 2.5 || (angleDeg > 8.0 && this.m_telemetryTimer >= 0.5) {
        this.m_telemetryTimer = 0.0;
        let widgetNameStr: String = IsDefined(activeWidget) ? NameToString(activeWidget.GetName()) : "NULL";
        LogChannel(n"DEBUG", "[DetachedReticle][DYNAMICS] AngleLag: " + FloatToStringPrec(angleDeg, 2) + " deg (Yaw: " + FloatToStringPrec(yawLagDeg, 2) + " | Pitch: " + FloatToStringPrec(pitchLagDeg, 2) + ") | Offset: (" + FloatToStringPrec(screenOffset.X, 1) + ", " + FloatToStringPrec(screenOffset.Y, 1) + ") px | Widget: " + widgetNameStr + " | ADS: " + (isAiming ? "TRUE" : "FALSE"));
    }
}

@wrapMethod(ShootEvents)
protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
    let weapon: ref<WeaponObject> = this.GetWeaponObject(scriptInterface);
    let player: ref<PlayerPuppet> = scriptInterface.executionOwner as PlayerPuppet;
    let aimSys: ref<DetachedAimSystem>;

    if IsDefined(player) {
        aimSys = GameInstance.GetScriptableSystemsContainer(player.GetGame()).Get(n"DetachedAimSystem") as DetachedAimSystem;
    }

    if IsDefined(weapon) {
        // Enforce straight shooting along barrel orientation rather than vanilla camera convergence
        weapon.ShootStraight(true);

        let targetingSys: ref<TargetingSystem> = scriptInterface.GetTargetingSystem();
        if IsDefined(targetingSys) {
            targetingSys.SetPlayerAimWeaponPositionProvider(scriptInterface.executionOwner, IPositionProvider.CreateSlotPositionProvider(weapon, n"Muzzle"));
        }
    }

    wrappedMethod(stateContext, scriptInterface);

    // Verification and Diagnostics on Shot Execution:
    if IsDefined(weapon) && IsDefined(aimSys) && aimSys.IsDetachedActive() {
        let muzzleTransform: Transform = weapon.GetMuzzleSlotWorldTransform();
        let muzzlePos: Vector4 = Transform.GetPosition(muzzleTransform);
        let targetPt: Vector4 = aimSys.GetTargetPoint();
        let camFwd: Vector4 = aimSys.GetCameraForward();
        let gunFwd: Vector4 = aimSys.GetGunForward();
        let screenOffset: Vector2 = aimSys.GetScreenOffset();

        let bulletDir: Vector4 = Vector4.Normalize(targetPt - muzzlePos);
        let dotWithCam: Float = Vector4.Dot(bulletDir, camFwd);
        if dotWithCam > 1.0 { dotWithCam = 1.0; } else if dotWithCam < -1.0 { dotWithCam = -1.0; }
        let bulletCamAngleDeg: Float = Rad2Deg(AcosF(dotWithCam));

        aimSys.RecordShot(muzzlePos, bulletDir, bulletCamAngleDeg);

        LogChannel(n"DEBUG", "[DetachedReticle][SHOT #" + IntToString(aimSys.GetShotCount()) + " VERIFICATION]"
            + " Weapon: " + TDBID.ToStringDEBUG(weapon.GetItemID().GetTDBID())
            + " | GunLagAngle: " + FloatToStringPrec(aimSys.GetAngleLagDeg(), 2) + " deg"
            + " | BulletDivergenceFromCam: " + FloatToStringPrec(bulletCamAngleDeg, 2) + " deg"
            + " | CrosshairOffset: (" + FloatToStringPrec(screenOffset.X, 1) + ", " + FloatToStringPrec(screenOffset.Y, 1) + ") px"
            + " | MuzzlePos: (" + FloatToStringPrec(muzzlePos.X, 2) + ", " + FloatToStringPrec(muzzlePos.Y, 2) + ", " + FloatToStringPrec(muzzlePos.Z, 2) + ")"
            + " | TargetPt: (" + FloatToStringPrec(targetPt.X, 2) + ", " + FloatToStringPrec(targetPt.Y, 2) + ", " + FloatToStringPrec(targetPt.Z, 2) + ")"
            + " | BulletDir: (" + FloatToStringPrec(bulletDir.X, 3) + ", " + FloatToStringPrec(bulletDir.Y, 3) + ", " + FloatToStringPrec(bulletDir.Z, 3) + ")"
        );
    }
}
