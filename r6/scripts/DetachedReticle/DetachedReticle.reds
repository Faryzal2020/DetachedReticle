// DetachedReticle.reds
// Decoupled Aim Mod for Cyberpunk 2077
// Camera freelook with decoupled gun reticle & ballistics redirection

module DetachedReticle

public class DetachedAimSystem extends ScriptableSystem {
    private let m_gunForward: Vector4;
    private let m_targetPoint: Vector4;
    private let m_muzzlePos: Vector4;
    private let m_cameraForward: Vector4;
    private let m_screenOffset: Vector2;
    private let m_angleLagDeg: Float;
    private let m_yawLagDeg: Float;
    private let m_pitchLagDeg: Float;
    private let m_isDetachedActive: Bool;
    private let m_shotCount: Int32;
    private let m_lastShotMuzzlePos: Vector4;
    private let m_lastShotBulletDir: Vector4;
    private let m_lastShotTargetPt: Vector4;
    private let m_lastShotAngleDeg: Float;
    private let m_testMode: Int32;          // 0 = Round-Robin Auto-Cycle (1..6), 1..6 = Locked Mode
    private let m_currentCycleIndex: Int32; // Tracks current step in 1..6 cycle
    private let m_lastShotTestMode: Int32;
    private let m_lastShotTestModeName: String;

    public static func GetInstance(game: GameInstance) -> ref<DetachedAimSystem> {
        return GameInstance.GetScriptableSystemsContainer(game).Get(n"DetachedReticle.DetachedAimSystem") as DetachedAimSystem;
    }

    public func SetAimState(gunFwd: Vector4, targetPt: Vector4, muzzlePos: Vector4, camFwd: Vector4, screenOffset: Vector2, angleLagDeg: Float, yawLagDeg: Float, pitchLagDeg: Float, isDetached: Bool) -> Void {
        this.m_gunForward = gunFwd;
        this.m_targetPoint = targetPt;
        this.m_muzzlePos = muzzlePos;
        this.m_cameraForward = camFwd;
        this.m_screenOffset = screenOffset;
        this.m_angleLagDeg = angleLagDeg;
        this.m_yawLagDeg = yawLagDeg;
        this.m_pitchLagDeg = pitchLagDeg;
        this.m_isDetachedActive = isDetached;
    }

    public func RecordShot(muzzlePos: Vector4, bulletDir: Vector4, targetPt: Vector4, testMode: Int32, modeName: String) -> Void {
        this.m_shotCount += 1;
        this.m_lastShotMuzzlePos = muzzlePos;
        this.m_lastShotBulletDir = bulletDir;
        this.m_lastShotTargetPt = targetPt;
        this.m_lastShotAngleDeg = this.m_angleLagDeg;
        this.m_lastShotTestMode = testMode;
        this.m_lastShotTestModeName = modeName;
    }

    public func SetTestMode(mode: Int32) -> Void {
        this.m_testMode = mode;
    }

    public func GetTestMode() -> Int32 {
        return this.m_testMode;
    }

    public func GetNextTestMode() -> Int32 {
        if this.m_testMode > 0 && this.m_testMode <= 6 {
            return this.m_testMode;
        }
        this.m_currentCycleIndex += 1;
        if this.m_currentCycleIndex > 6 {
            this.m_currentCycleIndex = 1;
        }
        return this.m_currentCycleIndex;
    }

    public func GetGunForward() -> Vector4 { return this.m_gunForward; }
    public func GetTargetPoint() -> Vector4 { return this.m_targetPoint; }
    public func GetMuzzlePos() -> Vector4 { return this.m_muzzlePos; }
    public func GetCameraForward() -> Vector4 { return this.m_cameraForward; }
    public func GetScreenOffset() -> Vector2 { return this.m_screenOffset; }
    public func GetAngleLagDeg() -> Float { return this.m_angleLagDeg; }
    public func GetYawLagDeg() -> Float { return this.m_yawLagDeg; }
    public func GetPitchLagDeg() -> Float { return this.m_pitchLagDeg; }
    public func IsDetachedActive() -> Bool { return this.m_isDetachedActive; }
    public func GetShotCount() -> Int32 { return this.m_shotCount; }
    public func GetLastShotMuzzlePos() -> Vector4 { return this.m_lastShotMuzzlePos; }
    public func GetLastShotBulletDir() -> Vector4 { return this.m_lastShotBulletDir; }
    public func GetLastShotTargetPt() -> Vector4 { return this.m_lastShotTargetPt; }
    public func GetLastShotAngleDeg() -> Float { return this.m_lastShotAngleDeg; }
    public func GetLastShotTestMode() -> Int32 { return this.m_lastShotTestMode; }
    public func GetLastShotTestModeName() -> String { return this.m_lastShotTestModeName; }
}

