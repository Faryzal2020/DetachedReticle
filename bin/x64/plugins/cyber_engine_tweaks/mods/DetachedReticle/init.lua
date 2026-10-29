-- DetachedReticle - Cyber Engine Tweaks Module
-- Decoupled Aiming System (MVP 2 Production Release)
-- 1. Camera Freelook: 100% controllable with mouse gaze; zero lag, instant response.
-- 2. Physical Aiming Direction: Weapon rig & body smoothly lag behind and chase gaze via native exponential smoothing.
-- 3. Muzzle Ballistics: Bullets launch physically from weapon barrel in 3D world space.

local Config = {
    enabled = true,               -- Master switch for decoupled aiming
    catchUpSpeed = 6.0,           -- Catch-up speed (higher = faster, lower = heavier physical weight)
    deadzone = 0.0,               -- Degrees: zero deadzone by default (turns immediately)
    maxDivergence = 65.0,         -- Degrees: maximum angular separation before pulling body
    smoothingMode = "exponential",-- "exponential", "linear", "spring", or "power"
    debugLogging = true           -- Verbose telemetry logging to DetachedReticle.log
}

local DetachedReticle = {
    version = "2.0.0",
    timer = 0,
    frameCounter = 0,
    bodyYaw = 0.0,
    baselineRot = nil,
    origHeadingLocked = nil,
    origSensX = nil,
    origSensY = nil,
    isActive = false,
    chaseActive = false,
    registeredPlayer = nil,
    lastShotCount = 0,
    isOverlayOpen = false,
    nativeSettingsInitAttempted = false
}

-- Math Helpers for Angle Normalization & Vectors
local function normalizeDeg(angle)
    while angle > 180.0 do angle = angle - 360.0 end
    while angle < -180.0 do angle = angle + 360.0 end
    return angle
end

-- Modular Catch-Up Smoothing Algorithms (script-side fallbacks/references)
local Algorithms = {
    exponential = function(diffYaw, diffPitch, divergenceMag, effectiveDivergence, dt, cfg, state)
        local decay = 1.0 - math.exp(-cfg.catchUpSpeed * dt)
        decay = math.max(0.0, math.min(1.0, decay))
        if cfg.deadzone > 0.0 and divergenceMag > 0.001 then
            decay = decay * (effectiveDivergence / divergenceMag)
        end
        return diffYaw * decay, diffPitch * decay
    end,

    linear = function(diffYaw, diffPitch, divergenceMag, effectiveDivergence, dt, cfg, state)
        local rate = cfg.catchUpSpeed * 15.0
        local maxStep = rate * dt
        local ratio = (divergenceMag > 0.001) and math.min(1.0, maxStep / divergenceMag) or 1.0
        if cfg.deadzone > 0.0 and divergenceMag > 0.001 then
            ratio = ratio * (effectiveDivergence / divergenceMag)
        end
        return diffYaw * ratio, diffPitch * ratio
    end,

    spring = function(diffYaw, diffPitch, divergenceMag, effectiveDivergence, dt, cfg, state)
        local omega = cfg.catchUpSpeed
        local expVal = 1.0 / (1.0 + omega * dt + 0.48 * omega * omega * dt * dt + 0.235 * omega * omega * omega * dt * dt * dt)
        local decay = 1.0 - expVal
        decay = math.max(0.0, math.min(1.0, decay))
        if cfg.deadzone > 0.0 and divergenceMag > 0.001 then
            decay = decay * (effectiveDivergence / divergenceMag)
        end
        return diffYaw * decay, diffPitch * decay
    end,

    power = function(diffYaw, diffPitch, divergenceMag, effectiveDivergence, dt, cfg, state)
        local norm = math.min(1.0, effectiveDivergence / math.max(1.0, cfg.maxDivergence))
        local ramp = norm ^ 1.5
        local decay = (1.0 - math.exp(-cfg.catchUpSpeed * dt)) * (0.2 + 0.8 * ramp)
        decay = math.max(0.0, math.min(1.0, decay))
        return diffYaw * decay, diffPitch * decay
    end
}

