--[[
    Auto Attack + Auto Dodge — Rayfield Gen 2 Edition (Sakura Theme + Mayhem)
    Uses Rayfield Gen2 (https://sirius.menu/gen2) — full rebuild, faster and
    more stable than the original. Custom Sakura theme with cherry-blossom
    pinks on a warm dark plum base.

    Sakura environment (since Rayfield is open source, animations go mayhem):
      - 36 procedurally-generated cherry blossom petals falling, swaying, and
        rotating across the whole screen, forever.
      - A procedural sakura tree in the lower-left: brown gradient trunk +
        8 overlapping pink canopy circles, gently swaying.
      - Window entrance: scale 0.85 -> 1 with Back easing + slight rotation.
      - Window idle drift: subtle figure-8 via RunService (sin/cos).
      - Petal burst at the window center on every toggle change and hotkey.

    Tabs:
      Combat:  Auto Attack (toggle + F hotkey), Range, Cooldown, Always Crit
      Dodge:   Auto Dodge (toggle + G hotkey), Range, Mode, Cooldown
      Visuals: Target Highlight (Filled/Outline), Range Ring, Visual Color
      Settings: Unload
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- ================================================================ cleanup ====
local store = (type(getgenv) == "function" and getgenv()) or _G
if store.LG_AAD2_Conns then
    for _, c in ipairs(store.LG_AAD2_Conns) do
        pcall(function() c:Disconnect() end)
    end
    store.LG_AAD2_Conns = nil
end
local conns = {}
store.LG_AAD2_Conns = conns
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
killOld("LG_AAD2_Ring")
killOld("LG_AAD2_Highlight")
killOld("LG_SakuraEnv")

-- ================================================================ library ====
local okFetch, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)
if not okFetch or type(Rayfield) ~= "table" then
    warn("[AAD2] Failed to load Rayfield Gen2: " .. tostring(Rayfield))
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
local visualColor = Color3.fromRGB(255, 122, 171) -- cherry pink

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
    ring.Name = "LG_AAD2_Ring"
    ring.Shape = Enum.PartType.Cylinder
    ring.Size = Vector3.new(0.06, range * 2, range * 2)
    ring.Color = visualColor
    ring.Material = Enum.Material.Neon
    ring.Transparency = 0.55
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
        h.FillTransparency = 0.6
        h.OutlineTransparency = 0
    end
end
local function setTargetHighlight(targetChar)
    if not highlightOn or not targetChar then clearHighlight(); return end
    if currentHighlight and currentHighlight.Parent == targetChar then return end
    clearHighlight()
    local ok = pcall(function()
        currentHighlight = Instance.new("Highlight")
        currentHighlight.Name = "LG_AAD2_Highlight"
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
-- AND roughly facing us, trigger evasive movement. Cooldown prevents spam.
local function performDodge(enemyRoot, myRoot, myHum)
    if not myHum or myHum.Health <= 0 then return end
    local toMe = (myRoot.Position - enemyRoot.Position)
    if toMe.Magnitude < 1e-3 then return end
    toMe = toMe.Unit
    -- perpendicular axis (horizontal only)
    local perp = Vector3.new(-toMe.Z, 0, toMe.X)
    if math.random() < 0.5 then perp = -perp end

    local function makeBV(vel)
        local bv = myRoot:FindFirstChild("LG_AAD2_DodgeBV")
        if not bv then
            bv = Instance.new("BodyVelocity")
            bv.Name = "LG_AAD2_DodgeBV"
            bv.MaxForce = Vector3.new(1e5, 0, 1e5)
            bv.P = 1e4
            bv.Parent = myRoot
        end
        bv.Velocity = vel
        task.delay(0.18, function() pcall(function() bv:Destroy() end) end)
    end

    if dodgeMode == "Jump" then
        myHum.Jump = true
    elseif dodgeMode == "Strafe" then
        myHum:Move(perp * 6, false)
        makeBV(perp * 32)
    elseif dodgeMode == "Both" then
        myHum.Jump = true
        myHum:Move(perp * 6, false)
        makeBV(perp * 28)
    elseif dodgeMode == "Backdash" then
        myHum:Move(-toMe * 6, false)
        makeBV((-toMe) * 30)
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

-- ================================================================ sakura env ====
-- Actual visible cherry blossom petals falling across the screen + a
-- procedural sakura tree decoration. Animation mayhem: entrance, idle drift,
-- glow pulse, and petal bursts on every toggle change.

local TweenService = game:GetService("TweenService")
local sakuraGui = nil
local petalFolder = nil
local treeFolder = nil
local envConns = {}

local function trackEnv(c) if c then table.insert(envConns, c) end; return c end

local PETAL_COLORS = {
    Color3.fromRGB(255, 183, 197),
    Color3.fromRGB(255, 210, 225),
    Color3.fromRGB(255, 122, 171),
    Color3.fromRGB(255, 143, 171),
    Color3.fromRGB(255, 235, 238),
}

-- One petal: a Frame with UICorner shaped like a rounded petal, gradient fill,
-- falling+swaying+rotating forever.
local function makePetal(parent, vpW, vpH)
    local size = math.random(8, 22)
    local p = Instance.new("Frame")
    p.Name = "Petal"
    p.Size = UDim2.fromOffset(size, math.floor(size * 0.78))
    p.BackgroundColor3 = PETAL_COLORS[math.random(1, #PETAL_COLORS)]
    p.BackgroundTransparency = math.random(20, 80) / 100
    p.BorderSizePixel = 0
    p.Rotation = math.random(0, 359)
    p.ZIndex = 9998

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.55, 0)
    corner.Parent = p

    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new(p.BackgroundColor3, Color3.fromRGB(255, 245, 248))
    grad.Rotation = math.random(0, 360)
    grad.Parent = p

    p.Parent = parent
    p.Position = UDim2.fromOffset(math.random(-20, vpW + 20), -size)

    local function drop()
        local startX = p.Position.X.Offset
        local targetX = startX + math.random(-120, 120)
        local targetY = vpH + size + 20
        local dur = math.random(7, 16)
        local sway = math.random(40, 120)

        -- position fall
        local posInfo = TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
        local posTween = TweenService:Create(p, posInfo, {
            Position = UDim2.fromOffset(targetX, targetY),
        })
        local rotInfo = TweenInfo.new(dur, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
        local rotTween = TweenService:Create(p, rotInfo, {
            Rotation = p.Rotation + math.random(-720, 720),
        })
        -- sway: nested sine oscillation via two opposing tweens
        local swayInfo = TweenInfo.new(sway / 60, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
        local swayA = TweenService:Create(p, swayInfo, { Position = UDim2.fromOffset(targetX - sway, p.Position.Y.Offset) })
        local swayB = TweenService:Create(p, swayInfo, { Position = UDim2.fromOffset(targetX + sway, p.Position.Y.Offset) })

        posTween:Play()
        rotTween:Play()
        swayA:Play()
        task.delay(sway / 60, function() pcall(function() swayB:Play() end) end)

        posTween.Completed:Connect(function()
            p.Position = UDim2.fromOffset(math.random(-20, vpW + 20), -size)
            p.Rotation = math.random(0, 359)
            p.BackgroundTransparency = math.random(20, 80) / 100
            drop()
        end)
    end

    drop()
    return p
end

-- Build the sakura tree procedurally (trunk + layered canopy circles).
local function buildTree(parent, x, y)
    local tree = Instance.new("Frame")
    tree.Name = "SakuraTree"
    tree.BackgroundTransparency = 1
    tree.Size = UDim2.fromOffset(180, 220)
    tree.Position = UDim2.fromOffset(x, y)
    tree.ZIndex = 9990
    tree.Parent = parent

    -- trunk
    local trunk = Instance.new("Frame")
    trunk.Name = "Trunk"
    trunk.AnchorPoint = Vector2.new(0.5, 1)
    trunk.Position = UDim2.new(0.5, 0, 1, 0)
    trunk.Size = UDim2.fromOffset(20, 110)
    trunk.BackgroundColor3 = Color3.fromRGB(82, 53, 42)
    trunk.BorderSizePixel = 0
    trunk.ZIndex = 9991
    trunk.Parent = tree
    local tgrad = Instance.new("UIGradient")
    tgrad.Color = ColorSequence.new(Color3.fromRGB(105, 70, 55), Color3.fromRGB(60, 38, 30))
    tgrad.Rotation = 90
    tgrad.Parent = trunk
    local tcorner = Instance.new("UICorner")
    tcorner.CornerRadius = UDim.new(0, 8)
    tcorner.Parent = trunk

    -- canopy: 8 overlapping pink circles
    local canopy = Instance.new("Frame")
    canopy.Name = "Canopy"
    canopy.BackgroundTransparency = 1
    canopy.AnchorPoint = Vector2.new(0.5, 1)
    canopy.Position = UDim2.new(0.5, 0, 0.5, -10)
    canopy.Size = UDim2.fromOffset(180, 130)
    canopy.ZIndex = 9992
    canopy.Parent = tree

    local circles = {
        { x = 0, y = 0, s = 92, c = 1 },
        { x = -42, y = 8, s = 78, c = 2 },
        { x = 42, y = 8, s = 78, c = 2 },
        { x = -28, y = -32, s = 70, c = 3 },
        { x = 28, y = -32, s = 70, c = 3 },
        { x = 0, y = -42, s = 64, c = 4 },
        { x = -58, y = -8, s = 56, c = 1 },
        { x = 58, y = -8, s = 56, c = 1 },
    }
    local canopyShapes = {}
    for i, c in ipairs(circles) do
        local circ = Instance.new("Frame")
        circ.Name = "Bloom" .. i
        circ.AnchorPoint = Vector2.new(0.5, 0.5)
        circ.Position = UDim2.fromOffset(90 + c.x, 65 + c.y)
        circ.Size = UDim2.fromOffset(c.s, c.s)
        circ.BackgroundColor3 = PETAL_COLORS[c.c]
        circ.BackgroundTransparency = 0.04
        circ.BorderSizePixel = 0
        circ.ZIndex = 9992 + (10 - i)
        circ.Parent = canopy
        local cc = Instance.new("UICorner")
        cc.CornerRadius = UDim.new(1, 0)
        cc.Parent = circ
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new(PETAL_COLORS[c.c], Color3.fromRGB(255, 235, 240))
        g.Rotation = math.random(0, 360)
        g.Parent = circ
        table.insert(canopyShapes, circ)
    end

    -- subtle ambient sway for the canopy
    task.spawn(function()
        while canopy.Parent do
            local swayInfo = TweenInfo.new(2.4 + math.random() * 0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
            local sway = TweenService:Create(canopy, swayInfo, {
                Rotation = 2 + math.random(-10, 10) / 10,
            })
            sway:Play()
            task.wait(2.4)
        end
    end)

    return tree, canopyShapes
end

-- Spawn a petal burst at a screen position (e.g. window center) on toggle changes.
local function petalBurst(x, y)
    if not sakuraGui or not sakuraGui.Parent then return end
    local burstFolder = Instance.new("Folder")
    burstFolder.Name = "Burst"
    burstFolder.Parent = sakuraGui

    local count = 14
    for i = 1, count do
        local angle = (i / count) * math.pi * 2 + math.random() * 0.4
        local dist = math.random(60, 140)
        local tx = x + math.cos(angle) * dist
        local ty = y + math.sin(angle) * dist
        local size = math.random(10, 20)

        local p = Instance.new("Frame")
        p.Name = "BurstPetal"
        p.Size = UDim2.fromOffset(size, math.floor(size * 0.78))
        p.Position = UDim2.fromOffset(x, y)
        p.BackgroundColor3 = PETAL_COLORS[math.random(1, #PETAL_COLORS)]
        p.BackgroundTransparency = 0.05
        p.BorderSizePixel = 0
        p.ZIndex = 9999
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0.55, 0)
        c.Parent = p
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new(p.BackgroundColor3, Color3.fromRGB(255, 245, 248))
        g.Rotation = math.random(0, 360)
        g.Parent = p
        p.Parent = burstFolder

        local info = TweenInfo.new(0.8 + math.random() * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local t = TweenService:Create(p, info, {
            Position = UDim2.fromOffset(tx, ty),
            Rotation = math.random(-720, 720),
            BackgroundTransparency = 1,
        })
        t:Play()
    end

    task.delay(1.6, function()
        pcall(function() burstFolder:Destroy() end)
    end)
end

-- Find the Rayfield window's main frame so we can animate it.
local function findRayfieldWindow()
    local holders = {}
    if type(gethui) == "function" then pcall(function() holders[#holders + 1] = gethui() end) end
    pcall(function() holders[#holders + 1] = game:GetService("CoreGui") end)
    pcall(function() holders[#holders + 1] = player:FindFirstChildOfClass("PlayerGui") end)
    for _, h in ipairs(holders) do
        if h then
            local rf = h:FindFirstChild("Rayfield", true)
            if rf then
                -- the visible window frame is usually the first large Frame inside
                for _, d in ipairs(rf:GetDescendants()) do
                    if d:IsA("Frame") and d.Name:lower():match("window") and d.Size.X.Scale > 0 then
                        return rf, d
                    end
                end
                return rf, rf:FindFirstChildWhichIsA("Frame")
            end
        end
    end
    return nil, nil
end

local function buildSakuraEnv()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    local vp = camera.ViewportSize
    local vw, vh = vp.X, vp.Y

    sakuraGui = Instance.new("ScreenGui")
    sakuraGui.Name = "LG_SakuraEnv"
    sakuraGui.ResetOnSpawn = false
    sakuraGui.IgnoreGuiInset = true
    sakuraGui.DisplayOrder = 2147483646 -- just below Rayfield (which is max)
    sakuraGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local okParent = pcall(function()
        local pg = player:FindFirstChildOfClass("PlayerGui")
        if pg then sakuraGui.Parent = pg end
    end)
    if not okParent or not sakuraGui.Parent then
        pcall(function()
            sakuraGui.Parent = (type(gethui) == "function" and gethui()) or game:GetService("CoreGui")
        end)
    end

    -- tree in the lower-left
    treeFolder = Instance.new("Folder")
    treeFolder.Name = "Trees"
    treeFolder.Parent = sakuraGui
    local _, canopyShapes = buildTree(treeFolder, 20, vh - 240)

    -- petals
    petalFolder = Instance.new("Folder")
    petalFolder.Name = "Petals"
    petalFolder.Parent = sakuraGui
    for _ = 1, 36 do
        makePetal(petalFolder, vw, vh)
    end

    -- ambient canopy breathing
    task.spawn(function()
        while treeFolder.Parent do
            for _, shape in ipairs(canopyShapes) do
                local info = TweenInfo.new(1.6 + math.random() * 0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
                TweenService:Create(shape, info, {
                    BackgroundTransparency = 0.02 + math.random() * 0.08,
                }):Play()
            end
            task.wait(1.6)
        end
    end)

    -- animate the Rayfield window itself
    task.spawn(function()
        local rf, winFrame = nil, nil
        for _ = 1, 40 do
            rf, winFrame = findRayfieldWindow()
            if winFrame then break end
            task.wait(0.1)
        end
        if not winFrame then return end

        -- entrance: scale + fade + slight rotation wobble
        local origSize = winFrame.Size
        local origPos = winFrame.Position
        winFrame.Size = UDim2.new(origSize.X.Scale, origSize.X.Offset * 0.85, origSize.Y.Scale, origSize.Y.Offset * 0.85)
        winFrame.Position = UDim2.new(origPos.X.Scale, origPos.X.Offset, origPos.Y.Scale, origPos.Y.Offset + 30)
        winFrame.AnchorPoint = Vector2.new(0.5, 0.5)
        local cx = winFrame.AbsolutePosition.X + winFrame.AbsoluteSize.X / 2
        local cy = winFrame.AbsolutePosition.Y + winFrame.AbsoluteSize.Y / 2
        winFrame.Position = UDim2.fromOffset(cx, cy)

        local entranceInfo = TweenInfo.new(0.9, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        local entrance = TweenService:Create(winFrame, entranceInfo, {
            Size = origSize,
            Position = UDim2.fromOffset(cx, cy - 15),
            Rotation = 0,
        })
        winFrame.Rotation = -2
        entrance:Play()

        -- idle drift: gentle figure-8 via RunService heartbeat
        local t0 = tick()
        trackEnv(RunService.RenderStepped:Connect(function()
            if not winFrame or not winFrame.Parent then return end
            local t = tick() - t0
            local dx = math.sin(t * 0.6) * 6
            local dy = math.sin(t * 0.3) * 4
            winFrame.Position = UDim2.fromOffset(cx + dx, cy - 15 + dy)
        end))
    end)
end

buildSakuraEnv()

-- ================================================================ sakura theme ====
-- Cherry blossom palette: warm dark plum base + cherry pink accents.
local function seq(a, b) return ColorSequence.new(a, b) end

local SakuraTheme = {
    -- Window & shape
    CornerRoundness = UDim.new(0, 14),
    PillCornerRadius = UDim.new(0, 8),
    ElementCornerRadius = UDim.new(0, 10),
    WindowColor = seq(Color3.fromRGB(31, 20, 25), Color3.fromRGB(43, 26, 34)),
    ShadowColor = Color3.fromRGB(13, 5, 6),
    LiveAnimation = true,
    SurfaceStroke = Color3.fromRGB(61, 42, 48),

    -- Text
    ContentColor = Color3.fromRGB(240, 224, 228),    -- warm off-white element text
    TitlingColor = Color3.fromRGB(255, 157, 190),    -- bright petal pink titles
    ElementTextHoverColor = Color3.fromRGB(255, 183, 197),
    ActionColor = Color3.fromRGB(255, 183, 197),

    -- Tabs
    TabColor = Color3.fromRGB(255, 183, 197),         -- soft petal pink tab text
    TabBackground = seq(Color3.fromRGB(255, 107, 157), Color3.fromRGB(255, 157, 190)),
    TabStroke = seq(Color3.fromRGB(255, 183, 197), Color3.fromRGB(255, 143, 171)),

    -- Elements
    ElementGradient = seq(Color3.fromRGB(42, 26, 32), Color3.fromRGB(51, 31, 38)),
    ElementStroke = Color3.fromRGB(74, 45, 56),
    ElementStrokeHover = Color3.fromRGB(106, 61, 72),
    ElementTransparency = 0,
    ElementStrokeTransparency = 0.15,

    -- Accent (toggle on, slider glow, popup primary)
    AccentColor = Color3.fromRGB(255, 107, 157),     -- cherry pink
    AccentStroke = Color3.fromRGB(255, 157, 190),
    AccentGlow = 0.35,

    -- Slider
    SliderBackground = Color3.fromRGB(42, 27, 34),
    SliderBackgroundHover = Color3.fromRGB(58, 37, 48),
    SliderProgress = seq(Color3.fromRGB(255, 107, 157), Color3.fromRGB(255, 183, 197)),
    SliderStroke = Color3.fromRGB(74, 45, 56),
    SliderHandle = Color3.fromRGB(255, 122, 171),

    -- Toggle
    ToggleTrack = Color3.fromRGB(42, 27, 34),
    ToggleTrackTransparency = 0,
    ToggleKnobOff = Color3.fromRGB(106, 61, 72),
    ToggleKnobOffTransparency = 0,
    DarkToggleOverlay = false,

    -- Dropdown
    DropdownHighlight = Color3.fromRGB(255, 107, 157),

    -- Fields
    FieldBackground = Color3.fromRGB(42, 26, 32),
    FieldTransparency = 0,
    FieldGlow = Color3.fromRGB(255, 107, 157),
    PlaceholderColor = Color3.fromRGB(138, 106, 114),

    -- Buttons
    NeutralButton = Color3.fromRGB(58, 37, 48),
    NeutralButtonHover = Color3.fromRGB(90, 53, 64),
    NeutralButtonStroke = Color3.fromRGB(90, 53, 64),

    -- Errors
    ErrorColor = Color3.fromRGB(232, 74, 106),
    ErrorStrokeColor = Color3.fromRGB(255, 107, 157),
}

-- ================================================================ window ====
local Window = Rayfield:CreateWindow({
    name = "Auto Attack + Dodge",
    subtitle = "Sakura Edition",
    theme = SakuraTheme,
    sidebarLayout = true,
    showName = "Sakura",
})

local function notify(title, content, image)
    pcall(function()
        Window:Notify({ title = title, content = content, duration = 2.5, image = image })
    end)
end

-- ================================================================ Combat tab ====
local CombatTab = Window:CreateTab({ name = "Combat" })

-- Trigger a petal burst at the Rayfield window center on important changes.
local function burstAtWindowCenter()
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local _, winFrame = findRayfieldWindow()
    if winFrame and winFrame.AbsoluteSize.X > 0 then
        local cx = winFrame.AbsolutePosition.X + winFrame.AbsoluteSize.X / 2
        local cy = winFrame.AbsolutePosition.Y + winFrame.AbsoluteSize.Y / 2
        petalBurst(cx, cy)
    else
        petalBurst(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
    end
end

local autoToggleCtl
autoToggleCtl = CombatTab:CreateToggle({
    name = "Auto Attack",
    description = "Attacks the closest player in range",
    value = false,
    callback = function(state)
        autoAttackOn = state
        if not state then clearHighlight() end
        burstAtWindowCenter()
        notify(state and "Auto Attack ON" or "Auto Attack OFF",
               state and ("Targeting within " .. tostring(range) .. " studs") or "Standby",
               state and "check" or "circle")
    end,
})

CombatTab:CreateSlider({
    name = "Attack Range (studs)",
    description = "How far the script searches for targets",
    range = { 1, 30 },
    value = range,
    callback = function(v) range = v end,
})

CombatTab:CreateSlider({
    name = "Attack Cooldown (s)",
    range = { 0.1, 2 },
    value = cooldown,
    callback = function(v) cooldown = v end,
})

CombatTab:CreateToggle({
    name = "Always Crit",
    value = alwaysCrit,
    callback = function(s) alwaysCrit = s; burstAtWindowCenter() end,
})

CombatTab:CreateKeybind({
    name = "Toggle Attack Hotkey",
    description = "Press to flip Auto Attack on/off",
    value = Enum.KeyCode.F,
    callback = function()
        local newState = not autoAttackOn
        autoAttackOn = newState
        if autoToggleCtl then pcall(function() autoToggleCtl:Set(newState, true) end) end
        if not newState then clearHighlight() end
        burstAtWindowCenter()
        notify(newState and "Auto Attack ON" or "Auto Attack OFF",
               "Hotkey toggled", newState and "check" or "circle")
    end,
})

-- ================================================================ Dodge tab ====
local DodgeTab = Window:CreateTab({ name = "Dodge" })

local dodgeToggleCtl
dodgeToggleCtl = DodgeTab:CreateToggle({
    name = "Auto Dodge",
    description = "Evades enemies rushing toward you",
    value = false,
    callback = function(state)
        autoDodgeOn = state
        burstAtWindowCenter()
        notify(state and "Auto Dodge ON" or "Auto Dodge OFF",
               state and ("Evading within " .. tostring(dodgeRange) .. " studs") or "Standby",
               state and "check" or "circle")
    end,
})

DodgeTab:CreateSlider({
    name = "Dodge Range (studs)",
    description = "Trigger distance from rushing enemies",
    range = { 3, 15 },
    value = dodgeRange,
    callback = function(v) dodgeRange = v end,
})

DodgeTab:CreateDropdown({
    name = "Dodge Mode",
    description = "How to evade when triggered",
    options = { "Jump", "Strafe", "Both", "Backdash" },
    value = { dodgeMode },
    callback = function(selected)
        -- single-mode callback receives a bare string
        if type(selected) == "string" then
            dodgeMode = selected
        elseif type(selected) == "table" then
            dodgeMode = selected[1] or dodgeMode
        end
    end,
})

DodgeTab:CreateSlider({
    name = "Dodge Cooldown (s)",
    range = { 0.3, 3 },
    value = dodgeCooldown,
    callback = function(v) dodgeCooldown = v end,
})

DodgeTab:CreateKeybind({
    name = "Toggle Dodge Hotkey",
    value = Enum.KeyCode.G,
    callback = function()
        local newState = not autoDodgeOn
        autoDodgeOn = newState
        if dodgeToggleCtl then pcall(function() dodgeToggleCtl:Set(newState, true) end) end
        burstAtWindowCenter()
        notify(newState and "Auto Dodge ON" or "Auto Dodge OFF",
               "Hotkey toggled", newState and "check" or "circle")
    end,
})

-- ================================================================ Visuals tab ====
local VisualsTab = Window:CreateTab({ name = "Visuals" })

VisualsTab:CreateToggle({
    name = "Target Highlight",
    description = "Outline the current target in your visual color",
    value = highlightOn,
    callback = function(s)
        highlightOn = s
        if not s then clearHighlight() end
    end,
})

VisualsTab:CreateDropdown({
    name = "Highlight Style",
    options = { "Filled", "Outline" },
    value = { highlightMode },
    callback = function(selected)
        local mode = selected
        if type(selected) == "table" then mode = selected[1] end
        if mode then
            highlightMode = mode
            if currentHighlight then pcall(function() applyHighlightStyle(currentHighlight) end) end
        end
    end,
})

VisualsTab:CreateToggle({
    name = "Range Ring",
    description = "Ground circle showing your attack range",
    value = ringOn,
    callback = function(s)
        ringOn = s
        if s then createRing() else removeRing() end
    end,
})

VisualsTab:CreateColorPicker({
    name = "Visual Color",
    value = visualColor,
    callback = function(c)
        -- color picker may return Color3 or a table; handle both
        local color = c
        if type(c) == "table" and c.Color then color = c.Color end
        if color and typeof(color) == "Color3" then
            visualColor = color
            refreshVisualColors()
        end
    end,
})

-- ================================================================ Settings tab ====
local SettingsTab = Window:CreateTab({ name = "Settings" })

if not combatReady then
    SettingsTab:CreateText({
        title = "Combat unavailable",
        body = "This game has no ReplicatedStorage.Remotes.Attack remote. UI loaded; auto attack won't fire. Auto dodge still works.",
    })
else
    SettingsTab:CreateText({
        title = "Combat ready",
        body = "Remotes.Attack detected. Auto attack will fire at the closest target in range.",
    })
end

SettingsTab:CreateButton({
    name = "Unload Script",
    description = "Stops everything and removes the UI",
    callback = function()
        autoAttackOn = false
        autoDodgeOn = false
        removeRing()
        clearHighlight()
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        conns = {}
        store.LG_AAD2_Conns = nil
        for _, c in ipairs(envConns) do pcall(function() c:Disconnect() end) end
        envConns = {}
        pcall(function() if sakuraGui then sakuraGui:Destroy() end end)
        pcall(function() Window:Unload() end)
        killOld("Rayfield")
        killOld("LG_AAD2_Ring")
        killOld("LG_AAD2_Highlight")
        killOld("LG_SakuraEnv")
        print("[AAD2] Unloaded.")
    end,
})

-- ================================================================ notify ====
if not combatReady then
    task.delay(0.6, function()
        notify("Combat unavailable",
               "No Remotes.Attack in this game. UI loaded; dodge still works.",
               "alert-triangle")
    end)
else
    task.delay(0.6, function()
        notify("Sakura loaded", "Auto Attack + Auto Dodge ready. Press F / G to toggle.", "check")
    end)
end

-- ================================================================ loops ====
track(RunService.Heartbeat:Connect(function()
    if ringOn then updateRing() end
    checkDodge()

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

print("[AAD2] Loaded via Rayfield Gen2 (Sakura). Combat ready: " .. tostring(combatReady))