@addField(gameuiCrosshairContainerController)
private let m_cameraCrosshair: ref<inkCanvas>;

@addField(gameuiCrosshairContainerController)
private let m_detachedTickProxy: ref<inkAnimProxy>;

@addField(gameuiCrosshairContainerController)
private let m_gunForward: Vector4;

@addField(gameuiCrosshairContainerController)
private let m_targetPoint: Vector4;

@addField(gameuiCrosshairContainerController)
private let m_muzzlePos: Vector4;

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
protected cb func OnPlayerDetach(playerGameObject: ref<GameObject>) -> Bool {
    this.UninitDetachedReticle();
    return wrappedMethod(playerGameObject);
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
        FTLog("[DetachedReticle] Initializing Camera Crosshair (Freelook Center Pip)...");
        this.m_detachedLoggedInit = true;
    }

    // Static Camera Crosshair (modded crosshair) anchored at screen center (0, 0)
    let container: ref<inkCanvas> = new inkCanvas();
    container.SetName(n"CameraCrosshairFreelookCenter");
    container.SetAnchor(inkEAnchor.Centered);
    container.SetAnchorPoint(new Vector2(0.5, 0.5));
    container.SetSize(new Vector2(16.0, 16.0));
    container.SetTranslation(new Vector2(0.0, 0.0));
    container.SetVisible(false);

    // 1. Dark outer diamond border (12x12, 45 deg)
    let shadow: ref<inkRectangle> = new inkRectangle();
    shadow.SetName(n"CamReticleShadow");
    shadow.SetAnchor(inkEAnchor.Centered);
    shadow.SetAnchorPoint(new Vector2(0.5, 0.5));
    shadow.SetSize(new Vector2(12.0, 12.0));
    shadow.SetRotation(45.0);
    shadow.SetTintColor(new HDRColor(0.0, 0.0, 0.0, 0.75));
    container.AddChildWidget(shadow);

    // 2. Cyan diamond (8x8, 45 deg)
    let cyanPip: ref<inkRectangle> = new inkRectangle();
    cyanPip.SetName(n"CamReticleCyan");
    cyanPip.SetAnchor(inkEAnchor.Centered);
    cyanPip.SetAnchorPoint(new Vector2(0.5, 0.5));
    cyanPip.SetSize(new Vector2(8.0, 8.0));
    cyanPip.SetRotation(45.0);
    cyanPip.SetTintColor(new HDRColor(0.2, 0.95, 1.0, 0.90));
    container.AddChildWidget(cyanPip);

    // 3. Crisp white center dot (2x2)
    let core: ref<inkRectangle> = new inkRectangle();
    core.SetName(n"CamReticleCore");
    core.SetAnchor(inkEAnchor.Centered);
    core.SetAnchorPoint(new Vector2(0.5, 0.5));
    core.SetSize(new Vector2(2.0, 2.0));
    core.SetTintColor(new HDRColor(1.0, 1.0, 1.0, 1.0));
    container.AddChildWidget(core);

    this.m_rootWidget.AddChildWidget(container);
    this.m_cameraCrosshair = container;
}

@addMethod(gameuiCrosshairContainerController)
private func StartDetachedReticleTick() -> Void {
    if !IsDefined(this.m_cameraCrosshair) {
        return;
    }

    if IsDefined(this.m_detachedTickProxy) {
        this.m_detachedTickProxy.UnregisterFromAllCallbacks(inkanimEventType.OnStartLoop);
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
        this.m_detachedTickProxy.RegisterToCallback(inkanimEventType.OnStartLoop, this, n"OnDetachedReticleTick");
    }
}

@addMethod(gameuiCrosshairContainerController)
private func UninitDetachedReticle() -> Void {
    if IsDefined(this.m_detachedTickProxy) {
        this.m_detachedTickProxy.UnregisterFromAllCallbacks(inkanimEventType.OnStartLoop);
        this.m_detachedTickProxy.Stop();
        this.m_detachedTickProxy = null;
    }
    if IsDefined(this.m_cameraCrosshair) && IsDefined(this.m_rootWidget) {
        this.m_rootWidget.RemoveChild(this.m_cameraCrosshair);
        this.m_cameraCrosshair = null;
    }

    let activeWidget: ref<inkWidget> = this.GetActiveCrosshairWidget();
    if IsDefined(activeWidget) {
        activeWidget.SetTranslation(new Vector2(0.0, 0.0));
    }
}