local function LoadConfig()
    local f = io.open("plugins/cyber_engine_tweaks/mods/DetachedReticle/config.json", "r")
    if not f then
        f = io.open("bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/config.json", "r")
    end
    if f then
        local content = f:read("*a")
        f:close()
        if content and #content > 0 then
            local ok, data = pcall(json.decode, content)
            if ok and type(data) == "table" then
                if data.enabled ~= nil then Config.enabled = (data.enabled == true) end
                if data.catchUpSpeed ~= nil then Config.catchUpSpeed = tonumber(data.catchUpSpeed) or Config.catchUpSpeed end
                if data.deadzone ~= nil then Config.deadzone = tonumber(data.deadzone) or Config.deadzone end
                if data.maxDivergence ~= nil then Config.maxDivergence = tonumber(data.maxDivergence) or Config.maxDivergence end
                if data.smoothingMode ~= nil then Config.smoothingMode = tostring(data.smoothingMode):lower() end
                if data.debugLogging ~= nil then Config.debugLogging = (data.debugLogging == true) end
            end
        end
    end
end

local function SaveConfig()
    local ok, content = pcall(json.encode, Config)
    if ok and content then
        local f = io.open("plugins/cyber_engine_tweaks/mods/DetachedReticle/config.json", "w")
        if not f then
            f = io.open("bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/config.json", "w")
        end
        if f then
            f:write(content)
            f:flush()
            f:close()
        end
    end
end

local function Log(msg)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local line = string.format("[%s] [DetachedReticle] %s", timestamp, msg)
    print(string.format("[DetachedReticle] %s", msg))

    local f = io.open("plugins/cyber_engine_tweaks/mods/DetachedReticle/DetachedReticle.log", "a")
    if not f then
        f = io.open("bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/DetachedReticle.log", "a")
    end
    if not f then
        f = io.open("DetachedReticle.log", "a")
    end
    if f then
        f:write(line .. "\n")
        f:flush()
        f:close()
    end
end

-- Math Helpers for Quaternions & Vectors (CET Sol sandbox compatible)
local function quatAxisAngle(x, y, z, deg)
    local rad = math.rad(deg)
    local half = rad * 0.5
    local s = math.sin(half)
    return Quaternion.new(x * s, y * s, z * s, math.cos(half))
end

local function quatMultiply(a, b)
    local ar = a.r or a.w or 1
    local ai = a.i or a.x or 0
    local aj = a.j or a.y or 0
    local ak = a.k or a.z or 0

    local br = b.r or b.w or 1
    local bi = b.i or b.x or 0
    local bj = b.j or b.y or 0
    local bk = b.k or b.z or 0

    return Quaternion.new(
        ar * bi + ai * br + aj * bk - ak * bj,
        ar * bj - ai * bk + aj * br + ak * bi,
        ar * bk + ai * bj - aj * bi + ak * br,
        ar * br - ai * bi - aj * bj - ak * bk
    )
end

