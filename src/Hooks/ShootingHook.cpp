#include "ShootingHook.hpp"

namespace DetachedReticle {

typedef bool (*PhysicalRayExecute_t)(void* aRayContext, void* aRayParams, void* aRayResult);
static PhysicalRayExecute_t s_originalPhysicalRayExecute = nullptr;

static bool HookedPhysicalRayExecute(void* aRayContext, void* aRayParams, void* aRayResult) {
    return s_originalPhysicalRayExecute ? s_originalPhysicalRayExecute(aRayContext, aRayParams, aRayResult) : false;
}

bool ShootingHook::Initialize(RED4ext::v1::PluginHandle aHandle, const RED4ext::v1::Sdk* aSdk) {
    s_handle = aHandle;
    s_sdk = aSdk;

    if (s_sdk && s_sdk->logger) {
        s_sdk->logger->Info(s_handle, "Setting up ShootingHook for ballistics ray redirection...");
    }

    s_isHooked = true;
    return true;
}

void ShootingHook::Shutdown() {
    if (s_isHooked) {
        s_isHooked = false;
    }
}

void ShootingHook::SetBulletForward(const RED4ext::Vector4& aBulletForward) {
    s_bulletForward = aBulletForward;
}

} // namespace DetachedReticle
