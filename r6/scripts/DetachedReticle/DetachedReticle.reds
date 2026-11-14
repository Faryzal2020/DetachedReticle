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
    private let m_leftTargetPoint: Vector4;
    private let m_leftScreenOffset: Vector2;
    private let m_isDualWield: Bool;
    private let m_loggedWeaponTick: Bool;
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
    public func GetLeftTargetPoint() -> Vector4 { return this.m_leftTargetPoint; }
    public func GetLeftScreenOffset() -> Vector2 { return this.m_leftScreenOffset; }
    public func IsDualWieldActive() -> Bool { return this.m_isDualWield; }

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

    public func SetWorldAimState(gunFwd: Vector4, targetPt: Vector4, muzzlePos: Vector4, camPos: Vector4, camFwd: Vector4, muzRelCam: Vector4, angleLagDeg: Float, yawLagDeg: Float, pitchLagDeg: Float, isDetached: Bool) -> Void {
        this.m_gunForward = gunFwd;
        this.m_targetPoint = targetPt;
        this.m_muzzlePos = muzzlePos;
        this.m_cameraPos = camPos;
        this.m_cameraForward = camFwd;
        this.m_muzzleRelCam = muzRelCam;
        this.m_angleLagDeg = angleLagDeg;
        this.m_yawLagDeg = yawLagDeg;
        this.m_pitchLagDeg = pitchLagDeg;
        this.m_isDetachedActive = isDetached;
    }

    public func SetScreenOffsets(screenOffset: Vector2, muzScreen: Vector2, leftScreenOffset: Vector2) -> Void {
        this.m_screenOffset = screenOffset;
        this.m_muzzleScreen = muzScreen;
        this.m_leftScreenOffset = leftScreenOffset;
    }

    public func ResolveMuzzleTransform(weapon: ref<WeaponObject>, out muzPos: Vector4, out muzFwd: Vector4) -> Void {
        let muzTransform: Transform = weapon.GetMuzzleSlotWorldTransform();
        muzPos = Transform.GetPosition(muzTransform);
        muzFwd = Transform.GetForward(muzTransform);
        if Vector4.IsZero(muzFwd) {
            muzFwd = weapon.GetWorldForward();
        }
        if Vector4.IsZero(muzPos) {
            muzPos = weapon.GetWorldPosition();
        }
        muzFwd = Vector4.Normalize(muzFwd);
    }

    private func MeasureCamRelativeAngles(dir: Vector4, camFwd3: Vector4, camRight: Vector4, camUp: Vector4, clampDz: Bool, out yawDeg: Float, out pitchDeg: Float) -> Void {
        let dx: Float = Vector4.Dot(dir, camRight);
        let dy: Float = Vector4.Dot(dir, camUp);
        let dz: Float = Vector4.Dot(dir, camFwd3);
        if clampDz {
            dz = MaxF(0.05, dz);
        }
        yawDeg = Rad2Deg(AtanF(dx, dz));
        pitchDeg = Rad2Deg(AtanF(dy, dz));
    }

    private func RaycastTarget(sqs: ref<SpatialQueriesSystem>, origin: Vector4, endPos: Vector4, checkDynamic: Bool) -> Vector4 {
        let bestPt: Vector4 = endPos;
        if !IsDefined(sqs) {
            return bestPt;
        }
        let trace: TraceResult;
        if sqs.SyncRaycastByCollisionPreset(origin, endPos, n"World Static", trace, true) && TraceResult.IsValid(trace) {
            bestPt = new Vector4(trace.position.X, trace.position.Y, trace.position.Z, 1.0);
        }
        if checkDynamic {
            if sqs.SyncRaycastByCollisionPreset(origin, bestPt, n"World Dynamic", trace) && TraceResult.IsValid(trace) {
                let dynHit: Vector4 = new Vector4(trace.position.X, trace.position.Y, trace.position.Z, 1.0);
                if Vector4.DistanceSquared(origin, dynHit) < Vector4.DistanceSquared(origin, bestPt) {
                    bestPt = dynHit;
                }
            }
        }
        return bestPt;
    }

    public func ConvergeFromTarget(muzzlePos: Vector4, targetPt: Vector4, fallbackDir: Vector4) -> Vector4 {
        let convDir: Vector4 = Vector4.Normalize(targetPt - muzzlePos);
        if Vector4.Dot(convDir, fallbackDir) > 0.2 {
            return convDir;
        }
        return fallbackDir;
    }

    public func ComputeDualVirtualFwd(muzFwd: Vector4, camFwd3: Vector4, camRight: Vector4, camUp: Vector4, isLeftHand: Bool, stabWeight: Float, out gunYaw: Float, out gunPitch: Float, out effYaw: Float, out effPitch: Float) -> Vector4 {
        this.MeasureCamRelativeAngles(muzFwd, camFwd3, camRight, camUp, true, gunYaw, gunPitch);
        let baseYaw: Float = isLeftHand ? this.m_leftBaseYaw : this.m_rightBaseYaw;
        let basePitch: Float = isLeftHand ? this.m_leftBasePitch : this.m_rightBasePitch;
        effYaw = gunYaw - (stabWeight * baseYaw);
        effPitch = gunPitch - (stabWeight * basePitch);
        return Vector4.Normalize(camFwd3 + (camRight * TanF(Deg2Rad(effYaw))) + (camUp * TanF(Deg2Rad(effPitch))));
    }

    public func ClearDetachedAim() -> Void {
        let zero4: Vector4 = new Vector4(0.0, 0.0, 0.0, 0.0);
        let zero2: Vector2 = new Vector2(0.0, 0.0);
        this.m_isDualWield = false;
        this.m_leftTargetPoint = zero4;
        this.m_leftScreenOffset = zero2;
        this.ResetDualSettled();
        this.SetAimState(zero4, zero4, zero4, zero4, zero2, 0.0, 0.0, 0.0, false);
        SetMuzzleAimState(new Vector4(0.0, 0.0, 0.0, 1.0), new Vector4(0.0, 1.0, 0.0, 0.0), new Vector4(0.0, 1.0, 0.0, 0.0), false);
    }

    // Executed strictly on the Main Thread via CET onUpdate (CRunningState::OnTick)
    // so SyncRaycastByCollisionPreset never runs concurrently from redDispatcher inkAnim callbacks.
    public func UpdateWorldAim(player: ref<PlayerPuppet>, dt: Float) -> Void {
        if !IsDefined(player) {
            this.ClearDetachedAim();
            return;
        }

        let safeDt: Float = (dt > 0.0001 && dt <= 0.2) ? dt : (1.0 / 60.0);

        if GameObject.IsDualWielding(player) {
            this.UpdateWorldAimDual(player, safeDt);
            return;
        }

        this.m_isDualWield = false;
        this.ResetDualSettled();

        let weapon: ref<WeaponObject> = GameObject.GetRightActiveWeapon(player);
        if !IsDefined(weapon) || weapon.IsMelee() {
            this.ClearDetachedAim();
            return;
        }

        let isSmartWeapon: Bool = Equals(RPGManager.GetWeaponEvolution(weapon.GetItemID()), gamedataWeaponEvolution.Smart);
        if isSmartWeapon {
            let zero4: Vector4 = new Vector4(0.0, 0.0, 0.0, 0.0);
            let camTransform: Transform;
            let camSys: ref<CameraSystem> = GameInstance.GetCameraSystem(player.GetGame());
            let camFwd3: Vector4 = new Vector4(0.0, 1.0, 0.0, 0.0);
            if IsDefined(camSys) && camSys.GetActiveCameraWorldTransform(camTransform) {
                camFwd3 = Vector4.Normalize(Transform.GetForward(camTransform));
            }
            this.SetAimState(camFwd3, zero4, zero4, camFwd3, new Vector2(0.0, 0.0), 0.0, 0.0, 0.0, false);
            SetMuzzleAimState(new Vector4(0.0, 0.0, 0.0, 1.0), new Vector4(0.0, 1.0, 0.0, 0.0), new Vector4(0.0, 1.0, 0.0, 0.0), false);
            return;
        }

        if !this.m_loggedWeaponTick {
            FTLog("[DetachedReticle] Active ranged weapon equipped: " + TDBID.ToStringDEBUG(ItemID.GetTDBID(weapon.GetItemID())) + " | Decoupled Gun Reticle active.");
            this.m_loggedWeaponTick = true;
        }

        let camTransform: Transform;
        let camSys: ref<CameraSystem> = GameInstance.GetCameraSystem(player.GetGame());
        if !IsDefined(camSys) || !camSys.GetActiveCameraWorldTransform(camTransform) {
            return;
        }

        let camPos: Vector4 = Transform.GetPosition(camTransform);
        let camFwd3: Vector4 = Vector4.Normalize(Transform.GetForward(camTransform));
        if Vector4.IsZero(camFwd3) {
            return;
        }
        let camRight: Vector4 = Transform.GetRight(camTransform);
        let camUp: Vector4 = Transform.GetUp(camTransform);

        let muzzlePos: Vector4;
        let gunFwd: Vector4;
        this.ResolveMuzzleTransform(weapon, muzzlePos, gunFwd);

        let yawLagDeg: Float = 0.0;
        let pitchLagDeg: Float = 0.0;
        this.MeasureCamRelativeAngles(gunFwd, camFwd3, camRight, camUp, false, yawLagDeg, pitchLagDeg);

        let isAiming: Bool = false;
        let psmBB: ref<IBlackboard> = player.GetPlayerStateMachineBlackboard();
        if IsDefined(psmBB) {
            let upperBody: Int32 = psmBB.GetInt(GetAllBlackboardDefs().PlayerStateMachine.UpperBody);
            let crosshair: Int32 = psmBB.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Crosshair);
            isAiming = upperBody == EnumInt(gamePSMUpperBodyStates.Aim) || crosshair == EnumInt(gamePSMCrosshairStates.Aim);
        }
        let wType: gamedataItemType = WeaponObject.GetWeaponType(weapon.GetItemID());
        let isHMG: Bool = weapon.IsHeavyWeapon() || Equals(wType, gamedataItemType.Wea_HeavyMachineGun);

        let effGunFwd: Vector4 = gunFwd;
        if isAiming && !isHMG {
            let adsHoriYawDeg: Float = DR_GetRecoilYaw() * this.GetAdsRecoilHoriMult();
            if AbsF(adsHoriYawDeg) > 0.001 {
                effGunFwd = Vector4.Normalize(gunFwd + camRight * TanF(Deg2Rad(adsHoriYawDeg)));
            }
        }

        let sqs: ref<SpatialQueriesSystem> = GameInstance.GetSpatialQueriesSystem(player.GetGame());
        let targetPoint: Vector4;
        let aimFwd: Vector4 = effGunFwd;
        if isAiming && !isHMG {
            let sightTargetEnd: Vector4 = camPos + (effGunFwd * 200.0);
            targetPoint = this.RaycastTarget(sqs, camPos, sightTargetEnd, true);
            aimFwd = this.ConvergeFromTarget(muzzlePos, targetPoint, effGunFwd);
        } else {
            let traceEnd: Vector4 = muzzlePos + (effGunFwd * 100.0);
            targetPoint = this.RaycastTarget(sqs, muzzlePos, traceEnd, false);
        }

        let toTargetDir: Vector4 = Vector4.Normalize(targetPoint - camPos);
        let dotCam: Float = Vector4.Dot(toTargetDir, camFwd3);
        let angleDeg: Float = Rad2Deg(AcosF(ClampF(dotCam, -1.0, 1.0)));

        let toMuzzle: Vector4 = muzzlePos - camPos;
        let muzRelCam: Vector4 = new Vector4(
            Vector4.Dot(toMuzzle, camRight),
            Vector4.Dot(toMuzzle, camFwd3),
            Vector4.Dot(toMuzzle, camUp),
            1.0
        );

        this.SetWorldAimState(effGunFwd, targetPoint, muzzlePos, camPos, camFwd3, muzRelCam, angleDeg, yawLagDeg, pitchLagDeg, true);
        SetMuzzleAimState(muzzlePos, aimFwd, camFwd3, true);
    }

    private func UpdateWorldAimDual(player: ref<PlayerPuppet>, dt: Float) -> Void {
        let rightWeapon: ref<WeaponObject> = GameObject.GetRightActiveWeapon(player);
        let leftWeapon: ref<WeaponObject> = GameObject.GetLeftActiveWeapon(player);

        if !IsDefined(rightWeapon) && !IsDefined(leftWeapon) {
            this.ClearDetachedAim();
            return;
        }

        let camTransform: Transform;
        let camSys: ref<CameraSystem> = GameInstance.GetCameraSystem(player.GetGame());
        if !IsDefined(camSys) || !camSys.GetActiveCameraWorldTransform(camTransform) {
            return;
        }

        let camPos: Vector4 = Transform.GetPosition(camTransform);
        let camFwd3: Vector4 = Vector4.Normalize(Transform.GetForward(camTransform));
        if Vector4.IsZero(camFwd3) {
            return;
        }
        let camRight: Vector4 = Transform.GetRight(camTransform);
        let camUp: Vector4 = Transform.GetUp(camTransform);

        let isAiming: Bool = false;
        let psmBB: ref<IBlackboard> = player.GetPlayerStateMachineBlackboard();
        if IsDefined(psmBB) {
            let upperBody: Int32 = psmBB.GetInt(GetAllBlackboardDefs().PlayerStateMachine.UpperBody);
            let crosshair: Int32 = psmBB.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Crosshair);
            isAiming = upperBody == EnumInt(gamePSMUpperBodyStates.Aim) || crosshair == EnumInt(gamePSMCrosshairStates.Aim);
        }

        let rYaw: Float = DR_GetResidualYaw();
        let rPitch: Float = DR_GetResidualPitch();
        let isRecoiling: Bool = (AbsF(DR_GetRecoilYaw()) + AbsF(DR_GetRecoilPitch())) > 0.02;
        let stabWeight: Float = ClampF(this.m_dualStabilizeWeight, 0.0, 1.0);

        let rMuzPos: Vector4 = camPos;
        let rMuzFwd: Vector4 = camFwd3;
        let rGunYaw: Float = 0.0;
        let rGunPitch: Float = 0.0;
        let rRelYaw: Float = 0.0;
        let rRelPitch: Float = 0.0;
        if IsDefined(rightWeapon) {
            this.ResolveMuzzleTransform(rightWeapon, rMuzPos, rMuzFwd);
            this.MeasureCamRelativeAngles(rMuzFwd, camFwd3, camRight, camUp, true, rGunYaw, rGunPitch);
            rRelYaw = rGunYaw - rYaw;
            rRelPitch = rGunPitch + rPitch;
        }

        let lMuzPos: Vector4 = camPos;
        let lMuzFwd: Vector4 = camFwd3;
        let lGunYaw: Float = 0.0;
        let lGunPitch: Float = 0.0;
        let lRelYaw: Float = 0.0;
        let lRelPitch: Float = 0.0;
        if IsDefined(leftWeapon) {
            this.ResolveMuzzleTransform(leftWeapon, lMuzPos, lMuzFwd);
            this.MeasureCamRelativeAngles(lMuzFwd, camFwd3, camRight, camUp, true, lGunYaw, lGunPitch);
            lRelYaw = lGunYaw - rYaw;
            lRelPitch = lGunPitch + rPitch;
        }

        this.UpdateDualBaseOffsets(rRelYaw, rRelPitch, lRelYaw, lRelPitch, isAiming, isRecoiling, stabWeight, dt);

        let sqs: ref<SpatialQueriesSystem> = GameInstance.GetSpatialQueriesSystem(player.GetGame());
        let sightRange: Float = 200.0;

        let rightAimFwd: Vector4 = camFwd3;
        let rightTargetPt: Vector4 = camPos + (camFwd3 * sightRange);
        let rEffYaw: Float = 0.0;
        let rEffPitch: Float = 0.0;
        let rAngleDeg: Float = 0.0;
        if IsDefined(rightWeapon) {
            let unusedYaw: Float = 0.0;
            let unusedPitch: Float = 0.0;
            let rEffFwd: Vector4 = this.ComputeDualVirtualFwd(rMuzFwd, camFwd3, camRight, camUp, false, stabWeight, unusedYaw, unusedPitch, rEffYaw, rEffPitch);
            let rSightOrigin: Vector4 = (rMuzPos * (1.0 - stabWeight)) + (camPos * stabWeight);
            rSightOrigin.W = 1.0;
            rightTargetPt = this.RaycastTarget(sqs, rSightOrigin, rSightOrigin + (rEffFwd * sightRange), true);
            rightAimFwd = this.ConvergeFromTarget(rMuzPos, rightTargetPt, rEffFwd);

            let toRDir: Vector4 = Vector4.Normalize(rightTargetPt - camPos);
            let dotRCam: Float = Vector4.Dot(toRDir, camFwd3);
            rAngleDeg = Rad2Deg(AcosF(ClampF(dotRCam, -1.0, 1.0)));
        }

        let leftAimFwd: Vector4 = camFwd3;
        let leftTargetPt: Vector4 = camPos + (camFwd3 * sightRange);
        if IsDefined(leftWeapon) {
            let unusedYawL: Float = 0.0;
            let unusedPitchL: Float = 0.0;
            let lEffYaw: Float = 0.0;
            let lEffPitch: Float = 0.0;
            let lEffFwd: Vector4 = this.ComputeDualVirtualFwd(lMuzFwd, camFwd3, camRight, camUp, true, stabWeight, unusedYawL, unusedPitchL, lEffYaw, lEffPitch);
            let lSightOrigin: Vector4 = (lMuzPos * (1.0 - stabWeight)) + (camPos * stabWeight);
            lSightOrigin.W = 1.0;
            leftTargetPt = this.RaycastTarget(sqs, lSightOrigin, lSightOrigin + (lEffFwd * sightRange), true);
            leftAimFwd = this.ConvergeFromTarget(lMuzPos, leftTargetPt, lEffFwd);
        }

        this.m_isDualWield = true;
        this.m_leftGunForward = leftAimFwd;
        this.m_leftMuzzlePos = lMuzPos;
        this.m_leftTargetPoint = leftTargetPt;
        this.SetWorldAimState(rightAimFwd, rightTargetPt, rMuzPos, camPos, camFwd3, new Vector4(0.0, 0.0, 0.0, 1.0), rAngleDeg, rEffYaw, rEffPitch, true);
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
private func GetRootCanvasSize() -> Vector2 {
    let rootCanvas: ref<inkCanvas> = this.m_rootWidget;
    if !IsDefined(rootCanvas) {
        rootCanvas = this.GetRootWidget() as inkCanvas;
    }
    let rootSize: Vector2 = IsDefined(rootCanvas) ? rootCanvas.GetSize() : new Vector2(3840.0, 2160.0);
    if rootSize.X <= 0.0 || rootSize.Y <= 0.0 {
        rootSize = new Vector2(3840.0, 2160.0);
    }
    return rootSize;
}

