#include <RED4ext/RED4ext.hpp>
#include <RED4ext/Scripting/Natives/Generated/Vector4.hpp>

#include <iostream>
#include <memory>

#include "Hooks/AnimationHook.hpp"
#include "Hooks/InputHook.hpp"
#include "Hooks/ShootingHook.hpp"

// Plugin metadata
constexpr auto PLUGIN_NAME = L"DetachedReticle";
constexpr auto PLUGIN_AUTHOR = L"Antigravity & User";

void SetMuzzleAimState(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);
    RED4EXT_UNUSED_PARAMETER(a4);

    RED4ext::Vector4 muzzlePos;
    RED4ext::Vector4 muzzleFwd;
    RED4ext::Vector4 camFwd;
    bool isDecoupled = false;

    RED4ext::GetParameter(aFrame, &muzzlePos);
    RED4ext::GetParameter(aFrame, &muzzleFwd);
    RED4ext::GetParameter(aFrame, &camFwd);
    RED4ext::GetParameter(aFrame, &isDecoupled);

    aFrame->code++; // skip ParamEnd

    DetachedReticle::ShootingHook::SetMuzzleAimState(muzzlePos, muzzleFwd, camFwd, isDecoupled);
}

void DR_SetSmoothing(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);
    RED4EXT_UNUSED_PARAMETER(a4);

    float lambda = 4.0f;
    int32_t mode = 0;
    float maxDiv = 65.0f;
    float deadzone = 0.0f;
    bool enabled = false;

    RED4ext::GetParameter(aFrame, &lambda);
    RED4ext::GetParameter(aFrame, &mode);
    RED4ext::GetParameter(aFrame, &maxDiv);
    RED4ext::GetParameter(aFrame, &deadzone);
    RED4ext::GetParameter(aFrame, &enabled);

    aFrame->code++; // skip ParamEnd

    DetachedReticle::InputHook::SetSmoothing(lambda, mode, maxDiv, deadzone, enabled);
}

void DR_GetTargetYaw(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetTargetYaw();
}

void DR_GetTargetPitch(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetTargetPitch();
}

void DR_GetAimYaw(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetAimYaw();
}

void DR_GetAimPitch(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetAimPitch();
}

void DR_GetResidualYaw(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetResidualYaw();
}

void DR_GetResidualPitch(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetResidualPitch();
}

void DR_SetBarrelOffset(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);
    RED4EXT_UNUSED_PARAMETER(a4);

    float offYaw = 0.0f;
    float offPitch = 0.0f;

    RED4ext::GetParameter(aFrame, &offYaw);
    RED4ext::GetParameter(aFrame, &offPitch);
    aFrame->code++; // skip ParamEnd

    DetachedReticle::InputHook::SetBarrelOffset(offYaw, offPitch);
}

void DR_GetCompYaw(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetCompYaw();
}

void DR_GetCompPitch(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetCompPitch();
}

void DR_GetT2BYaw(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetT2BYaw();
}

void DR_GetT2BPitch(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetT2BPitch();
}

void DR_GetRecoilYaw(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetRecoilYaw();
}

void DR_GetRecoilPitch(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetRecoilPitch();
}

void DR_GetLastDeltaRecoilYaw(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetLastDeltaRecoilYaw();
}

void DR_GetLastDeltaRecoilPitch(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetLastDeltaRecoilPitch();
}

void DR_GetSplitErrYaw(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetSplitErrYaw();
}

void DR_GetSplitErrPitch(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetSplitErrPitch();
}

void DR_SetCompParams(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);
    RED4EXT_UNUSED_PARAMETER(a4);

    float speedSettled = 12.0f;
    float speedMoving = 4.0f;
    float maxAngularSpeed = 240.0f;
    float gapThreshold = 3.0f;
    float minAngularSpeed = 6.0f;

    RED4ext::GetParameter(aFrame, &speedSettled);
    RED4ext::GetParameter(aFrame, &speedMoving);
    RED4ext::GetParameter(aFrame, &maxAngularSpeed);
    RED4ext::GetParameter(aFrame, &gapThreshold);
    RED4ext::GetParameter(aFrame, &minAngularSpeed);
    aFrame->code++; // skip ParamEnd

    DetachedReticle::InputHook::SetCompParams(speedSettled, speedMoving, maxAngularSpeed, gapThreshold, minAngularSpeed);
}

