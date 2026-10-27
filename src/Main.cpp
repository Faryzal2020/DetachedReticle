#include <RED4ext/RED4ext.hpp>
#include <RED4ext/Scripting/Natives/Generated/Vector4.hpp>

#include <iostream>
#include <memory>

#include "Hooks/AnimationHook.hpp"
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
    bool isDecoupled = false;

    RED4ext::GetParameter(aFrame, &muzzlePos);
    RED4ext::GetParameter(aFrame, &muzzleFwd);
    RED4ext::GetParameter(aFrame, &isDecoupled);

    aFrame->code++; // skip ParamEnd

    DetachedReticle::ShootingHook::SetMuzzleAimState(muzzlePos, muzzleFwd, isDecoupled);
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
    func->AddParam("Bool", "isDecoupled");
    rtti->RegisterFunction(func);
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
