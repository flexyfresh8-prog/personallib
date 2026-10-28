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
      Combat:  Auto Attack (F), Kill Aura (H) + Max Targets, Target Priority
               (Closest/Lowest HP/Strongest), Target Lock, Ignore Teammates,
               Range, Variable Delay Min/Max (every attack waits a RANDOM time
               in between, 0.05s slider steps), Burst Count, Charge, Sprint
               Attacks, Always Crit, Humanize Wobble, Aim Precision, Require
               Facing, Auto Swing, Live Stats (Attacks Fired / Targets in Range)
      AI Play: One-toggle hunting AI - picks the closest player, draws a live
               target line, routes around obstacles with PathfindingService
               (white path line bends as it recalculates), aimbot-locks the
               camera on the target and walks you in by replicating the
               game's own movement state.
               Move modes: Humanoid Walk (feeds your real input vector AND
               walks the humanoid - the game's own client replicates its own
               MoveState, nothing spoofed, nothing to flag) / Thumbstick Input
               (ControlModule) / MoveTo, with automatic fallback.
               Auto jump, stuck detection, stop distance, search range,
               repath delay, blacklist, live status panel, V hotkey.
      Dodge:   Auto Dodge (G) + Range/Mode + Variable Delay Min/Max, Low HP
               Alert + Threshold
      Visuals: Target Highlight (Filled/Outline), Range Ring, Visual Color
      Settings: Anti-AFK, Unload
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local PathfindingService = game:GetService("PathfindingService")

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
local delayMin = 0.45                -- variable timing: every attack waits a
local delayMax = 0.85                -- RANDOM time between delayMin and delayMax
local range = 8
local alwaysCrit = true

local dodgeRange = 8
local dodgeMin = 0.5                 -- variable dodge timing
local dodgeMax = 1.2
local dodgeDelayCur = 1.0            -- re-rolled after every dodge
local dodgeMode = "Both"
local lastDodge = 0

local highlightOn = true
local highlightMode = "Filled"
local ringOn = false
local visualColor = Color3.fromRGB(255, 122, 171)

-- combat extras
local killAura = false
local maxTargets = 3
local priority = "Closest"          -- Closest | Lowest HP | Strongest
local targetLock = false
local lockedTarget = nil
local ignoreTeam = false
local burstCount = 1
local charge = 1
local sprintAtk = false
local wobble = true                  -- tiny extra randomness (about 6%) on top of min/max
local aimPrecision = 0               -- degrees of direction randomization
local requireFacing = false
local autoSwing = false
local lastSwing = 0
local currentDelay = 0.625
local attacksFired = 0
local lowHPAlert = false
local lowHPThreshold = 30
local lowHPNotified = false
local antiAFK = false
local antiAFKConn = nil

-- AI Play state
local aiPlayOn = false
local aiDrawLine = true
local aiShowPath = true
local aiAimbot = true
local aiAimPart = "Head"
local aiAimSmooth = 0.3
local aiPathfind = true
local aiMoveMode = "Humanoid Walk"   -- Humanoid Walk | Thumbstick Input | MoveTo
local aiAutoJump = true
local aiStopRange = 6
local aiSearchRange = 150
local aiRepath = 1
local aiRepathCur = 1               -- re-rolled with jitter after every repath
local aiTarget = nil                -- current AI target character
local aiCleanup = nil               -- assigned by the AI engine at the bottom
local blacklist = {}                -- lowercase username set
local function updateBlacklist(text)
    blacklist = {}
    for token in string.gmatch(tostring(text or ""), "[^,%s]+") do
        blacklist[string.lower(token)] = true
    end
end

-- ================================================================ variable timing ====
-- Every attack / dodge waits a RANDOM time between min and max (never a fixed
-- 1s / 2s robot pattern). Wobble adds a tiny extra deviation on top.
local function randDelay(lo, hi)
    if lo > hi then lo, hi = hi, lo end
    return lo + math.random() * (hi - lo)
end
local function computeDelay()
    local d = randDelay(delayMin, delayMax)
    if wobble then d = d * (1 + (math.random() * 2 - 1) * 0.06) end
    return math.max(0.05, d)
end
local function computeDodgeDelay()
    local d = randDelay(dodgeMin, dodgeMax)
    if wobble then d = d * (1 + (math.random() * 2 - 1) * 0.06) end
    return math.max(0.1, d)
end

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
    if tick() - lastDodge < dodgeDelayCur then return end
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
                        dodgeDelayCur = computeDodgeDelay()  -- roll a new random wait
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
            task.wait(math.random(14, 28))
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