void DR_GetCompSpeedSettled(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetCompSpeedSettled();
}

void DR_GetCompSpeedMoving(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetCompSpeedMoving();
}

void DR_GetCompMaxSpeed(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetCompMaxSpeed();
}

void DR_GetCompGapThreshold(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetCompGapThreshold();
}

void DR_GetCompMinSpeed(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetCompMinSpeed();
}

void DR_SetBrakeParams(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);
    RED4EXT_UNUSED_PARAMETER(a4);

    float threshold = 2.0f;
    float maxSpeed = 360.0f;

    RED4ext::GetParameter(aFrame, &threshold);
    RED4ext::GetParameter(aFrame, &maxSpeed);
    aFrame->code++;

    DetachedReticle::InputHook::SetBrakeParams(threshold, maxSpeed);
}

void DR_GetBrakeThreshold(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetBrakeThreshold();
}

void DR_GetBrakeMaxSpeed(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetBrakeMaxSpeed();
}

void DR_SetExpParams(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);
    RED4EXT_UNUSED_PARAMETER(a4);

    float power = 0.6f;
    RED4ext::GetParameter(aFrame, &power);
    aFrame->code++;

    DetachedReticle::InputHook::SetExpParams(power);
}

void DR_GetExpPower(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetExpPower();
}

void DR_SetRecoilLeashParams(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);
    RED4EXT_UNUSED_PARAMETER(a4);

    float maxRadius = 7.0f;
    float leashCurve = 1.5f;
    RED4ext::GetParameter(aFrame, &maxRadius);
    RED4ext::GetParameter(aFrame, &leashCurve);
    aFrame->code++;

    DetachedReticle::InputHook::SetRecoilLeashParams(maxRadius, leashCurve);
}

void DR_GetRecoilMaxRadius(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetRecoilMaxRadius();
}

void DR_GetRecoilLeashCurve(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetRecoilLeashCurve();
}

void DR_SetChaseLeashParams(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);
    RED4EXT_UNUSED_PARAMETER(a4);

    bool enabled = true;
    float startDist = 20.0f;
    float maxDist = 60.0f;
    float stiffness = 0.6f;

    RED4ext::GetParameter(aFrame, &enabled);
    RED4ext::GetParameter(aFrame, &startDist);
    RED4ext::GetParameter(aFrame, &maxDist);
    RED4ext::GetParameter(aFrame, &stiffness);
    aFrame->code++;

    DetachedReticle::InputHook::SetChaseLeashParams(enabled, startDist, maxDist, stiffness);
}

void DR_GetChaseLeashEnabled(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<bool*>(aOut) = DetachedReticle::InputHook::GetChaseLeashEnabled();
}

void DR_GetChaseLeashStart(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetChaseLeashStart();
}

void DR_GetChaseLeashMax(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetChaseLeashMax();
}

void DR_GetChaseLeashStiffness(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetChaseLeashStiffness();
}

void DR_SetRecoilHorizontalParams(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);
    RED4EXT_UNUSED_PARAMETER(a4);

    bool statScaling = true;
    float scatter = 1.0f;
    float damping = 0.70f;
    float strengthFactor = 0.0f;
    RED4ext::GetParameter(aFrame, &statScaling);
    RED4ext::GetParameter(aFrame, &scatter);
    RED4ext::GetParameter(aFrame, &damping);
    RED4ext::GetParameter(aFrame, &strengthFactor);
    aFrame->code++;

    DetachedReticle::InputHook::SetRecoilHorizontalParams(statScaling, scatter, damping, strengthFactor);
}

void DR_GetRecoilHoriStatScaling(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<bool*>(aOut) = DetachedReticle::InputHook::GetRecoilHoriStatScaling();
}

void DR_GetRecoilHoriScatter(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetRecoilHoriScatter();
}

void DR_GetRecoilHoriDamping(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetRecoilHoriDamping();
}

void DR_GetPlayerStrengthFactor(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetPlayerStrengthFactor();
}


void DR_DrainEvents(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    std::string events = DetachedReticle::InputHook::DrainEvents();
    if (aOut) {
        *reinterpret_cast<RED4ext::CString*>(aOut) = RED4ext::CString(events);
    }
}

void DR_ResetChase(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    DetachedReticle::InputHook::ResetChase(0.0f);
}