@addMethod(gameuiCrosshairContainerController)
protected cb func OnDetachedReticleTick(anim: ref<inkAnimProxy>) -> Bool {
    this.UpdateDetachedAim();
    return true;
}

@addMethod(gameuiCrosshairContainerController)
private func UpdateDetachedAim() -> Void {
    let srh: ref<inkISystemRequestsHandler> = GameInstance.GetSystemRequestsHandler();
    if IsDefined(srh) && (srh.IsPreGame() || srh.IsGamePaused()) {
        if IsDefined(this.m_cameraCrosshair) { this.m_cameraCrosshair.SetVisible(false); }
        return;
    }

    let player: ref<PlayerPuppet> = this.GetPlayerControlledObject() as PlayerPuppet;
    if !IsDefined(player) || !player.IsAttached() {
        if IsDefined(this.m_cameraCrosshair) { this.m_cameraCrosshair.SetVisible(false); }
        return;
    }

    let aimSys: ref<DetachedAimSystem> = DetachedAimSystem.GetInstance(player.GetGame());
    let activeWidget: ref<inkWidget> = this.GetActiveCrosshairWidget();

    // Guard against dual-wielding: fall back cleanly to vanilla behavior
    if GameObject.IsDualWielding(player) {
        if IsDefined(this.m_cameraCrosshair) { this.m_cameraCrosshair.SetVisible(false); }
        if IsDefined(activeWidget) { activeWidget.SetTranslation(new Vector2(0.0, 0.0)); }
        if IsDefined(aimSys) {
            aimSys.SetAimState(new Vector4(0.0, 0.0, 0.0, 0.0), new Vector4(0.0, 0.0, 0.0, 0.0), new Vector4(0.0, 0.0, 0.0, 0.0), new Vector4(0.0, 0.0, 0.0, 0.0), new Vector2(0.0, 0.0), 0.0, 0.0, 0.0, false);
        }
        return;
    }

    let weapon: ref<WeaponObject> = GameObject.GetRightActiveWeapon(player);
    if !IsDefined(weapon) || !weapon.IsAttached() || weapon.IsMelee() {
        if IsDefined(this.m_cameraCrosshair) { this.m_cameraCrosshair.SetVisible(false); }
        if IsDefined(activeWidget) { activeWidget.SetTranslation(new Vector2(0.0, 0.0)); }
        if IsDefined(aimSys) {
            aimSys.SetAimState(new Vector4(0.0, 0.0, 0.0, 0.0), new Vector4(0.0, 0.0, 0.0, 0.0), new Vector4(0.0, 0.0, 0.0, 0.0), new Vector4(0.0, 0.0, 0.0, 0.0), new Vector2(0.0, 0.0), 0.0, 0.0, 0.0, false);
        }
        return;
    }

    if !this.m_detachedLoggedWeapon {
        FTLog("[DetachedReticle] Active ranged weapon equipped: " + TDBID.ToStringDEBUG(ItemID.GetTDBID(weapon.GetItemID())) + " | Decoupled Gun Reticle active.");
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

    // Physical 3D weapon barrel transform in world space
    let muzzleTransform: Transform = weapon.GetMuzzleSlotWorldTransform();
    let muzzlePos: Vector4 = Transform.GetPosition(muzzleTransform);
    let muzzleFwd: Vector4 = Transform.GetForward(muzzleTransform);
    if Vector4.IsZero(muzzleFwd) {
        muzzleFwd = weapon.GetWorldForward();
    }
    if Vector4.IsZero(muzzlePos) {
        muzzlePos = weapon.GetWorldPosition();
    }
    if Vector4.IsZero(muzzlePos) || Vector4.IsZero(muzzleFwd) {
        return;
    }
    this.m_gunForward = Vector4.Normalize(muzzleFwd);
    this.m_muzzlePos = muzzlePos;

    // Physical aim line in 3D world: raycast to find exact target impact point
    let maxRange: Float = 100.0;
    let traceEnd: Vector4 = muzzlePos + (this.m_gunForward * maxRange);
    let targetPoint: Vector4 = traceEnd;

    let sqs: ref<SpatialQueriesSystem> = GameInstance.GetSpatialQueriesSystem(player.GetGame());
    if IsDefined(sqs) {
        let traceStatic: TraceResult;
        if sqs.SyncRaycastByCollisionPreset(muzzlePos, traceEnd, n"World Static", traceStatic) && TraceResult.IsValid(traceStatic) {
            targetPoint = new Vector4(traceStatic.position.X, traceStatic.position.Y, traceStatic.position.Z, 1.0);
        }
    }
    this.m_targetPoint = targetPoint;

    // Project physical gun target point onto the screen relative to camera view
    let toTarget: Vector4 = targetPoint - camPos;
    let toTargetDir: Vector4 = Vector4.Normalize(toTarget);
    let dotCam: Float = Vector4.Dot(toTargetDir, camFwd3);
    let screenOffset: Vector2 = new Vector2(0.0, 0.0);

    // If target point is in front of camera (> 0.05 dot product), project onto screen
    if dotCam > 0.05 {
        let projection: Vector2 = this.ProjectWorldToScreen(targetPoint);
        let rootCanvas: ref<inkCanvas> = this.m_rootWidget;
        if !IsDefined(rootCanvas) {
            rootCanvas = this.GetRootWidget() as inkCanvas;
        }
        let rootSize: Vector2 = IsDefined(rootCanvas) ? rootCanvas.GetSize() : new Vector2(3840.0, 2160.0);
        if rootSize.X <= 0.0 || rootSize.Y <= 0.0 {
            rootSize = new Vector2(3840.0, 2160.0);
        }

        screenOffset = new Vector2(
            rootSize.X * 0.5 * projection.X,
            -rootSize.Y * 0.5 * projection.Y
        );

        if IsDefined(activeWidget) {
            let activeCtrl: ref<gameuiCrosshairBaseGameController> = this.GetActiveCrosshairGameController();
            let isNoWeaponCtrl: Bool = IsDefined(activeCtrl) && (activeCtrl as CrosshairGameController_NoWeapon) != null;

            if isNoWeaponCtrl {
                // If the active controller is NoWeapon (optical zoom reticle), center it at (0, 0)
                activeWidget.SetVisible(true);
                activeWidget.SetTranslation(new Vector2(0.0, 0.0));
            } else {
                // Gun crosshair follows the physical gun muzzle
                activeWidget.SetVisible(true);
                activeWidget.SetTranslation(screenOffset);

                // If active crosshair is HMG or has a child named 'fluff' (outer HUD brackets / ladder),
                // counter-translate 'fluff' so it stays centered at (0, 0) relative to screen center
                let compound: ref<inkCompoundWidget> = activeWidget as inkCompoundWidget;
                if IsDefined(compound) {
                    let fluffWidget: ref<inkWidget> = compound.GetWidgetByPathName(n"fluff");
                    if IsDefined(fluffWidget) && fluffWidget.IsVisible() {
                        fluffWidget.SetTranslation(new Vector2(-screenOffset.X, -screenOffset.Y));
                    }
                }
            }
        }
    } else {
        // Target is behind camera view: hide gun reticle
        if IsDefined(activeWidget) {
            activeWidget.SetVisible(false);
        }
    }

    // Ensure all secondary visible crosshair widgets in container (e.g. secondary zoom reticle) stay centered at (0, 0)
    if IsDefined(this.m_rootWidget) {
        let numRootChildren: Int32 = this.m_rootWidget.GetNumChildren();
        let rc: Int32 = 0;
        while rc < numRootChildren {
            let rChild: ref<inkWidget> = this.m_rootWidget.GetWidgetByIndex(rc);
            if IsDefined(rChild) && rChild != activeWidget && rChild != this.m_cameraCrosshair {
                if rChild.IsVisible() {
                    rChild.SetTranslation(new Vector2(0.0, 0.0));
                }
            }
            rc += 1;
        }
    }

    // Camera Crosshair (freelook center pip) stays fixed at screen center (0, 0)
    if IsDefined(this.m_cameraCrosshair) {
        this.m_cameraCrosshair.SetVisible(true);
    }

    // Calculate relative yaw and pitch lag between gun barrel and camera gaze
    let camRight: Vector4 = Transform.GetRight(camTransform);
    let camUp: Vector4 = Transform.GetUp(camTransform);
    let dx: Float = Vector4.Dot(this.m_gunForward, camRight);
    let dy: Float = Vector4.Dot(this.m_gunForward, camUp);
    let dz: Float = Vector4.Dot(this.m_gunForward, camFwd3);
    let yawLagDeg: Float = Rad2Deg(AtanF(dx, dz));
    let pitchLagDeg: Float = Rad2Deg(AtanF(dy, dz));
    let clampedDot: Float = ClampF(dotCam, -1.0, 1.0);
    let angleDeg: Float = Rad2Deg(AcosF(clampedDot));

    // Update global DetachedAimSystem for state query and telemetry
    if IsDefined(aimSys) {
        aimSys.SetAimState(this.m_gunForward, targetPoint, muzzlePos, camFwd3, screenOffset, angleDeg, yawLagDeg, pitchLagDeg, true);
    }

    // Feed continuous live barrel tracking to native ShootingHook
    SetMuzzleAimState(muzzlePos, this.m_gunForward, camFwd3, true);

    // Periodic telemetry log (every 3 seconds or during large divergence)
    this.m_telemetryTimer += dt;
    if this.m_telemetryTimer >= 3.0 || (angleDeg > 15.0 && this.m_telemetryTimer >= 0.5) {
        this.m_telemetryTimer = 0.0;
        let widgetNameStr: String = IsDefined(activeWidget) ? NameToString(activeWidget.GetName()) : "NULL";
        let ctrl: ref<gameuiCrosshairBaseGameController> = this.GetActiveCrosshairGameController();
        let ctrlNameStr: String = IsDefined(ctrl) ? NameToString(ctrl.GetClassName()) : "NULL";
        let psmBB: ref<IBlackboard> = player.GetPlayerStateMachineBlackboard();
        let crosshairState: Int32 = IsDefined(psmBB) ? psmBB.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Crosshair) : -1;
        let zoomVal: Float = IsDefined(psmBB) ? psmBB.GetFloat(GetAllBlackboardDefs().PlayerStateMachine.ZoomLevel) : 1.0;
        FTLog("[DetachedReticle][DYNAMICS] Div: " + FloatToStringPrec(angleDeg, 2) + " deg | Offset: (" + FloatToStringPrec(screenOffset.X, 1) + ", " + FloatToStringPrec(screenOffset.Y, 1) + ") px | Widget: " + widgetNameStr + " | Ctrl: " + ctrlNameStr + " | State: " + IntToString(crosshairState) + " | Zoom: " + FloatToStringPrec(zoomVal, 2));
    }
}

