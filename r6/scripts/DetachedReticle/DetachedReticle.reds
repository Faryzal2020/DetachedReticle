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
    private let m_cameraPos: Vector4;
    private let m_muzzleRelCam: Vector4;
    private let m_muzzleScreen: Vector2;
    private let m_shotCount: Int32;
    private let m_lastShotMuzzlePos: Vector4;
    private let m_lastShotBulletDir: Vector4;
    private let m_lastShotTargetPt: Vector4;
    private let m_lastShotAngleDeg: Float;
    private let m_testMode: Int32;          // 0 = Round-Robin Auto-Cycle (1..6), 1..6 = Locked Mode
    private let m_currentCycleIndex: Int32; // Tracks current step in 1..6 cycle
    private let m_lastShotTestMode: Int32;
    private let m_lastShotTestModeName: String;
    private let m_dualStabilizeWeight: Float;
    private let m_leftGunForward: Vector4;
    private let m_leftMuzzlePos: Vector4;
    private let m_leftScreenOffset: Vector2;
    private let m_dualSettledInit: Bool;
    private let m_dualLastAiming: Bool;
    private let m_dualTransTimer: Float;
    private let m_rightBaseYaw: Float;
    private let m_rightBasePitch: Float;
    private let m_leftBaseYaw: Float;
    private let m_leftBasePitch: Float;
    private let m_adsRecoilHoriMult: Float;

    public func SetAdsRecoilHoriMult(mult: Float) -> Void {
        this.m_adsRecoilHoriMult = mult;
    }

    public func GetAdsRecoilHoriMult() -> Float {
        if this.m_adsRecoilHoriMult <= 0.0001 && this.m_adsRecoilHoriMult >= -0.0001 {
            return 0.5;
        }
        return this.m_adsRecoilHoriMult;
    }

    public func SetDualStabilizeWeight(w: Float) -> Void {
        this.m_dualStabilizeWeight = w;
    }

    public func GetDualStabilizeWeight() -> Float {
        return this.m_dualStabilizeWeight;
    }

    public func ResetDualSettled() -> Void {
        this.m_dualSettledInit = false;
        this.m_dualTransTimer = 0.0;
        this.m_rightBaseYaw = 0.0;
        this.m_rightBasePitch = 0.0;
        this.m_leftBaseYaw = 0.0;
        this.m_leftBasePitch = 0.0;
    }

    public func UpdateDualBaseOffsets(rRelYaw: Float, rRelPitch: Float, lRelYaw: Float, lRelPitch: Float, isAiming: Bool, isRecoiling: Bool, stabWeight: Float, dt: Float) -> Void {
        if !this.m_dualSettledInit {
            this.m_rightBaseYaw = rRelYaw;
            this.m_rightBasePitch = rRelPitch;
            this.m_leftBaseYaw = lRelYaw;
            this.m_leftBasePitch = lRelPitch;
            this.m_dualLastAiming = isAiming;
            this.m_dualTransTimer = 0.40;
            this.m_dualSettledInit = true;
            return;
        }

        if !Equals(isAiming, this.m_dualLastAiming) {
            this.m_dualLastAiming = isAiming;
            this.m_dualTransTimer = 0.45;
        }

        if this.m_dualTransTimer > 0.0 {
            this.m_dualTransTimer = MaxF(0.0, this.m_dualTransTimer - dt);
        }

        if stabWeight > 0.01 {
            if this.m_dualTransTimer > 0.0 {
                let alphaFast: Float = ClampF(dt / (0.08 + dt), 0.0, 1.0);
                this.m_rightBaseYaw += (rRelYaw - this.m_rightBaseYaw) * alphaFast;
                this.m_rightBasePitch += (rRelPitch - this.m_rightBasePitch) * alphaFast;
                this.m_leftBaseYaw += (lRelYaw - this.m_leftBaseYaw) * alphaFast;
                this.m_leftBasePitch += (lRelPitch - this.m_leftBasePitch) * alphaFast;
            } else if !isRecoiling {
                let rErr: Float = AbsF(rRelYaw - this.m_rightBaseYaw) + AbsF(rRelPitch - this.m_rightBasePitch);
                let lErr: Float = AbsF(lRelYaw - this.m_leftBaseYaw) + AbsF(lRelPitch - this.m_leftBasePitch);
                let tauR: Float = (rErr > 3.5) ? 0.12 : 2.5;
                let tauL: Float = (lErr > 3.5) ? 0.12 : 2.5;
                let alphaR: Float = ClampF(dt / (tauR + dt), 0.0, 1.0);
                let alphaL: Float = ClampF(dt / (tauL + dt), 0.0, 1.0);
                this.m_rightBaseYaw += (rRelYaw - this.m_rightBaseYaw) * alphaR;
                this.m_rightBasePitch += (rRelPitch - this.m_rightBasePitch) * alphaR;
                this.m_leftBaseYaw += (lRelYaw - this.m_leftBaseYaw) * alphaL;
                this.m_leftBasePitch += (lRelPitch - this.m_leftBasePitch) * alphaL;
            }
        }
    }

    public func GetRightBaseYaw() -> Float { return this.m_rightBaseYaw; }
    public func GetRightBasePitch() -> Float { return this.m_rightBasePitch; }
    public func GetLeftBaseYaw() -> Float { return this.m_leftBaseYaw; }
    public func GetLeftBasePitch() -> Float { return this.m_leftBasePitch; }

    public func SetDualAimState(leftFwd: Vector4, leftMuzPos: Vector4, leftScreenOffset: Vector2) -> Void {
        this.m_leftGunForward = leftFwd;
        this.m_leftMuzzlePos = leftMuzPos;
        this.m_leftScreenOffset = leftScreenOffset;
    }

    public func GetLeftGunForward() -> Vector4 { return this.m_leftGunForward; }
    public func GetLeftMuzzlePos() -> Vector4 { return this.m_leftMuzzlePos; }
    public func GetLeftScreenOffset() -> Vector2 { return this.m_leftScreenOffset; }

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

    public func SetMuzzleTelemetry(camPos: Vector4, muzRelCam: Vector4, muzScreen: Vector2) -> Void {
        this.m_cameraPos = camPos;
        this.m_muzzleRelCam = muzRelCam;
        this.m_muzzleScreen = muzScreen;
    }

    public func GetCameraPos() -> Vector4 { return this.m_cameraPos; }
    public func GetMuzzleRelCam() -> Vector4 { return this.m_muzzleRelCam; }
    public func GetMuzzleScreen() -> Vector2 { return this.m_muzzleScreen; }

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

    // Smart gun diagnostic probe fields
    private let m_smartCalls: Int32;
    private let m_smartTargets: Int32;
    private let m_smartLocked: Int32;
    private let m_smartHasLink: Bool;
    private let m_smartRegion: Vector2;
    private let m_smartRootVis: Bool;
    private let m_smartRootOpacity: Float;
    private let m_smartPreIntro: Int32;
    private let m_smartCtrlClass: String;
    private let m_smartWidgetName: String;
    private let m_smartExpectedXhair: String;

    public func RecordSmartParams(targets: Int32, locked: Int32, hasLink: Bool, region: Vector2, rootVis: Bool, rootOpacity: Float) -> Void {
        this.m_smartCalls += 1;
        this.m_smartTargets = targets;
        this.m_smartLocked = locked;
        this.m_smartHasLink = hasLink;
        this.m_smartRegion = region;
        this.m_smartRootVis = rootVis;
        this.m_smartRootOpacity = rootOpacity;
    }

    public func RecordSmartPreIntro() -> Void {
        this.m_smartPreIntro += 1;
    }

    public func RecordSmartUIIdentity(ctrlClass: String, widgetName: String, expectedXhair: String) -> Void {
        this.m_smartCtrlClass = ctrlClass;
        this.m_smartWidgetName = widgetName;
        this.m_smartExpectedXhair = expectedXhair;
    }

    public func GetSmartCalls() -> Int32 { return this.m_smartCalls; }
    public func GetSmartTargets() -> Int32 { return this.m_smartTargets; }
    public func GetSmartLocked() -> Int32 { return this.m_smartLocked; }
    public func GetSmartHasLink() -> Bool { return this.m_smartHasLink; }
    public func GetSmartRegion() -> Vector2 { return this.m_smartRegion; }
    public func GetSmartRootVis() -> Bool { return this.m_smartRootVis; }
    public func GetSmartRootOpacity() -> Float { return this.m_smartRootOpacity; }
    public func GetSmartPreIntro() -> Int32 { return this.m_smartPreIntro; }
    public func GetSmartCtrlClass() -> String { return this.m_smartCtrlClass; }
    public func GetSmartWidgetName() -> String { return this.m_smartWidgetName; }
    public func GetSmartExpectedXhair() -> String { return this.m_smartExpectedXhair; }

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
private let m_leftCrosshair: ref<inkCanvas>;

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
    this.InitLeftCrosshair();

    this.StartDetachedReticleTick();
}