void DR_ResetChasePitch(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);
    RED4EXT_UNUSED_PARAMETER(a4);
    float initPitch = 0.0f;
    RED4ext::GetParameter(aFrame, &initPitch);
    aFrame->code++;
    DetachedReticle::InputHook::ResetChase(initPitch);
}


void DR_SetSensitivityMult(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);
    RED4EXT_UNUSED_PARAMETER(a4);

    RED4ext::Handle<RED4ext::IScriptable> fppHandle;
    float multX = 1.0f;
    float multY = 1.0f;

    RED4ext::GetParameter(aFrame, &fppHandle);
    RED4ext::GetParameter(aFrame, &multX);
    RED4ext::GetParameter(aFrame, &multY);
    aFrame->code++;

    DetachedReticle::InputHook::SetSensitivityMult(fppHandle.instance, multX, multY);
}

void DR_GetSensitivityMultX(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);

    RED4ext::Handle<RED4ext::IScriptable> fppHandle;
    RED4ext::GetParameter(aFrame, &fppHandle);
    aFrame->code++;

    if (aOut) {
        *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetSensitivityMultX(fppHandle.instance);
    }
}

void DR_GetSensitivityMultY(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);

    RED4ext::Handle<RED4ext::IScriptable> fppHandle;
    RED4ext::GetParameter(aFrame, &fppHandle);
    aFrame->code++;

    if (aOut) {
        *reinterpret_cast<float*>(aOut) = DetachedReticle::InputHook::GetSensitivityMultY(fppHandle.instance);
    }
}

void DR_SetHeadingLocked(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);
    RED4EXT_UNUSED_PARAMETER(a4);

    RED4ext::Handle<RED4ext::IScriptable> fppHandle;
    bool locked = false;

    RED4ext::GetParameter(aFrame, &fppHandle);
    RED4ext::GetParameter(aFrame, &locked);
    aFrame->code++;

    DetachedReticle::InputHook::SetHeadingLocked(fppHandle.instance, locked);
}

void DR_GetHeadingLocked(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);

    RED4ext::Handle<RED4ext::IScriptable> fppHandle;
    RED4ext::GetParameter(aFrame, &fppHandle);
    aFrame->code++;

    if (aOut) {
        *reinterpret_cast<bool*>(aOut) = DetachedReticle::InputHook::GetHeadingLocked(fppHandle.instance);
    }
}

void RegisterTypes() {
}