// In ShootEvents.OnEnter, SetMuzzleAimState prepares the physical muzzle trajectory
// before the vanilla shooting pipeline runs. PhysicalRay callsites are intercepted natively.
@wrapMethod(ShootEvents)
protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
    let player: ref<PlayerPuppet> = scriptInterface.executionOwner as PlayerPuppet;
    let isPlayerOwned: Bool = IsDefined(player) && player.IsPlayerControlled() && player.IsAttached();
    let weapon: ref<WeaponObject> = isPlayerOwned ? this.GetWeaponObject(scriptInterface) : null;
    let isDecoupledActive: Bool = isPlayerOwned && !GameObject.IsDualWielding(player) && IsDefined(weapon) && weapon.IsAttached() && !weapon.IsMelee();

    if isDecoupledActive {
        let muzzleTransform: Transform = weapon.GetMuzzleSlotWorldTransform();
        let muzzlePos: Vector4 = Transform.GetPosition(muzzleTransform);
        let muzzleFwd: Vector4 = Transform.GetForward(muzzleTransform);
        if Vector4.IsZero(muzzleFwd) {
            muzzleFwd = weapon.GetWorldForward();
        }
        if Vector4.IsZero(muzzlePos) {
            muzzlePos = weapon.GetWorldPosition();
        }
        let normMuzzleFwd: Vector4 = Vector4.Normalize(muzzleFwd);

        let camTransform: Transform;
        let camSys: ref<CameraSystem> = GameInstance.GetCameraSystem(scriptInterface.GetGame());
        let camFwd: Vector4 = new Vector4(0.0, 1.0, 0.0, 0.0);
        if IsDefined(camSys) && camSys.GetActiveCameraWorldTransform(camTransform) {
            camFwd = Vector4.Normalize(Transform.GetForward(camTransform));
        }

        // Feed exact physical aim state to native C++ ShootingHook
        SetMuzzleAimState(muzzlePos, normMuzzleFwd, camFwd, true);

        let aimSys: ref<DetachedAimSystem> = DetachedAimSystem.GetInstance(scriptInterface.GetGame());
        if IsDefined(aimSys) {
            let attackRecord: ref<Attack_Record> = this.GetDesiredAttackRecord(stateContext, scriptInterface);
            let maxRange: Float = IsDefined(attackRecord) ? attackRecord.Range() : 200.0;
            if maxRange <= 0.0 {
                maxRange = 200.0;
            }
            let traceEnd: Vector4 = muzzlePos + (normMuzzleFwd * maxRange);
            let targetPt: Vector4 = traceEnd;

            let sqs: ref<SpatialQueriesSystem> = GameInstance.GetSpatialQueriesSystem(scriptInterface.GetGame());
            if IsDefined(sqs) {
                let traceStatic: TraceResult;
                if sqs.SyncRaycastByCollisionPreset(muzzlePos, traceEnd, n"World Static", traceStatic) && TraceResult.IsValid(traceStatic) {
                    targetPt = new Vector4(traceStatic.position.X, traceStatic.position.Y, traceStatic.position.Z, 1.0);
                }
            }

            aimSys.RecordShot(muzzlePos, normMuzzleFwd, targetPt, 1, "Native PhysicalRay Redirection");
        }
    } else {
        SetMuzzleAimState(new Vector4(0.0, 0.0, 0.0, 1.0), new Vector4(0.0, 1.0, 0.0, 0.0), new Vector4(0.0, 1.0, 0.0, 0.0), false);
    }

    wrappedMethod(stateContext, scriptInterface);

    // Re-assert HMG attack record right after vanilla OnEnter has run GetDesiredAttackRecord and SetAttack
    // STRICTLY PLAYER-CONTROLLED ONLY to prevent mutating NPC weapons or effectors
    if isDecoupledActive && (weapon.IsHeavyWeapon() || EnumInt(WeaponObject.GetWeaponType(weapon.GetItemID())) == EnumInt(gamedataItemType.Wea_HeavyMachineGun)) {
        weapon.SetAttack(t"Attacks.ExplodingBulletMediumEffect");
    }
}