local function SetupNativeSettings()
    if DetachedReticle.nativeSettingsInitAttempted then return true end

    local ns = nil
    pcall(function()
        ns = GetMod("nativeSettings") or GetMod("NativeSettings")
    end)
    if not ns then return false end

    local ok = pcall(function()
        if not ns.pathExists("/detachedReticle") then
            ns.addTab("/detachedReticle", "Detached Reticle")
            ns.addSubcategory("/detachedReticle/aiming", "Aiming & Catch-up Settings")

            ns.addSwitch(
                "/detachedReticle/aiming",
                "Enable Decoupled Aim",
                "Master switch to toggle decoupled aiming and physical muzzle ballistics",
                Config.enabled, true,
                function(val)
                    DetachedReticle.SetEnabled(val)
                end
            )

            ns.addRangeFloat(
                "/detachedReticle/aiming",
                "Catch-up Speed",
                "Speed at which the body and gun turn to align with the camera reticle (0 = pure freelook, 6 = default realistic)",
                0.0, 30.0, 0.5, "%.1f", Config.catchUpSpeed, 6.0,
                function(val)
                    DetachedReticle.SetCatchUpSpeed(val)
                end
            )

            ns.addRangeFloat(
                "/detachedReticle/aiming",
                "Deadzone Angle",
                "Angular zone where the body does not turn towards the camera (0.0 = zero deadzone, turns immediately)",
                0.0, 30.0, 0.5, "%.1f deg", Config.deadzone, 0.0,
                function(val)
                    DetachedReticle.SetDeadzone(val)
                end
            )

            ns.addRangeFloat(
                "/detachedReticle/aiming",
                "Max Divergence",
                "Maximum angular separation between camera and body before pulling the body along immediately",
                15.0, 110.0, 1.0, "%.0f deg", Config.maxDivergence, 65.0,
                function(val)
                    DetachedReticle.SetMaxDivergence(val)
                end
            )

            local algoOptions = { "Exponential", "Linear", "Spring", "Power" }
            local currentIdx = 1
            for i, name in ipairs(algoOptions) do
                if name:lower() == Config.smoothingMode:lower() then
                    currentIdx = i
                    break
                end
            end

            ns.addSelectorString(
                "/detachedReticle/aiming",
                "Catch-up Algorithm",
                "Modular algorithm used to calculate the catch-up curve towards the camera reticle",
                algoOptions, currentIdx, 1,
                function(idx)
                    local selected = algoOptions[idx] or "Exponential"
                    DetachedReticle.SetSmoothingMode(selected:lower())
                end
            )

            Log("[SETTINGS] NativeSettings tab '/detachedReticle' successfully initialized.")
        end
    end)

    DetachedReticle.nativeSettingsInitAttempted = ok
    return ok
end

registerForEvent("onInit", function()
    LoadConfig()
    Log(string.format("Initializing Decoupled Aiming System v%s | Enabled=%s | Speed=%.1f | Deadzone=%.1f deg | MaxDiv=%.1f deg | Algorithm=%s",
        DetachedReticle.version, tostring(Config.enabled), Config.catchUpSpeed, Config.deadzone, Config.maxDivergence, Config.smoothingMode))

    SetupNativeSettings()
end)

