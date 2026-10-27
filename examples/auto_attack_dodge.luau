--[[
    Auto Attack + Auto Dodge — Rayfield Edition
    Uses Rayfield (https://sirius.menu/rayfield) — battle-tested, Delta-compatible.
    Default Rayfield theme has a translucent dark + blur aesthetic that gives
    the Liquid Glass look. Accent set to glass-blue.

    Features:
      Combat tab:
        - Auto Attack (toggle + hotkey) — finds closest player in range, fires Attack remote
        - Attack Range slider (1-30 studs)
        - Attack Cooldown slider (0.1-2s)
        - Always Crit toggle
      Dodge tab:
        - Auto Dodge (toggle + hotkey) — detects nearby enemies attacking you and evades
        - Dodge Range slider (3-15 studs) — trigger distance
        - Dodge Mode (Jump / Strafe / Both / Backdash)
        - Dodge Cooldown slider (0.3-3s)
      Visuals tab:
        - Target Highlight toggle (Filled / Outline)
        - Range Ring (ground circle showing attack range)
        - Visual Color picker
      Settings tab:
        - Unload button
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- ================================================================ cleanup ====
local store = (type(getgenv) == "function" and getgenv()) or _G
if store.LG_AAD_Conns then
    for _, c in ipairs(store.LG_AAD_Conns) do
        pcall(function() c:Disconnect() end)
    end
    store.LG_AAD_Conns = nil
end
local conns = {}
store.LG_AAD_Conns = conns
local function track(c)
    if c then table.insert(conns, c) end
    return c
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
killOld("Rayfield")
killOld("LG_AAD_Ring")
killOld("LG_AAD_Highlight")

-- ================================================================ library ====
local okFetch, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)
if not okFetch or type(Rayfield) ~= "table" then
    warn("[AAD] Failed to load Rayfield: " .. tostring(Rayfield))
    return
end

-- ================================================================ remotes ====
local attackRemote = nil
local swingRemote = nil
local combatReady = false
do
    local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 6)
    if remotesFolder then
        attackRemote = remotesFolder:WaitForChild("Attack", 6)
        if attackRemote then
            combatReady = true
            swingRemote = remotesFolder:WaitForChild("Swing", 2)
        end
    end
end

-- ================================================================ state ====
local autoAttackOn = false
local autoDodgeOn = false
local lastAttack = 0
local attackCount = 0
local cooldown = 0.625
local range = 8
local alwaysCrit = true

local dodgeRange = 8
local dodgeCooldown = 0.8
local dodgeMode = "Both"
local lastDodge = 0

local highlightOn = true
local highlightMode = "Filled"
local ringOn = false
local visualColor = Color3.fromRGB(96, 165, 250)

-- ================================================================ visuals ====
local ring = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function removeRing()
    if ring then pcall(function() ring:Destroy() end); ring = nil end
end
local function createRing()
    removeRing()
    ring = Instance.new("Part")
    ring.Name = "LG_AAD_Ring"
    ring.Shape = Enum.PartType.Cylinder
    ring.Size = Vector3.new(0.06, range * 2, range * 2)
    ring.Color = visualColor
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
    if not ring then return end
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    rayParams.FilterDescendantsInstances = { char, ring }
    local origin = root.Position
    local result = Workspace:Raycast(origin, Vector3.new(0, -12, 0), rayParams)
    local groundY = result and result.Position.Y or (origin.Y - 2.7)
    ring.Size = Vector3.new(0.06, range * 2, range * 2)
    ring.CFrame = CFrame.new(origin.X, groundY + 0.05, origin.Z) * CFrame.Angles(0, 0, math.rad(90))
end

local currentHighlight = nil
local function clearHighlight()
    if currentHighlight then pcall(function() currentHighlight:Destroy() end); currentHighlight = nil end
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
local function setTargetHighlight(targetChar)
    if not highlightOn or not targetChar then clearHighlight(); return end
    if currentHighlight and currentHighlight.Parent == targetChar then return end
    clearHighlight()
    local ok = pcall(function()
        currentHighlight = Instance.new("Highlight")
        currentHighlight.Name = "LG_AAD_Highlight"
        currentHighlight.FillColor = visualColor
        currentHighlight.OutlineColor = visualColor
        currentHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        applyHighlightStyle(currentHighlight)
        currentHighlight.Parent = targetChar
    end)
    if not ok then currentHighlight = nil end
end
local function refreshVisualColors()
    if ring then ring.Color = visualColor end
    if currentHighlight then
        pcall(function()
            currentHighlight.FillColor = visualColor
            currentHighlight.OutlineColor = visualColor
        end)
    end
end

-- ================================================================ helpers ====
local function getEyePosition(character)
    if not character then return nil end
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    return root.Position / 3 + Vector3.new(0, 0.72, 0)
end

local function getClosestTarget(maxDist)
    local character = player.Character
    local eye = getEyePosition(character)
    if not eye then return nil, nil end
    local closest, closestDist = nil, maxDist
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player then
            local otherChar = otherPlayer.Character
            local root = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
            local hum = otherChar and otherChar:FindFirstChildOfClass("Humanoid")
            if root and hum and hum.Health > 0 then
                local targetPos = root.Position / 3
                local dist = (targetPos - eye).Magnitude
                if dist <= closestDist then
                    closest = otherChar
                    closestDist = dist
                end
            end
        end
    end
    return closest, closestDist
end

-- ================================================================ dodge ====
-- Heuristic: when an enemy within dodgeRange is moving toward us at speed
-- (velocity dot direction-to-us > threshold) AND is roughly facing us,
-- trigger evasive movement. Cooldown prevents spam.
local function performDodge(enemyRoot, myRoot, myHum)
    if not myHum or myHum.Health <= 0 then return end
    local toMe = (myRoot.Position - enemyRoot.Position)
    if toMe.Magnitude < 1e-3 then return end
    toMe = toMe.Unit
    -- perpendicular axis (horizontal only)
    local perp = Vector3.new(-toMe.Z, 0, toMe.X)
    -- flip perp randomly per dodge so we don't always dodge same way
    if math.random() < 0.5 then perp = -perp end

    if dodgeMode == "Jump" then
        myHum.Jump = true
    elseif dodgeMode == "Strafe" then
        myHum:Move(perp * 6, false)
        -- nudge velocity for immediate effect
        local bv = myRoot:FindFirstChild("LG_AAD_DodgeBV")
        if not bv then
            bv = Instance.new("BodyVelocity")
            bv.Name = "LG_AAD_DodgeBV"
            bv.MaxForce = Vector3.new(1e5, 0, 1e5)
            bv.P = 1e4
            bv.Parent = myRoot
        end
        bv.Velocity = perp * 32
        task.delay(0.18, function()
            pcall(function() bv:Destroy() end)
        end)
    elseif dodgeMode == "Both" then
        myHum.Jump = true
        myHum:Move(perp * 6, false)
        local bv = myRoot:FindFirstChild("LG_AAD_DodgeBV")
        if not bv then
            bv = Instance.new("BodyVelocity")
            bv.Name = "LG_AAD_DodgeBV"
            bv.MaxForce = Vector3.new(1e5, 0, 1e5)
            bv.P = 1e4
            bv.Parent = myRoot
        end
        bv.Velocity = perp * 28
        task.delay(0.18, function()
            pcall(function() bv:Destroy() end)
        end)
    elseif dodgeMode == "Backdash" then
        myHum:Move(-toMe * 6, false)
        local bv = myRoot:FindFirstChild("LG_AAD_DodgeBV")
        if not bv then
            bv = Instance.new("BodyVelocity")
            bv.Name = "LG_AAD_DodgeBV"
            bv.MaxForce = Vector3.new(1e5, 0, 1e5)
            bv.P = 1e4
            bv.Parent = myRoot
        end
        bv.Velocity = (-toMe) * 30
        task.delay(0.18, function()
            pcall(function() bv:Destroy() end)
        end)
    end
end

local function checkDodge()
    if not autoDodgeOn then return end
    if tick() - lastDodge < dodgeCooldown then return end
    local character = player.Character
    local myRoot = character and character:FindFirstChild("HumanoidRootPart")
    local myHum = character and character:FindFirstChildOfClass("Humanoid")
    if not myRoot or not myHum or myHum.Health <= 0 then return end

    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player then
            local otherChar = otherPlayer.Character
            local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
            local otherHum = otherChar and otherChar:FindFirstChildOfClass("Humanoid")
            if otherRoot and otherHum and otherHum.Health > 0 then
                local delta = myRoot.Position - otherRoot.Position
                local dist = delta.Magnitude
                if dist <= dodgeRange then
                    local dir = dist > 1e-3 and (delta / dist) or Vector3.zero
                    local vel = otherRoot.AssemblyLinearVelocity or otherRoot.Velocity
                    local horizVel = Vector3.new(vel.X, 0, vel.Z)
                    local approachSpeed = horizVel:Dot(dir)
                    -- enemy moving toward us faster than ~6 studs/s and roughly facing us
                    local enemyLook = otherRoot.CFrame.LookVector
                    local facingUs = enemyLook:Dot(-dir)
                    if approachSpeed > 6 and facingUs > 0 then
                        performDodge(otherRoot, myRoot, myHum)
                        lastDodge = tick()
                        return
                    end
                end
            end
        end
    end
end

-- ================================================================ window ====
local Window = Rayfield:CreateWindow({
    Name = "Auto Attack + Dodge",
    LoadingTitle = "Loading AAD",
    LoadingSubtitle = "Rayfield edition",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false,
    Theme = "Default",
    DisableRayfieldPrompts = true,
    DisableUnhandledWarnings = true,
})

-- accent: glass blue
pcall(function() Window:SetAccent(Color3.fromRGB(96, 165, 250)) end)

-- ================================================================ Combat ====
local CombatTab = Window:CreateTab("Combat", "swords")

local autoToggleCtl = CombatTab:CreateToggle({
    Name = "Auto Attack",
    CurrentValue = false,
    Callback = function(state)
        autoAttackOn = state
        if not state then clearHighlight() end
        Rayfield:Notify({
            Title = state and "Auto Attack ON" or "Auto Attack OFF",
            Content = state and ("Targeting within " .. tostring(range) .. " studs") or "Standby",
            Duration = 2.5,
            Image = state and "check" or "circle",
        })
    end,
})

CombatTab:CreateSlider({
    Name = "Attack Range",
    Range = { 1, 30 },
    Increment = 0.5,
    Suffix = "studs",
    CurrentValue = range,
    Callback = function(v) range = v end,
})

CombatTab:CreateSlider({
    Name = "Attack Cooldown",
    Range = { 0.1, 2 },
    Increment = 0.025,
    Suffix = "s",
    CurrentValue = cooldown,
    Callback = function(v) cooldown = v end,
})

CombatTab:CreateToggle({
    Name = "Always Crit",
    CurrentValue = alwaysCrit,
    Callback = function(s) alwaysCrit = s end,
})

CombatTab:CreateKeybind({
    Name = "Toggle Attack Hotkey",
    CurrentKeybind = "F",
    Callback = function()
        local newState = not autoAttackOn
        autoAttackOn = newState
        if autoToggleCtl then pcall(function() autoToggleCtl:Set(newState) end) end
        if not newState then clearHighlight() end
        Rayfield:Notify({
            Title = newState and "Auto Attack ON" or "Auto Attack OFF",
            Content = "Hotkey toggled",
            Duration = 2,
            Image = newState and "check" or "circle",
        })
    end,
})

-- ================================================================ Dodge ====
local DodgeTab = Window:CreateTab("Dodge", "shield")

local dodgeToggleCtl = DodgeTab:CreateToggle({
    Name = "Auto Dodge",
    CurrentValue = false,
    Callback = function(state)
        autoDodgeOn = state
        Rayfield:Notify({
            Title = state and "Auto Dodge ON" or "Auto Dodge OFF",
            Content = state and ("Evading within " .. tostring(dodgeRange) .. " studs") or "Standby",
            Duration = 2.5,
            Image = state and "check" or "circle",
        })
    end,
})

DodgeTab:CreateSlider({
    Name = "Dodge Range",
    Range = { 3, 15 },
    Increment = 0.5,
    Suffix = "studs",
    CurrentValue = dodgeRange,
    Callback = function(v) dodgeRange = v end,
})

DodgeTab:CreateDropdown({
    Name = "Dodge Mode",
    Options = { "Jump", "Strafe", "Both", "Backdash" },
    CurrentOption = dodgeMode,
    Callback = function(opt) dodgeMode = opt end,
})

DodgeTab:CreateSlider({
    Name = "Dodge Cooldown",
    Range = { 0.3, 3 },
    Increment = 0.1,
    Suffix = "s",
    CurrentValue = dodgeCooldown,
    Callback = function(v) dodgeCooldown = v end,
})

DodgeTab:CreateKeybind({
    Name = "Toggle Dodge Hotkey",
    CurrentKeybind = "G",
    Callback = function()
        local newState = not autoDodgeOn
        autoDodgeOn = newState
        if dodgeToggleCtl then pcall(function() dodgeToggleCtl:Set(newState) end) end
        Rayfield:Notify({
            Title = newState and "Auto Dodge ON" or "Auto Dodge OFF",
            Content = "Hotkey toggled",
            Duration = 2,
            Image = newState and "check" or "circle",
        })
    end,
})

-- ================================================================ Visuals ====
local VisualsTab = Window:CreateTab("Visuals", "eye")

VisualsTab:CreateToggle({
    Name = "Target Highlight",
    CurrentValue = highlightOn,
    Callback = function(s)
        highlightOn = s
        if not s then clearHighlight() end
    end,
})

VisualsTab:CreateDropdown({
    Name = "Highlight Style",
    Options = { "Filled", "Outline" },
    CurrentOption = highlightMode,
    Callback = function(opt)
        highlightMode = opt
        if currentHighlight then pcall(function() applyHighlightStyle(currentHighlight) end) end
    end,
})

VisualsTab:CreateToggle({
    Name = "Range Ring (ground circle)",
    CurrentValue = ringOn,
    Callback = function(s)
        ringOn = s
        if s then createRing() else removeRing() end
    end,
})

VisualsTab:CreateColorPicker({
    Name = "Visual Color",
    Color = visualColor,
    Callback = function(c)
        visualColor = c
        refreshVisualColors()
    end,
})

-- ================================================================ Settings ====
local SettingsTab = Window:CreateTab("Settings", "settings")

if not combatReady then
    SettingsTab:CreateParagraph({
        Title = "Combat unavailable",
        Content = "This game has no ReplicatedStorage.Remotes.Attack remote. UI loaded; auto attack won't fire. Auto dodge still works.",
    })
end

SettingsTab:CreateButton({
    Name = "Unload Script",
    Callback = function()
        autoAttackOn = false
        autoDodgeOn = false
        removeRing()
        clearHighlight()
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        conns = {}
        store.LG_AAD_Conns = nil
        pcall(function() Rayfield:Destroy() end)
        killOld("Rayfield")
        killOld("LG_AAD_Ring")
        killOld("LG_AAD_Highlight")
        print("[AAD] Unloaded.")
    end,
})

-- ================================================================ notify ====
if not combatReady then
    task.delay(0.5, function()
        pcall(function()
            Rayfield:Notify({
                Title = "Combat unavailable",
                Content = "No Remotes.Attack in this game. UI loaded; dodge still works.",
                Duration = 6,
                Image = "alert-triangle",
            })
        end)
    end)
end

-- ================================================================ loops ====
track(RunService.Heartbeat:Connect(function()
    -- ring always follows player when on
    if ringOn then updateRing() end

    -- dodge check (cheap, runs every frame but bails fast on cooldown)
    checkDodge()

    -- attack
    if not autoAttackOn then return end
    if not attackRemote then return end
    if tick() - lastAttack < cooldown then return end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end

    local eyePosition = getEyePosition(character)
    if not eyePosition then return end

    local closestTarget, closestDistance = getClosestTarget(range)
    if not closestTarget then
        clearHighlight()
        return
    end

    if highlightOn then setTargetHighlight(closestTarget) end

    local targetRoot = closestTarget:FindFirstChild("HumanoidRootPart")
    if not targetRoot then return end

    local targetPosition = targetRoot.Position / 3
    local dir = targetPosition - eyePosition
    if dir.Magnitude < 1e-4 then return end

    lastAttack = tick()
    attackCount = attackCount + 1

    if swingRemote then swingRemote:FireServer() end
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
end))

print("[AAD] Loaded via Rayfield. Combat ready: " .. tostring(combatReady))
