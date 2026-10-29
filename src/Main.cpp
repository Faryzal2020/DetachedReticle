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

void DR_StartReturnToT2A(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);
    RED4EXT_UNUSED_PARAMETER(a4);

    float duration = 0.30f;
    RED4ext::GetParameter(aFrame, &duration);
    aFrame->code++; // skip ParamEnd

    DetachedReticle::InputHook::StartReturnToT2A(duration);
}

void DR_IsReturningToT2A(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4) {
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);
    aFrame->code++;
    if (aOut) *reinterpret_cast<bool*>(aOut) = DetachedReticle::InputHook::IsReturningToT2A();
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

    auto funcSetBarrelOffset = RED4ext::CGlobalFunction::Create("DR_SetBarrelOffset", "DR_SetBarrelOffset", &DR_SetBarrelOffset);
    funcSetBarrelOffset->flags = flags;
    funcSetBarrelOffset->AddParam("Float", "yaw");
    funcSetBarrelOffset->AddParam("Float", "pitch");
    rtti->RegisterFunction(funcSetBarrelOffset);

    auto funcReturnToT2A = RED4ext::CGlobalFunction::Create("DR_StartReturnToT2A", "DR_StartReturnToT2A", &DR_StartReturnToT2A);
    funcReturnToT2A->flags = flags;
    funcReturnToT2A->AddParam("Float", "duration");
    rtti->RegisterFunction(funcReturnToT2A);

    auto funcIsReturning = RED4ext::CGlobalFunction::Create("DR_IsReturningToT2A", "DR_IsReturningToT2A", &DR_IsReturningToT2A);
    funcIsReturning->flags = flags;
    funcIsReturning->SetReturnType("Bool");
    rtti->RegisterFunction(funcIsReturning);

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