registerForEvent("onUpdate", function(delta)
    local player = Game.GetPlayer()
    if not player then return end

    if not DetachedReticle.nativeSettingsInitAttempted then
        SetupNativeSettings()
    end

    local isDual = false
    pcall(function()
        isDual = GameObject.IsDualWielding(player)
    end)
    local weapon = GameObject.GetRightActiveWeapon(player)
    local isArmed = weapon and not weapon:IsMelee() and not isDual
    local fpp = player:GetFPPCameraComponent()

    if Config.enabled and isArmed and fpp then
        DetachedReticle.isActive = true
        DetachedReticle.frameCounter = (DetachedReticle.frameCounter or 0) + 1

        -- 1. Read player puppet world yaw in engine convention
        local bodyYaw = 0.0
        local okYaw, valYaw = pcall(function() return player:GetWorldYaw() end)
        if okYaw and valYaw then
            bodyYaw = valYaw
        else
            local okFwd, fwd = pcall(function() return player:GetWorldForward() end)
            if okFwd and fwd then
                local okHead, head = pcall(function() return Vector4.Heading(fwd) end)
                if okHead and head then bodyYaw = head end
            end
        end
        DetachedReticle.bodyYaw = bodyYaw

        -- 2. Read camera component local orientation
        local localRot = nil
        pcall(function() localRot = fpp:GetLocalOrientation() end)

        if not DetachedReticle.chaseActive then
            DetachedReticle.chaseActive = true
            DetachedReticle.baselineRot = localRot or Quaternion.new(0, 0, 0, 1)

            -- Capture baseline sensitivity and heading lock before enabling chase
            local okNatX, natX = pcall(function() return Game.DR_GetSensitivityMultX(fpp) end)
            local okNatY, natY = pcall(function() return Game.DR_GetSensitivityMultY(fpp) end)
            local okPropX, propX = pcall(function() return fpp.sensitivityMultX end)
            local okPropY, propY = pcall(function() return fpp.sensitivityMultY end)
            DetachedReticle.origSensX = (okNatX and type(natX) == "number" and natX > 0.0) and natX or ((okPropX and type(propX) == "number") and propX or 1.0)
            DetachedReticle.origSensY = (okNatY and type(natY) == "number" and natY > 0.0) and natY or ((okPropY and type(propY) == "number") and propY or 1.0)

            local okHead, headLocked = pcall(function() return Game.DR_GetHeadingLocked(fpp) end)
            DetachedReticle.origHeadingLocked = (okHead and headLocked) or false

            -- Get initial camera pitch before chase begins
            local initPitch = 0.0
            pcall(function()
                local aimSys = Game.GetScriptableSystemsContainer():Get(CName.new("DetachedReticle.DetachedAimSystem"))
                if aimSys then
                    local fwd = aimSys:GetCameraForward()
                    if fwd and (fwd.x ~= 0 or fwd.y ~= 0 or fwd.z ~= 0) then
                        local fx = fwd.x or fwd.X or 0.0
                        local fy = fwd.y or fwd.Y or 0.0
                        local fz = fwd.z or fwd.Z or 0.0
                        local xy = math.sqrt(fx * fx + fy * fy)
                        if xy > 0.0001 or math.abs(fz) > 0.0001 then
                            initPitch = math.deg(math.atan2(fz, xy))
                        end
                    end
                end
            end)

            -- Reset native chase state with initial pitch and activate native look smoothing
            pcall(function() Game.DR_ResetChasePitch(initPitch) end)
            pcall(function() Game.DR_SetSmoothing(Config.catchUpSpeed, 0, Config.maxDivergence, Config.deadzone, true) end)

            -- Ensure heading lock is FALSE so engine actuates native chase deltas
            pcall(function() Game.DR_SetHeadingLocked(fpp, false) end)
            pcall(function() fpp.headingLocked = false end)

            -- Ensure sensitivity multipliers are at baseline
            pcall(function() Game.DR_SetSensitivityMult(fpp, DetachedReticle.origSensX, DetachedReticle.origSensY) end)
            pcall(function() fpp.sensitivityMultX = DetachedReticle.origSensX end)
            pcall(function() fpp.sensitivityMultY = DetachedReticle.origSensY end)

            Log(string.format("Decoupled Aim ACTIVE: speed=%.1f maxDiv=%.1f deadzone=%.1f initPitch=%.2f",
                Config.catchUpSpeed, Config.maxDivergence, Config.deadzone, initPitch))
        end

        -- Read native camera residuals (R = T - A)
        local rYaw = 0.0
        local rPitch = 0.0
        pcall(function() rYaw = Game.DR_GetResidualYaw() end)
        pcall(function() rPitch = Game.DR_GetResidualPitch() end)

        -- Read native continuous camera pitch angle (tracked smoothly in C++ from raw mouse input)
        local nativePitch = 0.0
        pcall(function() nativePitch = Game.DR_GetAimPitch() end)
        local pitchRad = math.rad(nativePitch)
        local fwdZ = math.sin(pitchRad)
        local fwdXY = math.cos(pitchRad)

        -- Compose residual onto camera local orientation without gimbal roll:
        -- 1. qRx: pitch around local horizontal right axis (1, 0, 0)
        -- 2. qRz: yaw around true gravity-up axis (0, fwdZ, fwdXY) in parent coordinate frame
        local baseline = DetachedReticle.baselineRot or Quaternion.new(0, 0, 0, 1)
        local qRx = quatAxisAngle(1.0, 0.0, 0.0, rPitch)
        local qRz = quatAxisAngle(0.0, fwdZ, fwdXY, rYaw)
        local qRel = quatMultiply(qRz, qRx)
        local targetRot = quatMultiply(qRel, baseline)
        pcall(function()
            fpp:SetLocalTransform(fpp:GetLocalPosition(), targetRot)
        end)

        if Config.debugLogging and (DetachedReticle.frameCounter % 30 == 0 or math.abs(rYaw) > 0.05 or math.abs(rPitch) > 0.05) then
            local tYaw = 0.0
            local aYaw = 0.0
            local tPitch = 0.0
            local aPitch = 0.0
            pcall(function() tYaw = Game.DR_GetTargetYaw() end)
            pcall(function() aYaw = Game.DR_GetAimYaw() end)
            pcall(function() tPitch = Game.DR_GetTargetPitch() end)
            pcall(function() aPitch = Game.DR_GetAimPitch() end)
            local line = string.format("[F=%d] bodyYaw=%.4f rYaw=%.4f rPitch=%.4f tPitch=%.4f aPitch=%.4f fwdZ=%.4f fwdXY=%.4f",
                DetachedReticle.frameCounter, bodyYaw, rYaw, rPitch, tPitch, aPitch, fwdZ, fwdXY)
            Log(line)
        end
    else
        if DetachedReticle.isActive then
            DetachedReticle.isActive = false
            if DetachedReticle.chaseActive then
                DetachedReticle.chaseActive = false
                pcall(function() Game.DR_SetSmoothing(Config.catchUpSpeed, 0, Config.maxDivergence, Config.deadzone, false) end)
            end
            if fpp then
                if DetachedReticle.baselineRot then
                    pcall(function()
                        fpp:SetLocalTransform(fpp:GetLocalPosition(), DetachedReticle.baselineRot)
                    end)
                end
                -- Restore heading lock and sensitivity multipliers
                if DetachedReticle.origHeadingLocked ~= nil then
                    pcall(function() Game.DR_SetHeadingLocked(fpp, DetachedReticle.origHeadingLocked) end)
                    pcall(function() fpp.headingLocked = DetachedReticle.origHeadingLocked end)
                end
                if DetachedReticle.origSensX and DetachedReticle.origSensY then
                    pcall(function() Game.DR_SetSensitivityMult(fpp, DetachedReticle.origSensX, DetachedReticle.origSensY) end)
                    pcall(function() fpp.sensitivityMultX = DetachedReticle.origSensX end)
                    pcall(function() fpp.sensitivityMultY = DetachedReticle.origSensY end)
                end
            end
            DetachedReticle.baselineRot = nil
            DetachedReticle.origHeadingLocked = nil
            DetachedReticle.origSensX = nil
            DetachedReticle.origSensY = nil
        end
    end

    -- Telemetry bridge: poll DetachedAimSystem for ballistics shot telemetry
    local aimSys = nil
    pcall(function()
        aimSys = Game.GetScriptableSystemsContainer():Get(CName.new("DetachedReticle.DetachedAimSystem"))
    end)
    if aimSys then
        local okCount, shotCount = pcall(function() return aimSys:GetShotCount() end)
        if okCount and shotCount and shotCount > (DetachedReticle.lastShotCount or 0) then
            DetachedReticle.lastShotCount = shotCount
            local mPos, bDir, tPt, angle = nil, nil, nil, 0.0
            pcall(function()
                mPos = aimSys:GetLastShotMuzzlePos()
                bDir = aimSys:GetLastShotBulletDir()
                tPt = aimSys:GetLastShotTargetPt()
                angle = aimSys:GetLastShotAngleDeg()
            end)
            Log(string.format("[BALLISTICS RECORD #%d] Divergence=%.2f deg | Muzzle=(%.2f, %.2f, %.2f) | BulletDir=(%.3f, %.3f, %.3f)",
                shotCount, angle or 0.0,
                (mPos and (mPos.x or mPos.X)) or 0.0, (mPos and (mPos.y or mPos.Y)) or 0.0, (mPos and (mPos.z or mPos.Z)) or 0.0,
                (bDir and (bDir.x or bDir.X)) or 0.0, (bDir and (bDir.y or bDir.Y)) or 0.0, (bDir and (bDir.z or bDir.Z)) or 0.0
            ))
        end
    end
end)

