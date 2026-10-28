--[[
    Rocket Merge Auto Farm — Rayfield Gen 2 (Sakura Edition)
    For merge games (rockets / rovers / anything).

    AUTO FARM loop (one toggle, fully automatic):
      1. TELEPORT to an item (nearest mergeable, tiny human-like jitter).
      2. SEARCH the map for another item with the SAME NAME (same tier).
      3. TWEEN to that twin (speed randomized ±15% per trip) and MERGE it.
      4. If the game hasn't merged yet, presses closer and tries again.
      5. Repeat — merged tiers chain upward automatically.

    Safety / anti-flag notes:
      - NO forged remote packets. Movement is done by setting your own
        HumanoidRootPart CFrame (teleport) and TweenService (tween) —
        your client owns your character physics, so it replicates natively.
        Nothing is spoofed, there is nothing to validate.
      - Humanized timing everywhere (random delays, ±jitter, random target
        variety), pair cooldowns after failed merges, stuck detection.
      - If the item has a ProximityPrompt / ClickDetector the script fires
        it too (guarded — silently skips on executors without those fns).

    Tabs:
      Farm:     Auto Farm (F hotkey), Scan Items, live status + merge count
      Settings: Item name filter, ignore trailing numbers, first-item travel
                (Teleport/Tween), tween speed, merge wait, cycle delay,
                twin range limit, noclip travel, sakura petals, anti-AFK, unload
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
math.randomseed(os.time() % 100000)

-- ================================================================ cleanup ====
local store = (type(getgenv) == "function" and getgenv()) or _G
if store.LG_RMF_Conns then
    for _, c in ipairs(store.LG_RMF_Conns) do pcall(function() c:Disconnect() end) end
    store.LG_RMF_Conns = nil
end
local conns = {}
store.LG_RMF_Conns = conns
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
killOld("LG_RMF_Status")
killOld("LG_SakuraEnv")

-- ================================================================ library ====
local okFetch, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)
if not okFetch or type(Rayfield) ~= "table" then
    warn("[RMF] Failed to load Rayfield Gen2: " .. tostring(Rayfield))
    return
end

-- ================================================================ state ====
local farmOn = false
local merges = 0
local cycles = 0
local lastNote = "-"                 -- last thing the loop reported

local keyword = ""                   -- empty = merge any same-name items
local stripNums = false              -- ignore trailing numbers when matching names
local firstTravel = "Teleport"       -- Teleport | Tween (travel to the 1st item)
local tweenSpeed = 60                -- studs/sec, randomized ±15% per trip
local mergeWait = 0.45               -- randomized wait after arrival (let game merge)
local cycleDelay = 1.2               -- randomized wait between farm cycles
local twinRange = 0                  -- max source→twin distance (0 = unlimited)
local noclipTravel = true            -- pass through obstacles while tweening
local wobble = true                  -- tiny extra randomness on all timings
local petalsOn = true                -- sakura environment
local antiAFK = true
local antiAFKConn = nil

local farmToggleCtl = nil
local statusPanel = nil
local travelAbort = false            -- set when toggled off / unloaded mid-tween
local noclipRestore = nil            -- restore function while noclip is active
local currentTween = nil
local cooldownUntil = {}             -- [item instance] = os.clock() expiry

-- ================================================================ timing ====
local function randDelay(lo, hi)
    if lo > hi then lo, hi = hi, lo end
    return lo + math.random() * (hi - lo)
end
local function wob(x, amt)
    amt = amt or 0.06
    if not wobble then return x end
    return x * (1 + (math.random() * 2 - 1) * amt)
end

local function getChar()
    local char = player.Character
    if not char then return nil, nil, nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return nil, nil, nil end
    return char, root, hum
end

-- name used for same-tier matching (lowercased, optionally stripped)
local function matchName(inst)
    local n = inst.Name
    if stripNums then n = string.gsub(n, "[%s_%.%-]*%d+$", "") end
    return string.lower(n)
end

local function isCooling(inst)
    local untilT = cooldownUntil[inst]
    if not untilT then return false end
    if os.clock() >= untilT then
        cooldownUntil[inst] = nil
        return false
    end
    return true
end
local function cooldown(inst, secs)
    if inst then cooldownUntil[inst] = os.clock() + (secs or 10) end
end
local function gcCooldowns()
    for inst, untilT in pairs(cooldownUntil) do
        local gone = false
        pcall(function() gone = inst.Parent == nil end)
        if gone or os.clock() >= untilT then cooldownUntil[inst] = nil end
    end
end

-- ================================================================ sakura env ====
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

if petalsOn then buildSakuraEnv() end

-- ================================================================ window ====
local Window = Rayfield:CreateWindow({
    name = "Rocket Merge Auto Farm",
    subtitle = "Sakura",
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
        petalBurst(cx, cy, 8)
    else
        petalBurst(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2, 8)
    end
end

-- ================================================================ Farm tab ====
local FarmTab = Window:CreateTab({ name = "Farm" })

local scanAndReport -- assigned in the engine section below
local function panelText(state)
    return state .. "\nMerges: " .. tostring(merges)
        .. "\nCycles: " .. tostring(cycles)
        .. "\nLast: " .. lastNote
end

local function setPanel(state)
    local text = panelText(state)
    if not statusPanel then return end
    local ok = pcall(function() statusPanel:Set({ title = "Farm Status", content = text }) end)
    if not ok then pcall(function() statusPanel:Set({ Title = "Farm Status", Content = text }) end) end
end

farmToggleCtl = FarmTab:CreateToggle({
    name = "Auto Farm",
    description = "TP to an item, find its same-name twin, tween to merge - forever",
    value = false,
    callback = function(state)
        farmOn = state
        travelAbort = false
        if not state then
            travelAbort = true -- unstick any active tween watcher
            if currentTween then pcall(function() currentTween:Cancel() end) end
            if noclipRestore then pcall(noclipRestore); noclipRestore = nil end
        end
        burstAtWindowCenter()
        notify(state and "Auto Farm ON" or "Auto Farm OFF",
               state and "Teleporting to items and merging twins" or "Farm stopped",
               state and "check" or "circle")
    end,
})

FarmTab:CreateKeybind({
    name = "Auto Farm Hotkey",
    description = "Press to flip Auto Farm on/off",
    value = Enum.KeyCode.F,
    callback = function()
        local newState = not farmOn
        farmOn = newState
        if farmToggleCtl then pcall(function() farmToggleCtl:Set(newState, true) end) end
        if not newState then
            travelAbort = true
            if currentTween then pcall(function() currentTween:Cancel() end) end
            if noclipRestore then pcall(noclipRestore); noclipRestore = nil end
        else
            travelAbort = false
        end
        burstAtWindowCenter()
        notify(newState and "Auto Farm ON" or "Auto Farm OFF",
               "Hotkey toggled", newState and "check" or "circle")
    end,
})

FarmTab:CreateSection({ name = "TOOLS" })

FarmTab:CreateButton({
    name = "Scan Items",
    description = "Lists item names + counts so you can tune the filter",
    callback = function()
        if scanAndReport then scanAndReport() end
    end,
})

FarmTab:CreateSection({ name = "STATUS" })

pcall(function()
    statusPanel = FarmTab:CreateParagraph({
        title = "Farm Status", Title = "Farm Status",
        content = panelText("Idle - toggle Auto Farm to start."),
        Content = panelText("Idle - toggle Auto Farm to start."),
    })
end)

-- ================================================================ Settings tab ====
local SettingsTab = Window:CreateTab({ name = "Settings" })

SettingsTab:CreateSection({ name = "MATCHING" })

pcall(function()
    SettingsTab:CreateInput({
        name = "Item Name Filter", Name = "Item Name Filter",
        description = "Only merge items whose name contains this. Empty = any same-name pair",
        placeholder = "e.g. Rocket", PlaceholderText = "e.g. Rocket",
        removeTextAfterFocusLost = false, RemoveTextAfterFocusLost = false,
        callback = function(text) keyword = string.lower(tostring(text or "")) end,
        Callback = function(text) keyword = string.lower(tostring(text or "")) end,
    })
end)

SettingsTab:CreateToggle({
    name = "Ignore Trailing Numbers",
    description = "Match Rocket_1 with Rocket_2 (same tier, numbered spawns)",
    value = stripNums,
    callback = function(s) stripNums = s end,
})

SettingsTab:CreateSlider({
    name = "Twin Range Limit (studs)",
    description = "Max distance between the pair. 0 = unlimited",
    range = { 0, 2000 },
    increment = 25,
    value = twinRange,
    callback = function(v) twinRange = math.floor(v) end,
})

SettingsTab:CreateSection({ name = "TRAVEL" })

SettingsTab:CreateDropdown({
    name = "First Item Travel",
    description = "How to reach the first item of each pair",
    options = { "Teleport", "Tween" },
    value = { firstTravel },
    callback = function(selected)
        local p = selected
        if type(selected) == "table" then p = selected[1] end
        if p then firstTravel = p end
    end,
})

SettingsTab:CreateSlider({
    name = "Tween Speed (studs/s)",
    description = "Travel speed, randomized about 15 percent every trip",
    range = { 20, 200 },
    increment = 5,
    value = tweenSpeed,
    callback = function(v) tweenSpeed = v end,
})

SettingsTab:CreateToggle({
    name = "Noclip While Traveling",
    description = "Pass through obstacles during tweens (restored on arrival)",
    value = noclipTravel,
    callback = function(s) noclipTravel = s end,
})

SettingsTab:CreateSection({ name = "TIMING" })

SettingsTab:CreateSlider({
    name = "Merge Wait (s)",
    description = "Pause after arrival so the game can register the merge",
    range = { 0.1, 2 },
    increment = 0.05,
    value = mergeWait,
    callback = function(v) mergeWait = v end,
})

SettingsTab:CreateSlider({
    name = "Cycle Delay (s)",
    description = "Randomized pause between farm cycles",
    range = { 0.2, 5 },
    increment = 0.1,
    value = cycleDelay,
    callback = function(v) cycleDelay = v end,
})

SettingsTab:CreateToggle({
    name = "Humanize Wobble",
    description = "Extra randomness on all timings so it never looks robotic",
    value = wobble,
    callback = function(s) wobble = s end,
})

SettingsTab:CreateSection({ name = "EXTRAS" })

SettingsTab:CreateToggle({
    name = "Sakura Petals",
    description = "The sakura environment overlay",
    value = petalsOn,
    callback = function(s)
        petalsOn = s
        if s then
            if not sakuraGui or not sakuraGui.Parent then buildSakuraEnv() end
        else
            if sakuraGui then pcall(function() sakuraGui:Destroy() end) end
            sakuraGui = nil
        end
    end,
})

SettingsTab:CreateToggle({
    name = "Anti-AFK",
    description = "Prevents the 20-minute Roblox idle kick (recommended for farms)",
    value = antiAFK,
    callback = function(s)
        antiAFK = s
        if s then
            pcall(function()
                local VirtualUser = game:GetService("VirtualUser")
                antiAFKConn = track(player.Idled:Connect(function()
                    pcall(function()
                        VirtualUser:CaptureController()
                        VirtualUser:ClickButton2(Vector2.new())
                    end)
                end))
            end)
            notify("Anti-AFK ON", "Idle kick prevented", "check")
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
        farmOn = false
        travelAbort = true
        if currentTween then pcall(function() currentTween:Cancel() end) end
        if noclipRestore then pcall(noclipRestore); noclipRestore = nil end
        if antiAFKConn then pcall(function() antiAFKConn:Disconnect() end); antiAFKConn = nil end
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        conns = {}
        for _, c in ipairs(envConns) do pcall(function() c:Disconnect() end) end
        envConns = {}
        store.LG_RMF_Conns = nil
        pcall(function() if sakuraGui then sakuraGui:Destroy() end end)
        pcall(function() Window:Unload() end)
        killOld("Rayfield")
        killOld("LG_RMF_Status")
        killOld("LG_SakuraEnv")
        print("[RMF] Unloaded.")
    end,
})

task.delay(0.6, function()
    notify("Sakura Farm loaded",
           "Toggle Auto Farm (or press F) - it TPs to an item, finds its twin and merges.",
           "check")
end)

-- ================================================================ farm engine ====

-- initial Anti-AFK connection (default ON for farms)
if antiAFK then
    pcall(function()
        local VirtualUser = game:GetService("VirtualUser")
        antiAFKConn = track(player.Idled:Connect(function()
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end))
    end)
end

-- ---------- movement ----------
local function standCF(pos, faceTarget)
    local p = Vector3.new(pos.X, pos.Y, pos.Z)
    local look = Vector3.new(0, 0, 1)
    if faceTarget then
        local d = Vector3.new(faceTarget.X - p.X, 0, faceTarget.Z - p.Z)
        if d.Magnitude > 0.5 then look = d.Unit end
    end
    local ok, cf = pcall(function() return CFrame.lookAt(p, p + look) end)
    if ok and cf then return cf end
    return CFrame.new(p)
end

local function enterNoclip()
    local char = player.Character
    if not char then return nil end
    local saved = {}
    pcall(function()
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") then
                saved[d] = d.CanCollide
                d.CanCollide = false
            end
        end
    end)
    return function()
        for part, v in pairs(saved) do
            pcall(function() part.CanCollide = v end)
        end
    end
end

local function teleportTo(pos, faceTarget)
    local char, root = getChar()
    if not root then return false end
    local jitter = Vector3.new((math.random() - 0.5) * 1.2, 0, (math.random() - 0.5) * 1.2)
    local ok = pcall(function()
        root.CFrame = standCF(pos + jitter, faceTarget)
    end)
    return ok
end

-- tween the character to a CFrame; returns "arrived" | "gone" | "stuck" | "stopped"
local function tweenTo(targetCFrame, abortInst, speed)
    local char, root = getChar()
    if not root then return "stopped" end
    local dist = (root.Position - targetCFrame.Position).Magnitude
    if dist < 2.2 then return "arrived" end
    speed = speed or tweenSpeed
    local dur = math.max(0.08, dist / math.max(10, speed))
    local okT, tw = pcall(function()
        return TweenService:Create(root,
            TweenInfo.new(dur, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
            { CFrame = targetCFrame })
    end)
    if not okT or not tw then return "stopped" end
    currentTween = tw
    pcall(function() tw:Play() end)
    local t0 = os.clock()
    local lastPos = root.Position
    local lastMoveT = os.clock()
    local result = "stuck"
    while true do
        task.wait(0.15)
        if not farmOn or travelAbort then
            result = "stopped"
            break
        end
        local _, r2 = getChar()
        if not r2 then
            result = "stopped"
            break
        end
        if abortInst then
            local gone = false
            pcall(function() gone = abortInst.Parent == nil end)
            if gone then
                result = "gone"
                break
            end
        end
        local remaining = (r2.Position - targetCFrame.Position).Magnitude
        if remaining < 2.2 then
            result = "arrived"
            break
        end
        if (r2.Position - lastPos).Magnitude > 0.4 then
            lastPos = r2.Position
            lastMoveT = os.clock()
        elseif os.clock() - lastMoveT > 1.4 then
            break
        end
        if os.clock() - t0 > dur + 6 then
            break
        end
    end
    pcall(function() tw:Cancel() end)
    currentTween = nil
    return result
end

-- ---------- item discovery ----------
local function keywordPass(inst)
    local n = string.lower(inst.Name)
    if keyword ~= "" then
        return string.find(n, keyword, 1, true) ~= nil
    end
    return true
end

local function itemBox(inst)
    if inst:IsA("Model") then
        local ok, cf, size = pcall(function()
            local c, s = inst:GetBoundingBox()
            return c, s
        end)
        if ok and cf then return cf, size end
        local ok2, pivot = pcall(function() return inst:GetPivot() end)
        if ok2 and pivot then return pivot, Vector3.new(6, 6, 6) end
        return nil, nil
    end
    if inst:IsA("BasePart") then
        local ok, cf, size = pcall(function() return inst.CFrame, inst.Size end)
        if ok then return cf, size end
    end
    return nil, nil
end

-- depth-limited BFS over Workspace; skips characters, Terrain, Camera.
-- Models are items; loose BaseParts count only if big and not inside a Model.
local function collectItems()
    local myChar = player.Character
    local skipSet = {}
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character then skipSet[pl.Character] = true end
    end
    local out = {}
    local visited = 0
    local queue = { { Workspace, 0 } }
    while #queue > 0 do
        local entry = table.remove(queue)
        local node, depth = entry[1], entry[2]
        if depth <= 6 then
            local children = nil
            pcall(function() children = node:GetChildren() end)
            if children then
                for _, child in ipairs(children) do
                    visited = visited + 1
                    if visited > 8000 then return out end
                    local classOK, isSkip, isTerrain, isCam = false, skipSet[child] == true, false, false
                    pcall(function() classOK = child:IsA("Model") or child:IsA("BasePart") end)
                    pcall(function() isTerrain = child:IsA("Terrain") end)
                    pcall(function() isCam = child:IsA("Camera") end)
                    if not isSkip and not isTerrain and not isCam then
                        if child:IsA("Model") then
                            if keywordPass(child) then table.insert(out, child) end
                            table.insert(queue, { child, depth + 1 })
                        elseif child:IsA("BasePart") then
                            local inModel = false
                            pcall(function() inModel = child.Parent ~= nil and child.Parent:IsA("Model") end)
                            local big = false
                            pcall(function()
                                local s = child.Size
                                big = s.X >= 3 or s.Y >= 3 or s.Z >= 3
                            end)
                            if not inModel and not isTerrain and big and keywordPass(child) then
                                table.insert(out, child)
                            end
                        else
                            table.insert(queue, { child, depth + 1 })
                        end
                    end
                end
            end
        end
    end
    return out
end

-- stand beside an item: returns (stand position, item center to face)
local function sidePos(box, fromPos, pad)
    pad = pad or 2.6
    local p = box.cf.Position
    local d = Vector3.new(fromPos.X - p.X, 0, fromPos.Z - p.Z)
    if d.Magnitude < 0.5 then d = Vector3.new(1, 0, 0) end
    d = d.Unit
    local sx = (box.size and box.size.X) or 3
    local sz = (box.size and box.size.Z) or 3
    local sy = (box.size and box.size.Y) or 6
    local rad = math.max(sx, sz) / 2
    local target = p + d * (rad + pad)
    return Vector3.new(target.X, p.Y + sy / 2 + 1.5, target.Z), p
end

-- nearest mergeable pair: a source item + the closest other item with the SAME name
local function pickPair()
    local char, root = getChar()
    if not root then return nil, nil end
    local myPos = root.Position
    local items = collectItems()
    if #items < 2 then return nil, nil end

    local entries = {}
    local counts = {}
    for i = 1, #items do
        local it = items[i]
        if not isCooling(it) then
            local cf, size = itemBox(it)
            if cf and size then
                local e = { inst = it, cf = cf, size = size, name = matchName(it) }
                table.insert(entries, e)
                counts[e.name] = (counts[e.name] or 0) + 1
            end
        end
    end

    local cands = {}
    for i = 1, #entries do
        local e = entries[i]
        if counts[e.name] >= 2 then
            e.dist = (e.cf.Position - myPos).Magnitude
            table.insert(cands, e)
        end
    end
    if #cands == 0 then return nil, nil end
    table.sort(cands, function(a, b) return a.dist < b.dist end)

    -- usually the nearest pair, sometimes 2nd/3rd for human-like variety
    local pick = 1
    if #cands >= 3 and math.random() < 0.25 then
        pick = math.random(2, 3)
    elseif #cands == 2 and math.random() < 0.2 then
        pick = 2
    end
    local src = cands[pick]

    local maxD = (twinRange > 0) and twinRange or math.huge
    local twin, twinDist = nil, maxD
    for i = 1, #cands do
        local e = cands[i]
        if e ~= src and e.name == src.name then
            local d = (e.cf.Position - src.cf.Position).Magnitude
            if d < twinDist then twin, twinDist = e, d end
        end
    end
    if not twin then return nil, nil end
    return src, twin
end

scanAndReport = function()
    local items = collectItems()
    local counts, display = {}, {}
    for i = 1, #items do
        local n = matchName(items[i])
        counts[n] = (counts[n] or 0) + 1
        if not display[n] then display[n] = items[i].Name end
    end
    local names = {}
    for n, c in pairs(counts) do table.insert(names, { n = n, c = c }) end
    table.sort(names, function(a, b) return a.c > b.c end)
    local lines = {}
    for i = 1, math.min(6, #names) do
        table.insert(lines, display[names[i].n] .. " x" .. tostring(names[i].c))
    end
    if #lines == 0 then
        lastNote = "scan found nothing"
        notify("Scan", "No items found. Try clearing the name filter.", "alert-triangle")
        setPanel("Scan found nothing")
        return
    end
    local summary = table.concat(lines, ", ")
    lastNote = "scan: " .. summary
    notify("Scan result", summary, "search")
    setPanel("Scan done")
end

-- if the game merges via ProximityPrompt / ClickDetector, trigger it (guarded)
local function tryInteract(inst)
    if type(fireproximityprompt) == "function" then
        pcall(function()
            local pr = inst:FindFirstChildWhichIsA("ProximityPrompt", true)
            if pr then fireproximityprompt(pr) end
        end)
    end
    if type(fireclickdetector) == "function" then
        pcall(function()
            local cd = inst:FindFirstChildWhichIsA("ClickDetector", true)
            if cd then fireclickdetector(cd) end
        end)
    end
end

local function pairGone(a, b)
    local gone = false
    pcall(function() gone = a.Parent == nil end)
    if gone then return true end
    pcall(function() gone = b.Parent == nil end)
    return gone
end

-- ================================================================ main loop ====
task.spawn(function()
    while true do
        if farmOn then
            cycles = cycles + 1
            gcCooldowns()
            local char, root = getChar()
            if not root then
                lastNote = "waiting for character"
                setPanel("No character")
                task.wait(1)
            else
                local src, twin = pickPair()
                if not src then
                    lastNote = "no mergeable pairs in sight"
                    setPanel("Searching for pairs")
                    task.wait(randDelay(cycleDelay, cycleDelay * 1.8))
                else
                    -- STAGE 1: reach the source item
                    local srcPos, srcCenter = sidePos(src, root.Position, 2.6)
                    lastNote = "to " .. src.inst.Name
                    setPanel("Going to " .. src.inst.Name)
                    if firstTravel == "Teleport" then
                        teleportTo(srcPos, srcCenter)
                        task.wait(randDelay(0.2, 0.45))
                    else
                        if noclipTravel and not noclipRestore then noclipRestore = enterNoclip() end
                        tweenTo(standCF(srcPos, srcCenter), src.inst, wob(tweenSpeed, 0.15))
                        if noclipRestore then pcall(noclipRestore); noclipRestore = nil end
                    end
                    tryInteract(src.inst)

                    if not farmOn then
                        -- paused mid-cycle
                    elseif pairGone(src.inst, twin.inst) then
                        -- the pair got consumed while we were reaching it (the
                        -- game can register the merge right at pickup because
                        -- we often arrive already carrying the tier-up item)
                        merges = merges + 1
                        cooldown(src.inst, 3)
                        cooldown(twin.inst, 3)
                        lastNote = "merged " .. src.inst.Name .. " (consumed at pickup)"
                        setPanel("Merge #" .. tostring(merges))
                        pcall(burstAtWindowCenter)
                        task.wait(randDelay(0.3, 0.8))
                    else
                        -- STAGE 2: tween to the twin and merge
                        local tcf, tsize = itemBox(twin.inst)
                        if tcf then twin.cf, twin.size = tcf, tsize end
                        local tPos, tCenter = sidePos(twin, src.cf.Position, 3.0)
                        lastNote = "merging " .. src.inst.Name
                        setPanel("Merging " .. src.inst.Name)
                        if noclipTravel and not noclipRestore then noclipRestore = enterNoclip() end
                        local res = tweenTo(standCF(tPos, tCenter), twin.inst, wob(tweenSpeed, 0.15))
                        if noclipRestore then pcall(noclipRestore); noclipRestore = nil end

                        local merged = false
                        if not farmOn then
                            -- paused mid-travel
                        elseif res == "arrived" then
                            tryInteract(twin.inst)
                            task.wait(randDelay(mergeWait * 0.7, mergeWait * 1.5))
                            merged = pairGone(src.inst, twin.inst)
                            if not merged then
                                -- press right up against the twin and try once more
                                local tPos2 = sidePos(twin, src.cf.Position, 0.2)
                                if noclipTravel and not noclipRestore then noclipRestore = enterNoclip() end
                                local res2 = tweenTo(standCF(tPos2, tCenter), twin.inst, wob(tweenSpeed * 0.8, 0.15))
                                if noclipRestore then pcall(noclipRestore); noclipRestore = nil end
                                if res2 == "arrived" then
                                    tryInteract(twin.inst)
                                    task.wait(randDelay(mergeWait, mergeWait * 1.6))
                                    merged = pairGone(src.inst, twin.inst)
                                elseif res2 == "gone" then
                                    -- pair got consumed during the closer approach
                                    merged = true
                                end
                            end
                            if merged then
                                merges = merges + 1
                                lastNote = "merged " .. src.inst.Name
                                setPanel("Merge #" .. tostring(merges))
                                pcall(burstAtWindowCenter)
                                task.wait(randDelay(0.25, 0.6))
                            else
                                cooldown(src.inst, 10)
                                cooldown(twin.inst, 10)
                                lastNote = "no merge - pair cooldown 10s"
                                setPanel("No merge (cooldown)")
                            end
                        elseif res == "gone" then
                            -- the twin vanished while we were traveling to it -
                            -- in merge games this is the merge registering on
                            -- approach (the pair got consumed), so count it
                            merges = merges + 1
                            lastNote = "merged " .. src.inst.Name .. " (consumed mid-approach)"
                            setPanel("Merge #" .. tostring(merges))
                            pcall(burstAtWindowCenter)
                            task.wait(randDelay(0.25, 0.6))
                        else
                            cooldown(twin.inst, 6)
                            lastNote = "travel problem (" .. tostring(res) .. ")"
                            setPanel("Travel problem")
                        end

                        if farmOn then
                            task.wait(randDelay(cycleDelay * 0.8, cycleDelay * 1.5))
                        end
                    end
                end
            end
        else
            task.wait(0.3)
        end
    end
end)

print("[RMF] Rocket Merge Auto Farm loaded.")
