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

    public func RecordShot(muzzlePos: Vector4, bulletDir: Vector4, targetPt: Vector4) -> Void {
        this.m_shotCount += 1;
        this.m_lastShotMuzzlePos = muzzlePos;
        this.m_lastShotBulletDir = bulletDir;
        this.m_lastShotTargetPt = targetPt;
        this.m_lastShotAngleDeg = this.m_angleLagDeg;
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

    this.StartDetachedReticleTick();
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
    let player: ref<PlayerPuppet> = this.m_Player;
    if !IsDefined(player) {
        player = this.GetPlayerControlledObject() as PlayerPuppet;
    }
    if !IsDefined(player) {
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
    if !IsDefined(weapon) || weapon.IsMelee() {
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
            activeWidget.SetVisible(true);
            activeWidget.SetTranslation(screenOffset);
        }
    } else {
        // Target is behind camera view: hide gun reticle
        if IsDefined(activeWidget) {
            activeWidget.SetVisible(false);
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

    // Periodic telemetry log (every 3 seconds or during large divergence)
    this.m_telemetryTimer += dt;
    if this.m_telemetryTimer >= 3.0 || (angleDeg > 15.0 && this.m_telemetryTimer >= 0.5) {
        this.m_telemetryTimer = 0.0;
        let widgetNameStr: String = IsDefined(activeWidget) ? NameToString(activeWidget.GetName()) : "NULL";
        FTLog("[DetachedReticle][DYNAMICS] Divergence: " + FloatToStringPrec(angleDeg, 2) + " deg (Yaw: " + FloatToStringPrec(yawLagDeg, 2) + " | Pitch: " + FloatToStringPrec(pitchLagDeg, 2) + ") | Offset: (" + FloatToStringPrec(screenOffset.X, 1) + ", " + FloatToStringPrec(screenOffset.Y, 1) + ") px | Widget: " + widgetNameStr);
    }
}

// JUSTIFICATION FOR @replaceMethod:
// In vanilla ShootEvents.OnEnter, weapon.SetAttack() and weapon.QueueEvent(new WeaponPreFireEvent)
// are directly invoked, causing the native engine to cast a hitscan ray along the camera gaze vector.
// Because these native calls are embedded mid-method without individual script hooks, @wrapMethod
// cannot suppress the camera-centered ray. We replace OnEnter so that when DetachedReticle is active,
// the attack is dispatched along the physical 3D muzzle orientation toward the gun reticle,
// while preserving all vanilla behavior (animations, stamina, ammo, sounds, VFX) when inactive.
@replaceMethod(ShootEvents)
protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
    let weapon: ref<WeaponObject>;
    let attackRecord: ref<Attack_Record>;
    let attackID: TweakDBID;
    let gameInstance: GameInstance;
    let statsSystem: ref<StatsSystem>;
    let currentTime: Double;
    let broadcaster: ref<StimBroadcasterComponent>;
    let effectBlackboard: ref<worldEffectBlackboard>;
    let numBurstTotal: Float;
    let magazineCapacity: Float;
    let fullAutoPenalty: Float;
    let fullChargePenalty: Float;
    let visualStimDistance: Float;
    let muzzleFxScale: Float;
    let shellsFxScale: Float;
    let leftHandWeapon: String;
    let rightHandWeapon: String;
    let emptyInvestigateData: stimInvestigateData;

    gameInstance = scriptInterface.GetGame();
    statsSystem = GameInstance.GetStatsSystem(gameInstance);
    currentTime = EngineTime.ToDouble(GameInstance.GetSimTime(gameInstance));
    effectBlackboard = new worldEffectBlackboard();
    fullAutoPenalty = 1.0;
    fullChargePenalty = 1.0;
    visualStimDistance = 50.0;
    weapon = this.GetWeaponObject(scriptInterface);
    muzzleFxScale = statsSystem.GetStatValue(weapon.GetEntityID(), gamedataStatType.WeaponVFX_MuzzleFxScale);
    if muzzleFxScale >= 0.0 && muzzleFxScale != 1.0 {
        effectBlackboard.SetValueUnclamped(n"muzzleFxScale", muzzleFxScale);
    }
    shellsFxScale = statsSystem.GetStatValue(weapon.GetEntityID(), gamedataStatType.WeaponVFX_ShellsFxScale);
    if shellsFxScale >= 0.0 && shellsFxScale != 1.0 {
        effectBlackboard.SetValueUnclamped(n"shellsFxScale", shellsFxScale);
    }
    this.ForceDisableVisionMode(stateContext);
    this.ShowAttackPreview(true, weapon, scriptInterface, stateContext);
    if !scriptInterface.HasStatFlag(gamedataStatType.CanWeaponShootWhileSprinting) && scriptInterface.localBlackboard.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Locomotion) == EnumInt(gamePSMLocomotionStates.Sprint) {
        stateContext.SetTemporaryBoolParameter(n"InterruptSprint", true, true);
    }
    this.SetLastShotTime(stateContext, currentTime);
    attackRecord = this.GetDesiredAttackRecord(stateContext, scriptInterface);
    attackID = attackRecord.GetID();

    let player: ref<PlayerPuppet> = scriptInterface.executionOwner as PlayerPuppet;
    let aimSys: ref<DetachedAimSystem> = DetachedAimSystem.GetInstance(gameInstance);
    let isDecoupledActive: Bool = IsDefined(player) && !GameObject.IsDualWielding(player) && IsDefined(weapon) && !weapon.IsMelee() && IsDefined(aimSys) && aimSys.IsDetachedActive();

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

        let maxRange: Float = attackRecord.Range();
        if maxRange <= 0.0 {
            maxRange = 200.0;
        }
        let traceEnd: Vector4 = muzzlePos + (normMuzzleFwd * maxRange);
        let targetPt: Vector4 = traceEnd;

        let sqs: ref<SpatialQueriesSystem> = GameInstance.GetSpatialQueriesSystem(gameInstance);
        if IsDefined(sqs) {
            let traceStatic: TraceResult;
            if sqs.SyncRaycastByCollisionPreset(muzzlePos, traceEnd, n"World Static", traceStatic) && TraceResult.IsValid(traceStatic) {
                targetPt = Vector4(traceStatic.position.X, traceStatic.position.Y, traceStatic.position.Z, 1.0);
            }
        }

        let attackContext: AttackInitContext;
        attackContext.record = attackRecord;
        attackContext.instigator = scriptInterface.executionOwner;
        attackContext.source = scriptInterface.executionOwner;
        attackContext.weapon = weapon;

        let attackObj: ref<IAttack> = IAttack.Create(attackContext);
        let gameEffectAttack: ref<Attack_GameEffect> = attackObj as Attack_GameEffect;
        let projectileAttack: ref<Attack_Projectile> = attackObj as Attack_Projectile;

        if IsDefined(gameEffectAttack) {
            let statMods: array<gameStatModifierData>;
            gameEffectAttack.GetStatModList(statMods);
            let effect: ref<EffectInstance> = gameEffectAttack.PrepareAttack(scriptInterface.executionOwner);
            if IsDefined(effect) {
                let sharedData: EffectData = effect.GetSharedData();
                EffectData.SetVector(sharedData, GetAllBlackboardDefs().EffectSharedData.position, muzzlePos);
                EffectData.SetVector(sharedData, GetAllBlackboardDefs().EffectSharedData.muzzlePosition, muzzlePos);
                EffectData.SetVector(sharedData, GetAllBlackboardDefs().EffectSharedData.forward, normMuzzleFwd);
                EffectData.SetQuat(sharedData, GetAllBlackboardDefs().EffectSharedData.rotation, Transform.GetOrientation(muzzleTransform));
                EffectData.SetVector(sharedData, GetAllBlackboardDefs().EffectSharedData.raycastEnd, targetPt);
                EffectData.SetFloat(sharedData, GetAllBlackboardDefs().EffectSharedData.range, maxRange);
                EffectData.SetVariant(sharedData, GetAllBlackboardDefs().EffectSharedData.attack, ToVariant(attackObj));
                EffectData.SetVariant(sharedData, GetAllBlackboardDefs().EffectSharedData.attackStatModList, ToVariant(statMods));
                EffectData.SetBool(sharedData, GetAllBlackboardDefs().EffectSharedData.playerOwnedWeapon, true);
                gameEffectAttack.StartAttack();
            }
        } else if IsDefined(projectileAttack) {
            let launchEvt: ref<gameprojectileSpawnerLaunchEvent> = projectileAttack.PrepareAttack(scriptInterface.executionOwner);
            if IsDefined(launchEvt) {
                launchEvt.launchParams.logicalPositionProvider = IPositionProvider.CreateSlotPositionProvider(weapon, n"Muzzle");
                launchEvt.launchParams.logicalOrientationProvider = IOrientationProvider.CreateStaticOrientationProvider(Quaternion.BuildFromDirectionVector(normMuzzleFwd));
                launchEvt.launchParams.visualPositionProvider = launchEvt.launchParams.logicalPositionProvider;
                launchEvt.launchParams.visualOrientationProvider = launchEvt.launchParams.logicalOrientationProvider;
                weapon.QueueEvent(launchEvt);
            }
        }

        aimSys.RecordShot(muzzlePos, normMuzzleFwd, targetPt);

        let screenOffset: Vector2 = aimSys.GetScreenOffset();
        FTLog("[DetachedReticle][DECOUPLED SHOT #" + IntToString(aimSys.GetShotCount()) + " FIRED]"
            + " Weapon: " + TDBID.ToStringDEBUG(ItemID.GetTDBID(weapon.GetItemID()))
            + " | GunDivergence: " + FloatToStringPrec(aimSys.GetAngleLagDeg(), 2) + " deg"
            + " | CrosshairOffset: (" + FloatToStringPrec(screenOffset.X, 1) + ", " + FloatToStringPrec(screenOffset.Y, 1) + ") px"
            + " | MuzzlePos: (" + FloatToStringPrec(muzzlePos.X, 2) + ", " + FloatToStringPrec(muzzlePos.Y, 2) + ", " + FloatToStringPrec(muzzlePos.Z, 2) + ")"
            + " | TargetPt: (" + FloatToStringPrec(targetPt.X, 2) + ", " + FloatToStringPrec(targetPt.Y, 2) + ", " + FloatToStringPrec(targetPt.Z, 2) + ")"
            + " | BarrelDir: (" + FloatToStringPrec(normMuzzleFwd.X, 3) + ", " + FloatToStringPrec(normMuzzleFwd.Y, 3) + ", " + FloatToStringPrec(normMuzzleFwd.Z, 3) + ")"
        );
    } else {
        weapon.SetAttack(attackID);
        weapon.QueueEvent(new WeaponPreFireEvent());
    }

    stateContext.SetPermanentIntParameter(this.GetLastChargePressCount(), Cast<Int32>(scriptInterface.GetActionPressCount(n"RangedAttack")), true);
    stateContext.SetPermanentFloatParameter(this.GetTurnOffPublicSafeTimeStamp(), Cast<Float>(currentTime), true);
    if this.IsRightWeaponLogic() {
        stateContext.SetPermanentBoolParameter(n"WeaponInSafe", false, true);
    }
    scriptInterface.PushAnimationEvent(this.IsRightWeaponLogic() ? n"RightShoot" : n"LeftShoot");
    stateContext.SetPermanentFloatParameter(this.GetStoppedFiringTimestamp(), Cast<Float>(currentTime), true);
    if this.IsInValentinosFrenzy(scriptInterface) {
        stateContext.SetPermanentIntParameter(n"LastShotInValentinosFrenzy", this.IsRightWeaponLogic() ? EnumInt(gamePSMShootStates.LeftWeapon) : EnumInt(gamePSMShootStates.RightWeapon), true);
    }
    this.SetBlackboardIntVariable(scriptInterface, this.GetBlackboardID(scriptInterface), EnumInt(gamePSMRangedWeaponStates.Shoot));
    broadcaster = scriptInterface.executionOwner.GetStimBroadcasterComponent();
    if statsSystem.GetStatValue(weapon.GetEntityID(), gamedataStatType.CanSilentKill) > 0.0 {
        if IsDefined(broadcaster) {
            broadcaster.TriggerSingleBroadcast(scriptInterface.executionOwner, gamedataStimType.IllegalAction);
            broadcaster.TriggerSingleBroadcast(scriptInterface.executionOwner, gamedataStimType.SilencedGunshot);
            broadcaster.TriggerSingleBroadcast(scriptInterface.executionOwner, gamedataStimType.SilencedGunshot, 10.0, emptyInvestigateData, true);
            if WeaponObject.GetWeaponType(weapon.GetItemID()) == gamedataItemType.Wea_SniperRifle {
                broadcaster.TriggerSingleBroadcast(scriptInterface.executionOwner, gamedataStimType.Gunshot, 10.0);
            }
        }
        WeaponObject.TriggerWeaponEffects(weapon, gamedataFxAction.SilencedShoot, effectBlackboard);
        WeaponObject.SendAmmoUpdateEvent(scriptInterface.executionOwner, weapon);
    } else {
        if statsSystem.GetStatValue(weapon.GetEntityID(), gamedataStatType.HasMuzzleBrake) > 0.0 {
            WeaponObject.TriggerWeaponEffects(weapon, gamedataFxAction.MuzzleBrakeShoot, effectBlackboard);
            WeaponObject.SendAmmoUpdateEvent(scriptInterface.executionOwner, weapon);
        } else {
            WeaponObject.TriggerWeaponEffects(weapon, gamedataFxAction.Shoot, effectBlackboard);
            WeaponObject.SendAmmoUpdateEvent(scriptInterface.executionOwner, weapon);
        }
        if IsDefined(broadcaster) {
            GameInstance.GetQuestsSystem(gameInstance).SetFact(n"player_fired_a_weapon", 1);
            if IsEntityInInteriorArea(GetPlayer(gameInstance)) {
                broadcaster.TriggerSingleBroadcast(scriptInterface.executionOwner, gamedataStimType.Gunshot, 25.0);
                visualStimDistance = 45.0;
            } else {
                broadcaster.TriggerSingleBroadcast(scriptInterface.executionOwner, gamedataStimType.Gunshot, GetPlayer(gameInstance).GetGunshotRange());
                if weapon.GetPreventionSystem().GetCurrentDistrict().IsDogTown() {
                    if scriptInterface.localBlackboard.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Combat) == EnumInt(gamePSMCombat.InCombat) {
                        visualStimDistance = 30.0;
                    } else {
                        visualStimDistance = 40.0;
                    }
                } else {
                    visualStimDistance = 50.0;
                }
            }
            broadcaster.TriggerSingleBroadcast(scriptInterface.executionOwner, gamedataStimType.Gunshot, visualStimDistance, emptyInvestigateData, true);
        }
        PlayerCoverHelper.BlockCoverVisibilityReduction(scriptInterface.executionOwner);
    }
    numBurstTotal = Cast<Float>(stateContext.GetIntParameter(this.GetShootingNumBurstTotalName(), true));
    magazineCapacity = Cast<Float>(WeaponObject.GetMagazineCapacity(weapon));
    if numBurstTotal > 0.0 {
        fullAutoPenalty = 1.0 + (((numBurstTotal + 1.0) / magazineCapacity) * statsSystem.GetStatValue(GetPlayer(gameInstance).GetEntityID(), gamedataStatType.FullAutoStaminaCostPenalty));
    }
    if RPGManager.GetWeaponEvolution(weapon.GetItemID()) == gamedataWeaponEvolution.Tech && scriptInterface.GetStatPoolsSystem().GetStatPoolValue(weapon.GetEntityID(), gamedataStatPoolType.WeaponCharge, false) >= WeaponObject.GetBaseMaxChargeThreshold(weapon) {
        fullChargePenalty = 1.5;
    }
    this.ConsumeStamina(scriptInterface, attackRecord, fullAutoPenalty, fullChargePenalty);
    this.SendDataTrackingRequest(scriptInterface, ETelemetryData.RangedAttacksMade, 1);
    this.ChangeStatPoolValue(scriptInterface, scriptInterface.ownerEntityID, gamedataStatPoolType.WeaponOverheat, this.GetStaticFloatParameterDefault("overheatValAdd", 10.0));
    this.ShootingSequencePostShoot(stateContext);
    GameObject.GetDualWieldWeaponNames(scriptInterface.executionOwner, leftHandWeapon, rightHandWeapon);
    GameInstance.GetTelemetrySystem(scriptInterface.owner.GetGame()).LogWeaponAttackPerformed(this.GetWeaponObject(scriptInterface), leftHandWeapon, rightHandWeapon);
}