registerForEvent("onShutdown", function()
    local player = Game.GetPlayer()
    local fpp = player and player:GetFPPCameraComponent()
    if fpp then
        if DetachedReticle.baselineRot then
            pcall(function()
                fpp:SetLocalTransform(fpp:GetLocalPosition(), DetachedReticle.baselineRot)
            end)
        end
        if DetachedReticle.origHeadingLocked ~= nil then
            pcall(function() Game.DR_SetHeadingLocked(fpp, DetachedReticle.origHeadingLocked) end)
            pcall(function() fpp.headingLocked = DetachedReticle.origHeadingLocked end)
        end
        if DetachedReticle.origSensX and DetachedReticle.origSensY then
            pcall(function() Game.DR_SetSensitivityMult(fpp, DetachedReticle.origSensX, DetachedReticle.origSensY) end)
            pcall(function() fpp.sensitivityMultX = DetachedReticle.origSensX end)
            pcall(function() fpp.sensitivityMultY = DetachedReticle.origSensY end)
        end
    end
    Log("Shutdown cleanly.")
end)

-- CET Overlay UI
registerForEvent("onOverlayOpen", function()
    DetachedReticle.isOverlayOpen = true
end)

registerForEvent("onOverlayClose", function()
    DetachedReticle.isOverlayOpen = false
end)