// Intercept attack resolution for Heavy Machine Guns so they use the unified
// PhysicalRay game effect pipeline instead of unguided screen-center projectiles.
// STRICTLY PLAYER-CONTROLLED ONLY
@wrapMethod(WeaponTransition)
protected func GetDesiredAttackRecord(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> ref<Attack_Record> {
    let player: ref<PlayerPuppet> = scriptInterface.executionOwner as PlayerPuppet;
    if !IsDefined(player) || !player.IsPlayerControlled() || !player.IsAttached() {
        return wrappedMethod(stateContext, scriptInterface);
    }

    let weapon: ref<WeaponObject> = this.GetWeaponObject(scriptInterface);
    if IsDefined(weapon) && (weapon.IsHeavyWeapon() || EnumInt(WeaponObject.GetWeaponType(weapon.GetItemID())) == EnumInt(gamedataItemType.Wea_HeavyMachineGun)) {
        let hmgAttack: ref<Attack_Record> = TweakDBInterface.GetAttackRecord(t"Attacks.ExplodingBulletMediumEffect");
        if IsDefined(hmgAttack) {
            return hmgAttack;
        }
    }
    return wrappedMethod(stateContext, scriptInterface);
}

// Enforce screen-center positioning for optical zoom crosshairs (NoWeapon)
@wrapMethod(CrosshairGameController_NoWeapon)
protected func OnState_Aim() -> Void {
    wrappedMethod();
    let root: ref<inkWidget> = this.GetRootWidget();
    if IsDefined(root) {
        root.SetTranslation(new Vector2(0.0, 0.0));
    }
}

@wrapMethod(CrosshairGameController_NoWeapon)
protected func OnState_HipFire() -> Void {
    wrappedMethod();
    let root: ref<inkWidget> = this.GetRootWidget();
    if IsDefined(root) {
        root.SetTranslation(new Vector2(0.0, 0.0));
    }
}

@wrapMethod(CrosshairGameController_NoWeapon)
protected cb func OnZoomLevel(argZoom: Float) -> Bool {
    wrappedMethod(argZoom);
    let root: ref<inkWidget> = this.GetRootWidget();
    if IsDefined(root) {
        root.SetTranslation(new Vector2(0.0, 0.0));
    }
}