@addMethod(gameuiCrosshairContainerController)
private func InitLeftCrosshair() -> Void {
    if IsDefined(this.m_leftCrosshair) || !IsDefined(this.m_rootWidget) {
        return;
    }

    let container: ref<inkCanvas> = new inkCanvas();
    container.SetName(n"LeftGunReticleDualWield");
    container.SetAnchor(inkEAnchor.Centered);
    container.SetAnchorPoint(new Vector2(0.5, 0.5));
    container.SetSize(new Vector2(32.0, 32.0));
    container.SetTranslation(new Vector2(0.0, 0.0));
    container.SetVisible(false);

    // 1. Dark outer diamond border (14x14, 45 deg)
    let shadow: ref<inkRectangle> = new inkRectangle();
    shadow.SetName(n"LeftReticleShadow");
    shadow.SetAnchor(inkEAnchor.Centered);
    shadow.SetAnchorPoint(new Vector2(0.5, 0.5));
    shadow.SetSize(new Vector2(14.0, 14.0));
    shadow.SetRotation(45.0);
    shadow.SetTintColor(new HDRColor(0.0, 0.0, 0.0, 0.70));
    container.AddChildWidget(shadow);

    // 2. Amber/gold diamond pip (8x8, 45 deg)
    let amberPip: ref<inkRectangle> = new inkRectangle();
    amberPip.SetName(n"LeftReticleAmber");
    amberPip.SetAnchor(inkEAnchor.Centered);
    amberPip.SetAnchorPoint(new Vector2(0.5, 0.5));
    amberPip.SetSize(new Vector2(8.0, 8.0));
    amberPip.SetRotation(45.0);
    amberPip.SetTintColor(new HDRColor(1.0, 0.80, 0.20, 0.90));
    container.AddChildWidget(amberPip);

    // 3. Crisp white center dot (2x2)
    let core: ref<inkRectangle> = new inkRectangle();
    core.SetName(n"LeftReticleCore");
    core.SetAnchor(inkEAnchor.Centered);
    core.SetAnchorPoint(new Vector2(0.5, 0.5));
    core.SetSize(new Vector2(2.0, 2.0));
    core.SetTintColor(new HDRColor(1.0, 1.0, 1.0, 1.0));
    container.AddChildWidget(core);

    // 4. Subtle left bracket marker to visually distinguish left hand
    let leftBracket: ref<inkRectangle> = new inkRectangle();
    leftBracket.SetName(n"LeftReticleBracket");
    leftBracket.SetAnchor(inkEAnchor.Centered);
    leftBracket.SetAnchorPoint(new Vector2(0.5, 0.5));
    leftBracket.SetSize(new Vector2(2.0, 12.0));
    leftBracket.SetTranslation(new Vector2(-10.0, 0.0));
    leftBracket.SetTintColor(new HDRColor(1.0, 0.80, 0.20, 0.75));
    container.AddChildWidget(leftBracket);

    this.m_rootWidget.AddChildWidget(container);
    this.m_leftCrosshair = container;
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
    if IsDefined(this.m_leftCrosshair) && IsDefined(this.m_rootWidget) {
        this.m_rootWidget.RemoveChild(this.m_leftCrosshair);
        this.m_leftCrosshair = null;
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

    // Frame Delta Time calculation
    let currentEngineTime: Float = EngineTime.ToFloat(GameInstance.GetEngineTime(player.GetGame()));
    let dt: Float = (this.m_lastEngineTime > 0.0) ? (currentEngineTime - this.m_lastEngineTime) : (1.0 / 60.0);
    this.m_lastEngineTime = currentEngineTime;
    if dt <= 0.0001 || dt > 0.2 {
        dt = 1.0 / 60.0;
    }

    if GameObject.IsDualWielding(player) {
        this.UpdateDualWieldAim(player, aimSys, activeWidget, dt);
        return;
    } else {
        if IsDefined(this.m_leftCrosshair) {
            this.m_leftCrosshair.SetVisible(false);
        }
        if IsDefined(aimSys) {
            aimSys.ResetDualSettled();
        }
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

    let isSmartWeapon: Bool = Equals(RPGManager.GetWeaponEvolution(weapon.GetItemID()), gamedataWeaponEvolution.Smart);
    if isSmartWeapon {
        if IsDefined(this.m_cameraCrosshair) { this.m_cameraCrosshair.SetVisible(false); }
        if IsDefined(activeWidget) {
            activeWidget.SetTranslation(new Vector2(0.0, 0.0));
        }

        let camTransform: Transform;
        let camSys: ref<CameraSystem> = GameInstance.GetCameraSystem(player.GetGame());
        let camFwd3: Vector4 = new Vector4(0.0, 1.0, 0.0, 0.0);
        if IsDefined(camSys) && camSys.GetActiveCameraWorldTransform(camTransform) {
            camFwd3 = Vector4.Normalize(Transform.GetForward(camTransform));
        }

        if IsDefined(aimSys) {
            aimSys.SetAimState(camFwd3, new Vector4(0.0, 0.0, 0.0, 0.0), new Vector4(0.0, 0.0, 0.0, 0.0), camFwd3, new Vector2(0.0, 0.0), 0.0, 0.0, 0.0, false);

            let activeCtrl: ref<gameuiCrosshairBaseGameController> = this.GetActiveCrosshairGameController();
            let ctrlClassStr: String = IsDefined(activeCtrl) ? NameToString(activeCtrl.GetClassName()) : "NULL";
            let widgetNameStr: String = IsDefined(activeWidget) ? NameToString(activeWidget.GetName()) : "NULL";
            let expectedXhairStr: String = TDBID.ToStringDEBUG(TweakDBInterface.GetItemRecord(ItemID.GetTDBID(weapon.GetItemID())).Crosshair().GetID());
            aimSys.RecordSmartUIIdentity(ctrlClassStr, widgetNameStr, expectedXhairStr);
        }
        SetMuzzleAimState(new Vector4(0.0, 0.0, 0.0, 1.0), new Vector4(0.0, 1.0, 0.0, 0.0), new Vector4(0.0, 1.0, 0.0, 0.0), false);
        return;
    }

    if !this.m_detachedLoggedWeapon {
        FTLog("[DetachedReticle] Active ranged weapon equipped: " + TDBID.ToStringDEBUG(ItemID.GetTDBID(weapon.GetItemID())) + " | Decoupled Gun Reticle active.");
        this.m_detachedLoggedWeapon = true;
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

    let camRight: Vector4 = Transform.GetRight(camTransform);
    let camUp: Vector4 = Transform.GetUp(camTransform);
    let dx: Float = Vector4.Dot(this.m_gunForward, camRight);
    let dy: Float = Vector4.Dot(this.m_gunForward, camUp);
    let dz: Float = Vector4.Dot(this.m_gunForward, camFwd3);
    let yawLagDeg: Float = Rad2Deg(AtanF(dx, dz));
    let pitchLagDeg: Float = Rad2Deg(AtanF(dy, dz));

    // Check if player is aiming down sights (ADS)
    let isAiming: Bool = false;
    let psmBB: ref<IBlackboard> = player.GetPlayerStateMachineBlackboard();
    if IsDefined(psmBB) {
        let upperBody: Int32 = psmBB.GetInt(GetAllBlackboardDefs().PlayerStateMachine.UpperBody);
        let crosshair: Int32 = psmBB.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Crosshair);
        isAiming = upperBody == EnumInt(gamePSMUpperBodyStates.Aim) || crosshair == EnumInt(gamePSMCrosshairStates.Aim);
    }
    let wType: gamedataItemType = WeaponObject.GetWeaponType(weapon.GetItemID());
    let isHMG: Bool = weapon.IsHeavyWeapon() || Equals(wType, gamedataItemType.Wea_HeavyMachineGun);

    // Effective barrel direction: starts from the physical 3D gun barrel (m_gunForward)
    // plus ADS horizontal recoil deflection
    let effGunFwd: Vector4 = this.m_gunForward;
    if isAiming && !isHMG {
        let horiMult: Float = IsDefined(aimSys) ? aimSys.GetAdsRecoilHoriMult() : 0.5;
        let adsHoriYawDeg: Float = DR_GetRecoilYaw() * horiMult;
        if AbsF(adsHoriYawDeg) > 0.001 {
            effGunFwd = Vector4.Normalize(this.m_gunForward + camRight * TanF(Deg2Rad(adsHoriYawDeg)));
        }
    }

    let maxRange: Float = 100.0;
    let traceEnd: Vector4 = muzzlePos + (effGunFwd * maxRange);
    let targetPoint: Vector4 = traceEnd;
    let aimFwd: Vector4 = effGunFwd;

    let sqs: ref<SpatialQueriesSystem> = GameInstance.GetSpatialQueriesSystem(player.GetGame());
    if isAiming && !isHMG {
        // In ADS, the 3D gun and scope naturally align with the camera (T1) while retaining
        // 3D breathing sway, mouse-chase lag (T2A), and recoil (W) in effGunFwd.
        // Raycasting from camPos (scope/sight eye origin) along effGunFwd zeroes out the 6-13cm
        // height-over-bore drop between the scope and MuzzleSlot while 100% preserving effGunFwd's pitch & yaw.
        let sightTargetRange: Float = 200.0;
        let sightTargetEnd: Vector4 = camPos + (effGunFwd * sightTargetRange);
        let sightTarget: Vector4 = sightTargetEnd;
        if IsDefined(sqs) {
            let sightTrace: TraceResult;
            if sqs.SyncRaycastByCollisionPreset(camPos, sightTargetEnd, n"World Static", sightTrace) && TraceResult.IsValid(sightTrace) {
                sightTarget = new Vector4(sightTrace.position.X, sightTrace.position.Y, sightTrace.position.Z, 1.0);
            }
            if sqs.SyncRaycastByCollisionPreset(camPos, sightTarget, n"World Dynamic", sightTrace) && TraceResult.IsValid(sightTrace) {
                let dynHit: Vector4 = new Vector4(sightTrace.position.X, sightTrace.position.Y, sightTrace.position.Z, 1.0);
                if Vector4.DistanceSquared(camPos, dynHit) < Vector4.DistanceSquared(camPos, sightTarget) {
                    sightTarget = dynHit;
                }
            }
        }
        let toSightTarget: Vector4 = sightTarget - muzzlePos;
        let convDir: Vector4 = Vector4.Normalize(toSightTarget);
        if Vector4.Dot(convDir, effGunFwd) > 0.2 {
            aimFwd = convDir;
            targetPoint = sightTarget;
        }
    } else {
        // Hipfire or HMG: physical barrel aim line from muzzlePos
        if IsDefined(sqs) {
            let traceStatic: TraceResult;
            if sqs.SyncRaycastByCollisionPreset(muzzlePos, traceEnd, n"World Static", traceStatic) && TraceResult.IsValid(traceStatic) {
                targetPoint = new Vector4(traceStatic.position.X, traceStatic.position.Y, traceStatic.position.Z, 1.0);
            }
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

    // Calculate angular lag between gun barrel and camera gaze
    let clampedDot: Float = ClampF(dotCam, -1.0, 1.0);
    let angleDeg: Float = Rad2Deg(AcosF(clampedDot));

    // Update global DetachedAimSystem for state query and telemetry
    if IsDefined(aimSys) {
        aimSys.SetAimState(effGunFwd, targetPoint, muzzlePos, camFwd3, screenOffset, angleDeg, yawLagDeg, pitchLagDeg, true);

        // Project physical 3D muzzle location and compute camera-relative coordinates
        let toMuzzle: Vector4 = muzzlePos - camPos;
        let muzRightM: Float = Vector4.Dot(toMuzzle, camRight);
        let muzFwdM: Float = Vector4.Dot(toMuzzle, camFwd3);
        let muzUpM: Float = Vector4.Dot(toMuzzle, camUp);
        let muzRelCam: Vector4 = new Vector4(muzRightM, muzFwdM, muzUpM, 1.0);

        let muzProj: Vector2 = this.ProjectWorldToScreen(muzzlePos);
        let rCanvas: ref<inkCanvas> = this.m_rootWidget;
        if !IsDefined(rCanvas) {
            rCanvas = this.GetRootWidget() as inkCanvas;
        }
        let rSize: Vector2 = IsDefined(rCanvas) ? rCanvas.GetSize() : new Vector2(3840.0, 2160.0);
        if rSize.X <= 0.0 || rSize.Y <= 0.0 {
            rSize = new Vector2(3840.0, 2160.0);
        }
        let muzScreen: Vector2 = new Vector2(
            rSize.X * 0.5 * muzProj.X,
            -rSize.Y * 0.5 * muzProj.Y
        );

        aimSys.SetMuzzleTelemetry(camPos, muzRelCam, muzScreen);
    }

    // Feed continuous live barrel tracking to native ShootingHook
    SetMuzzleAimState(muzzlePos, aimFwd, camFwd3, true);

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

@addMethod(gameuiCrosshairContainerController)
private func UpdateDualWieldAim(player: ref<PlayerPuppet>, aimSys: ref<DetachedAimSystem>, activeWidget: ref<inkWidget>, dt: Float) -> Void {
    let rightWeapon: ref<WeaponObject> = GameObject.GetRightActiveWeapon(player);
    let leftWeapon: ref<WeaponObject> = GameObject.GetLeftActiveWeapon(player);

    if !IsDefined(rightWeapon) && !IsDefined(leftWeapon) {
        if IsDefined(this.m_cameraCrosshair) { this.m_cameraCrosshair.SetVisible(false); }
        if IsDefined(this.m_leftCrosshair) { this.m_leftCrosshair.SetVisible(false); }
        if IsDefined(activeWidget) { activeWidget.SetTranslation(new Vector2(0.0, 0.0)); }
        return;
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
    let camRight: Vector4 = Transform.GetRight(camTransform);
    let camUp: Vector4 = Transform.GetUp(camTransform);

    // Camera diamond T1 is always fixed at screen center (0, 0)
    if IsDefined(this.m_cameraCrosshair) {
        this.m_cameraCrosshair.SetVisible(true);
        this.m_cameraCrosshair.SetTranslation(new Vector2(0.0, 0.0));
    }

    // Initialize left crosshair if not created yet
    if !IsDefined(this.m_leftCrosshair) {
        this.InitLeftCrosshair();
    }

    let rootCanvas: ref<inkCanvas> = this.m_rootWidget;
    if !IsDefined(rootCanvas) {
        rootCanvas = this.GetRootWidget() as inkCanvas;
    }
    let rootSize: Vector2 = IsDefined(rootCanvas) ? rootCanvas.GetSize() : new Vector2(3840.0, 2160.0);
    if rootSize.X <= 0.0 || rootSize.Y <= 0.0 {
        rootSize = new Vector2(3840.0, 2160.0);
    }

    let isAiming: Bool = false;
    let psmBB: ref<IBlackboard> = player.GetPlayerStateMachineBlackboard();
    if IsDefined(psmBB) {
        let upperBody: Int32 = psmBB.GetInt(GetAllBlackboardDefs().PlayerStateMachine.UpperBody);
        let crosshair: Int32 = psmBB.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Crosshair);
        isAiming = upperBody == EnumInt(gamePSMUpperBodyStates.Aim) || crosshair == EnumInt(gamePSMCrosshairStates.Aim);
    }

    let rYaw: Float = DR_GetResidualYaw();
    let rPitch: Float = DR_GetResidualPitch();
    let wYaw: Float = DR_GetRecoilYaw();
    let wPitch: Float = DR_GetRecoilPitch();
    let isRecoiling: Bool = (AbsF(wYaw) + AbsF(wPitch)) > 0.02;

    // Dynamic stabilization weight towards center reticle (1.0 in ready hipfire & ADS, 0.0 in sprint/safe)
    let stabWeight: Float = 1.0;
    if IsDefined(aimSys) {
        stabWeight = ClampF(aimSys.GetDualStabilizeWeight(), 0.0, 1.0);
    }

    // Measure both guns' raw camera-space barrel angles and body-relative (T2B-relative) angles
    let rMuzPos: Vector4 = camPos;
    let normRMuzFwd: Vector4 = camFwd3;
    let rGunYaw: Float = 0.0;
    let rGunPitch: Float = 0.0;
    let rRelYaw: Float = 0.0;
    let rRelPitch: Float = 0.0;
    if IsDefined(rightWeapon) {
        let rMuzTransform: Transform = rightWeapon.GetMuzzleSlotWorldTransform();
        rMuzPos = Transform.GetPosition(rMuzTransform);
        let rMuzFwd: Vector4 = Transform.GetForward(rMuzTransform);
        if Vector4.IsZero(rMuzFwd) { rMuzFwd = rightWeapon.GetWorldForward(); }
        if Vector4.IsZero(rMuzPos) { rMuzPos = rightWeapon.GetWorldPosition(); }
        normRMuzFwd = Vector4.Normalize(rMuzFwd);
        let rDx: Float = Vector4.Dot(normRMuzFwd, camRight);
        let rDy: Float = Vector4.Dot(normRMuzFwd, camUp);
        let rDz: Float = MaxF(0.05, Vector4.Dot(normRMuzFwd, camFwd3));
        rGunYaw = Rad2Deg(AtanF(rDx, rDz));
        rGunPitch = Rad2Deg(AtanF(rDy, rDz));
        rRelYaw = rGunYaw - rYaw;
        rRelPitch = rGunPitch + rPitch;
    }

    let lMuzPos: Vector4 = camPos;
    let normLMuzFwd: Vector4 = camFwd3;
    let lGunYaw: Float = 0.0;
    let lGunPitch: Float = 0.0;
    let lRelYaw: Float = 0.0;
    let lRelPitch: Float = 0.0;
    if IsDefined(leftWeapon) {
        let lMuzTransform: Transform = leftWeapon.GetMuzzleSlotWorldTransform();
        lMuzPos = Transform.GetPosition(lMuzTransform);
        let lMuzFwd: Vector4 = Transform.GetForward(lMuzTransform);
        if Vector4.IsZero(lMuzFwd) { lMuzFwd = leftWeapon.GetWorldForward(); }
        if Vector4.IsZero(lMuzPos) { lMuzPos = leftWeapon.GetWorldPosition(); }
        normLMuzFwd = Vector4.Normalize(lMuzFwd);
        let lDx: Float = Vector4.Dot(normLMuzFwd, camRight);
        let lDy: Float = Vector4.Dot(normLMuzFwd, camUp);
        let lDz: Float = MaxF(0.05, Vector4.Dot(normLMuzFwd, camFwd3));
        lGunYaw = Rad2Deg(AtanF(lDx, lDz));
        lGunPitch = Rad2Deg(AtanF(lDy, lDz));
        lRelYaw = lGunYaw - rYaw;
        lRelPitch = lGunPitch + rPitch;
    }

    let rBaseYaw: Float = rRelYaw;
    let rBasePitch: Float = rRelPitch;
    let lBaseYaw: Float = lRelYaw;
    let lBasePitch: Float = lRelPitch;
    if IsDefined(aimSys) {
        aimSys.UpdateDualBaseOffsets(rRelYaw, rRelPitch, lRelYaw, lRelPitch, isAiming, isRecoiling, stabWeight, dt);
        rBaseYaw = aimSys.GetRightBaseYaw();
        rBasePitch = aimSys.GetRightBasePitch();
        lBaseYaw = aimSys.GetLeftBaseYaw();
        lBasePitch = aimSys.GetLeftBasePitch();
    }

    let sqs: ref<SpatialQueriesSystem> = GameInstance.GetSpatialQueriesSystem(player.GetGame());
    let sightRange: Float = 200.0;

    // --- Right Gun (Right T3 -> activeWidget) ---
    let rightAimFwd: Vector4 = camFwd3;
    let rightMuzzlePos: Vector4 = rMuzPos;
    let rightTargetPt: Vector4 = camPos + (camFwd3 * sightRange);
    let rightScreenOffset: Vector2 = new Vector2(0.0, 0.0);
    let rEffYaw: Float = 0.0;
    let rEffPitch: Float = 0.0;
    let rAngleDeg: Float = 0.0;
    if IsDefined(rightWeapon) {
        // Subtract low-pass resting anatomical splay while preserving 100% of natural 3D sway, T2A chase lag, and W recoil
        rEffYaw = rGunYaw - (stabWeight * rBaseYaw);
        rEffPitch = rGunPitch - (stabWeight * rBasePitch);
        let rEffFwd: Vector4 = Vector4.Normalize(camFwd3 + (camRight * TanF(Deg2Rad(rEffYaw))) + (camUp * TanF(Deg2Rad(rEffPitch))));

        // Interpolate sight raycast origin from physical muzzle to camera by stabWeight to eliminate parallax in ready stance
        let rSightOrigin: Vector4 = (rMuzPos * (1.0 - stabWeight)) + (camPos * stabWeight);
        rSightOrigin.W = 1.0;
        let rSightEnd: Vector4 = rSightOrigin + (rEffFwd * sightRange);
        rightTargetPt = rSightEnd;
        if IsDefined(sqs) {
            let rTrace: TraceResult;
            if sqs.SyncRaycastByCollisionPreset(rSightOrigin, rSightEnd, n"World Static", rTrace) && TraceResult.IsValid(rTrace) {
                rightTargetPt = new Vector4(rTrace.position.X, rTrace.position.Y, rTrace.position.Z, 1.0);
            }
            if sqs.SyncRaycastByCollisionPreset(rSightOrigin, rightTargetPt, n"World Dynamic", rTrace) && TraceResult.IsValid(rTrace) {
                let dynHit: Vector4 = new Vector4(rTrace.position.X, rTrace.position.Y, rTrace.position.Z, 1.0);
                if Vector4.DistanceSquared(rSightOrigin, dynHit) < Vector4.DistanceSquared(rSightOrigin, rightTargetPt) {
                    rightTargetPt = dynHit;
                }
            }
        }

        let toRTarget: Vector4 = rightTargetPt - camPos;
        let toRDir: Vector4 = Vector4.Normalize(toRTarget);
        let dotRCam: Float = Vector4.Dot(toRDir, camFwd3);
        rAngleDeg = Rad2Deg(AcosF(ClampF(dotRCam, -1.0, 1.0)));
        if dotRCam > 0.05 {
            let rProj: Vector2 = this.ProjectWorldToScreen(rightTargetPt);
            rightScreenOffset = new Vector2(rootSize.X * 0.5 * rProj.X, -rootSize.Y * 0.5 * rProj.Y);
            if IsDefined(activeWidget) {
                activeWidget.SetVisible(true);
                activeWidget.SetTranslation(rightScreenOffset);
            }
        } else if IsDefined(activeWidget) {
            activeWidget.SetVisible(false);
        }

        // Physical bullet trajectory from right muzzle converging onto Right T3's 3D target point
        let rConvDir: Vector4 = Vector4.Normalize(rightTargetPt - rMuzPos);
        if Vector4.Dot(rConvDir, rEffFwd) > 0.2 {
            rightAimFwd = rConvDir;
        } else {
            rightAimFwd = rEffFwd;
        }
    } else if IsDefined(activeWidget) {
        activeWidget.SetVisible(false);
    }

    // --- Left Gun (Left T3 -> m_leftCrosshair) ---
    let leftAimFwd: Vector4 = camFwd3;
    let leftMuzzlePos: Vector4 = lMuzPos;
    let leftTargetPt: Vector4 = camPos + (camFwd3 * sightRange);
    let leftScreenOffset: Vector2 = new Vector2(0.0, 0.0);
    if IsDefined(leftWeapon) {
        // Subtract low-pass resting anatomical splay while preserving 100% of natural 3D sway, T2A chase lag, and W recoil
        let lEffYaw: Float = lGunYaw - (stabWeight * lBaseYaw);
        let lEffPitch: Float = lGunPitch - (stabWeight * lBasePitch);
        let lEffFwd: Vector4 = Vector4.Normalize(camFwd3 + (camRight * TanF(Deg2Rad(lEffYaw))) + (camUp * TanF(Deg2Rad(lEffPitch))));

        // Interpolate sight raycast origin from physical muzzle to camera by stabWeight to eliminate parallax in ready stance
        let lSightOrigin: Vector4 = (lMuzPos * (1.0 - stabWeight)) + (camPos * stabWeight);
        lSightOrigin.W = 1.0;
        let lSightEnd: Vector4 = lSightOrigin + (lEffFwd * sightRange);
        leftTargetPt = lSightEnd;
        if IsDefined(sqs) {
            let lTrace: TraceResult;
            if sqs.SyncRaycastByCollisionPreset(lSightOrigin, lSightEnd, n"World Static", lTrace) && TraceResult.IsValid(lTrace) {
                leftTargetPt = new Vector4(lTrace.position.X, lTrace.position.Y, lTrace.position.Z, 1.0);
            }
            if sqs.SyncRaycastByCollisionPreset(lSightOrigin, leftTargetPt, n"World Dynamic", lTrace) && TraceResult.IsValid(lTrace) {
                let dynHitL: Vector4 = new Vector4(lTrace.position.X, lTrace.position.Y, lTrace.position.Z, 1.0);
                if Vector4.DistanceSquared(lSightOrigin, dynHitL) < Vector4.DistanceSquared(lSightOrigin, leftTargetPt) {
                    leftTargetPt = dynHitL;
                }
            }
        }

        let toLTarget: Vector4 = leftTargetPt - camPos;
        let toLDir: Vector4 = Vector4.Normalize(toLTarget);
        let dotLCam: Float = Vector4.Dot(toLDir, camFwd3);
        if dotLCam > 0.05 {
            let lProj: Vector2 = this.ProjectWorldToScreen(leftTargetPt);
            leftScreenOffset = new Vector2(rootSize.X * 0.5 * lProj.X, -rootSize.Y * 0.5 * lProj.Y);
            if IsDefined(this.m_leftCrosshair) {
                this.m_leftCrosshair.SetVisible(true);
                this.m_leftCrosshair.SetTranslation(leftScreenOffset);
            }
        } else if IsDefined(this.m_leftCrosshair) {
            this.m_leftCrosshair.SetVisible(false);
        }

        // Physical bullet trajectory from left muzzle converging onto Left T3's 3D target point
        let lConvDir: Vector4 = Vector4.Normalize(leftTargetPt - lMuzPos);
        if Vector4.Dot(lConvDir, lEffFwd) > 0.2 {
            leftAimFwd = lConvDir;
        } else {
            leftAimFwd = lEffFwd;
        }
    } else if IsDefined(this.m_leftCrosshair) {
        this.m_leftCrosshair.SetVisible(false);
    }

    if IsDefined(aimSys) {
        aimSys.SetAimState(rightAimFwd, rightTargetPt, rightMuzzlePos, camFwd3, rightScreenOffset, rAngleDeg, rEffYaw, rEffPitch, true);
        aimSys.SetDualAimState(leftAimFwd, leftMuzzlePos, leftScreenOffset);
    }
}

// In ShootEvents.OnEnter, QueueMuzzleShot & SetMuzzleAimState prepare the physical muzzle trajectory
// before the vanilla shooting pipeline runs. PhysicalRay callsites are intercepted natively.
@wrapMethod(ShootEvents)
protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
    let weapon: ref<WeaponObject> = this.GetWeaponObject(scriptInterface);
    let player: ref<PlayerPuppet> = scriptInterface.executionOwner as PlayerPuppet;
    let isSmartWeapon: Bool = IsDefined(weapon) && Equals(RPGManager.GetWeaponEvolution(weapon.GetItemID()), gamedataWeaponEvolution.Smart);
    let isDecoupledActive: Bool = IsDefined(player) && IsDefined(weapon) && !weapon.IsMelee() && !isSmartWeapon;

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
        let aimSys: ref<DetachedAimSystem> = DetachedAimSystem.GetInstance(scriptInterface.GetGame());

        let camTransform: Transform;
        let camSys: ref<CameraSystem> = GameInstance.GetCameraSystem(scriptInterface.GetGame());
        let camFwd: Vector4 = new Vector4(0.0, 1.0, 0.0, 0.0);
        let camPos: Vector4 = new Vector4(0.0, 0.0, 0.0, 1.0);
        let hasCam: Bool = IsDefined(camSys) && camSys.GetActiveCameraWorldTransform(camTransform);
        if hasCam {
            camFwd = Vector4.Normalize(Transform.GetForward(camTransform));
            camPos = Transform.GetPosition(camTransform);
        }

        let attackRecord: ref<Attack_Record> = this.GetDesiredAttackRecord(stateContext, scriptInterface);
        let maxRange: Float = IsDefined(attackRecord) ? attackRecord.Range() : 200.0;
        if maxRange <= 0.0 {
            maxRange = 200.0;
        }

        let aimFwd: Vector4 = normMuzzleFwd;
        let isDual: Bool = GameObject.IsDualWielding(player);
        if isDual && hasCam {
            let leftWeapon: ref<WeaponObject> = GameObject.GetLeftActiveWeapon(player);
            let isLeftHand: Bool = this.IsLeftWeaponLogic() || (IsDefined(leftWeapon) && weapon == leftWeapon);
            let stabWeight: Float = IsDefined(aimSys) ? ClampF(aimSys.GetDualStabilizeWeight(), 0.0, 1.0) : 1.0;

            let camRight: Vector4 = Transform.GetRight(camTransform);
            let camUp: Vector4 = Transform.GetUp(camTransform);
            let dx: Float = Vector4.Dot(normMuzzleFwd, camRight);
            let dy: Float = Vector4.Dot(normMuzzleFwd, camUp);
            let dz: Float = MaxF(0.05, Vector4.Dot(normMuzzleFwd, camFwd));
            let gunYaw: Float = Rad2Deg(AtanF(dx, dz));
            let gunPitch: Float = Rad2Deg(AtanF(dy, dz));

            let baseYaw: Float = 0.0;
            let basePitch: Float = 0.0;
            if IsDefined(aimSys) {
                if isLeftHand {
                    baseYaw = aimSys.GetLeftBaseYaw();
                    basePitch = aimSys.GetLeftBasePitch();
                } else {
                    baseYaw = aimSys.GetRightBaseYaw();
                    basePitch = aimSys.GetRightBasePitch();
                }
            }

            let effYaw: Float = gunYaw - (stabWeight * baseYaw);
            let effPitch: Float = gunPitch - (stabWeight * basePitch);
            let effGunFwd: Vector4 = Vector4.Normalize(camFwd + (camRight * TanF(Deg2Rad(effYaw))) + (camUp * TanF(Deg2Rad(effPitch))));

            let sightOrigin: Vector4 = (muzzlePos * (1.0 - stabWeight)) + (camPos * stabWeight);
            sightOrigin.W = 1.0;
            let sightEnd: Vector4 = sightOrigin + (effGunFwd * maxRange);
            let sightTarget: Vector4 = sightEnd;

            let sqs: ref<SpatialQueriesSystem> = GameInstance.GetSpatialQueriesSystem(scriptInterface.GetGame());
            if IsDefined(sqs) {
                let sightTrace: TraceResult;
                if sqs.SyncRaycastByCollisionPreset(sightOrigin, sightEnd, n"World Static", sightTrace) && TraceResult.IsValid(sightTrace) {
                    sightTarget = new Vector4(sightTrace.position.X, sightTrace.position.Y, sightTrace.position.Z, 1.0);
                }
                if sqs.SyncRaycastByCollisionPreset(sightOrigin, sightTarget, n"World Dynamic", sightTrace) && TraceResult.IsValid(sightTrace) {
                    let dynHit: Vector4 = new Vector4(sightTrace.position.X, sightTrace.position.Y, sightTrace.position.Z, 1.0);
                    if Vector4.DistanceSquared(sightOrigin, dynHit) < Vector4.DistanceSquared(sightOrigin, sightTarget) {
                        sightTarget = dynHit;
                    }
                }
            }

            let convDir: Vector4 = Vector4.Normalize(sightTarget - muzzlePos);
            if Vector4.Dot(convDir, effGunFwd) > 0.2 {
                aimFwd = convDir;
            } else {
                aimFwd = effGunFwd;
            }
        } else {
            let isAiming: Bool = false;
            let wType: gamedataItemType = WeaponObject.GetWeaponType(weapon.GetItemID());
            let isHMG: Bool = weapon.IsHeavyWeapon() || Equals(wType, gamedataItemType.Wea_HeavyMachineGun);
            if IsDefined(scriptInterface.localBlackboard) {
                let upperBody: Int32 = scriptInterface.localBlackboard.GetInt(GetAllBlackboardDefs().PlayerStateMachine.UpperBody);
                let crosshair: Int32 = scriptInterface.localBlackboard.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Crosshair);
                isAiming = upperBody == EnumInt(gamePSMUpperBodyStates.Aim) || crosshair == EnumInt(gamePSMCrosshairStates.Aim);
            }
            if !isAiming {
                let psmBB: ref<IBlackboard> = player.GetPlayerStateMachineBlackboard();
                if IsDefined(psmBB) {
                    let upperBody: Int32 = psmBB.GetInt(GetAllBlackboardDefs().PlayerStateMachine.UpperBody);
                    let crosshair: Int32 = psmBB.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Crosshair);
                    isAiming = upperBody == EnumInt(gamePSMUpperBodyStates.Aim) || crosshair == EnumInt(gamePSMCrosshairStates.Aim);
                }
            }

            if isAiming && !isHMG {
                let effGunFwd: Vector4 = normMuzzleFwd;
                let horiMult: Float = IsDefined(aimSys) ? aimSys.GetAdsRecoilHoriMult() : 0.5;
                let adsHoriYawDeg: Float = DR_GetRecoilYaw() * horiMult;
                if AbsF(adsHoriYawDeg) > 0.001 {
                    let camRight: Vector4 = Transform.GetRight(camTransform);
                    effGunFwd = Vector4.Normalize(normMuzzleFwd + camRight * TanF(Deg2Rad(adsHoriYawDeg)));
                }

                let sqs: ref<SpatialQueriesSystem> = GameInstance.GetSpatialQueriesSystem(scriptInterface.GetGame());
                let sightTarget: Vector4 = camPos + (effGunFwd * maxRange);
                if IsDefined(sqs) {
                    let sightTrace: TraceResult;
                    if sqs.SyncRaycastByCollisionPreset(camPos, sightTarget, n"World Static", sightTrace) && TraceResult.IsValid(sightTrace) {
                        sightTarget = new Vector4(sightTrace.position.X, sightTrace.position.Y, sightTrace.position.Z, 1.0);
                    }
                    if sqs.SyncRaycastByCollisionPreset(camPos, sightTarget, n"World Dynamic", sightTrace) && TraceResult.IsValid(sightTrace) {
                        let dynHit: Vector4 = new Vector4(sightTrace.position.X, sightTrace.position.Y, sightTrace.position.Z, 1.0);
                        if Vector4.DistanceSquared(camPos, dynHit) < Vector4.DistanceSquared(camPos, sightTarget) {
                            sightTarget = dynHit;
                        }
                    }
                }
                let toSightTarget: Vector4 = sightTarget - muzzlePos;
                let convDir: Vector4 = Vector4.Normalize(toSightTarget);
                if Vector4.Dot(convDir, effGunFwd) > 0.2 {
                    aimFwd = convDir;
                } else {
                    aimFwd = effGunFwd;
                }
            }
        }

        // Query projectiles per shot so multi-pellet weapons consume the exact number of rays for this hand
        let statsSys: ref<StatsSystem> = scriptInterface.GetStatsSystem();
        let pps: Float = IsDefined(statsSys) ? statsSys.GetStatValue(Cast<StatsObjectID>(weapon.GetEntityID()), gamedataStatType.ProjectilesPerShot) : 1.0;
        let pellets: Int32 = Max(1, RoundF(pps));

        // Enqueue this weapon's shot into the FIFO queue (so simultaneous Right+Left dual-wield shots never overwrite each other)
        QueueMuzzleShot(muzzlePos, aimFwd, camFwd, pellets);
        SetMuzzleAimState(muzzlePos, aimFwd, camFwd, true);

        if IsDefined(aimSys) {
            let traceEnd: Vector4 = muzzlePos + (aimFwd * maxRange);
            let targetPt: Vector4 = traceEnd;

            let sqs: ref<SpatialQueriesSystem> = GameInstance.GetSpatialQueriesSystem(scriptInterface.GetGame());
            if IsDefined(sqs) {
                let traceStatic: TraceResult;
                if sqs.SyncRaycastByCollisionPreset(muzzlePos, traceEnd, n"World Static", traceStatic) && TraceResult.IsValid(traceStatic) {
                    targetPt = new Vector4(traceStatic.position.X, traceStatic.position.Y, traceStatic.position.Z, 1.0);
                }
            }

            aimSys.RecordShot(muzzlePos, aimFwd, targetPt, 1, "Native PhysicalRay Redirection");
        }
    } else {
        SetMuzzleAimState(new Vector4(0.0, 0.0, 0.0, 1.0), new Vector4(0.0, 1.0, 0.0, 0.0), new Vector4(0.0, 1.0, 0.0, 0.0), false);
    }

    wrappedMethod(stateContext, scriptInterface);

    // Re-assert HMG attack record right after vanilla OnEnter has run GetDesiredAttackRecord and SetAttack
    if isDecoupledActive && (weapon.IsHeavyWeapon() || EnumInt(WeaponObject.GetWeaponType(weapon.GetItemID())) == EnumInt(gamedataItemType.Wea_HeavyMachineGun)) {
        weapon.SetAttack(t"Attacks.ExplodingBulletMediumEffect");
    }
}

// Intercept attack resolution for Heavy Machine Guns so they use the unified
// PhysicalRay game effect pipeline instead of unguided screen-center projectiles.
@wrapMethod(WeaponTransition)
protected func GetDesiredAttackRecord(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> ref<Attack_Record> {
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

// Diagnostic probe for smart weapons targeting parameters and lifecycle
@wrapMethod(CrosshairGameController_Smart_Rifl)
protected cb func OnSmartGunParams(argParams: Variant) -> Bool {
    let result: Bool = wrappedMethod(argParams);

    let aimSys: ref<DetachedAimSystem> = DetachedAimSystem.GetInstance(this.GetGame());
    if IsDefined(aimSys) {
        let smartData: ref<smartGunUIParameters> = FromVariant<ref<smartGunUIParameters>>(argParams);
        if IsDefined(smartData) {
            let numTargets: Int32 = ArraySize(smartData.targets);
            let numLocked: Int32 = 0;
            let i: Int32 = 0;
            while i < numTargets {
                if Equals(smartData.targets[i].state, gamesmartGunTargetState.Locked) {
                    numLocked += 1;
                }
                i += 1;
            }
            let root: ref<inkWidget> = this.GetRootWidget();
            let rootVis: Bool = IsDefined(root) ? root.IsVisible() : false;
            let rootOpacity: Float = IsDefined(root) ? root.GetOpacity() : 0.0;
            aimSys.RecordSmartParams(numTargets, numLocked, smartData.hasRequiredCyberware, smartData.sight.targetableRegionSize, rootVis, rootOpacity);
        }
    }

    return result;
}

@wrapMethod(CrosshairGameController_Smart_Rifl)
protected cb func OnPreIntro() -> Bool {
    let result: Bool = wrappedMethod();
    let aimSys: ref<DetachedAimSystem> = DetachedAimSystem.GetInstance(this.GetGame());
    if IsDefined(aimSys) {
        aimSys.RecordSmartPreIntro();
    }
    return result;
}