registerForEvent("onDraw", function()
    if not DetachedReticle.isOverlayOpen then return end

    if ImGui.Begin("Detached Reticle Options", true, ImGuiWindowFlags.AlwaysAutoResize) then
        ImGui.Text(string.format("Detached Reticle v%s", DetachedReticle.version))
        ImGui.Separator()

        -- Enable Mod Checkbox
        local newEnabled, enabledChanged = ImGui.Checkbox("Enable Decoupled Aim", Config.enabled)
        if enabledChanged then
            DetachedReticle.SetEnabled(newEnabled)
        end

        -- Catch-Up Speed Slider
        local newSpeed, speedChanged = ImGui.SliderFloat("Catch-up Speed", Config.catchUpSpeed, 0.0, 30.0, "%.1f")
        if speedChanged then
            DetachedReticle.SetCatchUpSpeed(newSpeed)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Speed at which the body turns to align with the camera reticle.\n0 = Body doesn't catch up (pure freelook)\n6 = Default realistic smoothed weight\n20+ = Fast / snappy")
        end

        -- Deadzone Slider (Zero deadzone by default)
        local newDeadzone, dzChanged = ImGui.SliderFloat("Deadzone", Config.deadzone, 0.0, 30.0, "%.1f deg")
        if dzChanged then
            DetachedReticle.SetDeadzone(newDeadzone)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Angular zone within which the body does not turn.\n0.0 deg = Zero deadzone (any mouse movement immediately turns body)")
        end

        -- Max Divergence Slider
        local newMaxDiv, maxDivChanged = ImGui.SliderFloat("Max Divergence", Config.maxDivergence, 15.0, 110.0, "%.1f deg")
        if maxDivChanged then
            DetachedReticle.SetMaxDivergence(newMaxDiv)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Maximum angle the camera can look away from the body before dragging the body along immediately.")
        end

        -- Algorithm Selector
        ImGui.Separator()
        ImGui.Text("Catch-Up Algorithm:")
        local algoList = { "exponential", "linear", "spring", "power" }
        for _, algoName in ipairs(algoList) do
            local isSelected = (Config.smoothingMode:lower() == algoName)
            if ImGui.RadioButton(algoName:gsub("^%l", string.upper), isSelected) then
                DetachedReticle.SetSmoothingMode(algoName)
            end
            ImGui.SameLine()
        end
        ImGui.NewLine()

        -- Debug Telemetry Checkbox
        local newDebug, debugChanged = ImGui.Checkbox("Verbose Debug Logging", Config.debugLogging)
        if debugChanged then
            DetachedReticle.SetDebugLogging(newDebug)
        end

        ImGui.Separator()
        -- Live status preview
        local statusStr = "Disabled"
        if Config.enabled then
            statusStr = DetachedReticle.isActive and "ARMED (Decoupled)" or "Holstered / Inactive"
        end
        ImGui.Text(string.format("Status: %s", statusStr))
        ImGui.Text(string.format("Current Body Yaw: %.2f deg", DetachedReticle.bodyYaw or 0.0))
        if DetachedReticle.isActive then
            local rYaw = 0.0
            local rPitch = 0.0
            pcall(function() rYaw = Game.DR_GetResidualYaw() end)
            pcall(function() rPitch = Game.DR_GetResidualPitch() end)
            ImGui.Text(string.format("Camera Residual: Yaw=%.2f deg | Pitch=%.2f deg", rYaw, rPitch))
        end

        ImGui.End()
    end
end)

