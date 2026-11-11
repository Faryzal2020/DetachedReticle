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

    // ADS Sway & Resting Stabilization fields
    private let m_disableProceduralSway: Bool;
    private let m_adsIdleStabilize: Bool;
    private let m_adsRecoilHoriMult: Float;
    private let m_isRecoiling: Bool;
    private let m_lastShotEngineTime: Float;
    private let m_swayItemOwner: StatsObjectID;
    private let m_swayItemIdOwner: StatsObjectID;
    private let m_swayWeaponOwner: StatsObjectID;
    private let m_swayPlayerOwner: StatsObjectID;
    private let m_hasItemOwner: Bool;
    private let m_swayWeaponId: EntityID;
    private let m_hasSwayApplied: Bool;
    private let m_swayStatusLog: String;

    public func SetDisableProceduralSway(enable: Bool) -> Void {
        this.m_disableProceduralSway = enable;
        if !enable && this.m_hasSwayApplied {
            this.RemoveSwayModifiers(this.GetGameInstance());
        }
    }

    public func GetDisableProceduralSway() -> Bool {
        return this.m_disableProceduralSway;
    }

    public func SetAdsIdleStabilize(enable: Bool) -> Void {
        this.m_adsIdleStabilize = enable;
    }

    public func GetAdsIdleStabilize() -> Bool {
        return this.m_adsIdleStabilize;
    }

    public func SetAdsRecoilHoriMult(mult: Float) -> Void {
        this.m_adsRecoilHoriMult = mult;
    }

    public func GetAdsRecoilHoriMult() -> Float {
        if this.m_adsRecoilHoriMult <= 0.0001 && this.m_adsRecoilHoriMult >= -0.0001 {
            return 0.5;
        }
        return this.m_adsRecoilHoriMult;
    }

    public func GetSwayStatusLog() -> String {
        return this.m_swayStatusLog;
    }

    public func ClearSwayStatusLog() -> Void {
        this.m_swayStatusLog = "";
    }

    public func SetIsRecoiling(recoiling: Bool) -> Void {
        this.m_isRecoiling = recoiling;
    }

    public func GetIsRecoiling() -> Bool {
        return this.m_isRecoiling;
    }

    public func SetLastShotEngineTime(t: Float) -> Void {
        this.m_lastShotEngineTime = t;
    }

    public func GetLastShotEngineTime() -> Float {
        return this.m_lastShotEngineTime;
    }

    public func HasSwayApplied() -> Bool {
        return this.m_hasSwayApplied;
    }

    public func GetSwayWeaponId() -> EntityID {
        return this.m_swayWeaponId;
    }

    public func ApplySwayModifiers(game: GameInstance, weapon: ref<WeaponObject>, player: ref<PlayerPuppet>) -> Void {
        if this.m_hasSwayApplied {
            this.RemoveSwayModifiers(game);
        }
        if !IsDefined(weapon) || !IsDefined(player) {
            return;
        }
        let statsSys: ref<StatsSystem> = GameInstance.GetStatsSystem(game);
        if !IsDefined(statsSys) {
            return;
        }

        let weaOwner: StatsObjectID = Cast<StatsObjectID>(weapon.GetEntityID());
        let plyOwner: StatsObjectID = Cast<StatsObjectID>(player.GetEntityID());
        let itemIdOwner: StatsObjectID = Cast<StatsObjectID>(weapon.GetItemID());

        let itemData: ref<gameItemData> = weapon.GetItemData();
        let hasItem: Bool = IsDefined(itemData);
        let itemOwner: StatsObjectID;
        if hasItem {
            itemOwner = itemData.GetStatsObjectID();
        }

        let statsToForce: array<gamedataStatType>;
        ArrayPush(statsToForce, gamedataStatType.SwaySideMaximumAngleDistance);
        ArrayPush(statsToForce, gamedataStatType.SwaySideMinimumAngleDistance);
        ArrayPush(statsToForce, gamedataStatType.SwayCenterMaximumAngleOffset);
        ArrayPush(statsToForce, gamedataStatType.SwaySideTopAngleLimit);
        ArrayPush(statsToForce, gamedataStatType.SwaySideBottomAngleLimit);
        ArrayPush(statsToForce, gamedataStatType.Sway);
        ArrayPush(statsToForce, gamedataStatType.SwayCurvatureMaximumFactor);
        ArrayPush(statsToForce, gamedataStatType.SwayCurvatureMinimumFactor);
        ArrayPush(statsToForce, gamedataStatType.SwayInitialOffsetRandomFactor);
        ArrayPush(statsToForce, gamedataStatType.SwayStartBlendTime);

        let i: Int32 = 0;
        let count: Int32 = ArraySize(statsToForce);
        while i < count {
            let statType: gamedataStatType = statsToForce[i];
            let mod: ref<gameStatModifierData> = RPGManager.CreateStatModifier(statType, gameStatModifierType.Additive, 0.0);
            statsSys.ForceModifier(weaOwner, mod);
            statsSys.ForceModifier(plyOwner, mod);
            statsSys.ForceModifier(itemIdOwner, mod);
            if hasItem {
                statsSys.ForceModifier(itemOwner, mod);
            }
            i += 1;
        }

        this.m_swayWeaponOwner = weaOwner;
        this.m_swayPlayerOwner = plyOwner;
        this.m_swayItemIdOwner = itemIdOwner;
        this.m_hasItemOwner = hasItem;
        if hasItem {
            this.m_swayItemOwner = itemOwner;
        }
        this.m_swayWeaponId = weapon.GetEntityID();
        this.m_hasSwayApplied = true;
        this.m_swayStatusLog = "[SWAY_STATS] Applied ForceModifier(0.0) across 10 sway stats to ItemData, ItemID, Weapon, and Player.";
        FTLog("[DetachedReticle] Procedural weapon sway disabled via StatsSystem.ForceModifier.");
    }

    public func RemoveSwayModifiers(game: GameInstance) -> Void {
        if !this.m_hasSwayApplied {
            return;
        }
        let statsSys: ref<StatsSystem> = GameInstance.GetStatsSystem(game);
        if IsDefined(statsSys) {
            let statsToUnforce: array<gamedataStatType>;
            ArrayPush(statsToUnforce, gamedataStatType.SwaySideMaximumAngleDistance);
            ArrayPush(statsToUnforce, gamedataStatType.SwaySideMinimumAngleDistance);
            ArrayPush(statsToUnforce, gamedataStatType.SwayCenterMaximumAngleOffset);
            ArrayPush(statsToUnforce, gamedataStatType.SwaySideTopAngleLimit);
            ArrayPush(statsToUnforce, gamedataStatType.SwaySideBottomAngleLimit);
            ArrayPush(statsToUnforce, gamedataStatType.Sway);
            ArrayPush(statsToUnforce, gamedataStatType.SwayCurvatureMaximumFactor);
            ArrayPush(statsToUnforce, gamedataStatType.SwayCurvatureMinimumFactor);
            ArrayPush(statsToUnforce, gamedataStatType.SwayInitialOffsetRandomFactor);
            ArrayPush(statsToUnforce, gamedataStatType.SwayStartBlendTime);

            let i: Int32 = 0;
            let count: Int32 = ArraySize(statsToUnforce);
            while i < count {
                let statType: gamedataStatType = statsToUnforce[i];
                statsSys.UnforceStat(this.m_swayWeaponOwner, statType);
                statsSys.UnforceStat(this.m_swayPlayerOwner, statType);
                statsSys.UnforceStat(this.m_swayItemIdOwner, statType);
                if this.m_hasItemOwner {
                    statsSys.UnforceStat(this.m_swayItemOwner, statType);
                }
                i += 1;
            }
        }
        this.m_hasSwayApplied = false;
        this.m_hasItemOwner = false;
        this.m_swayStatusLog = "[SWAY_STATS] Unforced all sway stats: restored to vanilla.";
        FTLog("[DetachedReticle] Procedural weapon sway modifiers unforced/removed.");
    }

    public func OnWeaponUnequipped(game: GameInstance) -> Void {
        if this.m_hasSwayApplied {
            this.RemoveSwayModifiers(game);
        }
    }

    public func SetDualStabilizeWeight(w: Float) -> Void {
        this.m_dualStabilizeWeight = w;
    }

    public func GetDualStabilizeWeight() -> Float {
        return this.m_dualStabilizeWeight;
    }

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
        this.m_lastShotEngineTime = EngineTime.ToFloat(GameInstance.GetEngineTime(this.GetGameInstance()));
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

    if GameObject.IsDualWielding(player) {
        this.UpdateDualWieldAim(player, aimSys, activeWidget);
        return;
    } else {
        if IsDefined(this.m_leftCrosshair) {
            this.m_leftCrosshair.SetVisible(false);
        }
    }

    let weapon: ref<WeaponObject> = GameObject.GetRightActiveWeapon(player);
    if !IsDefined(weapon) || weapon.IsMelee() {
        if IsDefined(this.m_cameraCrosshair) { this.m_cameraCrosshair.SetVisible(false); }
        if IsDefined(activeWidget) { activeWidget.SetTranslation(new Vector2(0.0, 0.0)); }
        if IsDefined(aimSys) {
            aimSys.OnWeaponUnequipped(player.GetGame());
            aimSys.SetAimState(new Vector4(0.0, 0.0, 0.0, 0.0), new Vector4(0.0, 0.0, 0.0, 0.0), new Vector4(0.0, 0.0, 0.0, 0.0), new Vector4(0.0, 0.0, 0.0, 0.0), new Vector2(0.0, 0.0), 0.0, 0.0, 0.0, false);
        }
        return;
    }

    // Update procedural weapon sway stat modifiers if toggle is active
    if IsDefined(aimSys) {
        if aimSys.GetDisableProceduralSway() {
            if !aimSys.HasSwayApplied() || aimSys.GetSwayWeaponId() != weapon.GetEntityID() {
                aimSys.ApplySwayModifiers(player.GetGame(), weapon, player);
            }
        } else {
            if aimSys.HasSwayApplied() {
                aimSys.RemoveSwayModifiers(player.GetGame());
            }
        }
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
    let isPrecisionOrSniper: Bool = Equals(wType, gamedataItemType.Wea_PrecisionRifle) || Equals(wType, gamedataItemType.Wea_SniperRifle);

    let isRestingADS: Bool = false;
    if isAiming && !isHMG && !isPrecisionOrSniper && IsDefined(aimSys) && aimSys.GetAdsIdleStabilize() {
        let isRecoiling: Bool = aimSys.GetIsRecoiling();
        let timeSinceShot: Float = currentEngineTime - aimSys.GetLastShotEngineTime();
        if AbsF(yawLagDeg) < 0.60 && AbsF(pitchLagDeg) < 0.60 && !isRecoiling && timeSinceShot > 0.35 {
            isRestingADS = true;
        }
    }

    // Physical aim line in 3D world: raycast to find exact target impact point
    let effGunFwd: Vector4 = this.m_gunForward;
    if isAiming && !isHMG && !isPrecisionOrSniper && !isRestingADS {
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
    if isAiming && !isHMG && (isPrecisionOrSniper || isRestingADS) {
        // In ADS for precision & sniper rifles, or stabilized resting ADS: sightline convergence towards camera gaze target
        let camTargetRange: Float = 200.0;
        let camTargetEnd: Vector4 = camPos + (camFwd3 * camTargetRange);
        let camTarget: Vector4 = camTargetEnd;
        if IsDefined(sqs) {
            let camTrace: TraceResult;
            if sqs.SyncRaycastByCollisionPreset(camPos, camTargetEnd, n"World Static", camTrace) && TraceResult.IsValid(camTrace) {
                camTarget = new Vector4(camTrace.position.X, camTrace.position.Y, camTrace.position.Z, 1.0);
            }
            if sqs.SyncRaycastByCollisionPreset(camPos, camTarget, n"World Dynamic", camTrace) && TraceResult.IsValid(camTrace) {
                let dynHit: Vector4 = new Vector4(camTrace.position.X, camTrace.position.Y, camTrace.position.Z, 1.0);
                if Vector4.DistanceSquared(camPos, dynHit) < Vector4.DistanceSquared(camPos, camTarget) {
                    camTarget = dynHit;
                }
            }
        }
        let toCamTarget: Vector4 = camTarget - muzzlePos;
        let convDir: Vector4 = Vector4.Normalize(toCamTarget);
        if Vector4.Dot(convDir, camFwd3) > 0.2 {
            aimFwd = convDir;
            targetPoint = camTarget;
        }
    } else {
        // Hipfire, recoiling/moving ADS, or unstabilized ADS: physical barrel aim line
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
private func UpdateDualWieldAim(player: ref<PlayerPuppet>, aimSys: ref<DetachedAimSystem>, activeWidget: ref<inkWidget>) -> Void {
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

    let sqs: ref<SpatialQueriesSystem> = GameInstance.GetSpatialQueriesSystem(player.GetGame());
    let maxRange: Float = 100.0;

    // Camera target point in 3D world (T1)
    let camTarget: Vector4 = camPos + (camFwd3 * maxRange);
    if IsDefined(sqs) {
        let camTrace: TraceResult;
        if sqs.SyncRaycastByCollisionPreset(camPos, camTarget, n"World Static", camTrace) && TraceResult.IsValid(camTrace) {
            camTarget = new Vector4(camTrace.position.X, camTrace.position.Y, camTrace.position.Z, 1.0);
        }
    }

    // Dynamic stabilization weight towards T1 (set by CET readyWeight * dualStabilizeMax)
    let stabWeight: Float = 0.65;
    if IsDefined(aimSys) {
        stabWeight = aimSys.GetDualStabilizeWeight();
        if stabWeight < 0.0 { stabWeight = 0.0; }
        if stabWeight > 1.0 { stabWeight = 1.0; }
    }

    // --- Right Gun (Right T3 -> activeWidget) ---
    let rightAimFwd: Vector4 = camFwd3;
    let rightMuzzlePos: Vector4 = camPos;
    let rightScreenOffset: Vector2 = new Vector2(0.0, 0.0);
    if IsDefined(rightWeapon) {
        let rMuzTransform: Transform = rightWeapon.GetMuzzleSlotWorldTransform();
        let rMuzPos: Vector4 = Transform.GetPosition(rMuzTransform);
        let rMuzFwd: Vector4 = Transform.GetForward(rMuzTransform);
        if Vector4.IsZero(rMuzFwd) { rMuzFwd = rightWeapon.GetWorldForward(); }
        if Vector4.IsZero(rMuzPos) { rMuzPos = rightWeapon.GetWorldPosition(); }
        rightMuzzlePos = rMuzPos;
        let normRMuzFwd: Vector4 = Vector4.Normalize(rMuzFwd);

        // Raw physical trace target
        let rRawTarget: Vector4 = rMuzPos + (normRMuzFwd * maxRange);
        if IsDefined(sqs) {
            let rTrace: TraceResult;
            if sqs.SyncRaycastByCollisionPreset(rMuzPos, rRawTarget, n"World Static", rTrace) && TraceResult.IsValid(rTrace) {
                rRawTarget = new Vector4(rTrace.position.X, rTrace.position.Y, rTrace.position.Z, 1.0);
            }
        }

        // Screen projection of raw physical hit point
        let toRTarget: Vector4 = rRawTarget - camPos;
        let toRDir: Vector4 = Vector4.Normalize(toRTarget);
        if Vector4.Dot(toRDir, camFwd3) > 0.05 {
            let rProj: Vector2 = this.ProjectWorldToScreen(rRawTarget);
            rightScreenOffset = new Vector2(rootSize.X * 0.5 * rProj.X, -rootSize.Y * 0.5 * rProj.Y);
        }

        // Artificially stabilize T3 towards T1 (camera center)
        let stabOffsetR: Vector2 = new Vector2(rightScreenOffset.X * (1.0 - stabWeight), rightScreenOffset.Y * (1.0 - stabWeight));
        if IsDefined(activeWidget) {
            activeWidget.SetVisible(true);
            activeWidget.SetTranslation(stabOffsetR);
        }

        // Converged aim direction for ballistics
        let rConvDir: Vector4 = Vector4.Normalize(camTarget - rMuzPos);
        rightAimFwd = Vector4.Normalize(normRMuzFwd * (1.0 - stabWeight) + rConvDir * stabWeight);
    } else if IsDefined(activeWidget) {
        activeWidget.SetVisible(false);
    }

    // --- Left Gun (Left T3 -> m_leftCrosshair) ---
    let leftAimFwd: Vector4 = camFwd3;
    let leftMuzzlePos: Vector4 = camPos;
    let leftScreenOffset: Vector2 = new Vector2(0.0, 0.0);
    if IsDefined(leftWeapon) {
        let lMuzTransform: Transform = leftWeapon.GetMuzzleSlotWorldTransform();
        let lMuzPos: Vector4 = Transform.GetPosition(lMuzTransform);
        let lMuzFwd: Vector4 = Transform.GetForward(lMuzTransform);
        if Vector4.IsZero(lMuzFwd) { lMuzFwd = leftWeapon.GetWorldForward(); }
        if Vector4.IsZero(lMuzPos) { lMuzPos = leftWeapon.GetWorldPosition(); }
        leftMuzzlePos = lMuzPos;
        let normLMuzFwd: Vector4 = Vector4.Normalize(lMuzFwd);

        // Raw physical trace target
        let lRawTarget: Vector4 = lMuzPos + (normLMuzFwd * maxRange);
        if IsDefined(sqs) {
            let lTrace: TraceResult;
            if sqs.SyncRaycastByCollisionPreset(lMuzPos, lRawTarget, n"World Static", lTrace) && TraceResult.IsValid(lTrace) {
                lRawTarget = new Vector4(lTrace.position.X, lTrace.position.Y, lTrace.position.Z, 1.0);
            }
        }

        // Screen projection of raw physical hit point
        let toLTarget: Vector4 = lRawTarget - camPos;
        let toLDir: Vector4 = Vector4.Normalize(toLTarget);
        if Vector4.Dot(toLDir, camFwd3) > 0.05 {
            let lProj: Vector2 = this.ProjectWorldToScreen(lRawTarget);
            leftScreenOffset = new Vector2(rootSize.X * 0.5 * lProj.X, -rootSize.Y * 0.5 * lProj.Y);
        }

        // Artificially stabilize T3 towards T1 (camera center)
        let stabOffsetL: Vector2 = new Vector2(leftScreenOffset.X * (1.0 - stabWeight), leftScreenOffset.Y * (1.0 - stabWeight));
        if IsDefined(this.m_leftCrosshair) {
            this.m_leftCrosshair.SetVisible(true);
            this.m_leftCrosshair.SetTranslation(stabOffsetL);
        }

        // Converged aim direction for ballistics
        let lConvDir: Vector4 = Vector4.Normalize(camTarget - lMuzPos);
        leftAimFwd = Vector4.Normalize(normLMuzFwd * (1.0 - stabWeight) + lConvDir * stabWeight);
    } else if IsDefined(this.m_leftCrosshair) {
        this.m_leftCrosshair.SetVisible(false);
    }

    if IsDefined(aimSys) {
        aimSys.SetAimState(rightAimFwd, camTarget, rightMuzzlePos, camFwd3, rightScreenOffset, 0.0, 0.0, 0.0, true);
        aimSys.SetDualAimState(leftAimFwd, leftMuzzlePos, leftScreenOffset);
    }

    // Default shooting hook standby state set to right weapon (overridden per shot in ShootEvents.OnEnter)
    SetMuzzleAimState(rightMuzzlePos, rightAimFwd, camFwd3, true);
}

// In ShootEvents.OnEnter, SetMuzzleAimState prepares the physical muzzle trajectory
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
        if IsDefined(camSys) && camSys.GetActiveCameraWorldTransform(camTransform) {
            camFwd = Vector4.Normalize(Transform.GetForward(camTransform));
        }

        let aimFwd: Vector4 = normMuzzleFwd;
        let isDual: Bool = GameObject.IsDualWielding(player);
        if isDual {
            let stabWeight: Float = IsDefined(aimSys) ? aimSys.GetDualStabilizeWeight() : 0.65;
            if stabWeight > 0.001 {
                let sqs: ref<SpatialQueriesSystem> = GameInstance.GetSpatialQueriesSystem(scriptInterface.GetGame());
                let camPos: Vector4 = new Vector4(0.0, 0.0, 0.0, 1.0);
                if IsDefined(camSys) && camSys.GetActiveCameraWorldTransform(camTransform) {
                    camPos = Transform.GetPosition(camTransform);
                }
                let camTarget: Vector4 = camPos + (camFwd * 100.0);
                if IsDefined(sqs) {
                    let camTrace: TraceResult;
                    if sqs.SyncRaycastByCollisionPreset(camPos, camTarget, n"World Static", camTrace) && TraceResult.IsValid(camTrace) {
                        camTarget = new Vector4(camTrace.position.X, camTrace.position.Y, camTrace.position.Z, 1.0);
                    }
                }
                let convDir: Vector4 = Vector4.Normalize(camTarget - muzzlePos);
                aimFwd = Vector4.Normalize(normMuzzleFwd * (1.0 - stabWeight) + convDir * stabWeight);
            }
        } else {
            let isAiming: Bool = false;
            let wType: gamedataItemType = WeaponObject.GetWeaponType(weapon.GetItemID());
            let isHMG: Bool = weapon.IsHeavyWeapon() || Equals(wType, gamedataItemType.Wea_HeavyMachineGun);
            let isPrecisionOrSniper: Bool = Equals(wType, gamedataItemType.Wea_PrecisionRifle) || Equals(wType, gamedataItemType.Wea_SniperRifle);
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

            let isRestingADS: Bool = false;
            let curEngineTime: Float = EngineTime.ToFloat(GameInstance.GetEngineTime(scriptInterface.GetGame()));
            if isAiming && !isHMG && !isPrecisionOrSniper && IsDefined(aimSys) && aimSys.GetAdsIdleStabilize() {
                let isRecoiling: Bool = aimSys.GetIsRecoiling();
                let prevShotTime: Float = aimSys.GetLastShotEngineTime();
                let timeSinceShot: Float = curEngineTime - prevShotTime;
                let camRight: Vector4 = Transform.GetRight(camTransform);
                let camUp: Vector4 = Transform.GetUp(camTransform);
                let dx: Float = Vector4.Dot(normMuzzleFwd, camRight);
                let dy: Float = Vector4.Dot(normMuzzleFwd, camUp);
                let dz: Float = Vector4.Dot(normMuzzleFwd, camFwd);
                let yawLag: Float = Rad2Deg(AtanF(dx, dz));
                let pitchLag: Float = Rad2Deg(AtanF(dy, dz));
                if AbsF(yawLag) < 0.60 && AbsF(pitchLag) < 0.60 && !isRecoiling && timeSinceShot > 0.35 {
                    isRestingADS = true;
                }
            }

            if isAiming && !isHMG && (isPrecisionOrSniper || isRestingADS) {
                let sqs: ref<SpatialQueriesSystem> = GameInstance.GetSpatialQueriesSystem(scriptInterface.GetGame());
                let camPos: Vector4 = new Vector4(0.0, 0.0, 0.0, 1.0);
                if IsDefined(camSys) && camSys.GetActiveCameraWorldTransform(camTransform) {
                    camPos = Transform.GetPosition(camTransform);
                }
                let attackRecord: ref<Attack_Record> = this.GetDesiredAttackRecord(stateContext, scriptInterface);
                let maxRange: Float = IsDefined(attackRecord) ? attackRecord.Range() : 200.0;
                if maxRange <= 0.0 {
                    maxRange = 200.0;
                }
                let camTarget: Vector4 = camPos + (camFwd * maxRange);
                if IsDefined(sqs) {
                    let camTrace: TraceResult;
                    if sqs.SyncRaycastByCollisionPreset(camPos, camTarget, n"World Static", camTrace) && TraceResult.IsValid(camTrace) {
                        camTarget = new Vector4(camTrace.position.X, camTrace.position.Y, camTrace.position.Z, 1.0);
                    }
                    if sqs.SyncRaycastByCollisionPreset(camPos, camTarget, n"World Dynamic", camTrace) && TraceResult.IsValid(camTrace) {
                        let dynHit: Vector4 = new Vector4(camTrace.position.X, camTrace.position.Y, camTrace.position.Z, 1.0);
                        if Vector4.DistanceSquared(camPos, dynHit) < Vector4.DistanceSquared(camPos, camTarget) {
                            camTarget = dynHit;
                        }
                    }
                }
                let toCamTarget: Vector4 = camTarget - muzzlePos;
                let convDir: Vector4 = Vector4.Normalize(toCamTarget);
                if Vector4.Dot(convDir, camFwd) > 0.2 {
                    aimFwd = convDir;
                }
            } else if isAiming && !isHMG && !isPrecisionOrSniper {
                let horiMult: Float = IsDefined(aimSys) ? aimSys.GetAdsRecoilHoriMult() : 0.5;
                let adsHoriYawDeg: Float = DR_GetRecoilYaw() * horiMult;
                if AbsF(adsHoriYawDeg) > 0.001 {
                    let camRight: Vector4 = Transform.GetRight(camTransform);
                    aimFwd = Vector4.Normalize(normMuzzleFwd + camRight * TanF(Deg2Rad(adsHoriYawDeg)));
                } else {
                    aimFwd = normMuzzleFwd;
                }
            }
        }

        // Feed exact physical aim state to native C++ ShootingHook
        SetMuzzleAimState(muzzlePos, aimFwd, camFwd, true);

        if IsDefined(aimSys) {
            aimSys.SetLastShotEngineTime(EngineTime.ToFloat(GameInstance.GetEngineTime(scriptInterface.GetGame())));
            let attackRecord: ref<Attack_Record> = this.GetDesiredAttackRecord(stateContext, scriptInterface);
            let maxRange: Float = IsDefined(attackRecord) ? attackRecord.Range() : 200.0;
            if maxRange <= 0.0 {
                maxRange = 200.0;
            }
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