@addMethod(gameuiCrosshairContainerController)
private func ProjectToScreenOffset(worldPt: Vector4, rootSize: Vector2) -> Vector2 {
    let proj: Vector2 = this.ProjectWorldToScreen(worldPt);
    return new Vector2(rootSize.X * 0.5 * proj.X, -rootSize.Y * 0.5 * proj.Y);
}

@addMethod(gameuiCrosshairContainerController)
private func TryProjectScreenOffset(worldPt: Vector4, camPos: Vector4, camFwd3: Vector4, rootSize: Vector2, out screenOffset: Vector2) -> Bool {
    let toTargetDir: Vector4 = Vector4.Normalize(worldPt - camPos);
    if Vector4.Dot(toTargetDir, camFwd3) > 0.05 {
        screenOffset = this.ProjectToScreenOffset(worldPt, rootSize);
        return true;
    }
    screenOffset = new Vector2(0.0, 0.0);
    return false;
}

@addMethod(gameuiCrosshairContainerController)
private func UpdateDetachedAim() -> Void {
    let player: ref<PlayerPuppet> = this.m_Player;
    if !IsDefined(player) {
        player = this.GetPlayerControlledObject() as PlayerPuppet;
    }
    let activeWidget: ref<inkWidget> = this.GetActiveCrosshairWidget();
    if !IsDefined(player) {
        if IsDefined(this.m_cameraCrosshair) { this.m_cameraCrosshair.SetVisible(false); }
        if IsDefined(this.m_leftCrosshair) { this.m_leftCrosshair.SetVisible(false); }
        return;
    }

    let aimSys: ref<DetachedAimSystem> = DetachedAimSystem.GetInstance(player.GetGame());
    if !IsDefined(aimSys) || !aimSys.IsDetachedActive() {
        if IsDefined(this.m_cameraCrosshair) { this.m_cameraCrosshair.SetVisible(false); }
        if IsDefined(this.m_leftCrosshair) { this.m_leftCrosshair.SetVisible(false); }
        if IsDefined(activeWidget) {
            activeWidget.SetTranslation(new Vector2(0.0, 0.0));
        }
        let weapon: ref<WeaponObject> = GameObject.GetRightActiveWeapon(player);
        if IsDefined(aimSys) && IsDefined(weapon) && Equals(RPGManager.GetWeaponEvolution(weapon.GetItemID()), gamedataWeaponEvolution.Smart) {
            let activeCtrl: ref<gameuiCrosshairBaseGameController> = this.GetActiveCrosshairGameController();
            let ctrlClassStr: String = IsDefined(activeCtrl) ? NameToString(activeCtrl.GetClassName()) : "NULL";
            let widgetNameStr: String = IsDefined(activeWidget) ? NameToString(activeWidget.GetName()) : "NULL";
            let expectedXhairStr: String = TDBID.ToStringDEBUG(TweakDBInterface.GetItemRecord(ItemID.GetTDBID(weapon.GetItemID())).Crosshair().GetID());
            aimSys.RecordSmartUIIdentity(ctrlClassStr, widgetNameStr, expectedXhairStr);
        }
        return;
    }

    // Frame Delta Time calculation for periodic telemetry throttling
    let currentEngineTime: Float = EngineTime.ToFloat(GameInstance.GetEngineTime(player.GetGame()));
    let dt: Float = (this.m_lastEngineTime > 0.0) ? (currentEngineTime - this.m_lastEngineTime) : (1.0 / 60.0);
    this.m_lastEngineTime = currentEngineTime;
    if dt <= 0.0001 || dt > 0.2 {
        dt = 1.0 / 60.0;
    }

    let camPos: Vector4 = aimSys.GetCameraPos();
    let camFwd3: Vector4 = aimSys.GetCameraForward();
    if Vector4.IsZero(camFwd3) {
        return;
    }

    let rootSize: Vector2 = this.GetRootCanvasSize();
    if aimSys.IsDualWieldActive() {
        this.UpdateDualWieldAim(player, aimSys, activeWidget, camPos, camFwd3, rootSize);
        return;
    }

    if IsDefined(this.m_leftCrosshair) {
        this.m_leftCrosshair.SetVisible(false);
    }

    // Read main-thread cached target point and muzzle position; UI tick only projects & translates widgets.
    let targetPoint: Vector4 = aimSys.GetTargetPoint();
    let muzzlePos: Vector4 = aimSys.GetMuzzlePos();
    let screenOffset: Vector2;
    if this.TryProjectScreenOffset(targetPoint, camPos, camFwd3, rootSize, screenOffset) {
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

    let muzScreen: Vector2 = this.ProjectToScreenOffset(muzzlePos, rootSize);
    aimSys.SetScreenOffsets(screenOffset, muzScreen, new Vector2(0.0, 0.0));

    // Periodic telemetry log (every 3 seconds or during large divergence)
    let angleDeg: Float = aimSys.GetAngleLagDeg();
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
private func UpdateDualWieldAim(player: ref<PlayerPuppet>, aimSys: ref<DetachedAimSystem>, activeWidget: ref<inkWidget>, camPos: Vector4, camFwd3: Vector4, rootSize: Vector2) -> Void {
    let rightWeapon: ref<WeaponObject> = GameObject.GetRightActiveWeapon(player);
    let leftWeapon: ref<WeaponObject> = GameObject.GetLeftActiveWeapon(player);

    if !IsDefined(rightWeapon) && !IsDefined(leftWeapon) {
        if IsDefined(this.m_cameraCrosshair) { this.m_cameraCrosshair.SetVisible(false); }
        if IsDefined(this.m_leftCrosshair) { this.m_leftCrosshair.SetVisible(false); }
        if IsDefined(activeWidget) { activeWidget.SetTranslation(new Vector2(0.0, 0.0)); }
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

    let rightScreenOffset: Vector2 = new Vector2(0.0, 0.0);
    if IsDefined(rightWeapon) && this.TryProjectScreenOffset(aimSys.GetTargetPoint(), camPos, camFwd3, rootSize, rightScreenOffset) {
        if IsDefined(activeWidget) {
            activeWidget.SetVisible(true);
            activeWidget.SetTranslation(rightScreenOffset);
        }
    } else if IsDefined(activeWidget) {
        activeWidget.SetVisible(false);
    }

    let leftScreenOffset: Vector2 = new Vector2(0.0, 0.0);
    if IsDefined(leftWeapon) && this.TryProjectScreenOffset(aimSys.GetLeftTargetPoint(), camPos, camFwd3, rootSize, leftScreenOffset) {
        if IsDefined(this.m_leftCrosshair) {
            this.m_leftCrosshair.SetVisible(true);
            this.m_leftCrosshair.SetTranslation(leftScreenOffset);
        }
    } else if IsDefined(this.m_leftCrosshair) {
        this.m_leftCrosshair.SetVisible(false);
    }

    aimSys.SetScreenOffsets(rightScreenOffset, new Vector2(0.0, 0.0), leftScreenOffset);
}

// In ShootEvents.OnEnter, QueueMuzzleShot & SetMuzzleAimState prepare the physical muzzle trajectory
// before the vanilla shooting pipeline runs. PhysicalRay callsites are intercepted natively.
@wrapMethod(ShootEvents)
protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
    let weapon: ref<WeaponObject> = this.GetWeaponObject(scriptInterface);
    let player: ref<PlayerPuppet> = scriptInterface.executionOwner as PlayerPuppet;
    let isSmartWeapon: Bool = IsDefined(weapon) && Equals(RPGManager.GetWeaponEvolution(weapon.GetItemID()), gamedataWeaponEvolution.Smart);
    let aimSys: ref<DetachedAimSystem> = DetachedAimSystem.GetInstance(scriptInterface.GetGame());
    let isDecoupledActive: Bool = IsDefined(player) && IsDefined(weapon) && !weapon.IsMelee() && !isSmartWeapon && IsDefined(aimSys);

    if isDecoupledActive {
        let muzzlePos: Vector4;
        let normMuzzleFwd: Vector4;
        aimSys.ResolveMuzzleTransform(weapon, muzzlePos, normMuzzleFwd);

        let camTransform: Transform;
        let camSys: ref<CameraSystem> = GameInstance.GetCameraSystem(scriptInterface.GetGame());
        let camFwd: Vector4 = new Vector4(0.0, 1.0, 0.0, 0.0);
        let hasCam: Bool = IsDefined(camSys) && camSys.GetActiveCameraWorldTransform(camTransform);
        if hasCam {
            camFwd = Vector4.Normalize(Transform.GetForward(camTransform));
        }

        let attackRecord: ref<Attack_Record> = this.GetDesiredAttackRecord(stateContext, scriptInterface);
        let maxRange: Float = IsDefined(attackRecord) ? attackRecord.Range() : 200.0;
        if maxRange <= 0.0 {
            maxRange = 200.0;
        }

        let aimFwd: Vector4 = normMuzzleFwd;
        let targetPt: Vector4 = muzzlePos + (normMuzzleFwd * maxRange);
        let isDual: Bool = GameObject.IsDualWielding(player);
        if isDual && hasCam {
            let leftWeapon: ref<WeaponObject> = GameObject.GetLeftActiveWeapon(player);
            let isLeftHand: Bool = this.IsLeftWeaponLogic() || (IsDefined(leftWeapon) && weapon == leftWeapon);
            let stabWeight: Float = ClampF(aimSys.GetDualStabilizeWeight(), 0.0, 1.0);
            let camRight: Vector4 = Transform.GetRight(camTransform);
            let camUp: Vector4 = Transform.GetUp(camTransform);
            let gunYaw: Float = 0.0;
            let gunPitch: Float = 0.0;
            let effYaw: Float = 0.0;
            let effPitch: Float = 0.0;
            let effGunFwd: Vector4 = aimSys.ComputeDualVirtualFwd(normMuzzleFwd, camFwd, camRight, camUp, isLeftHand, stabWeight, gunYaw, gunPitch, effYaw, effPitch);

            if aimSys.IsDetachedActive() && aimSys.IsDualWieldActive() {
                targetPt = isLeftHand ? aimSys.GetLeftTargetPoint() : aimSys.GetTargetPoint();
                aimFwd = aimSys.ConvergeFromTarget(muzzlePos, targetPt, effGunFwd);
            } else {
                aimFwd = effGunFwd;
                targetPt = muzzlePos + (aimFwd * maxRange);
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
                let adsHoriYawDeg: Float = DR_GetRecoilYaw() * aimSys.GetAdsRecoilHoriMult();
                if AbsF(adsHoriYawDeg) > 0.001 && hasCam {
                    let camRight: Vector4 = Transform.GetRight(camTransform);
                    effGunFwd = Vector4.Normalize(normMuzzleFwd + camRight * TanF(Deg2Rad(adsHoriYawDeg)));
                }
                if aimSys.IsDetachedActive() {
                    targetPt = aimSys.GetTargetPoint();
                    aimFwd = aimSys.ConvergeFromTarget(muzzlePos, targetPt, effGunFwd);
                } else {
                    aimFwd = effGunFwd;
                    targetPt = muzzlePos + (aimFwd * maxRange);
                }
            } else if aimSys.IsDetachedActive() {
                targetPt = aimSys.GetTargetPoint();
            }
        }

        // Query projectiles per shot so multi-pellet weapons consume the exact number of rays for this hand
        let statsSys: ref<StatsSystem> = scriptInterface.GetStatsSystem();
        let pps: Float = IsDefined(statsSys) ? statsSys.GetStatValue(Cast<StatsObjectID>(weapon.GetEntityID()), gamedataStatType.ProjectilesPerShot) : 1.0;
        let pellets: Int32 = Max(1, RoundF(pps));

        // Enqueue this weapon's shot into the FIFO queue (so simultaneous Right+Left dual-wield shots never overwrite each other)
        QueueMuzzleShot(muzzlePos, aimFwd, camFwd, pellets);
        SetMuzzleAimState(muzzlePos, aimFwd, camFwd, true);
        aimSys.RecordShot(muzzlePos, aimFwd, targetPt, 1, "Native PhysicalRay Redirection");
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