-- Modular Options API for CET Console and in-game adjustment:
DetachedReticle.SetEnabled = function(val)
    Config.enabled = val and true or false
    SaveConfig()
    if not Config.enabled and DetachedReticle.chaseActive then
        DetachedReticle.chaseActive = false
        pcall(function() Game.DR_SetSmoothing(Config.catchUpSpeed, 0, Config.maxDivergence, Config.deadzone, false) end)
        local player = Game.GetPlayer()
        local fpp = player and player:GetFPPCameraComponent()
        if fpp and DetachedReticle.baselineRot then
            pcall(function() fpp:SetLocalTransform(fpp:GetLocalPosition(), DetachedReticle.baselineRot) end)
        end
    end
    Log(string.format("[OPTIONS] Enabled set to: %s", tostring(Config.enabled)))
end

DetachedReticle.SetCatchUpSpeed = function(val)
    Config.catchUpSpeed = math.max(0.0, tonumber(val) or 6.0)
    SaveConfig()
    Log(string.format("[OPTIONS] catchUpSpeed set to: %.2f", Config.catchUpSpeed))
end

DetachedReticle.SetDeadzone = function(val)
    Config.deadzone = math.max(0.0, tonumber(val) or 0.0)
    SaveConfig()
    Log(string.format("[OPTIONS] deadzone set to: %.2f deg", Config.deadzone))
end

DetachedReticle.SetMaxDivergence = function(val)
    Config.maxDivergence = math.max(10.0, tonumber(val) or 65.0)
    SaveConfig()
    Log(string.format("[OPTIONS] maxDivergence set to: %.2f deg", Config.maxDivergence))
end

DetachedReticle.SetSmoothingMode = function(mode)
    local m = tostring(mode):lower()
    if Algorithms[m] then
        Config.smoothingMode = m
        SaveConfig()
        Log(string.format("[OPTIONS] smoothingMode set to: %s", Config.smoothingMode))
    else
        Log(string.format("[OPTIONS] Unknown smoothing mode '%s'. Available: %s", mode, table.concat(DetachedReticle.GetAlgorithms(), ", ")))
    end
end

DetachedReticle.SetDebugLogging = function(val)
    Config.debugLogging = val and true or false
    SaveConfig()
    Log(string.format("[OPTIONS] debugLogging set to: %s", tostring(Config.debugLogging)))
end

DetachedReticle.GetOptions = function()
    Log(string.format("[OPTIONS] enabled=%s | catchUpSpeed=%.2f | deadzone=%.2f deg | maxDivergence=%.2f deg | smoothingMode=%s",
        tostring(Config.enabled), Config.catchUpSpeed, Config.deadzone, Config.maxDivergence, Config.smoothingMode))
    return Config
end

DetachedReticle.RegisterAlgorithm = function(name, fn)
    if type(name) == "string" and type(fn) == "function" then
        Algorithms[name:lower()] = fn
        Log(string.format("[ALGORITHM] Registered custom catch-up algorithm: '%s'", name))
    end
end

DetachedReticle.GetAlgorithms = function()
    local names = {}
    for k, _ in pairs(Algorithms) do
        table.insert(names, k)
    end
    table.sort(names)
    return names
end

return DetachedReticle
