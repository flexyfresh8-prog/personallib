--[[
    Auto Attack + Auto Dodge — Rayfield Gen 2 (Sakura Mayhem Edition)
    Uses Rayfield Gen2 (https://sirius.menu/gen2) — open source, animations go wild.

    Sakura environment:
      - Proper branching sakura tree (trunk → 2-3 main branches → sub-branches
        → blossom clusters at tips) with per-branch sway.
      - 50 falling petals with sway + rotation + transparency variance.
      - Periodic wind-gust bursts.
      - Cursor trail of mini petals following your finger/mouse.
      - Random sparkle bursts at random positions.
      - Background gradient slowly shifting through pink hues.
      - Tree occasionally drops a blossom that floats down.
      - Window: smaller size, entrance with back easing, figure-8 idle drift,
        subtle rotation wobble, edge glow pulse.
      - Petal burst at window center on every toggle/hotkey.

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
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- ================================================================ cleanup ====
local store = (type(getgenv) == "function" and getgenv()) or _G
if store.LG_AAD3_Conns then
    for _, c in ipairs(store.LG_AAD3_Conns) do pcall(function() c:Disconnect() end) end
    store.LG_AAD3_Conns = nil
end
local conns = {}
store.LG_AAD3_Conns = conns
local function track(c) if c then table.insert(conns, c) end; return c end

local function killOld(name)
    local holders = {}
    if type(gethui) == "function" then pcall(function() holders[#holders + 1] = gethui() end) end
    pcall(function() holders[#holders + 1] = game:GetService("CoreGui") end)
    pcall(function() holders[#holders + 1] = player:FindFirstChildOfClass("PlayerGui") end)
    for _, holder in ipairs(holders) do
        local old = holder and holder:FindFirstChild(name, true)
        if old then pcall(function() old:Destroy() end) end
    end
end
killOld("Rayfield")
killOld("LG_AAD3_Ring")
killOld("LG_AAD3_Highlight")
killOld("LG_SakuraEnv")

-- ================================================================ library ====
local okFetch, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)
if not okFetch or type(Rayfield) ~= "table" then
    warn("[AAD3] Failed to load Rayfield Gen2: " .. tostring(Rayfield))
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
local visualColor = Color3.fromRGB(255, 122, 171)

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
    ring.Name = "LG_AAD3_Ring"
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
        currentHighlight.Name = "LG_AAD3_Highlight"
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
local function performDodge(enemyRoot, myRoot, myHum)
    if not myHum or myHum.Health <= 0 then return end
    local toMe = (myRoot.Position - enemyRoot.Position)
    if toMe.Magnitude < 1e-3 then return end
    toMe = toMe.Unit
    local perp = Vector3.new(-toMe.Z, 0, toMe.X)
    if math.random() < 0.5 then perp = -perp end

    local function makeBV(vel)
        local bv = myRoot:FindFirstChild("LG_AAD3_DodgeBV")
        if not bv then
            bv = Instance.new("BodyVelocity")
            bv.Name = "LG_AAD3_DodgeBV"
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
-- Full sakura environment with branching tree, falling petals, cursor trail,
-- sparkles, wind gusts, and background color shift.

local sakuraGui = nil
local envConns = {}
local function trackEnv(c) if c then table.insert(envConns, c) end; return c end

local PETAL_COLORS = {
    Color3.fromRGB(255, 183, 197),
    Color3.fromRGB(255, 210, 225),
    Color3.fromRGB(255, 122, 171),
    Color3.fromRGB(255, 143, 171),
    Color3.fromRGB(255, 235, 238),
    Color3.fromRGB(255, 156, 187),
}

local function seq(a, b) return ColorSequence.new(a, b) end

-- single petal frame (rounded shape via UICorner with high radius + aspect)
local function makePetalFrame(parent, size, color, transparency)
    local p = Instance.new("Frame")
    p.Name = "Petal"
    p.Size = UDim2.fromOffset(size, math.floor(size * 0.78))
    p.BackgroundColor3 = color
    p.BackgroundTransparency = transparency or 0.1
    p.BorderSizePixel = 0
    p.ZIndex = 9998

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = p

    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(color, Color3.fromRGB(255, 245, 248))
    g.Rotation = math.random(0, 360)
    g.Parent = p

    p.Parent = parent
    return p
end

-- A petal that falls forever with sway + rotation, then respawns at top.
local function spawnFallingPetal(parent, vpW, vpH, startY)
    local size = math.random(8, 22)
    local color = PETAL_COLORS[math.random(1, #PETAL_COLORS)]
    local p = makePetalFrame(parent, size, color, math.random(15, 70) / 100)
    p.Position = UDim2.fromOffset(math.random(-20, vpW + 20), startY or -size)

    local function drop()
        local startX = p.Position.X.Offset
        local targetX = startX + math.random(-160, 160)
        local targetY = vpH + size + 20
        local dur = math.random(7, 16)
        local rotEnd = p.Rotation + math.random(-720, 720)

        local posInfo = TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
        local posT = TweenService:Create(p, posInfo, { Position = UDim2.fromOffset(targetX, targetY) })
        local rotInfo = TweenInfo.new(dur, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
        local rotT = TweenService:Create(p, rotInfo, { Rotation = rotEnd })

        posT:Play()
        rotT:Play()

        posT.Completed:Connect(function()
            if not p.Parent then return end
            p.Position = UDim2.fromOffset(math.random(-20, vpW + 20), -size)
            p.Rotation = math.random(0, 359)
            p.BackgroundTransparency = math.random(15, 70) / 100
            drop()
        end)
    end
    drop()
    return p
end

-- Build a real branching sakura tree.
-- Trunk splits into 2-3 main branches, each splits again, blossoms cluster at tips.
local function buildBranchingTree(parent, baseX, baseY, scale)
    scale = scale or 1
    local tree = Instance.new("Frame")
    tree.Name = "SakuraTree"
    tree.BackgroundTransparency = 1
    tree.Size = UDim2.fromOffset(math.floor(180 * scale), math.floor(220 * scale))
    tree.Position = UDim2.fromOffset(baseX, baseY)
    tree.ZIndex = 9990
    tree.Parent = parent

    -- trunk
    local trunk = Instance.new("Frame")
    trunk.Name = "Trunk"
    trunk.AnchorPoint = Vector2.new(0.5, 1)
    trunk.Position = UDim2.new(0.5, 0, 1, 0)
    trunk.Size = UDim2.fromOffset(math.floor(18 * scale), math.floor(95 * scale))
    trunk.BackgroundColor3 = Color3.fromRGB(82, 53, 42)
    trunk.BorderSizePixel = 0
    trunk.ZIndex = 9991
    trunk.Parent = tree
    local tgrad = Instance.new("UIGradient")
    tgrad.Color = ColorSequence.new(Color3.fromRGB(112, 75, 58), Color3.fromRGB(58, 36, 28))
    tgrad.Rotation = 90
    tgrad.Parent = trunk
    local tcorner = Instance.new("UICorner")
    tcorner.CornerRadius = UDim.new(0, math.floor(6 * scale))
    tcorner.Parent = trunk

    -- helper: create a branch as a rotated tapered frame
    local branches = {}
    local function makeBranch(x, y, length, angle, thickness, depth)
        local b = Instance.new("Frame")
        b.Name = "Branch" .. depth
        b.AnchorPoint = Vector2.new(0.5, 1)
        b.Size = UDim2.fromOffset(math.max(2, thickness), length)
        b.Position = UDim2.fromOffset(x, y)
        b.BackgroundColor3 = Color3.fromRGB(95, 62, 48)
        b.BorderSizePixel = 0
        b.Rotation = angle
        b.ZIndex = 9992 - depth
        b.Parent = tree
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new(Color3.fromRGB(115, 78, 62), Color3.fromRGB(70, 44, 34))
        g.Rotation = 90
        g.Parent = b
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, math.max(1, thickness / 2))
        c.Parent = b
        table.insert(branches, b)
        return b
    end

    -- blossom cluster: small circles bunched at branch tips
    local blossoms = {}
    local function makeBlossomCluster(x, y, radius)
        local cluster = Instance.new("Frame")
        cluster.Name = "BlossomCluster"
        cluster.BackgroundTransparency = 1
        cluster.AnchorPoint = Vector2.new(0.5, 0.5)
        cluster.Position = UDim2.fromOffset(x, y)
        cluster.Size = UDim2.fromOffset(radius * 2, radius * 2)
        cluster.ZIndex = 9995
        cluster.Parent = tree

        -- 5-7 small circles overlapping
        local count = math.random(5, 8)
        for i = 1, count do
            local ang = (i / count) * math.pi * 2
            local r = radius * 0.55
            local cx = radius + math.cos(ang) * r
            local cy = radius + math.sin(ang) * r
            local sz = math.random(math.floor(radius * 0.7), math.floor(radius * 1.1))

            local circ = Instance.new("Frame")
            circ.Name = "Blossom" .. i
            circ.AnchorPoint = Vector2.new(0.5, 0.5)
            circ.Position = UDim2.fromOffset(cx, cy)
            circ.Size = UDim2.fromOffset(sz, sz)
            circ.BackgroundColor3 = PETAL_COLORS[math.random(1, #PETAL_COLORS)]
            circ.BackgroundTransparency = math.random(5, 25) / 100
            circ.BorderSizePixel = 0
            circ.ZIndex = 9995 + i
            circ.Parent = cluster
            local cc = Instance.new("UICorner")
            cc.CornerRadius = UDim.new(1, 0)
            cc.Parent = circ
            local g = Instance.new("UIGradient")
            g.Color = ColorSequence.new(circ.BackgroundColor3, Color3.fromRGB(255, 235, 240))
            g.Rotation = math.random(0, 360)
            g.Parent = circ
            table.insert(blossoms, circ)
        end
        -- center blossom
        local center = Instance.new("Frame")
        center.Name = "BlossomCenter"
        center.AnchorPoint = Vector2.new(0.5, 0.5)
        center.Position = UDim2.fromOffset(radius, radius)
        center.Size = UDim2.fromOffset(math.floor(radius * 0.9), math.floor(radius * 0.9))
        center.BackgroundColor3 = PETAL_COLORS[1]
        center.BackgroundTransparency = 0.05
        center.BorderSizePixel = 0
        center.ZIndex = 9995
        center.Parent = cluster
        local cc = Instance.new("UICorner")
        cc.CornerRadius = UDim.new(1, 0)
        cc.Parent = center
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new(PETAL_COLORS[1], Color3.fromRGB(255, 220, 230))
        g.Parent = center
        table.insert(blossoms, center)
        return cluster, blossoms
    end

    -- recursive branch structure
    local function growBranch(x, y, length, angle, thickness, depth, parentBranch)
        if depth <= 0 or length < 6 then
            -- tip: blossom cluster
            local tipX = x + math.sin(math.rad(angle)) * length * 0.5
            local tipY = y - length * 0.5
            makeBlossomCluster(tipX, tipY, math.random(12, 18))
            return
        end

        local b = makeBranch(x, y, length, angle, thickness, depth)

        -- tip position (top of branch, accounting for rotation)
        -- anchor point is (0.5, 1), so top is at (x, y - length) rotated around (x, y)
        local rad = math.rad(angle)
        local tipX = x + math.sin(rad) * length
        local tipY = y - math.cos(rad) * length

        -- split into 2-3 children
        local numChildren = math.random(2, 3)
        for i = 1, numChildren do
            local spread = 35 + math.random(-15, 15)
            local childAngle = angle + (i - (numChildren + 1) / 2) * spread
            local childLength = length * (0.55 + math.random() * 0.2)
            local childThickness = math.max(2, thickness * 0.65)
            growBranch(tipX, tipY, childLength, childAngle, childThickness, depth - 1, b)
        end
    end

    -- start: trunk top is at (centerX, treeBottom - trunkHeight)
    local centerX = math.floor(90 * scale)
    local trunkTopY = math.floor(220 * scale) - math.floor(95 * scale)

    -- 3 main branches emerging from trunk top
    local mainAngles = { -32, 0, 32 }
    for _, ang in ipairs(mainAngles) do
        growBranch(centerX, trunkTopY, math.floor(48 * scale), ang, math.floor(11 * scale), 3, nil)
    end

    -- per-branch sway: each branch rotates a tiny amount on a different phase
    task.spawn(function()
        local phases = {}
        for i, b in ipairs(branches) do
            phases[b] = math.random() * math.pi * 2
            b:SetAttribute("BaseAngle", b.Rotation)
        end
        while tree.Parent do
            local t = tick()
            for _, b in ipairs(branches) do
                if b and b.Parent then
                    local base = b:GetAttribute("BaseAngle") or b.Rotation
                    local phase = phases[b] or 0
                    local sway = math.sin(t * 0.7 + phase) * 2.5
                    b.Rotation = base + sway
                end
            end
            task.wait(0.05)
        end
    end)

    -- blossoms occasionally detach and float down
    task.spawn(function()
        while tree.Parent do
            task.wait(math.random(4, 9))
            if #blossoms > 0 then
                local idx = math.random(1, #blossoms)
                local src = blossoms[idx]
                if src and src.Parent then
                    local clone = src:Clone()
                    clone.Name = "DetachedBlossom"
                    clone.Parent = sakuraGui
                    -- get absolute position
                    local absX = src.AbsolutePosition.X
                    local absY = src.AbsolutePosition.Y
                    clone.AnchorPoint = Vector2.new(0.5, 0.5)
                    clone.Position = UDim2.fromOffset(absX, absY)
                    clone.ZIndex = 9997
                    local info = TweenInfo.new(math.random(6, 10), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
                    local t = TweenService:Create(clone, info, {
                        Position = UDim2.fromOffset(absX + math.random(-80, 80), absY + 600),
                        Rotation = math.random(-540, 540),
                        BackgroundTransparency = 1,
                    })
                    t:Play()
                    t.Completed:Connect(function() pcall(function() clone:Destroy() end) end)
                end
            end
        end
    end)

    return tree, branches
end

-- petal burst at (x, y)
local function petalBurst(x, y, count)
    count = count or 14
    if not sakuraGui or not sakuraGui.Parent then return end
    local burst = Instance.new("Folder")
    burst.Name = "Burst"
    burst.Parent = sakuraGui

    for i = 1, count do
        local angle = (i / count) * math.pi * 2 + math.random() * 0.4
        local dist = math.random(60, 150)
        local tx = x + math.cos(angle) * dist
        local ty = y + math.sin(angle) * dist
        local size = math.random(10, 22)
        local color = PETAL_COLORS[math.random(1, #PETAL_COLORS)]
        local p = makePetalFrame(burst, size, color, 0.05)
        p.Position = UDim2.fromOffset(x, y)
        p.ZIndex = 9999

        local info = TweenInfo.new(0.8 + math.random() * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local t = TweenService:Create(p, info, {
            Position = UDim2.fromOffset(tx, ty),
            Rotation = math.random(-720, 720),
            BackgroundTransparency = 1,
        })
        t:Play()
    end
    task.delay(1.6, function() pcall(function() burst:Destroy() end) end)
end

-- find the Rayfield window frame (search for the named window frame inside Rayfield holder)
local function findRayfieldWindow()
    local holders = {}
    if type(gethui) == "function" then pcall(function() holders[#holders + 1] = gethui() end) end
    pcall(function() holders[#holders + 1] = game:GetService("CoreGui") end)
    pcall(function() holders[#holders + 1] = player:FindFirstChildOfClass("PlayerGui") end)
    for _, h in ipairs(holders) do
        if h then
            local rf = h:FindFirstChild("Rayfield", true)
            if rf then
                -- look for the largest Frame inside Rayfield
                local best
                for _, d in ipairs(rf:GetDescendants()) do
                    if d:IsA("Frame") and d.Size.X.Scale > 0 and d.Size.Y.Scale > 0 then
                        if not best or (d.AbsoluteSize.X * d.AbsoluteSize.Y) > (best.AbsoluteSize.X * best.AbsoluteSize.Y) then
                            best = d
                        end
                    end
                end
                return rf, best or rf:FindFirstChildWhichIsA("Frame")
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
    sakuraGui.DisplayOrder = 2147483646
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

    -- background gradient frame: slowly shifts through pink hues
    local bg = Instance.new("Frame")
    bg.Name = "SakuraBg"
    bg.Size = UDim2.fromScale(1, 1)
    bg.BackgroundColor3 = Color3.fromRGB(255, 122, 171)
    bg.BackgroundTransparency = 0.96
    bg.BorderSizePixel = 0
    bg.ZIndex = 9985
    bg.Parent = sakuraGui
    local bgGrad = Instance.new("UIGradient")
    bgGrad.Color = seq(Color3.fromRGB(255, 122, 171), Color3.fromRGB(255, 183, 197))
    bgGrad.Rotation = 45
    bgGrad.Parent = bg

    -- animate the background gradient rotation + color shift
    task.spawn(function()
        local t0 = tick()
        while bg.Parent do
            local t = tick() - t0
            bgGrad.Rotation = (t * 8) % 360
            -- subtle transparency pulse
            bg.BackgroundTransparency = 0.94 + math.sin(t * 0.5) * 0.04
            task.wait(0.1)
        end
    end)

    -- tree in the lower-left
    local tree, branches = buildBranchingTree(sakuraGui, 20, vh - 240, 1)

    -- 50 falling petals
    local petalFolder = Instance.new("Folder")
    petalFolder.Name = "Petals"
    petalFolder.Parent = sakuraGui
    for _ = 1, 50 do
        spawnFallingPetal(petalFolder, vw, vh, math.random(-50, vh))
    end

    -- periodic wind gust: sudden burst of petals across screen
    task.spawn(function()
        while sakuraGui.Parent do
            task.wait(math.random(8, 18))
            for _ = 1, 20 do
                spawnFallingPetal(petalFolder, vw, vh, -20)
            end
        end
    end)

    -- cursor trail: mini petals follow mouse/touch
    local trailFolder = Instance.new("Folder")
    trailFolder.Name = "CursorTrail"
    trailFolder.Parent = sakuraGui

    trackEnv(UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
           or input.UserInputType == Enum.UserInputType.Touch then
            local pos = input.Position
            -- spawn one mini petal that fades
            local size = math.random(6, 12)
            local color = PETAL_COLORS[math.random(1, #PETAL_COLORS)]
            local p = makePetalFrame(trailFolder, size, color, 0.1)
            p.Position = UDim2.fromOffset(pos.X + math.random(-8, 8), pos.Y + math.random(-8, 8))
            p.ZIndex = 9997
            local info = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            local t = TweenService:Create(p, info, {
                Position = UDim2.fromOffset(pos.X + math.random(-30, 30), pos.Y + 40),
                Rotation = math.random(-360, 360),
                BackgroundTransparency = 1,
            })
            t:Play()
            t.Completed:Connect(function() pcall(function() p:Destroy() end) end)
        end
    end))

    -- random sparkles at random positions
    task.spawn(function()
        while sakuraGui.Parent do
            task.wait(math.random(2, 6))
            local sx = math.random(0, vw)
            local sy = math.random(0, vh)
            -- 4-point star sparkle
            local sparkle = Instance.new("Frame")
            sparkle.Name = "Sparkle"
            sparkle.AnchorPoint = Vector2.new(0.5, 0.5)
            sparkle.Position = UDim2.fromOffset(sx, sy)
            sparkle.Size = UDim2.fromOffset(4, 4)
            sparkle.BackgroundColor3 = Color3.fromRGB(255, 245, 220)
            sparkle.BorderSizePixel = 0
            sparkle.ZIndex = 9996
            sparkle.Parent = sakuraGui
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(1, 0)
            c.Parent = sparkle

            local info = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            local t = TweenService:Create(sparkle, info, {
                Size = UDim2.fromOffset(20, 20),
                BackgroundTransparency = 1,
            })
            t:Play()
            t.Completed:Connect(function() pcall(function() sparkle:Destroy() end) end)
        end
    end)

    -- animate the Rayfield window: resize smaller, entrance, idle drift, rotation wobble
    task.spawn(function()
        local rf, winFrame = nil, nil
        for _ = 1, 60 do
            rf, winFrame = findRayfieldWindow()
            if winFrame then break end
            task.wait(0.1)
        end
        if not winFrame then return end

        -- shrink the window: target ~70% of original size, centered
        task.wait(0.2) -- let rayfield settle
        local origSize = winFrame.Size
        local origPos = winFrame.Position
        local origAbsSize = winFrame.AbsoluteSize
        local targetW = math.floor(origAbsSize.X * 0.7)
        local targetH = math.floor(origAbsSize.Y * 0.7)

        -- compute center
        local centerX = winFrame.AbsolutePosition.X + origAbsSize.X / 2
        local centerY = winFrame.AbsolutePosition.Y + origAbsSize.Y / 2

        -- set anchor to center, reposition
        winFrame.AnchorPoint = Vector2.new(0.5, 0.5)
        winFrame.Size = UDim2.fromOffset(targetW, targetH)
        winFrame.Position = UDim2.fromOffset(centerX, centerY)

        -- entrance animation: scale up from 0.6 with back easing
        local startSize = UDim2.fromOffset(math.floor(targetW * 0.6), math.floor(targetH * 0.6))
        local endSize = UDim2.fromOffset(targetW, targetH)
        winFrame.Size = startSize
        winFrame.Rotation = -3
        winFrame.Position = UDim2.fromOffset(centerX, centerY + 40)

        local entranceInfo = TweenInfo.new(0.9, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        local entrance = TweenService:Create(winFrame, entranceInfo, {
            Size = endSize,
            Position = UDim2.fromOffset(centerX, centerY),
            Rotation = 0,
        })
        entrance:Play()

        -- idle drift: figure-8 + rotation wobble via RenderStepped
        local t0 = tick()
        trackEnv(RunService.RenderStepped:Connect(function()
            if not winFrame or not winFrame.Parent then return end
            local t = tick() - t0
            local dx = math.sin(t * 0.6) * 5
            local dy = math.sin(t * 0.3) * 4
            local rot = math.sin(t * 0.4) * 0.8
            winFrame.Position = UDim2.fromOffset(centerX + dx, centerY + dy)
            winFrame.Rotation = rot
        end))

        -- subtle glow pulse: find the stroke inside the window and pulse its transparency
        task.spawn(function()
            while winFrame and winFrame.Parent do
                for _, d in ipairs(winFrame:GetDescendants()) do
                    if d:IsA("UIStroke") then
                        local orig = d.Transparency
                        local info = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
                        TweenService:Create(d, info, { Transparency = math.max(0, orig - 0.3) }):Play()
                        task.wait(1.5)
                        TweenService:Create(d, info, { Transparency = orig }):Play()
                        task.wait(1.5)
                    end
                end
                task.wait(0.5)
            end
        end)
    end)
end

buildSakuraEnv()

-- ================================================================ sakura theme ====
local SakuraTheme = {
    CornerRoundness = UDim.new(0, 14),
    PillCornerRadius = UDim.new(0, 8),
    ElementCornerRadius = UDim.new(0, 10),
    WindowColor = seq(Color3.fromRGB(31, 20, 25), Color3.fromRGB(43, 26, 34)),
    ShadowColor = Color3.fromRGB(13, 5, 6),
    LiveAnimation = true,
    SurfaceStroke = Color3.fromRGB(61, 42, 48),

    ContentColor = Color3.fromRGB(240, 224, 228),
    TitlingColor = Color3.fromRGB(255, 157, 190),
    ElementTextHoverColor = Color3.fromRGB(255, 183, 197),
    ActionColor = Color3.fromRGB(255, 183, 197),

    TabColor = Color3.fromRGB(255, 183, 197),
    TabBackground = seq(Color3.fromRGB(255, 107, 157), Color3.fromRGB(255, 157, 190)),
    TabStroke = seq(Color3.fromRGB(255, 183, 197), Color3.fromRGB(255, 143, 171)),

    ElementGradient = seq(Color3.fromRGB(42, 26, 32), Color3.fromRGB(51, 31, 38)),
    ElementStroke = Color3.fromRGB(74, 45, 56),
    ElementStrokeHover = Color3.fromRGB(106, 61, 72),
    ElementTransparency = 0,
    ElementStrokeTransparency = 0.15,

    AccentColor = Color3.fromRGB(255, 107, 157),
    AccentStroke = Color3.fromRGB(255, 157, 190),
    AccentGlow = 0.25,

    SliderBackground = Color3.fromRGB(42, 27, 34),
    SliderBackgroundHover = Color3.fromRGB(58, 37, 48),
    SliderProgress = seq(Color3.fromRGB(255, 107, 157), Color3.fromRGB(255, 183, 197)),
    SliderStroke = Color3.fromRGB(74, 45, 56),
    SliderHandle = Color3.fromRGB(255, 122, 171),

    ToggleTrack = Color3.fromRGB(42, 27, 34),
    ToggleTrackTransparency = 0,
    ToggleKnobOff = Color3.fromRGB(106, 61, 72),
    ToggleKnobOffTransparency = 0,
    DarkToggleOverlay = false,

    DropdownHighlight = Color3.fromRGB(255, 107, 157),

    FieldBackground = Color3.fromRGB(42, 26, 32),
    FieldTransparency = 0,
    FieldGlow = Color3.fromRGB(255, 107, 157),
    PlaceholderColor = Color3.fromRGB(138, 106, 114),

    NeutralButton = Color3.fromRGB(58, 37, 48),
    NeutralButtonHover = Color3.fromRGB(90, 53, 64),
    NeutralButtonStroke = Color3.fromRGB(90, 53, 64),

    ErrorColor = Color3.fromRGB(232, 74, 106),
    ErrorStrokeColor = Color3.fromRGB(255, 107, 157),
}

-- ================================================================ window ====
local Window = Rayfield:CreateWindow({
    name = "Auto Attack + Dodge",
    subtitle = "Sakura Mayhem",
    theme = SakuraTheme,
    sidebarLayout = true,
    showName = "Sakura",
})

local function notify(title, content, image)
    pcall(function()
        Window:Notify({ title = title, content = content, duration = 2.5, image = image })
    end)
end

local function burstAtWindowCenter()
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local _, winFrame = findRayfieldWindow()
    if winFrame and winFrame.AbsoluteSize.X > 0 then
        local cx = winFrame.AbsolutePosition.X + winFrame.AbsoluteSize.X / 2
        local cy = winFrame.AbsolutePosition.Y + winFrame.AbsoluteSize.Y / 2
        petalBurst(cx, cy, 18)
    else
        petalBurst(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2, 18)
    end
end

-- ================================================================ Combat tab ====
local CombatTab = Window:CreateTab({ name = "Combat" })

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
        for _, c in ipairs(envConns) do pcall(function() c:Disconnect() end) end
        envConns = {}
        store.LG_AAD3_Conns = nil
        pcall(function() if sakuraGui then sakuraGui:Destroy() end end)
        pcall(function() Window:Unload() end)
        killOld("Rayfield")
        killOld("LG_AAD3_Ring")
        killOld("LG_AAD3_Highlight")
        killOld("LG_SakuraEnv")
        print("[AAD3] Unloaded.")
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
        notify("Sakura Mayhem loaded", "Auto Attack + Auto Dodge ready. Press F / G to toggle.", "check")
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

print("[AAD3] Loaded via Rayfield Gen2 (Sakura Mayhem). Combat ready: " .. tostring(combatReady))
