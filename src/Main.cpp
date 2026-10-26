#include <RED4ext/RED4ext.hpp>

#include <iostream>
#include <memory>

#include "Hooks/AnimationHook.hpp"
#include "Hooks/ShootingHook.hpp"

// Plugin metadata
constexpr auto PLUGIN_NAME = L"DetachedReticle";
constexpr auto PLUGIN_AUTHOR = L"MayanoTopgun";

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(const RED4ext::v1::PluginHandle aHandle, const RED4ext::v1::EMainReason aReason, const RED4ext::v1::Sdk* aSdk) {
    switch (aReason) {
    case RED4ext::v1::EMainReason::Load: {
        auto logger = aSdk->logger;
        logger->Info(aHandle, "Initializing DetachedReticle native plugin...");

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
