#pragma once

#include <RED4ext/RED4ext.hpp>
#include <RED4ext/Scripting/Natives/Generated/Vector4.hpp>

namespace DetachedReticle {

class ShootingHook {
public:
    static bool Initialize(RED4ext::v1::PluginHandle aHandle, const RED4ext::v1::Sdk* aSdk);
    static void Shutdown();

    static void SetBulletForward(const RED4ext::Vector4& aBulletForward);

private:
    static inline RED4ext::v1::PluginHandle s_handle{ nullptr };
    static inline const RED4ext::v1::Sdk* s_sdk{ nullptr };
    static inline RED4ext::Vector4 s_bulletForward{ 0.0f, 0.0f, 0.0f, 0.0f };
    static inline bool s_isHooked{ false };
};

} // namespace DetachedReticle
