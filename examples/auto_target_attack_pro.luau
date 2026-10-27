--[[
    Auto Target Attack — PRO
    powered by personallib (LiquidGlass UI)

    Upgrades over the base version:
      - Attack Range slider (1-16 studs, live FOV ring resizing)
      - Attack Cooldown slider (0.1-2s)
      - Always Crit toggle
      - Toggle hotkey (bind any key)
      - Range / FOV circle that follows you and sticks to the ground
      - Target highlight (Filled / Outline, custom color)
      - Theme switcher (5 themes) + Unload button
      - Safe loader core: on-screen diagnostics + 2 mirror fallbacks
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- ================================================================ cleanup ====
local store = (type(getgenv) == "function" and getgenv()) or _G
if store.LG_AutoTargetConn then
    pcall(function() store.LG_AutoTargetConn:Disconnect() end)
    store.LG_AutoTargetConn = nil
end

local function killOld(name)
    local holders = {}
    if type(gethui) == "function" then
        pcall(function() holders[#holders + 1] = gethui() end)
    end
    pcall(function() holders[#holders + 1] = game:GetService("CoreGui") end)
    pcall(function() holders[#holders + 1] = player:FindFirstChildOfClass("PlayerGui") end)
    for _, holder in ipairs(holders) do
        local old = holder and holder:FindFirstChild(name, true)
        if old then pcall(function() old:Destroy() end) end
    end
end

killOld("LiquidGlass_Auto Target Attack")
killOld("LG_Loader_Status")
killOld("LG_FOV_Ring")
killOld("LG_TargetHighlight")

-- ========================================================= status console ====
local statusGui = Instance.new("ScreenGui")
statusGui.Name = "LG_Loader_Status"
statusGui.ResetOnSpawn = false
statusGui.IgnoreGuiInset = true
statusGui.DisplayOrder = 2147483647

local okParent = pcall(function()
    local pg = player:FindFirstChildOfClass("PlayerGui")
    if not pg then
        pg = player:WaitForChild("PlayerGui", 5)
    end
    statusGui.Parent = pg
end)
if not okParent or not statusGui.Parent then
    pcall(function()
        statusGui.Parent = (type(gethui) == "function" and gethui()) or game:GetService("CoreGui")
    end)
end

local box = Instance.new("Frame")
box.Size = UDim2.fromOffset(460, 250)
box.Position = UDim2.new(0.5, -230, 0.5, -125)
box.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
box.BackgroundTransparency = 0.08
box.BorderSizePixel = 0
box.Parent = statusGui

local boxCorner = Instance.new("UICorner")
boxCorner.CornerRadius = UDim.new(0, 12)
boxCorner.Parent = box

local boxStroke = Instance.new("UIStroke")
boxStroke.Color = Color3.fromRGB(96, 150, 255)
boxStroke.Transparency = 0.5
boxStroke.Thickness = 1.5
boxStroke.Parent = box

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -24, 0, 30)
title.Position = UDim2.new(0, 12, 0, 8)
title.BackgroundTransparency = 1
title.Text = "LiquidGlass Loader — PRO"
title.TextColor3 = Color3.fromRGB(235, 240, 250)
title.TextSize = 16
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = box

local logLabel = Instance.new("TextLabel")
logLabel.Size = UDim2.new(1, -24, 1, -50)
logLabel.Position = UDim2.new(0, 12, 0, 42)
logLabel.BackgroundTransparency = 1
logLabel.Text = ""
logLabel.TextColor3 = Color3.fromRGB(180, 190, 205)
logLabel.TextSize = 13
logLabel.Font = Enum.Font.Code
logLabel.TextXAlignment = Enum.TextXAlignment.Left
logLabel.TextYAlignment = Enum.TextYAlignment.Top
logLabel.TextWrapped = true
logLabel.Parent = box

local lines = {}
local function trace(e)
    if type(debug) == "table" and type(debug.traceback) == "function" then
        local ok, tb = pcall(debug.traceback, e, 2)
        if ok and type(tb) == "string" then
            return tb
        end
    end
    return tostring(e)
end

local function log(msg)
    table.insert(lines, msg)
    while #lines > 8 do
        table.remove(lines, 1)
    end
    logLabel.Text = table.concat(lines, "\n")
    warn("[LG PRO] " .. msg)
end

local function closeStatus(delay)
    task.delay(delay or 1.2, function()
        pcall(function() statusGui:Destroy() end)
    end)
end

-- ================================================================== fetch ====
log("[1/4] Fetching library...")

local SOURCES = {
    "https://raw.githubusercontent.com/flexyfresh8-prog/personallib/main/build/LiquidGlass.lua",
    "https://cdn.jsdelivr.net/gh/flexyfresh8-prog/personallib@main/build/LiquidGlass.lua",
}

local src = nil
for i, url in ipairs(SOURCES) do
    local ok, res = pcall(function()
        return game:HttpGet(url)
    end)
    if ok and type(res) == "string" and #res > 10000 then
        src = res
        log("[OK] Source " .. i .. " fetched (" .. tostring(#res) .. " bytes)")
        break
    else
        log("[FAIL] Source " .. i .. " -> " .. tostring(res))
    end
end

if not src then
    log("")
    log("ALL SOURCES FAILED. Your network is most likely")
    log("blocking GitHub. Try mobile data / different wifi.")
    return
end

log("[2/4] Compiling...")
local fn, compileErr = loadstring(src)
if not fn then
    log("[FAIL] Compile error:")
    log(tostring(compileErr))
    return
end
log("[OK] Compiled")

log("[3/4] Running library...")
local okRun, result = xpcall(fn, trace)
if not okRun then
    log("[FAIL] Runtime error:")
    log(tostring(result))
    return
end

local Lib = result
if type(Lib) ~= "table" or type(Lib.CreateWindow) ~= "function" then
    log("[FAIL] Library object invalid: " .. tostring(Lib))
    return
end
log("[OK] Library ready")

log("[4/4] Building PRO UI...")

-- =============================================================== remotes =====
local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
assert(remotes, "[Auto Target Attack] ReplicatedStorage.Remotes not found")
local attackRemote = remotes:WaitForChild("Attack", 10)
assert(attackRemote, "[Auto Target Attack] Remotes.Attack not found")
local swingRemote = remotes:WaitForChild("Swing", 5)

-- ================================================================== state ====
local isToggled = false
local lastAttack = 0
local attackCount = 0
local cooldown = 0.625
local range = 4
local alwaysCrit = true
local showRing = false
local showHighlight = true
local highlightMode = "Filled"
local highlightColor = Color3.fromRGB(96, 150, 255)

-- =================================================================== ring ====
local ring = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function removeRing()
    if ring then
        pcall(function() ring:Destroy() end)
        ring = nil
    end
end

local function createRing()
    removeRing()
    ring = Instance.new("Part")
    ring.Name = "LG_FOV_Ring"
    ring.Shape = Enum.PartType.Cylinder
    ring.Size = Vector3.new(0.06, range * 2, range * 2)
    ring.Color = highlightColor
    ring.Material = Enum.Material.Neon
    ring.Transparency = 0.65
    ring.Anchored = true
    ring.CanCollide = false
    ring.CanQuery = false
    ring.CanTouch = false
    ring.CastShadow = false
    ring.Parent = Workspace
end

local function updateRing()
    if not ring then
        return
    end
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        return
    end
    rayParams.FilterDescendantsInstances = { character, ring }
    local origin = root.Position
    local result = Workspace:Raycast(origin, Vector3.new(0, -12, 0), rayParams)
    local groundY = result and result.Position.Y or (origin.Y - 2.7)
    ring.Size = Vector3.new(0.06, range * 2, range * 2)
    ring.CFrame = CFrame.new(origin.X, groundY + 0.05, origin.Z) * CFrame.Angles(0, 0, math.rad(90))
end

-- ============================================================== highlight ====
local currentHighlight = nil

local function clearHighlight()
    if currentHighlight then
        pcall(function() currentHighlight:Destroy() end)
        currentHighlight = nil
    end
end

local function applyHighlightStyle(h)
    if highlightMode == "Outline" then
        h.FillTransparency = 1
        h.OutlineTransparency = 0
    else
        h.FillTransparency = 0.65
        h.OutlineTransparency = 0
    end
end

local function setTargetHighlight(targetCharacter)
    if not showHighlight or not targetCharacter then
        clearHighlight()
        return
    end
    if currentHighlight and currentHighlight.Parent == targetCharacter then
        return
    end
    clearHighlight()
    local ok = pcall(function()
        currentHighlight = Instance.new("Highlight")
        currentHighlight.Name = "LG_TargetHighlight"
        currentHighlight.FillColor = highlightColor
        currentHighlight.OutlineColor = highlightColor
        currentHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        applyHighlightStyle(currentHighlight)
        currentHighlight.Parent = targetCharacter
    end)
    if not ok then
        currentHighlight = nil
    end
end

local function refreshVisualColors()
    if ring then
        ring.Color = highlightColor
    end
    if currentHighlight then
        pcall(function()
            currentHighlight.FillColor = highlightColor
            currentHighlight.OutlineColor = highlightColor
        end)
    end
end

-- ==================================================================== app ====
local Window, Tab, VisualsTab, SettingsTab
local autoToggleCtl = nil

local function notifyState(on)
    Window:Notify({
        Title = on and "Auto Attack ENABLED" or "Auto Attack DISABLED",
        Description = on and ("Targeting players within " .. tostring(range) .. " studs") or "Standby",
        Type = on and "success" or "info",
        Duration = 2.5,
    })
end

local function setAttackState(newState)
    newState = newState == true
    if isToggled == newState then
        return
    end
    isToggled = newState
    if not isToggled then
        clearHighlight()
    end
    if autoToggleCtl then
        pcall(function() autoToggleCtl:Set(isToggled, true) end)
    end
    notifyState(isToggled)
end

local okApp, appErr = xpcall(function()
    Window = Lib:CreateWindow({
        Title = "Auto Target Attack",
        Subtitle = "PRO",
        Theme = "Midnight",
    })

    ------------------------------------------------------------- Combat ----
    Tab = Window:CreateTab({ Name = "Combat", Icon = "⚔" })

    Tab:CreateSection({ Name = "COMBAT" })

    autoToggleCtl = Tab:CreateToggle({
        Name = "Auto Attack",
        Description = "Attacks the closest player in range",
        Default = false,
        Callback = function(state)
            isToggled = state
            if not isToggled then
                clearHighlight()
            end
            notifyState(state)
        end,
    })

    Tab:CreateSlider({
        Name = "Attack Range",
        Min = 1,
        Max = 16,
        Increment = 0.5,
        Default = 4,
        Suffix = "studs",
        Callback = function(value)
            range = value
        end,
    })

    Tab:CreateSlider({
        Name = "Attack Cooldown",
        Min = 0.1,
        Max = 2,
        Increment = 0.025,
        Default = 0.625,
        Suffix = "s",
        Callback = function(value)
            cooldown = value
        end,
    })

    Tab:CreateToggle({
        Name = "Always Crit",
        Default = true,
        Callback = function(state)
            alwaysCrit = state
        end,
    })

    Tab:CreateKeybind({
        Name = "Toggle Hotkey",
        Callback = function()
            setAttackState(not isToggled)
        end,
    })

    ------------------------------------------------------------ Visuals ----
    VisualsTab = Window:CreateTab({ Name = "Visuals", Icon = "◎" })

    VisualsTab:CreateSection({ Name = "RANGE" })

    VisualsTab:CreateToggle({
        Name = "Range Circle",
        Description = "Ground ring showing your attack range",
        Default = false,
        Callback = function(state)
            showRing = state
            if showRing then
                createRing()
            else
                removeRing()
            end
        end,
    })

    VisualsTab:CreateSection({ Name = "TARGET" })

    VisualsTab:CreateToggle({
        Name = "Target Highlight",
        Default = true,
        Callback = function(state)
            showHighlight = state
            if not state then
                clearHighlight()
            end
        end,
    })

    VisualsTab:CreateDropdown({
        Name = "Highlight Style",
        Options = { "Filled", "Outline" },
        Default = "Filled",
        Callback = function(choice)
            highlightMode = choice
            if currentHighlight then
                pcall(function() applyHighlightStyle(currentHighlight) end)
            end
        end,
    })

    VisualsTab:CreateColorPicker({
        Name = "Visual Color",
        Default = highlightColor,
        Callback = function(color)
            highlightColor = color
            refreshVisualColors()
        end,
    })

    ------------------------------------------------------------ Settings ---
    SettingsTab = Window:CreateTab({ Name = "Settings", Icon = "⚙" })

    SettingsTab:CreateSection({ Name = "APPEARANCE" })

    SettingsTab:CreateDropdown({
        Name = "Theme",
        Options = { "Midnight", "Arctic", "Aurora", "Sunset", "Obsidian" },
        Default = "Midnight",
        Callback = function(choice)
            pcall(function() Window:SetTheme(choice) end)
        end,
    })

    SettingsTab:CreateSection({ Name = "DANGER ZONE" })

    SettingsTab:CreateButton({
        Name = "Unload Script",
        Description = "Removes the UI, ring, highlight and stops everything",
        Callback = function()
            setAttackState(false)
            removeRing()
            clearHighlight()
            if store.LG_AutoTargetConn then
                pcall(function() store.LG_AutoTargetConn:Disconnect() end)
                store.LG_AutoTargetConn = nil
            end
            pcall(function() Window:Destroy() end)
            killOld("LiquidGlass_Auto Target Attack")
            print("[Auto Target Attack PRO] Unloaded.")
        end,
    })
end, trace)

if not okApp then
    log("[FAIL] UI error:")
    log(tostring(appErr))
    return
end

log("[OK] Loaded! Closing this box...")

-- ================================================================ combat =====
local function getEyePosition(character)
    if not character then
        return nil
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then
        return nil
    end
    return root.Position / 3 + Vector3.new(0, 0.72, 0)
end

store.LG_AutoTargetConn = RunService.Heartbeat:Connect(function()
    -- ring follows the player every frame (cheap: one raycast + one CFrame)
    if showRing then
        updateRing()
    end

    if not isToggled then
        return
    end

    if tick() - lastAttack < cooldown then
        return
    end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return
    end

    local eyePosition = getEyePosition(character)
    if not eyePosition then
        return
    end

    local closestTarget = nil
    local closestDistance = range

    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player then
            local otherCharacter = otherPlayer.Character
            local root = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
            local otherHumanoid = otherCharacter and otherCharacter:FindFirstChildOfClass("Humanoid")
            if root and otherHumanoid and otherHumanoid.Health > 0 then
                local targetPosition = root.Position / 3
                local distance = (targetPosition - eyePosition).Magnitude
                if distance <= closestDistance then
                    closestTarget = otherCharacter
                    closestDistance = distance
                end
            end
        end
    end

    if not closestTarget then
        clearHighlight()
        return
    end

    setTargetHighlight(closestTarget)

    local targetRoot = closestTarget:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        return
    end

    local targetPosition = targetRoot.Position / 3

    local dir = targetPosition - eyePosition
    if dir.Magnitude < 1e-4 then
        return
    end

    lastAttack = tick()
    attackCount += 1

    if swingRemote then
        swingRemote:FireServer()
    end

    attackRemote:FireServer(closestTarget, {
        sprint = false,
        charge = 1,
        vt = Workspace:GetServerTimeNow(),
        dir = dir.Unit,
        eye = eyePosition,
        t = Workspace.DistributedGameTime,
        crit = alwaysCrit,
        n = attackCount,
    })
end)

closeStatus(1.2)
print("[Auto Target Attack PRO] Loaded via safe loader.")