-- petal burst at (x, y) — small, quick feedback puff
local function petalBurst(x, y, count)
    count = count or 5
    if not sakuraGui or not sakuraGui.Parent then return end
    local burst = Instance.new("Folder")
    burst.Name = "Burst"
    burst.Parent = sakuraGui

    for i = 1, count do
        local angle = (i / count) * math.pi * 2 + math.random() * 0.4
        local dist = math.random(35, 80)
        local tx = x + math.cos(angle) * dist
        local ty = y + math.sin(angle) * dist
        local size = math.random(8, 15)
        local color = PETAL_COLORS[math.random(1, #PETAL_COLORS)]
        local p = makePetalFrame(burst, size, color, 0.05)
        p.Position = UDim2.fromOffset(x, y)
        p.ZIndex = 9999

        local info = TweenInfo.new(0.6 + math.random() * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local t = TweenService:Create(p, info, {
            Position = UDim2.fromOffset(tx, ty),
            Rotation = math.random(-360, 360),
            BackgroundTransparency = 1,
        })
        t:Play()
    end
    task.delay(1.2, function() pcall(function() burst:Destroy() end) end)
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
            bgGrad.Rotation = (t * 2) % 360
            task.wait(0.3)
        end
    end)

    -- tree in the lower-left
    local tree, branches = buildBranchingTree(sakuraGui, 20, vh - 240, 1)

    -- a handful of falling petals
    local petalFolder = Instance.new("Folder")
    petalFolder.Name = "Petals"
    petalFolder.Parent = sakuraGui
    for _ = 1, 14 do
        spawnFallingPetal(petalFolder, vw, vh, math.random(-50, vh))
    end

    -- animate the Rayfield window: resize smaller, soft entrance, subtle glow
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

        -- very subtle glow pulse: breathe the window stroke a little
        task.spawn(function()
            while winFrame and winFrame.Parent do
                for _, d in ipairs(winFrame:GetDescendants()) do
                    if d:IsA("UIStroke") then
                        local orig = d.Transparency
                        local info = TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
                        TweenService:Create(d, info, { Transparency = math.max(0, orig - 0.12) }):Play()
                        task.wait(3)
                        TweenService:Create(d, info, { Transparency = orig }):Play()
                        task.wait(3)
                    end
                end
                task.wait(1)
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
    description = "Attacks the best target in range",
    value = false,
    callback = function(state)
        autoAttackOn = state
        if not state then
            clearHighlight()
            lockedTarget = nil
        end
        burstAtWindowCenter()
        notify(state and "Auto Attack ON" or "Auto Attack OFF",
               state and ("Targeting within " .. tostring(range) .. " studs") or "Standby",
               state and "check" or "circle")
    end,
})

CombatTab:CreateSection({ name = "TARGETING" })

local killAuraCtl
killAuraCtl = CombatTab:CreateToggle({
    name = "Kill Aura",
    description = "Attack ALL players in range, not just one",
    value = false,
    callback = function(s)
        killAura = s
        burstAtWindowCenter()
        notify(s and "Kill Aura ON" or "Kill Aura OFF",
               s and ("Hitting up to " .. tostring(maxTargets) .. " targets") or "Single target mode",
               s and "swords" or "circle")
    end,
})

CombatTab:CreateSlider({
    name = "Max Targets",
    description = "How many players Kill Aura hits per swing",
    range = { 1, 8 },
    increment = 1,
    value = maxTargets,
    callback = function(v) maxTargets = math.floor(v) end,
})

CombatTab:CreateDropdown({
    name = "Target Priority",
    description = "Who gets attacked first",
    options = { "Closest", "Lowest HP", "Strongest" },
    value = { priority },
    callback = function(selected)
        local p = selected
        if type(selected) == "table" then p = selected[1] end
        if p then priority = p end
    end,
})

CombatTab:CreateToggle({
    name = "Target Lock",
    description = "Stick to one target until it dies or leaves range",
    value = false,
    callback = function(s)
        targetLock = s
        if not s then lockedTarget = nil end
    end,
})

CombatTab:CreateToggle({
    name = "Ignore Teammates",
    description = "Never attack players on your team",
    value = false,
    callback = function(s) ignoreTeam = s end,
})

CombatTab:CreateSection({ name = "ATTACK STYLE" })

CombatTab:CreateSlider({
    name = "Attack Range (studs)",
    description = "How far the script searches for targets",
    range = { 1, 30 },
    increment = 0.5,
    value = range,
    callback = function(v) range = v end,
})

CombatTab:CreateSection({ name = "TIMING" })

CombatTab:CreateSlider({
    name = "Attack Delay Min (s)",
    description = "Fastest gap between attacks (0.05s slider steps)",
    range = { 0.05, 3 },
    increment = 0.05,
    value = delayMin,
    callback = function(v)
        delayMin = v
        currentDelay = computeDelay()
    end,
})

CombatTab:CreateSlider({
    name = "Attack Delay Max (s)",
    description = "Slowest gap - every attack waits a RANDOM time between min and max",
    range = { 0.05, 5 },
    increment = 0.05,
    value = delayMax,
    callback = function(v)
        delayMax = v
        currentDelay = computeDelay()
    end,
})

CombatTab:CreateSlider({
    name = "Burst Count",
    description = "Hits fired per swing cycle",
    range = { 1, 4 },
    increment = 1,
    value = burstCount,
    callback = function(v) burstCount = math.floor(v) end,
})

CombatTab:CreateSlider({
    name = "Charge",
    description = "Attack charge value sent to the server",
    range = { 0, 1 },
    increment = 0.05,
    value = charge,
    callback = function(v) charge = v end,
})

CombatTab:CreateToggle({
    name = "Sprint Attacks",
    description = "Send sprint=true with every attack",
    value = false,
    callback = function(s) sprintAtk = s end,
})

CombatTab:CreateToggle({
    name = "Always Crit",
    value = alwaysCrit,
    callback = function(s) alwaysCrit = s; burstAtWindowCenter() end,
})

CombatTab:CreateSection({ name = "STEALTH" })

CombatTab:CreateToggle({
    name = "Humanize Wobble",
    description = "Adds tiny extra randomness (about 6%) on top of the min/max range",
    value = wobble,
    callback = function(s) wobble = s end,
})

CombatTab:CreateSlider({
    name = "Aim Precision",
    description = "Degrees of random aim offset (0 = perfect)",
    range = { 0, 15 },
    increment = 0.5,
    value = aimPrecision,
    callback = function(v) aimPrecision = v end,
})

CombatTab:CreateToggle({
    name = "Require Facing",
    description = "Only attack when your camera looks at the target",
    value = false,
    callback = function(s) requireFacing = s end,
})

CombatTab:CreateSection({ name = "EXTRAS" })

CombatTab:CreateToggle({
    name = "Auto Swing",
    description = "Keep swinging even with no target in range",
    value = false,
    callback = function(s) autoSwing = s end,
})

CombatTab:CreateKeybind({
    name = "Kill Aura Hotkey",
    description = "Press to flip Kill Aura on/off",
    value = Enum.KeyCode.H,
    callback = function()
        local newState = not killAura
        killAura = newState
        if killAuraCtl then pcall(function() killAuraCtl:Set(newState, true) end) end
        burstAtWindowCenter()
        notify(newState and "Kill Aura ON" or "Kill Aura OFF",
               "Hotkey toggled", newState and "swords" or "circle")
    end,
})

CombatTab:CreateKeybind({
    name = "Toggle Attack Hotkey",
    description = "Press to flip Auto Attack on/off",
    value = Enum.KeyCode.F,
    callback = function()
        local newState = not autoAttackOn
        autoAttackOn = newState
        if autoToggleCtl then pcall(function() autoToggleCtl:Set(newState, true) end) end
        if not newState then
            clearHighlight()
            lockedTarget = nil
        end
        burstAtWindowCenter()
        notify(newState and "Auto Attack ON" or "Auto Attack OFF",
               "Hotkey toggled", newState and "check" or "circle")
    end,
})

CombatTab:CreateSection({ name = "LIVE STATS" })
local statRow = CombatTab:CreateGroup()
local statAttacks = statRow:CreateStat({
    name = "Attacks Fired",
    value = 0,
    compact = true,
    numberEasing = true,
})
local statTargets = statRow:CreateStat({
    name = "Targets in Range",
    value = 0,
    compact = true,
    numberEasing = true,
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
    increment = 0.5,
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
    name = "Dodge Delay Min (s)",
    description = "Fastest re-dodge wait (0.1s slider steps)",
    range = { 0.1, 5 },
    increment = 0.1,
    value = dodgeMin,
    callback = function(v)
        dodgeMin = v
        dodgeDelayCur = computeDodgeDelay()
    end,
})

DodgeTab:CreateSlider({
    name = "Dodge Delay Max (s)",
    description = "Slowest re-dodge wait - randomized between min and max",
    range = { 0.1, 6 },
    increment = 0.1,
    value = dodgeMax,
    callback = function(v)
        dodgeMax = v
        dodgeDelayCur = computeDodgeDelay()
    end,
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

DodgeTab:CreateSection({ name = "DEFENSE" })

DodgeTab:CreateToggle({
    name = "Low HP Alert",
    description = "Notify when your health drops below the threshold",
    value = false,
    callback = function(s)
        lowHPAlert = s
        lowHPNotified = false
    end,
})

DodgeTab:CreateSlider({
    name = "Low HP Threshold (%)",
    range = { 10, 80 },
    increment = 1,
    value = lowHPThreshold,
    callback = function(v) lowHPThreshold = v end,
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

-- ================================================================ AI Play tab ====
local AITab = Window:CreateTab({ name = "AI Play" })

local function setAIPlay(state)
    aiPlayOn = state
    if state then
        -- hunting is pointless without attacking: auto-enable Auto Attack
        if not autoAttackOn and autoToggleCtl then
            autoAttackOn = true
            pcall(function() autoToggleCtl:Set(true, true) end)
        end
        notify("AI Play ON", "Hunting the closest player. Line + path + aimbot active.", "swords")
    else
        if aiCleanup then pcall(aiCleanup) end
        notify("AI Play OFF", "Navigation stopped", "circle")
    end
    burstAtWindowCenter()
end

AITab:CreateSection({ name = "AI PLAY" })

local aiToggleCtl
aiToggleCtl = AITab:CreateToggle({
    name = "AI Play",
    description = "Finds the closest player, draws a line to them, routes around obstacles, aimbot-locks your camera and walks you in with simulated WASD. Auto-enables Auto Attack.",
    value = false,
    callback = setAIPlay,
})

AITab:CreateToggle({
    name = "Draw Target Line",
    description = "Live pink beam from you to the current target",
    value = aiDrawLine,
    callback = function(s) aiDrawLine = s; burstAtWindowCenter() end,
})

AITab:CreateToggle({
    name = "Show Path Line",
    description = "White beam that bends around obstacles as the path recalculates",
    value = aiShowPath,
    callback = function(s) aiShowPath = s; burstAtWindowCenter() end,
})

AITab:CreateToggle({
    name = "Aimbot",
    description = "Smoothly locks your camera onto the target",
    value = aiAimbot,
    callback = function(s) aiAimbot = s end,
})

AITab:CreateDropdown({
    name = "Aim Part",
    description = "Body part the camera locks onto",
    options = { "Head", "HumanoidRootPart" },
    value = { aiAimPart },
    callback = function(selected)
        local p = selected
        if type(selected) == "table" then p = selected[1] end
        if p then aiAimPart = p end
    end,
})

AITab:CreateSlider({
    name = "Aim Smoothness",
    description = "0.05 = heavy smoothing, 1 = instant snap",
    range = { 0.05, 1 },
    increment = 0.05,
    value = aiAimSmooth,
    callback = function(v) aiAimSmooth = v end,
})

AITab:CreateSection({ name = "NAVIGATION" })

AITab:CreateToggle({
    name = "Obstacle Routing",
    description = "Pathfind around walls and gaps instead of walking straight",
    value = aiPathfind,
    callback = function(s) aiPathfind = s end,
})

local aiMoveModeCtl
aiMoveModeCtl = AITab:CreateDropdown({
    name = "Move Mode",
    description = "Humanoid Walk = safest, looks like real walking. No packets are spoofed.",
    options = { "Humanoid Walk", "Thumbstick Input", "MoveTo" },
    value = { aiMoveMode },
    callback = function(selected)
        local m = selected
        if type(selected) == "table" then m = selected[1] end
        if m then aiMoveMode = m end
    end,
})

AITab:CreateToggle({
    name = "Auto Jump",
    description = "Jump when the path says to or when stuck",
    value = aiAutoJump,
    callback = function(s) aiAutoJump = s end,
})

AITab:CreateSlider({
    name = "Stop Distance (studs)",
    description = "Stop walking once this close to the target",
    range = { 3, 20 },
    increment = 0.5,
    value = aiStopRange,
    callback = function(v) aiStopRange = v end,
})

AITab:CreateSlider({
    name = "Search Range (studs)",
    description = "How far the AI looks for the closest player",
    range = { 50, 500 },
    increment = 10,
    value = aiSearchRange,
    callback = function(v) aiSearchRange = math.floor(v) end,
})

AITab:CreateSlider({
    name = "Repath Delay (s)",
    description = "Seconds between recalcs - auto-jittered every cycle",
    range = { 0.2, 3 },
    increment = 0.1,
    value = aiRepath,
    callback = function(v) aiRepath = v end,
})

AITab:CreateSection({ name = "FILTERS" })

pcall(function()
    AITab:CreateInput({
        name = "Blacklist", Name = "Blacklist",
        description = "Players the AI (and Auto Attack) will never target",
        placeholder = "player1, player2", PlaceholderText = "player1, player2",
        removeTextAfterFocusLost = false, RemoveTextAfterFocusLost = false,
        callback = function(text) updateBlacklist(text) end,
        Callback = function(text) updateBlacklist(text) end,
    })
end)

AITab:CreateKeybind({
    name = "AI Play Hotkey",
    description = "Press to flip AI Play on/off",
    value = Enum.KeyCode.V,
    callback = function()
        setAIPlay(not aiPlayOn)
        if aiToggleCtl then pcall(function() aiToggleCtl:Set(aiPlayOn, true) end) end
    end,
})

AITab:CreateSection({ name = "STATUS" })

local aiStatus
pcall(function()
    aiStatus = AITab:CreateParagraph({
        title = "AI Status", Title = "AI Status",
        content = "Idle - turn on AI Play to start hunting.",
        Content = "Idle - turn on AI Play to start hunting.",
    })
end)

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

SettingsTab:CreateSection({ name = "UTILITY" })

SettingsTab:CreateToggle({
    name = "Anti-AFK",
    description = "Prevents the 20-minute Roblox idle kick",
    value = false,
    callback = function(s)
        antiAFK = s
        if s then
            local ok, VirtualUser = pcall(function()
                return game:GetService("VirtualUser")
            end)
            if ok and VirtualUser then
                antiAFKConn = player.Idled:Connect(function()
                    pcall(function()
                        VirtualUser:CaptureController()
                        VirtualUser:ClickButton2(Vector2.new())
                    end)
                end)
                notify("Anti-AFK ON", "Idle kick prevented", "check")
            else
                notify("Anti-AFK unavailable", "VirtualUser not found", "alert-triangle")
                antiAFK = false
            end
        else
            if antiAFKConn then
                pcall(function() antiAFKConn:Disconnect() end)
                antiAFKConn = nil
            end
            notify("Anti-AFK OFF", "Idle timer active again", "circle")
        end
    end,
})

SettingsTab:CreateButton({
    name = "Unload Script",
    description = "Stops everything and removes the UI",
    callback = function()
        autoAttackOn = false
        autoDodgeOn = false
        aiPlayOn = false
        if aiCleanup then pcall(aiCleanup) end
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

-- ================================================================ combat engine ====
local function jitterDir(dir, maxDeg)
    if maxDeg <= 0 then return dir end
    local rad = math.rad(maxDeg)
    local yaw = (math.random() * 2 - 1) * rad
    local pitch = (math.random() * 2 - 1) * rad
    return (CFrame.Angles(pitch, yaw, 0) * CFrame.new(dir)).Position.Unit
end

local function isValidTargetEntry(op)
    if op == player then return nil end
    if blacklist[string.lower(op.Name)] then return nil end
    local char = op.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (root and hum and hum.Health > 0) then return nil end
    if ignoreTeam and op.Team ~= nil and op.Team == player.Team then return nil end
    return { char = char, root = root, hum = hum }
end

local function collectTargets(eye, maxDist)
    local list = {}
    for _, op in ipairs(Players:GetPlayers()) do
        local entry = isValidTargetEntry(op)
        if entry then
            local d = (entry.root.Position / 3 - eye).Magnitude
            if d <= maxDist then
                entry.dist = d
                table.insert(list, entry)
            end
        end
    end
    if priority == "Lowest HP" then
        table.sort(list, function(a, b) return a.hum.Health < b.hum.Health end)
    elseif priority == "Strongest" then
        table.sort(list, function(a, b) return a.hum.Health > b.hum.Health end)
    else
        table.sort(list, function(a, b) return a.dist < b.dist end)
    end
    return list
end

local function facingOK(eye, targetPos)
    if not requireFacing then return true end
    local cam = Workspace.CurrentCamera
    if not cam then return true end
    local toTarget = (targetPos - eye)
    if toTarget.Magnitude < 1e-4 then return true end
    return cam.CFrame.LookVector:Dot(toTarget.Unit) > 0.4
end

local function burstAttack(targetChar, targetRoot, eyePosition)
    local targetPosition = targetRoot.Position / 3
    if not facingOK(eyePosition, targetPosition) then return false end
    local dir = targetPosition - eyePosition
    if dir.Magnitude < 1e-4 then return false end
    dir = jitterDir(dir.Unit, aimPrecision)

    local bursts = math.clamp(math.floor(burstCount), 1, 4)
    for i = 1, bursts do
        attackCount = attackCount + 1
        attacksFired = attacksFired + 1
        if swingRemote then swingRemote:FireServer() end
        attackRemote:FireServer(targetChar, {
            sprint = sprintAtk,
            charge = charge,
            vt = Workspace:GetServerTimeNow(),
            dir = dir,
            eye = eyePosition,
            t = Workspace.DistributedGameTime,
            crit = alwaysCrit,
            n = attackCount,
        })
        if i < bursts then task.wait(0.06) end
    end
    return true
end

-- ================================================================ loops ====
local statAccum = 0

track(RunService.Heartbeat:Connect(function(dt)
    if ringOn then updateRing() end
    checkDodge()

    -- low HP alert
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if lowHPAlert and humanoid and humanoid.Health > 0 then
        local pct = humanoid.Health / math.max(1, humanoid.MaxHealth) * 100
        if pct < lowHPThreshold and not lowHPNotified then
            lowHPNotified = true
            notify("LOW HEALTH", "You are below " .. tostring(math.floor(lowHPThreshold)) .. "% HP!", "alert-triangle")
        elseif pct >= lowHPThreshold + 10 then
            lowHPNotified = false
        end
    end

    -- live stats (every 0.5s)
    statAccum = statAccum + (dt or 0.016)
    if statAccum >= 0.5 then
        statAccum = 0
        pcall(function() statAttacks:Set(attacksFired) end)
        pcall(function()
            local eye = getEyePosition(character)
            local n = eye and #collectTargets(eye, range) or 0
            statTargets:Set(n)
        end)
    end

    -- auto swing (idle swing even with no target)
    if autoAttackOn and autoSwing and swingRemote and tick() - lastSwing > math.max(0.4, currentDelay) then
        lastSwing = tick()
        pcall(function() swingRemote:FireServer() end)
    end

    if not autoAttackOn then return end
    if not attackRemote then return end
    if tick() - lastAttack < currentDelay then return end

    if not humanoid or humanoid.Health <= 0 then return end

    local eyePosition = getEyePosition(character)
    if not eyePosition then return end

    -- maintain target lock validity
    if targetLock and lockedTarget then
        local lhum = lockedTarget:FindFirstChildOfClass("Humanoid")
        local lroot = lockedTarget:FindFirstChild("HumanoidRootPart")
        local stillValid = lhum and lroot and lhum.Health > 0
            and (lroot.Position / 3 - eyePosition).Magnitude <= range
        if not stillValid then lockedTarget = nil end
    end

    local list = collectTargets(eyePosition, range)
    if #list == 0 then
        clearHighlight()
        lockedTarget = nil
        return
    end

    if killAura then
        -- hit up to maxTargets players per cycle
        if targetLock and lockedTarget then
            for _, t in ipairs(list) do
                if t.char == lockedTarget then
                    if highlightOn then setTargetHighlight(t.char) end
                    burstAttack(t.char, t.root, eyePosition)
                    break
                end
            end
        else
            local n = math.min(#list, math.max(1, math.floor(maxTargets)))
            for i = 1, n do
                local t = list[i]
                if i == 1 and highlightOn then setTargetHighlight(t.char) end
                burstAttack(t.char, t.root, eyePosition)
                if i < n then task.wait(0.05) end
            end
            if targetLock then lockedTarget = list[1].char end
        end
    else
        -- single target mode
        local t = list[1]
        if targetLock and lockedTarget then
            for _, tt in ipairs(list) do
                if tt.char == lockedTarget then t = tt break end
            end
        end
        if highlightOn then setTargetHighlight(t.char) end
        if targetLock then lockedTarget = t.char end
        burstAttack(t.char, t.root, eyePosition)
    end

    lastAttack = tick()
    currentDelay = computeDelay()
end))

-- ================================================================ AI Play engine ====
local aiControls = nil
local aiWasActive = false
local aiForceRepath = false
local aiWps = nil
local aiWpIndex = 0
local aiPathTarget = nil
local aiPathTime = 0
local aiLastPos = nil
local aiStuck = 0
local aiLastJump = 0
local aiPulseT = 0
local aiStatusText = nil
local aiStatusTime = 0
local aiMoveFallbackDone = false
local aiDriveActive = false          -- true only while we are actively driving the walk

local targetAtt0, targetAtt1, targetBeam
local pathAtt0, pathAtt1, pathBeam
local wpPart

local pathAgent = PathfindingService:CreatePath({
    AgentRadius = 2.5,
    AgentHeight = 5,
    AgentCanJump = true,
    AgentCanClimb = false,
    WaypointSpacing = 4,
})

local function ensureControls()
    if aiControls ~= nil then return aiControls end
    local ok, ctl = pcall(function()
        local ps = player:FindFirstChildOfClass("PlayerScripts")
            or player:WaitForChild("PlayerScripts", 4)
        if not ps then return false end
        local pm = ps:FindFirstChild("PlayerModule") or ps:WaitForChild("PlayerModule", 4)
        if not pm then return false end
        return require(pm):GetControls()
    end)
    aiControls = (ok and ctl) or false
    return aiControls
end

local function camBasis()
    local cam = Workspace.CurrentCamera
    local look = (cam and cam.CFrame.LookVector) or Vector3.new(0, 0, -1)
    local flatLook = Vector3.new(look.X, 0, look.Z)
    flatLook = (flatLook.Magnitude > 1e-3) and flatLook.Unit or Vector3.new(0, 0, -1)
    return flatLook, Vector3.new(-flatLook.Z, 0, flatLook.X)
end

-- stop driving. GUARDED: only sends one zero - never spams, so your own
-- thumbstick/joystick keeps working when the AI is idle or standing still.
local function aiStop()
    if aiControls then pcall(function() aiControls:SetMoveVector(Vector3.zero) end) end
    if aiDriveActive then
        aiDriveActive = false
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then pcall(function() hum:Move(Vector3.zero, false) end) end
    end
end

-- Drive the walk WITHOUT spoofing anything: feed the ControlModule input
-- vector (so input-reading client scripts see real movement) and walk the
-- humanoid directly (guaranteed to work on iPad). The game's own client then
-- replicates its own MoveState packets - we never touch that remote.
local function aiMove(dir)
    aiDriveActive = true
    local flatLook, flatRight = camBasis()
    local f = dir:Dot(flatLook)
    local r = dir:Dot(flatRight)
    -- feed the input channel (harmless if the game ignores it)
    local ctl = ensureControls()
    if ctl then
        pcall(function() ctl:SetMoveVector(Vector3.new(r, 0, -f)) end)
    end
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum then return end
    if aiMoveMode == "Thumbstick Input" and ctl then
        return -- input vector above is the whole driver
    end
    if aiMoveMode == "MoveTo" then
        pcall(function() hum:MoveTo(root.Position + Vector3.new(dir.X, 0, dir.Z) * 8) end)
        return
    end
    -- Humanoid Walk (default): Heartbeat runs after the control scripts each
    -- frame, so this looks exactly like a real walk to the server
    pcall(function() hum:Move(Vector3.new(dir.X, 0, dir.Z), false) end)
end

local function destroyBeam(att0, att1, beam)
    if beam then pcall(function() beam:Destroy() end) end
    if att0 then pcall(function() att0:Destroy() end) end
    if att1 then pcall(function() att1:Destroy() end) end
    return nil, nil, nil
end

local function removeAIVisuals()
    targetAtt0, targetAtt1, targetBeam = destroyBeam(targetAtt0, targetAtt1, targetBeam)
    pathAtt0, pathAtt1, pathBeam = destroyBeam(pathAtt0, pathAtt1, pathBeam)
    if wpPart then pcall(function() wpPart:Destroy() end); wpPart = nil end
end

local function makeBeam(att0, att1, parentTo, colA, colB, w0, w1, curve)
    local b = Instance.new("Beam")
    b.Attachment0 = att0
    b.Attachment1 = att1
    b.Color = ColorSequence.new(colA, colB)
    b.Transparency = NumberSequence.new(0.1)
    b.Width0 = w0
    b.Width1 = w1
    b.FaceCamera = true
    b.LightEmission = 1
    b.LightInfluence = 0
    b.Segments = 20
    b.CurveSize0 = curve
    b.CurveSize1 = curve
    b.Parent = parentTo
    return b
end

local function ensureTargetLine(myRoot, tRoot)
    if not aiDrawLine then return end
    if targetBeam and targetAtt0 and targetAtt0.Parent == myRoot
        and targetAtt1 and targetAtt1.Parent == tRoot then return end
    targetAtt0, targetAtt1, targetBeam = destroyBeam(targetAtt0, targetAtt1, targetBeam)
    local ok = pcall(function()
        local a0 = Instance.new("Attachment")
        a0.Position = Vector3.new(0, 1, 0)
        a0.Parent = myRoot
        local a1 = Instance.new("Attachment")
        a1.Position = Vector3.new(0, 1, 0)
        a1.Parent = tRoot
        targetAtt0, targetAtt1 = a0, a1
        targetBeam = makeBeam(a0, a1, myRoot, visualColor, Color3.fromRGB(255, 236, 244), 0.14, 0.1, 0)
    end)
    if not ok then targetAtt0, targetAtt1, targetBeam = destroyBeam(targetAtt0, targetAtt1, targetBeam) end
end

local function ensureWpPart()
    if wpPart and wpPart.Parent then return wpPart end
    wpPart = Instance.new("Part")
    wpPart.Name = "LG_AAD3_WP"
    wpPart.Size = Vector3.new(0.4, 0.4, 0.4)
    wpPart.Transparency = 1
    wpPart.Anchored = true
    wpPart.CanCollide = false
    wpPart.CanQuery = false
    wpPart.CanTouch = false
    wpPart.CastShadow = false
    wpPart.Parent = Workspace
    return wpPart
end

local function ensurePathLine(myRoot)
    if not aiShowPath then return end
    local ok, part = pcall(function()
        local p = ensureWpPart()
        if pathBeam and pathAtt0 and pathAtt0.Parent == myRoot
            and pathAtt1 and pathAtt1.Parent == p then return p end
        pathAtt0, pathAtt1, pathBeam = destroyBeam(pathAtt0, pathAtt1, pathBeam)
        local a0 = Instance.new("Attachment")
        a0.Position = Vector3.new(0, 1, 0)
        a0.Parent = myRoot
        local a1 = Instance.new("Attachment")
        a1.Parent = p
        pathAtt0, pathAtt1 = a0, a1
        pathBeam = makeBeam(a0, a1, myRoot, Color3.fromRGB(255, 255, 255), visualColor, 0.07, 0.07, 2)
        return p
    end)
    if not ok then
        pathAtt0, pathAtt1, pathBeam = destroyBeam(pathAtt0, pathAtt1, pathBeam)
    end
end

local function setAIStatus(text)
    if text == aiStatusText and tick() - aiStatusTime < 1 then return end
    aiStatusText = text
    aiStatusTime = tick()
    if not aiStatus then return end
    local ok = pcall(function() aiStatus:Set({ title = "AI Status", content = text }) end)
    if not ok then pcall(function() aiStatus:Set({ Title = "AI Status", Content = text }) end) end
end

local function aiSelectTarget(myRoot)
    local best, bestDist = nil, aiSearchRange
    for _, op in ipairs(Players:GetPlayers()) do
        local entry = isValidTargetEntry(op)
        if entry then
            local d = (entry.root.Position - myRoot.Position).Magnitude
            if d < bestDist then best, bestDist = entry, d end
        end
    end
    return best, bestDist
end

local function aiEnsurePath(myPos, tPos)
    local targetMoved = (not aiPathTarget) or ((tPos - aiPathTarget).Magnitude > 6)
    local aged = (tick() - aiPathTime) > aiRepathCur
    local exhausted = (not aiWps) or (aiWpIndex >= #aiWps)
    if not (targetMoved or aged or exhausted or aiForceRepath) then return true end
    aiForceRepath = false
    local ok = pcall(function() pathAgent:ComputeAsync(myPos, tPos) end)
    aiPathTime = tick()
    aiRepathCur = math.max(0.2, aiRepath * (0.75 + math.random() * 0.5))  -- variable repath timing
    aiPathTarget = tPos
    aiWps = nil
    aiWpIndex = 1
    if ok and pathAgent.Status == Enum.PathStatus.Success then
        aiWps = pathAgent:GetWaypoints()
        return true
    end
    return false
end

local function aiFollowPath(myRoot, myHum)
    local wp = aiWps and aiWps[aiWpIndex]
    if not wp then return nil end
    local wpPos = wp.Position
    local flatDelta = Vector3.new(wpPos.X - myRoot.Position.X, 0, wpPos.Z - myRoot.Position.Z)
    if flatDelta.Magnitude < 3 then
        aiWpIndex = aiWpIndex + 1
        wp = aiWps[aiWpIndex]
        if not wp then return nil end
        wpPos = wp.Position
    end
    if wp.Action == Enum.PathWaypointAction.Jump and aiAutoJump and myHum
        and tick() - aiLastJump > 0.4 then
        aiLastJump = tick()
        pcall(function() myHum.Jump = true end)
    end
    local dir = wpPos - myRoot.Position
    dir = Vector3.new(dir.X, 0, dir.Z)
    if dir.Magnitude < 1e-3 then return nil end
    return dir.Unit
end

local function aiStep()
    local char = player.Character
    local myRoot = char and char:FindFirstChild("HumanoidRootPart")
    local myHum = char and char:FindFirstChildOfClass("Humanoid")

    if not aiPlayOn then
        if aiWasActive then
            aiWasActive = false
            pcall(aiStop)
            removeAIVisuals()
            aiTarget = nil
            aiWps = nil
            setAIStatus("Idle")
        end
        return
    end
    aiWasActive = true

    if not myRoot or not myHum or myHum.Health <= 0 then
        pcall(aiStop)
        removeAIVisuals()
        aiTarget = nil
        setAIStatus("Waiting for character...")
        return
    end

    local entry = aiSelectTarget(myRoot)
    if not entry then
        aiTarget = nil
        pcall(aiStop)
        removeAIVisuals()
        setAIStatus("No player within " .. tostring(math.floor(aiSearchRange)) .. " studs")
        return
    end

    aiTarget = entry.char
    local tRoot = entry.root
    local tPos = tRoot.Position
    local myPos = myRoot.Position
    local dist = (tPos - myPos).Magnitude

    ensureTargetLine(myRoot, tRoot)

    if dist <= aiStopRange then
        pcall(aiStop)
        aiWps = nil
        aiWpIndex = 0
        if wpPart and wpPart.Parent then
            pcall(function() wpPart.CFrame = CFrame.new(tPos) end)
        end
        setAIStatus("In range: " .. entry.char.Name .. " | " .. string.format("%.0f", dist) .. " studs | attacking")
        aiStuck = 0
        aiLastPos = myPos
        return
    end

    local dir = nil
    if aiPathfind then
        local okPath = aiEnsurePath(myPos, tPos)
        if okPath and aiWps then
            ensurePathLine(myRoot)
            dir = aiFollowPath(myRoot, myHum)
        end
        if not dir then
            -- path unavailable this frame: beeline so we never freeze
            local d = tPos - myPos
            local flat = Vector3.new(d.X, 0, d.Z)
            if flat.Magnitude > 1e-3 then dir = flat.Unit end
        end
    else
        local d = tPos - myPos
        local flat = Vector3.new(d.X, 0, d.Z)
        if flat.Magnitude > 1e-3 then dir = flat.Unit end
    end

    if aiPathfind and wpPart and wpPart.Parent then
        local cur = aiWps and aiWps[aiWpIndex]
        pcall(function() wpPart.CFrame = CFrame.new((cur and cur.Position) or tPos) end)
    end

    if dir then
        aiMove(dir)
        if aiLastPos and (myPos - aiLastPos).Magnitude < 0.4 then
            aiStuck = aiStuck + 0.05
            if aiStuck > 1.2 then
                aiStuck = 0
                if aiAutoJump and myHum then pcall(function() myHum.Jump = true end) end
                aiForceRepath = true
                if aiMoveMode == "Humanoid Walk" and not aiMoveFallbackDone then
                    -- direct walk blocked: switch strategy once
                    aiMoveFallbackDone = true
                    aiMoveMode = "Thumbstick Input"
                    if aiMoveModeCtl then pcall(function() aiMoveModeCtl:Set("Thumbstick Input", true) end) end
                    notify("AI Play", "Walk drive didn't move you - switched to Thumbstick Input", "alert-triangle")
                end
            end
        else
            aiStuck = 0
        end
        setAIStatus("Chasing " .. entry.char.Name .. " | " .. string.format("%.0f", dist)
            .. " studs | " .. (aiPathfind and "routing around obstacles" or "beelining"))
    else
        pcall(aiStop)
    end
    aiLastPos = myPos
end

aiCleanup = function()
    aiPlayOn = false
    pcall(aiStop)
    removeAIVisuals()
    aiTarget = nil
    aiWps = nil
    aiWpIndex = 0
    aiStuck = 0
    setAIStatus("Idle")
end

-- beam pulse + aimbot (RenderStepped)
track(RunService.RenderStepped:Connect(function()
    local ok, err = pcall(function()
        aiPulseT = aiPulseT + 0.016
        local w = 0.12 + math.sin(aiPulseT * 5) * 0.04
        if targetBeam then
            targetBeam.Width0 = w
            targetBeam.Width1 = w * 0.8
        end
        if pathBeam then
            pathBeam.CurveSize0 = 1.5 + math.sin(aiPulseT * 2.2) * 1.2
            pathBeam.CurveSize1 = pathBeam.CurveSize0
        end
        if aiPlayOn and aiAimbot and aiTarget then
            local myChar = player.Character
            local cam = Workspace.CurrentCamera
            local part = aiTarget:FindFirstChild(aiAimPart)
                or aiTarget:FindFirstChild("HumanoidRootPart")
            if myChar and myChar:FindFirstChild("HumanoidRootPart") and cam and part then
                local myPos = cam.CFrame.Position
                local aimPos = part.Position
                if (aimPos - myPos).Magnitude > 1 then
                    cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(myPos, aimPos), aiAimSmooth)
                end
            end
        end
    end)
    if not ok then warn("[AAD3 AI] render: " .. tostring(err)) end
end))

-- main AI loop
task.spawn(function()
    while true do
        local ok, err = pcall(aiStep)
        if not ok then warn("[AAD3 AI] " .. tostring(err)) end
        task.wait(aiPlayOn and 0.05 or 0.25)
    end
end)

print("[AAD3] Loaded via Rayfield Gen2 (Sakura Mayhem). Combat ready: " .. tostring(combatReady))
