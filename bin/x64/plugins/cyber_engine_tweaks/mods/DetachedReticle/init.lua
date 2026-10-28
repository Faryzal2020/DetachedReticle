-- DetachedReticle - Cyber Engine Tweaks Module
-- Phase: Decoupled Chained Aiming System
-- 1. Camera Freelook: 100% controllable ONLY with mouse. Nothing alters, clamps, decays, or pulls the camera back.
-- 2. Aiming Direction: The base world heading of the player puppet & weapon rig, smoothly chained towards Camera Reticle via modular catch-up algorithms.
-- 3. Gun Reticle: Physical weapon muzzle in 3D world space, naturally driven from Aiming Direction via vanilla animations, sway, recoil, and resting states.

local Config = {
    catchUpSpeed = 6.0,           -- Modular catch-up weight (higher = faster catch-up, lower = heavier lag)
    deadzone = 0.0,               -- Degrees: zero deadzone by default (configurable via options)
    maxDivergence = 65.0,         -- Degrees: maximum angular separation before pulling body
    smoothingMode = "exponential" -- "exponential", "linear", "spring", or "power"
}

local DetachedReticle = {
    version = "4.0.0-chase-probe",
    timer = 0,
    frameCounter = 0,
    probeMode = "L1", -- "L1" (pure observation, no teleport/camera writes), "L3" (camera yaw lock test), or "off"
    lockedYaw = nil,
    freeYaw = 0.0,
    freePitch = 0.0,
    rawMouseX = 0.0,
    rawMouseY = 0.0,
    entryNativePitch = 0.0,
    intendedWorldYaw = 0.0,
    bodyYaw = 0.0,
    baselinePos = nil,
    baselineRot = nil,
    isActive = false,
    mouseScale = 0.07, -- degrees per mouse unit
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

-- Modular Catch-Up Smoothing Algorithms
-- Each algorithm takes (diffYaw, diffPitch, divergenceMag, effectiveDivergence, dt, Config, DetachedReticle)
-- and returns (yawStep, pitchStep) to rotate the Aiming Direction towards the Camera Reticle
local Algorithms = {
    -- 1. Exponential decay: rate proportional to current angular divergence
    exponential = function(diffYaw, diffPitch, divergenceMag, effectiveDivergence, dt, cfg, state)
        local decay = 1.0 - math.exp(-cfg.catchUpSpeed * dt)
        decay = math.max(0.0, math.min(1.0, decay))
        if cfg.deadzone > 0.0 and divergenceMag > 0.001 then
            decay = decay * (effectiveDivergence / divergenceMag)
        end
        return diffYaw * decay, diffPitch * decay
    end,

    -- 2. Linear rate limit: constant angular speed (catchUpSpeed * 15.0 deg/sec)
    linear = function(diffYaw, diffPitch, divergenceMag, effectiveDivergence, dt, cfg, state)
        local rate = cfg.catchUpSpeed * 15.0 -- deg per second
        local maxStep = rate * dt
        local ratio = (divergenceMag > 0.001) and math.min(1.0, maxStep / divergenceMag) or 1.0
        if cfg.deadzone > 0.0 and divergenceMag > 0.001 then
            ratio = ratio * (effectiveDivergence / divergenceMag)
        end
        return diffYaw * ratio, diffPitch * ratio
    end,

    -- 3. Critically damped spring (SmoothDamp approximation):
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

    -- 4. Power-curve ramp: progressive acceleration as angle widens
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
                if data.catchUpSpeed ~= nil then Config.catchUpSpeed = tonumber(data.catchUpSpeed) or Config.catchUpSpeed end
                if data.deadzone ~= nil then Config.deadzone = tonumber(data.deadzone) or Config.deadzone end
                if data.maxDivergence ~= nil then Config.maxDivergence = tonumber(data.maxDivergence) or Config.maxDivergence end
                if data.smoothingMode ~= nil then Config.smoothingMode = tostring(data.smoothingMode):lower() end
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

local function LogProbe(rawLine)
    print(rawLine)
    local f = io.open("plugins/cyber_engine_tweaks/mods/DetachedReticle/DetachedReticle.log", "a")
    if not f then
        f = io.open("bin/x64/plugins/cyber_engine_tweaks/mods/DetachedReticle/DetachedReticle.log", "a")
    end
    if not f then
        f = io.open("DetachedReticle.log", "a")
    end
    if f then
        f:write(rawLine .. "\n")
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

local function toVector(v)
    return Vector4.new(v.x or v.X or 0.0, v.y or v.Y or 0.0, v.z or v.Z or 0.0, v.w or v.W or 1.0)
end

local function toQuaternion(q)
    return Quaternion.new(q.i or q.x or 0.0, q.j or q.y or 0.0, q.k or q.z or 0.0, q.r or q.w or 1.0)
end

local function registerInputListeners(player)
    if not player or not IsDefined(player) or player:IsReplacer() then
        return
    end

    if DetachedReticle.registeredPlayer == player then
        return
    end

    pcall(function()
        player:RegisterInputListener(player, "CameraMouseX")
        player:RegisterInputListener(player, "CameraMouseY")
        player:RegisterInputListener(player, "CameraX")
        player:RegisterInputListener(player, "CameraY")
        player:RegisterInputListener(player, "right_stick_x")
        player:RegisterInputListener(player, "right_stick_y")
        player:RegisterInputListener(player, "RangedAttack")
        player:RegisterInputListener(player, "mouse_left")
    end)

    DetachedReticle.registeredPlayer = player
    Log("Input listeners registered on PlayerPuppet.")
end

local function unregisterInputListeners(player)
    if not player or not IsDefined(player) then
        return
    end

    pcall(function()
        player:UnregisterInputListener(player, "CameraMouseX")
        player:UnregisterInputListener(player, "CameraMouseY")
        player:UnregisterInputListener(player, "CameraX")
        player:UnregisterInputListener(player, "CameraY")
        player:UnregisterInputListener(player, "right_stick_x")
        player:UnregisterInputListener(player, "right_stick_y")
        player:UnregisterInputListener(player, "RangedAttack")
        player:UnregisterInputListener(player, "mouse_left")
    end)

    DetachedReticle.registeredPlayer = nil
    Log("Input listeners unregistered from PlayerPuppet.")
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

            ns.addRangeFloat(
                "/detachedReticle/aiming",
                "Catch-up Speed",
                "Speed at which the body turns to align with the camera reticle (0 = pure freelook, 6 = default realistic)",
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
    Log(string.format("Initializing Chained Aiming System v%s | CatchUpSpeed=%.2f | Deadzone=%.2f deg | MaxDivergence=%.2f deg | Algorithm=%s",
        DetachedReticle.version, Config.catchUpSpeed, Config.deadzone, Config.maxDivergence, Config.smoothingMode))

    SetupNativeSettings()

    local player = Game.GetPlayer()
    if player then
        registerInputListeners(player)
    end

    Observe('PlayerPuppet', 'OnGameAttached', function(player)
        registerInputListeners(player)
    end)

    Observe('PlayerPuppet', 'OnTakeControl', function(player)
        registerInputListeners(player)
    end)

    Observe('PlayerPuppet', 'OnDetach', function(player)
        unregisterInputListeners(player)
    end)

    -- Intercept mouse look input:
    -- 1. Consume from body so raw mouse doesn't instantly snap the body
    -- 2. Accumulate delta exclusively for the Camera Freelook
    Observe('PlayerPuppet', 'OnAction', function(first, second, third)
        if not DetachedReticle.isActive then return end

        local action = (third ~= nil) and second or first
        local consumer = (third ~= nil) and third or second
        if not action then return end

        local listenerAction = GetSingleton('gameinputScriptListenerAction')
        if not listenerAction then return end

        local ok, actionName, actionValue = pcall(function()
            return Game.NameToString(listenerAction:GetName(action)), listenerAction:GetValue(action)
        end)

        if not ok or not actionName or not actionValue then return end

        if actionName == "RangedAttack" or actionName == "mouse_left" then
            if actionValue > 0.5 then
                Log(string.format("[FIRE INPUT DETECTED] Action=%s | FreeYaw=%.2f deg | FreePitch=%.2f deg | IsActive=%s",
                    actionName, DetachedReticle.freeYaw, DetachedReticle.freePitch, tostring(DetachedReticle.isActive)))
            end
        end

        -- Do NOT intercept mouse_left or RangedAttack; left click must fire the gun!
        if actionName == "CameraMouseX" or actionName == "CameraX" or actionName == "right_stick_x" then
            DetachedReticle.rawMouseX = DetachedReticle.rawMouseX + actionValue
            if DetachedReticle.probeMode == "off" and consumer then
                pcall(function() consumer:ConsumeSingleAction() end)
            end
        elseif actionName == "CameraMouseY" or actionName == "CameraY" or actionName == "right_stick_y" then
            DetachedReticle.rawMouseY = DetachedReticle.rawMouseY + actionValue
            if DetachedReticle.probeMode == "off" and consumer then
                pcall(function() consumer:ConsumeSingleAction() end)
            end
        end
    end)
end)

registerForEvent("onUpdate", function(delta)
    local player = Game.GetPlayer()
    if not player then return end

    if not DetachedReticle.registeredPlayer then
        registerInputListeners(player)
    end

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

    if isArmed and fpp then
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

        -- 2. Read camera component local orientation Euler angles
        local localPitch, localYaw, localRoll = 0.0, 0.0, 0.0
        local okRot, localRot = pcall(function() return fpp:GetLocalOrientation() end)
        if okRot and localRot then
            local euler = nil
            pcall(function() euler = localRot:ToEulerAngles() end)
            if not euler then
                pcall(function() euler = Quaternion.ToEulerAngles(localRot) end)
            end
            if euler then
                localPitch = euler.pitch or euler.Pitch or 0.0
                localYaw = euler.yaw or euler.Yaw or 0.0
                localRoll = euler.roll or euler.Roll or 0.0
            end
        end

        -- 3. Read camera component world yaw
        local camWorldYaw = 0.0
        local okMat, worldMatrix = pcall(function() return fpp:GetLocalToWorld() end)
        if okMat and worldMatrix then
            local okWorldRot, worldEuler = pcall(function() return Matrix.GetRotation(worldMatrix) end)
            if okWorldRot and worldEuler then
                camWorldYaw = worldEuler.yaw or worldEuler.Yaw or 0.0
            end
        end

        local rawX = DetachedReticle.rawMouseX or 0.0
        local rawY = DetachedReticle.rawMouseY or 0.0
        DetachedReticle.rawMouseX = 0.0
        DetachedReticle.rawMouseY = 0.0

        if DetachedReticle.probeMode == "L1" then
            -- PROBE L1: Observe raw mouse routing. Zero SetLocalTransform, zero Teleport.
            -- Vanilla natively rotates body in yaw and camera in pitch.
            local line = string.format("[F=%d] [L1] bodyYaw=%.4f camLocalPitch=%.4f camLocalYaw=%.4f camLocalRoll=%.4f camWorldYaw=%.4f rawX=%.4f rawY=%.4f",
                DetachedReticle.frameCounter, bodyYaw, localPitch, localYaw, localRoll, camWorldYaw, rawX, rawY)
            LogProbe(line)

        elseif DetachedReticle.probeMode == "L3" then
            -- PROBE L3: Script-side camera world-lock test.
            if not DetachedReticle.lockedYaw then
                DetachedReticle.lockedYaw = bodyYaw
                LogProbe(string.format("[F=%d] [L3] Baseline captured: lockedYaw=%.4f", DetachedReticle.frameCounter, DetachedReticle.lockedYaw))
            end

            if okRot and localRot then
                local relYaw = normalizeDeg(DetachedReticle.lockedYaw - bodyYaw)
                local qRz = quatAxisAngle(0.0, 0.0, 1.0, relYaw)
                local targetRot = quatMultiply(qRz, localRot)
                pcall(function()
                    fpp:SetLocalTransform(fpp:GetLocalPosition(), targetRot)
                end)
            end

            -- Re-read camera world transform after write
            local postWorldYaw = camWorldYaw
            local okPostMat, postMatrix = pcall(function() return fpp:GetLocalToWorld() end)
            if okPostMat and postMatrix then
                local okPostRot, postEuler = pcall(function() return Matrix.GetRotation(postMatrix) end)
                if okPostRot and postEuler then
                    postWorldYaw = postEuler.yaw or postEuler.Yaw or 0.0
                end
            end
            local err = normalizeDeg(postWorldYaw - DetachedReticle.lockedYaw)
            local line = string.format("[F=%d] [L3] bodyYaw=%.4f camWorldYaw=%.4f err=%.4f",
                DetachedReticle.frameCounter, bodyYaw, postWorldYaw, err)
            LogProbe(line)
        end
    else
        if DetachedReticle.isActive then
            DetachedReticle.isActive = false
            DetachedReticle.lockedYaw = nil
            DetachedReticle.rawMouseX = 0.0
            DetachedReticle.rawMouseY = 0.0
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
            local modeNum = 0
            local modeName = "Unknown"
            pcall(function()
                mPos = aimSys:GetLastShotMuzzlePos()
                bDir = aimSys:GetLastShotBulletDir()
                tPt = aimSys:GetLastShotTargetPt()
                angle = aimSys:GetLastShotAngleDeg()
                modeNum = aimSys:GetLastShotTestMode() or 0
                modeName = aimSys:GetLastShotTestModeName() or "Unknown"
            end)
            Log(string.format("[BALLISTICS RECORD #%d] [%s (Mode #%d)] GunDivergence=%.2f deg | FreeYaw=%.2f deg, FreePitch=%.2f deg | Muzzle=(%.2f, %.2f, %.2f) | BulletDir=(%.3f, %.3f, %.3f)",
                shotCount, modeName, modeNum, angle or 0.0, DetachedReticle.freeYaw, DetachedReticle.freePitch,
                (mPos and (mPos.x or mPos.X)) or 0.0, (mPos and (mPos.y or mPos.Y)) or 0.0, (mPos and (mPos.z or mPos.Z)) or 0.0,
                (bDir and (bDir.x or bDir.X)) or 0.0, (bDir and (bDir.y or bDir.Y)) or 0.0, (bDir and (bDir.z or bDir.Z)) or 0.0
            ))
        end
    end

    -- Periodic diagnostic health log every 3 seconds
    DetachedReticle.timer = DetachedReticle.timer + delta
    if DetachedReticle.timer >= 3.0 then
        DetachedReticle.timer = 0
        if DetachedReticle.isActive then
            local diffYaw = normalizeDeg(DetachedReticle.intendedWorldYaw - (DetachedReticle.bodyYaw or 0.0))
            Log(string.format("[STATUS] Chained Aiming ACTIVE | CamYaw=%.2f deg | BodyYaw=%.2f deg | DiffYaw=%.2f deg | Pitch=%.2f deg | Speed=%.1f | Deadzone=%.1f deg | Mode=%s",
                DetachedReticle.intendedWorldYaw, DetachedReticle.bodyYaw or 0.0, diffYaw, DetachedReticle.freePitch, Config.catchUpSpeed, Config.deadzone, Config.smoothingMode))
        end
    end
end)

registerForEvent("onShutdown", function()
    local player = Game.GetPlayer()
    local fpp = player and player:GetFPPCameraComponent()
    if fpp and DetachedReticle.baselinePos and DetachedReticle.baselineRot then
        pcall(function()
            fpp:SetLocalTransform(DetachedReticle.baselinePos, DetachedReticle.baselineRot)
        end)
    end
    if player then
        unregisterInputListeners(player)
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

        -- Round 4 Probe Selector
        ImGui.Separator()
        ImGui.Text("Round 4 Probe Mode:")
        local probeList = { "L1", "L3", "off" }
        for _, pMode in ipairs(probeList) do
            local isSelected = (DetachedReticle.probeMode == pMode)
            local label = (pMode == "L1") and "Probe L1 (Observation)" or ((pMode == "L3") and "Probe L3 (Camera Lock)" or "Off")
            if ImGui.RadioButton(label, isSelected) then
                DetachedReticle.SetProbeMode(pMode)
            end
            ImGui.SameLine()
        end
        ImGui.NewLine()

        ImGui.Separator()
        -- Live telemetry preview
        ImGui.Text(string.format("Status: %s", DetachedReticle.isActive and "ARMED" or "Holstered / Inactive"))
        ImGui.Text(string.format("Active Probe: %s | Frame: %d", DetachedReticle.probeMode, DetachedReticle.frameCounter or 0))
        ImGui.Text(string.format("Current Body Yaw: %.2f deg", DetachedReticle.bodyYaw or 0.0))
        if DetachedReticle.probeMode == "L3" and DetachedReticle.lockedYaw then
            ImGui.Text(string.format("Locked Yaw: %.2f deg", DetachedReticle.lockedYaw))
        end

        ImGui.End()
    end
end)

-- Console helper for switching probe modes from CET console:
DetachedReticle.SetProbeMode = function(mode)
    local m = tostring(mode):upper()
    if m == "L1" or m == "L3" or m == "OFF" then
        DetachedReticle.probeMode = (m == "OFF") and "off" or m
        DetachedReticle.lockedYaw = nil
        Log(string.format("[PROBE] Probe mode changed to: %s", DetachedReticle.probeMode))
    else
        Log(string.format("[PROBE] Unknown probe mode '%s'. Options: L1, L3, off", tostring(mode)))
    end
end

-- Console helper for switching test modes from CET console:
DetachedReticle.SetMode = function(mode)
    local aimSys = nil
    pcall(function()
        aimSys = Game.GetScriptableSystemsContainer():Get(CName.new("DetachedReticle.DetachedAimSystem"))
    end)
    if aimSys then
        local m = tonumber(mode) or 0
        aimSys:SetTestMode(m)
        Log(string.format("[CONFIG] Test Mode changed to: %d", m))
    end
end

-- Modular Options API for CET Console and in-game adjustment:
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

DetachedReticle.GetOptions = function()
    Log(string.format("[OPTIONS] catchUpSpeed=%.2f | deadzone=%.2f deg | maxDivergence=%.2f deg | smoothingMode=%s",
        Config.catchUpSpeed, Config.deadzone, Config.maxDivergence, Config.smoothingMode))
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
