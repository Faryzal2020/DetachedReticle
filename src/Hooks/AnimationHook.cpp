#include "AnimationHook.hpp"

namespace DetachedReticle {

typedef void (*EvaluateBones_t)(void* aAnimInstance, void* aBoneBuffer, uint32_t aBoneCount);
static EvaluateBones_t s_originalEvaluateBones = nullptr;

static void HookedEvaluateBones(void* aAnimInstance, void* aBoneBuffer, uint32_t aBoneCount) {
    if (s_originalEvaluateBones) {
        s_originalEvaluateBones(aAnimInstance, aBoneBuffer, aBoneCount);
    }
}

bool AnimationHook::Initialize(RED4ext::v1::PluginHandle aHandle, const RED4ext::v1::Sdk* aSdk) {
    s_handle = aHandle;
    s_sdk = aSdk;

    if (s_sdk && s_sdk->logger) {
        s_sdk->logger->Info(s_handle, "AnimationHook initialized (standby).");
    }

    s_isHooked = true;
    return true;
}

void AnimationHook::Shutdown() {
    if (s_isHooked) {
        s_isHooked = false;
    }
}

void AnimationHook::SetAimDeflection(float aYawDeg, float aPitchDeg) {
    s_yawLagDeg = aYawDeg;
    s_pitchLagDeg = aPitchDeg;
}

} // namespace DetachedReticle