void PostRegisterTypes() {
    auto rtti = RED4ext::CRTTISystem::Get();
    RED4ext::CBaseFunction::Flags flags = { .isNative = true, .isStatic = true };

    auto func = RED4ext::CGlobalFunction::Create("SetMuzzleAimState", "SetMuzzleAimState", &SetMuzzleAimState);
    func->flags = flags;
    func->AddParam("Vector4", "muzzlePos");
    func->AddParam("Vector4", "muzzleFwd");
    func->AddParam("Vector4", "camFwd");
    func->AddParam("Bool", "isDecoupled");
    rtti->RegisterFunction(func);

    auto funcSetSmoothing = RED4ext::CGlobalFunction::Create("DR_SetSmoothing", "DR_SetSmoothing", &DR_SetSmoothing);
    funcSetSmoothing->flags = flags;
    funcSetSmoothing->AddParam("Float", "lambda");
    funcSetSmoothing->AddParam("Int32", "mode");
    funcSetSmoothing->AddParam("Float", "maxDiv");
    funcSetSmoothing->AddParam("Float", "deadzone");
    funcSetSmoothing->AddParam("Bool", "enabled");
    rtti->RegisterFunction(funcSetSmoothing);

    auto regGetter = [&](const char* name, auto fn) {
        auto gFunc = RED4ext::CGlobalFunction::Create(name, name, fn);
        gFunc->flags = flags;
        gFunc->SetReturnType("Float");
        rtti->RegisterFunction(gFunc);
    };

    regGetter("DR_GetTargetYaw", &DR_GetTargetYaw);
    regGetter("DR_GetTargetPitch", &DR_GetTargetPitch);
    regGetter("DR_GetAimYaw", &DR_GetAimYaw);
    regGetter("DR_GetAimPitch", &DR_GetAimPitch);
    regGetter("DR_GetResidualYaw", &DR_GetResidualYaw);
    regGetter("DR_GetResidualPitch", &DR_GetResidualPitch);
    regGetter("DR_GetCompYaw", &DR_GetCompYaw);
    regGetter("DR_GetCompPitch", &DR_GetCompPitch);
    regGetter("DR_GetT2BYaw", &DR_GetT2BYaw);
    regGetter("DR_GetT2BPitch", &DR_GetT2BPitch);
    regGetter("DR_GetRecoilYaw", &DR_GetRecoilYaw);
    regGetter("DR_GetRecoilPitch", &DR_GetRecoilPitch);
    regGetter("DR_GetLastDeltaRecoilYaw", &DR_GetLastDeltaRecoilYaw);
    regGetter("DR_GetLastDeltaRecoilPitch", &DR_GetLastDeltaRecoilPitch);
    regGetter("DR_GetSplitErrYaw", &DR_GetSplitErrYaw);
    regGetter("DR_GetSplitErrPitch", &DR_GetSplitErrPitch);
    regGetter("DR_GetCompSpeedSettled", &DR_GetCompSpeedSettled);
    regGetter("DR_GetCompSpeedMoving", &DR_GetCompSpeedMoving);
    regGetter("DR_GetCompMaxSpeed", &DR_GetCompMaxSpeed);
    regGetter("DR_GetCompGapThreshold", &DR_GetCompGapThreshold);
    regGetter("DR_GetCompMinSpeed", &DR_GetCompMinSpeed);

    auto funcSetBarrelOffset = RED4ext::CGlobalFunction::Create("DR_SetBarrelOffset", "DR_SetBarrelOffset", &DR_SetBarrelOffset);
    funcSetBarrelOffset->flags = flags;
    funcSetBarrelOffset->AddParam("Float", "yaw");
    funcSetBarrelOffset->AddParam("Float", "pitch");
    rtti->RegisterFunction(funcSetBarrelOffset);

    auto funcSetCompParams = RED4ext::CGlobalFunction::Create("DR_SetCompParams", "DR_SetCompParams", &DR_SetCompParams);
    funcSetCompParams->flags = flags;
    funcSetCompParams->AddParam("Float", "speedSettled");
    funcSetCompParams->AddParam("Float", "speedMoving");
    funcSetCompParams->AddParam("Float", "maxAngularSpeed");
    funcSetCompParams->AddParam("Float", "gapThreshold");
    funcSetCompParams->AddParam("Float", "minAngularSpeed");
    rtti->RegisterFunction(funcSetCompParams);

    auto funcSetBrakeParams = RED4ext::CGlobalFunction::Create("DR_SetBrakeParams", "DR_SetBrakeParams", &DR_SetBrakeParams);
    funcSetBrakeParams->flags = flags;
    funcSetBrakeParams->AddParam("Float", "threshold");
    funcSetBrakeParams->AddParam("Float", "maxSpeed");
    rtti->RegisterFunction(funcSetBrakeParams);

    auto funcGetBrakeThreshold = RED4ext::CGlobalFunction::Create("DR_GetBrakeThreshold", "DR_GetBrakeThreshold", &DR_GetBrakeThreshold);
    funcGetBrakeThreshold->flags = flags;
    funcGetBrakeThreshold->SetReturnType("Float");
    rtti->RegisterFunction(funcGetBrakeThreshold);

    auto funcGetBrakeMaxSpeed = RED4ext::CGlobalFunction::Create("DR_GetBrakeMaxSpeed", "DR_GetBrakeMaxSpeed", &DR_GetBrakeMaxSpeed);
    funcGetBrakeMaxSpeed->flags = flags;
    funcGetBrakeMaxSpeed->SetReturnType("Float");
    rtti->RegisterFunction(funcGetBrakeMaxSpeed);

    auto funcSetExpParams = RED4ext::CGlobalFunction::Create("DR_SetExpParams", "DR_SetExpParams", &DR_SetExpParams);
    funcSetExpParams->flags = flags;
    funcSetExpParams->AddParam("Float", "power");
    rtti->RegisterFunction(funcSetExpParams);

    auto funcGetExpPower = RED4ext::CGlobalFunction::Create("DR_GetExpPower", "DR_GetExpPower", &DR_GetExpPower);
    funcGetExpPower->flags = flags;
    funcGetExpPower->SetReturnType("Float");
    rtti->RegisterFunction(funcGetExpPower);

    auto funcSetRecoilLeashParams = RED4ext::CGlobalFunction::Create("DR_SetRecoilLeashParams", "DR_SetRecoilLeashParams", &DR_SetRecoilLeashParams);
    funcSetRecoilLeashParams->flags = flags;
    funcSetRecoilLeashParams->AddParam("Float", "maxRadius");
    funcSetRecoilLeashParams->AddParam("Float", "leashCurve");
    rtti->RegisterFunction(funcSetRecoilLeashParams);

    regGetter("DR_GetRecoilMaxRadius", &DR_GetRecoilMaxRadius);
    regGetter("DR_GetRecoilLeashCurve", &DR_GetRecoilLeashCurve);

    auto funcSetChaseLeashParams = RED4ext::CGlobalFunction::Create("DR_SetChaseLeashParams", "DR_SetChaseLeashParams", &DR_SetChaseLeashParams);
    funcSetChaseLeashParams->flags = flags;
    funcSetChaseLeashParams->AddParam("Bool", "enabled");
    funcSetChaseLeashParams->AddParam("Float", "startDist");
    funcSetChaseLeashParams->AddParam("Float", "maxDist");
    funcSetChaseLeashParams->AddParam("Float", "stiffness");
    rtti->RegisterFunction(funcSetChaseLeashParams);

    auto funcGetChaseLeashEnabled = RED4ext::CGlobalFunction::Create("DR_GetChaseLeashEnabled", "DR_GetChaseLeashEnabled", &DR_GetChaseLeashEnabled);
    funcGetChaseLeashEnabled->flags = flags;
    funcGetChaseLeashEnabled->SetReturnType("Bool");
    rtti->RegisterFunction(funcGetChaseLeashEnabled);

    regGetter("DR_GetChaseLeashStart", &DR_GetChaseLeashStart);
    regGetter("DR_GetChaseLeashMax", &DR_GetChaseLeashMax);
    regGetter("DR_GetChaseLeashStiffness", &DR_GetChaseLeashStiffness);

    auto funcSetRecoilHoriParams = RED4ext::CGlobalFunction::Create("DR_SetRecoilHorizontalParams", "DR_SetRecoilHorizontalParams", &DR_SetRecoilHorizontalParams);
    funcSetRecoilHoriParams->flags = flags;
    funcSetRecoilHoriParams->AddParam("Bool", "statScaling");
    funcSetRecoilHoriParams->AddParam("Float", "scatter");
    funcSetRecoilHoriParams->AddParam("Float", "damping");
    funcSetRecoilHoriParams->AddParam("Float", "strengthFactor");
    rtti->RegisterFunction(funcSetRecoilHoriParams);

    auto funcGetRecoilHoriStatScaling = RED4ext::CGlobalFunction::Create("DR_GetRecoilHoriStatScaling", "DR_GetRecoilHoriStatScaling", &DR_GetRecoilHoriStatScaling);
    funcGetRecoilHoriStatScaling->flags = flags;
    funcGetRecoilHoriStatScaling->SetReturnType("Bool");
    rtti->RegisterFunction(funcGetRecoilHoriStatScaling);

    regGetter("DR_GetRecoilHoriScatter", &DR_GetRecoilHoriScatter);
    regGetter("DR_GetRecoilHoriDamping", &DR_GetRecoilHoriDamping);
    regGetter("DR_GetPlayerStrengthFactor", &DR_GetPlayerStrengthFactor);


    auto funcDrain = RED4ext::CGlobalFunction::Create("DR_DrainEvents", "DR_DrainEvents", &DR_DrainEvents);
    funcDrain->flags = flags;
    funcDrain->SetReturnType("String");
    rtti->RegisterFunction(funcDrain);

    auto funcResetChase = RED4ext::CGlobalFunction::Create("DR_ResetChase", "DR_ResetChase", &DR_ResetChase);
    funcResetChase->flags = flags;
    rtti->RegisterFunction(funcResetChase);

    auto funcResetChasePitch = RED4ext::CGlobalFunction::Create("DR_ResetChasePitch", "DR_ResetChasePitch", &DR_ResetChasePitch);
    funcResetChasePitch->flags = flags;
    funcResetChasePitch->AddParam("Float", "initPitch");
    rtti->RegisterFunction(funcResetChasePitch);


    auto funcSetSens = RED4ext::CGlobalFunction::Create("DR_SetSensitivityMult", "DR_SetSensitivityMult", &DR_SetSensitivityMult);
    funcSetSens->flags = flags;
    funcSetSens->AddParam("handle:IScriptable", "fpp");
    funcSetSens->AddParam("Float", "multX");
    funcSetSens->AddParam("Float", "multY");
    rtti->RegisterFunction(funcSetSens);

    auto funcGetSensX = RED4ext::CGlobalFunction::Create("DR_GetSensitivityMultX", "DR_GetSensitivityMultX", &DR_GetSensitivityMultX);
    funcGetSensX->flags = flags;
    funcGetSensX->AddParam("handle:IScriptable", "fpp");
    funcGetSensX->SetReturnType("Float");
    rtti->RegisterFunction(funcGetSensX);

    auto funcGetSensY = RED4ext::CGlobalFunction::Create("DR_GetSensitivityMultY", "DR_GetSensitivityMultY", &DR_GetSensitivityMultY);
    funcGetSensY->flags = flags;
    funcGetSensY->AddParam("handle:IScriptable", "fpp");
    funcGetSensY->SetReturnType("Float");
    rtti->RegisterFunction(funcGetSensY);

    auto funcSetHeading = RED4ext::CGlobalFunction::Create("DR_SetHeadingLocked", "DR_SetHeadingLocked", &DR_SetHeadingLocked);
    funcSetHeading->flags = flags;
    funcSetHeading->AddParam("handle:IScriptable", "fpp");
    funcSetHeading->AddParam("Bool", "locked");
    rtti->RegisterFunction(funcSetHeading);

    auto funcGetHeading = RED4ext::CGlobalFunction::Create("DR_GetHeadingLocked", "DR_GetHeadingLocked", &DR_GetHeadingLocked);
    funcGetHeading->flags = flags;
    funcGetHeading->AddParam("handle:IScriptable", "fpp");
    funcGetHeading->SetReturnType("Bool");
    rtti->RegisterFunction(funcGetHeading);

    // Route A: RTTI inspection across camera and player puppet classes
    DetachedReticle::InputHook::ProbeRTTI();
}

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(const RED4ext::v1::PluginHandle aHandle, const RED4ext::v1::EMainReason aReason, const RED4ext::v1::Sdk* aSdk) {
    switch (aReason) {
    case RED4ext::v1::EMainReason::Load: {
        auto logger = aSdk->logger;
        logger->Info(aHandle, "Initializing DetachedReticle native plugin...");

        auto rtti = RED4ext::CRTTISystem::Get();
        rtti->AddRegisterCallback(RegisterTypes);
        rtti->AddPostRegisterCallback(PostRegisterTypes);

        // Initialize Native Hooks via RED4ext SDK Hooking subsystem
        if (!DetachedReticle::AnimationHook::Initialize(aHandle, aSdk)) {
            logger->Warn(aHandle, "AnimationHook initialization pending / partial.");
        }

        if (!DetachedReticle::InputHook::Initialize(aHandle, aSdk)) {
            logger->Warn(aHandle, "InputHook initialization pending / partial.");
        }

        if (!DetachedReticle::ShootingHook::Initialize(aHandle, aSdk)) {
            logger->Warn(aHandle, "ShootingHook initialization pending / partial.");
        }

        logger->Info(aHandle, "DetachedReticle native plugin loaded successfully!");
        break;
    }
    case RED4ext::v1::EMainReason::Unload: {
        auto logger = aSdk->logger;
        logger->Info(aHandle, "Unloading DetachedReticle native plugin...");

        DetachedReticle::AnimationHook::Shutdown();
        DetachedReticle::InputHook::Shutdown();
        DetachedReticle::ShootingHook::Shutdown();

        logger->Info(aHandle, "DetachedReticle native plugin unloaded.");
        break;
    }
    }

    return true;
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* aInfo) {
    aInfo->name = PLUGIN_NAME;
    aInfo->author = PLUGIN_AUTHOR;
    aInfo->version = RED4EXT_V1_SEMVER(1, 0, 0);
    aInfo->runtime = RED4EXT_V1_RUNTIME_VERSION_LATEST;
    aInfo->sdk = RED4EXT_V1_SDK_VERSION_CURRENT;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports() {
    return RED4EXT_API_VERSION_1;
}
