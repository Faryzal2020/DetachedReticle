// NativeBridge.reds
// Global native function bindings registered by DetachedReticle.dll

public native func SetMuzzleAimState(muzzlePos: Vector4, muzzleFwd: Vector4, camFwd: Vector4, isDecoupled: Bool) -> Void;
public native func QueueMuzzleShot(muzzlePos: Vector4, muzzleFwd: Vector4, camFwd: Vector4, pelletCount: Int32) -> Void;
public native func DR_GetResidualYaw() -> Float;
public native func DR_GetResidualPitch() -> Float;
public native func DR_GetRecoilYaw() -> Float;
public native func DR_GetRecoilPitch() -> Float;
