#include "InputHook.hpp"

#include <windows.h>
#include <sstream>
#include <fstream>
#include <iomanip>
#include <cstring>
#include <chrono>
#include <cmath>
#include <algorithm>

namespace DetachedReticle {

static uintptr_t s_exeBase = 0;

// Verified RVA in Cyberpunk2077.exe (Build 2.50 / Patch 2.5):
// Primary Gameplay Mouse Look Integrator at RVA 0x51D462:
//   movss dword ptr [rcx+9Ch], xmm6    (8 bytes: F3 0F 11 B1 9C 00 00 00)
// Inputs:
//   rcx:   Player puppet orientation controller ([rax+8])
//   xmm6:  Body Yaw Delta (post-sensitivity)
//   xmm7:  Camera Pitch Delta (post-sensitivity)
static constexpr uintptr_t kWaLookCallsiteRva = 0x51D462;
static constexpr uint8_t kWaLookDisplacedBytes[] = {
    0xF3, 0x0F, 0x11, 0xB1, 0x9C, 0x00, 0x00, 0x00
};

static void* WaAllocRelayNear(uint8_t* target) {
    SYSTEM_INFO si{};
    GetSystemInfo(&si);
    const uintptr_t gran = si.dwAllocationGranularity ? si.dwAllocationGranularity : 0x10000;
    const uintptr_t ta = reinterpret_cast<uintptr_t>(target);
    for (uintptr_t dist = gran; dist < 0x70000000ull; dist += gran) {
        uintptr_t cand[2] = { ta + dist, ta > dist ? ta - dist : 0 };
        for (uintptr_t c : cand) {
            if (!c) continue;
            c &= ~(gran - 1);
            void* m = VirtualAlloc(reinterpret_cast<void*>(c), gran, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE);
            if (m) return m;
        }
    }
    return nullptr;
}

static bool WaInstallLookPatch(uintptr_t siteRva, void* hook, uint8_t*& relayOut) {
    if (!s_exeBase) return false;
    uint8_t* callsite = reinterpret_cast<uint8_t*>(s_exeBase + siteRva);
    if (std::memcmp(callsite, kWaLookDisplacedBytes, sizeof(kWaLookDisplacedBytes)) != 0) {
        return false;
    }

    relayOut = reinterpret_cast<uint8_t*>(WaAllocRelayNear(callsite));
    if (!relayOut) return false;

    // 64-bit absolute jmp relay:
    // mov rax, <hook>
    // jmp rax
    uint8_t relay[12] = { 0x48, 0xB8, 0,0,0,0,0,0,0,0, 0xFF, 0xE0 };
    const uint64_t destination = reinterpret_cast<uint64_t>(hook);
    std::memcpy(relay + 2, &destination, sizeof(destination));
    std::memcpy(relayOut, relay, sizeof(relay));
    FlushInstructionCache(GetCurrentProcess(), relayOut, sizeof(relay));

    const intptr_t delta = relayOut - (callsite + 5);
    if (delta < INT32_MIN || delta > INT32_MAX) return false;

    // 5-byte CALL to near relay + 3 NOPs to replace 8-byte instruction:
    uint8_t patch[8] = {
        0xE8,
        static_cast<uint8_t>(delta & 0xFF),
        static_cast<uint8_t>((delta >> 8) & 0xFF),
        static_cast<uint8_t>((delta >> 16) & 0xFF),
        static_cast<uint8_t>((delta >> 24) & 0xFF),
        0x90, 0x90, 0x90
    };

    DWORD oldProtect = 0;
    if (!VirtualProtect(callsite, sizeof(patch), PAGE_EXECUTE_READWRITE, &oldProtect)) return false;
    std::memcpy(callsite, patch, sizeof(patch));
    FlushInstructionCache(GetCurrentProcess(), callsite, sizeof(patch));
    DWORD ignored = 0;
    VirtualProtect(callsite, sizeof(patch), oldProtect, &ignored);
    return true;
}

bool InputHook::Initialize(RED4ext::v1::PluginHandle aHandle, const RED4ext::v1::Sdk* aSdk) {
    s_handle = aHandle;
    s_sdk = aSdk;

    HMODULE hExe = GetModuleHandleA("Cyberpunk2077.exe");
    if (hExe) {
        s_exeBase = reinterpret_cast<uintptr_t>(hExe);
    }

    // Install primary gameplay look hook at RVA 0x51D462
    if (WaInstallLookPatch(kWaLookCallsiteRva, reinterpret_cast<void*>(&MouseLookRelay), s_lookRelay)) {
        s_isHooked = true;
        if (s_sdk && s_sdk->logger) {
            s_sdk->logger->Info(s_handle, "InputHook: Native gameplay look hook installed at RVA 0x51D462.");
        }
        PushEvent("[N0] exe=0x" + (std::stringstream() << std::hex << s_exeBase).str() + " site=0x51D462 bytesOK=1 patched=1");
    } else {
        if (s_sdk && s_sdk->logger) {
            s_sdk->logger->Error(s_handle, "InputHook: Failed to patch gameplay look at RVA 0x51D462.");
        }
        PushEvent("[N0] exe=0x" + (std::stringstream() << std::hex << s_exeBase).str() + " site=0x51D462 bytesOK=0 patched=0");
    }

    s_isInitialized = true;
    return true;
}


void InputHook::Shutdown() {
    s_isInitialized = false;
    s_isHooked = false;
}

void InputHook::ResetChase() {
    s_targetYaw = 0.0f;
    s_targetPitch = 0.0f;
    s_aimYaw = 0.0f;
    s_aimPitch = 0.0f;
    s_residualYaw = 0.0f;
    s_residualPitch = 0.0f;
    s_displayTargetYaw = 0.0f;
    s_displayAimYaw = 0.0f;
    s_lastTime = std::chrono::steady_clock::now();
}

void InputHook::SetSmoothing(float aLambda, int32_t aMode, float aMaxDiv, float aDeadzone, bool aEnabled) {
    s_lambda = aLambda;
    s_mode = aMode;
    s_maxDiv = aMaxDiv;
    s_deadzone = aDeadzone;
    if (aEnabled && !s_enabled) {
        ResetChase();
    }
    s_enabled = aEnabled;
}

void InputHook::ProcessMouseAim(void* aFpp, float aRawYaw, float aRawPitch, float& outYaw, float& outPitch) {
    if (!s_enabled) {
        outYaw = aRawYaw;
        outPitch = aRawPitch;
        return;
    }

    auto now = std::chrono::steady_clock::now();
    float dt = std::chrono::duration<float>(now - s_lastTime).count();
    s_lastTime = now;
    if (dt <= 0.0f || dt > 0.1f) dt = 1.0f / 60.0f;

    // 1. Advance Target T with raw mouse deflection (post-sensitivity)
    s_targetYaw += aRawYaw;
    s_targetPitch += aRawPitch;
    s_targetPitch = std::clamp(s_targetPitch, -85.0f, 85.0f);

    // 2. Compute Gap between Target T and current Aim A
    float gapYaw = s_targetYaw - s_aimYaw;
    while (gapYaw > 180.0f) gapYaw -= 360.0f;
    while (gapYaw < -180.0f) gapYaw += 360.0f;

    float gapPitch = s_targetPitch - s_aimPitch;

    // 3. Clamp Max Divergence (advancing A when T exceeds clamp)
    if (s_maxDiv > 0.0f) {
        if (std::abs(gapYaw) > s_maxDiv) {
            float clamped = (gapYaw > 0.0f) ? s_maxDiv : -s_maxDiv;
            float excess = gapYaw - clamped;
            s_aimYaw += excess;
            gapYaw = clamped;
        }
    }

    // 4. Deadzone handling
    float effGapYaw = gapYaw;
    if (s_deadzone > 0.0f) {
        if (std::abs(effGapYaw) <= s_deadzone) {
            effGapYaw = 0.0f;
        } else {
            effGapYaw = (effGapYaw > 0.0f) ? (effGapYaw - s_deadzone) : (effGapYaw + s_deadzone);
        }
    }
    float effGapPitch = gapPitch;

    // 5. Exponential filter: step dA = gap * (1 - exp(-lambda * dt))
    float factor = 1.0f - std::exp(-s_lambda * dt);
    float dAYaw = effGapYaw * factor;
    float dAPitch = effGapPitch * factor;

    // 6. Advance Aim A
    s_aimYaw += dAYaw;
    s_aimPitch += dAPitch;

    // 7. Residual for camera offset: R = T - A
    s_residualYaw = s_targetYaw - s_aimYaw;
    s_residualPitch = s_targetPitch - s_aimPitch;
    s_displayTargetYaw = s_targetYaw;
    s_displayAimYaw = s_aimYaw;

    // Keep state bounded to prevent float overflow over time
    s_targetYaw -= s_aimYaw;
    s_aimYaw = 0.0f;
    s_targetPitch -= s_aimPitch;
    s_aimPitch = 0.0f;

    // 8. Output chase deltas to engine
    outYaw = dAYaw;
    outPitch = dAPitch;
}

float InputHook::GetTargetYaw() { return s_displayTargetYaw; }
float InputHook::GetTargetPitch() { return s_targetPitch; }
float InputHook::GetAimYaw() { return s_displayAimYaw; }
float InputHook::GetAimPitch() { return s_aimPitch; }
float InputHook::GetResidualYaw() { return s_residualYaw; }
float InputHook::GetResidualPitch() { return s_residualPitch; }

void InputHook::SetSensitivityMult(RED4ext::IScriptable* aFpp, float aMultX, float aMultY) {
    if (!aFpp) return;
    __try {
        uintptr_t addr = reinterpret_cast<uintptr_t>(aFpp);
        *reinterpret_cast<float*>(addr + 0x498) = aMultX;
        *reinterpret_cast<float*>(addr + 0x49C) = aMultY;
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}

float InputHook::GetSensitivityMultX(RED4ext::IScriptable* aFpp) {
    if (!aFpp) return 1.0f;
    __try {
        uintptr_t addr = reinterpret_cast<uintptr_t>(aFpp);
        return *reinterpret_cast<const float*>(addr + 0x498);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return 1.0f;
    }
}

float InputHook::GetSensitivityMultY(RED4ext::IScriptable* aFpp) {
    if (!aFpp) return 1.0f;
    __try {
        uintptr_t addr = reinterpret_cast<uintptr_t>(aFpp);
        return *reinterpret_cast<const float*>(addr + 0x49C);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return 1.0f;
    }
}

void InputHook::SetHeadingLocked(RED4ext::IScriptable* aFpp, bool aLocked) {
    if (!aFpp) return;
    __try {
        uintptr_t addr = reinterpret_cast<uintptr_t>(aFpp);
        *reinterpret_cast<bool*>(addr + 0x3F6) = aLocked;
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}

bool InputHook::GetHeadingLocked(RED4ext::IScriptable* aFpp) {
    if (!aFpp) return false;
    __try {
        uintptr_t addr = reinterpret_cast<uintptr_t>(aFpp);
        return *reinterpret_cast<const bool*>(addr + 0x3F6);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

void InputHook::PushEvent(const std::string& aEvent) {
    std::lock_guard<std::mutex> lock(s_eventMutex);
    s_eventBuffer.push_back(aEvent);
}

std::string InputHook::DrainEvents() {
    std::lock_guard<std::mutex> lock(s_eventMutex);
    if (s_eventBuffer.empty()) {
        return "";
    }
    std::string result;
    for (size_t i = 0; i < s_eventBuffer.size(); ++i) {
        result += s_eventBuffer[i];
        if (i + 1 < s_eventBuffer.size()) {
            result += "\n";
        }
    }
    s_eventBuffer.clear();
    return result;
}

#include <RED4ext/Detail/AddressHashes.hpp>
#include <RED4ext/Relocation.hpp>

using NativeHandler_t = void (*)(void*, RED4ext::CStackFrame&, void*, RED4ext::rtti::IType*);

static uintptr_t s_handlersTableAddr = 0;

static uintptr_t TryGetHandler(uint32_t aRegIndex) {
    if (!s_handlersTableAddr) {
        s_handlersTableAddr = RED4ext::UniversalRelocBase::Resolve(RED4ext::Detail::AddressHashes::CBaseFunction_Handlers);
    }
    if (!s_handlersTableAddr) return 0;

    __try {
        auto table = *reinterpret_cast<NativeHandler_t**>(s_handlersTableAddr);
        if (table && aRegIndex < 65536) {
            auto handler = table[aRegIndex];
            return reinterpret_cast<uintptr_t>(handler);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
    }
    return 0;
}

static uintptr_t TryDisasmCallTarget(uintptr_t aHandlerAddr, uintptr_t aExeBase) {
    if (!aHandlerAddr || !aExeBase) return 0;
    __try {
        const uint8_t* bytes = reinterpret_cast<const uint8_t*>(aHandlerAddr);
        for (int i = 0; i < 32; ++i) {
            if (bytes[i] == 0xE8) { // CALL rel32
                int32_t rel = 0;
                std::memcpy(&rel, bytes + i + 1, sizeof(rel));
                uintptr_t target = (aHandlerAddr + i + 5) + rel;
                if (target >= aExeBase) {
                    return target - aExeBase;
                }
                break;
            }
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
    return 0;
}

static void TryDisasmBytes(uintptr_t aAddr, int count, char* outBuf, size_t bufSize) {
    if (!outBuf || bufSize == 0) return;
    outBuf[0] = '\0';
    if (!aAddr) {
        snprintf(outBuf, bufSize, "none");
        return;
    }
    __try {
        const uint8_t* p = reinterpret_cast<const uint8_t*>(aAddr);
        size_t off = 0;
        for (int i = 0; i < count && off + 4 < bufSize; ++i) {
            off += snprintf(outBuf + off, bufSize - off, "%02X ", p[i]);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        snprintf(outBuf, bufSize, "err");
    }
}

static void ScanSensitivityMultAccess(uintptr_t aExeBase, std::stringstream& ss) {
    if (!aExeBase) return;

    auto dosHeader = reinterpret_cast<const IMAGE_DOS_HEADER*>(aExeBase);
    if (dosHeader->e_magic != IMAGE_DOS_SIGNATURE) return;

    auto ntHeaders = reinterpret_cast<const IMAGE_NT_HEADERS*>(aExeBase + dosHeader->e_lfanew);
    if (ntHeaders->Signature != IMAGE_NT_SIGNATURE) return;

    auto section = IMAGE_FIRST_SECTION(ntHeaders);
    uintptr_t textStart = 0;
    size_t textSize = 0;

    for (WORD i = 0; i < ntHeaders->FileHeader.NumberOfSections; ++i, ++section) {
        if (std::memcmp(section->Name, ".text", 5) == 0) {
            textStart = aExeBase + section->VirtualAddress;
            textSize = section->Misc.VirtualSize;
            break;
        }
    }

    if (!textStart || !textSize) return;

    ss << "\n[N1] === Scanning .text for sensitivityMultX (0x498) & sensitivityMultY (0x49c) ===\n";

    const uint8_t* p = reinterpret_cast<const uint8_t*>(textStart);
    const uint8_t* end = p + textSize - 8;

    int hits = 0;
    __try {
        while (p < end) {
            // Check for 0x00000498 or 0x0000049c in immediate / displacement
            if ((p[0] == 0x98 || p[0] == 0x9C) && p[1] == 0x04 && p[2] == 0x00 && p[3] == 0x00) {
                uintptr_t hitAddr = reinterpret_cast<uintptr_t>(p);
                uintptr_t hitRva = hitAddr - aExeBase;
                const char* axis = (p[0] == 0x98) ? "sensitivityMultX (yaw)" : "sensitivityMultY (pitch)";

                ss << "  [SCAN HIT #" << std::dec << (++hits) << "] " << axis << " at RVA=0x" << std::hex << hitRva << " bytes: ";
                for (int b = -6; b <= 5; ++b) {
                    ss << std::setw(2) << std::setfill('0') << static_cast<int>(p[b]) << " ";
                }
                ss << "\n";
            }
            ++p;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        ss << "[N1] Memory read exception during .text scan.\n";
    }
    ss << "[N1] Scan completed. Total hits: " << std::dec << hits << "\n\n";
}

void InputHook::ProbeRTTI() {
    auto rtti = RED4ext::CRTTISystem::Get();
    if (!rtti) return;

    if (!s_exeBase) {
        HMODULE hExe = GetModuleHandleA("Cyberpunk2077.exe");
        if (hExe) s_exeBase = reinterpret_cast<uintptr_t>(hExe);
    }

    std::stringstream ss;
    ss << "[N0] exe=0x" << std::hex << s_exeBase << " build=2.50 bytesOK=1 patched=0\n";

    const char* classNames[] = {
        "gameFPPCameraComponent",
        "FPPCameraComponent",
        "CameraComponent",
        "entCameraComponent",
        "PlayerPuppet"
    };

    for (const char* className : classNames) {
        RED4ext::CClass* cls = rtti->GetClass(className);
        if (!cls) {
            cls = rtti->GetClassByScriptName(className);
        }

        if (!cls) {
            ss << "[N1] route=A class=" << className << " status=NOT_FOUND\n";
            continue;
        }

        const char* parentName = cls->parent ? cls->parent->name.ToString() : "none";
        ss << "[N1] route=A class=" << className
           << " size=0x" << std::hex << cls->size
           << " parent=" << parentName
           << " propsCount=" << std::dec << cls->props.size()
           << " funcsCount=" << cls->funcs.size() << "\n";

        // Enumerate properties
        for (uint32_t i = 0; i < cls->props.size(); ++i) {
            auto prop = cls->props[i];
            if (!prop) continue;
            const char* propName = prop->name.ToString();
            const char* typeName = (prop->type && prop->type->GetName().ToString()) ? prop->type->GetName().ToString() : "unknown";
            ss << "  [PROP] " << className << "." << (propName ? propName : "unnamed")
               << " type=" << typeName
               << " offset=0x" << std::hex << prop->valueOffset << "\n";
        }

        // Enumerate functions
        for (uint32_t i = 0; i < cls->funcs.size(); ++i) {
            auto fn = cls->funcs[i];
            if (!fn) continue;
            const char* shortName = fn->shortName.ToString();
            const char* fullName = fn->fullName.ToString();
            uint32_t regIdx = fn->GetRegIndex();

            uintptr_t handlerAddr = 0;
            uintptr_t handlerRva = 0;
            uintptr_t targetRva = 0;

            if (fn->flags.isNative) {
                handlerAddr = TryGetHandler(regIdx);
                if (handlerAddr && s_exeBase && handlerAddr >= s_exeBase) {
                    handlerRva = handlerAddr - s_exeBase;
                    targetRva = TryDisasmCallTarget(handlerAddr, s_exeBase);
                }
            }

            char disasmBuf[64] = {};
            TryDisasmBytes(targetRva ? (s_exeBase + targetRva) : handlerAddr, 16, disasmBuf, sizeof(disasmBuf));

            ss << "  [FUNC] " << (shortName ? shortName : (fullName ? fullName : "unnamed"))
               << " regIdx=" << std::dec << regIdx
               << " native=" << (fn->flags.isNative ? 1 : 0)
               << " handlerRva=0x" << std::hex << handlerRva
               << " targetRva=0x" << std::hex << targetRva
               << " targetBytes: " << disasmBuf << "\n";
        }
    }

    // Scan .text for sensitivityMultX (0x498) and sensitivityMultY (0x49c)
    ScanSensitivityMultAccess(s_exeBase, ss);

    std::string report = ss.str();

    // Write full report to log file (try multiple paths starting with CET mod directory)
    const char* logPaths[] = {
        "plugins/cyber_engine_tweaks/mods/DetachedReticle/rtti_probe.log",
        "../../red4ext/plugins/DetachedReticle/rtti_probe.log",
        "red4ext/plugins/DetachedReticle/rtti_probe.log",
        "rtti_probe.log"
    };

    for (const char* path : logPaths) {
        std::ofstream ofs(path);
        if (ofs.is_open()) {
            ofs << report;
            ofs.close();
            if (s_sdk && s_sdk->logger) {
                std::string msg = std::string("Route A RTTI probing written to: ") + path;
                s_sdk->logger->Info(s_handle, msg.c_str());
            }
            break;
        }
    }

    PushEvent("[N0] exe=0x" + (std::stringstream() << std::hex << s_exeBase).str() + " build=2.50 bytesOK=1 patched=0");
    PushEvent("[N1] route=A RTTI probe completed. Check rtti_probe.log for full details.");
}

} // namespace DetachedReticle

extern "C" void OnNativeMouseAim(void* aFpp, float* aYawDelta, float* aPitchDelta) {
    if (!aFpp || !aYawDelta || !aPitchDelta) return;
    DetachedReticle::InputHook::ProcessMouseAim(aFpp, *aYawDelta, *aPitchDelta, *aYawDelta, *aPitchDelta);
}

