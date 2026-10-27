--[[
    Auto Target Attack — SAFE LOADER with on-screen diagnostics
    Run THIS if the normal script "doesn't load". It:
      1. Shows a status box on screen (works even if the UI library is broken)
      2. Tries TWO mirrors (raw.githubusercontent + jsDelivr CDN) in case
         raw.githubusercontent.com is blocked on your network
      3. Reports the exact error + line if the library fails to compile or run
      4. Auto-builds the Auto Target Attack UI on success
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- ---------------------------------------------------------------- cleanup ---
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

-- --------------------------------------------------------- status console ---
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
title.Text = "LiquidGlass Loader"
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
    warn("[LG Loader] " .. msg)
end

local function closeStatus(delay)
    task.delay(delay or 1.2, function()
        pcall(function() statusGui:Destroy() end)
    end)
end

-- ------------------------------------------------------------------ fetch ---
log("[1/4] Fetching library...")

local SOURCES = {
    "https://raw.githubusercontent.com/flexyfresh8-prog/personallib/main/build/LiquidGlass.lua",
    "https://cdn.jsdelivr.net/gh/flexyfresh8-prog/personallib@main/build/LiquidGlass.lua",
}

local src, fetchReport = nil, {}
for i, url in ipairs(SOURCES) do
    local ok, res = pcall(function()
        return game:HttpGet(url)
    end)
    if ok and type(res) == "string" and #res > 10000 then
        src = res
        log("[OK] Source " .. i .. " fetched (" .. tostring(#res) .. " bytes)")
        break
    else
        fetchReport[#fetchReport + 1] = "src" .. i .. ": " .. tostring(res)
        log("[FAIL] Source " .. i .. " -> " .. tostring(res))
    end
end

if not src then
    log("")
    log("ALL SOURCES FAILED. Your network is most likely")
    log("blocking GitHub (common on school wifi).")
    log("Try mobile data / different wifi, then re-run.")
    return
end

-- --------------------------------------------------------------- compile ----
log("[2/4] Compiling...")
local fn, compileErr = loadstring(src)
if not fn then
    log("[FAIL] Compile error:")
    log(tostring(compileErr))
    return
end
log("[OK] Compiled")

-- ------------------------------------------------------------------ run -----
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

-- ---------------------------------------------------------------- combat ----
log("[4/4] Building UI...")

local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
assert(remotes, "[Auto Target Attack] ReplicatedStorage.Remotes not found")
local attackRemote = remotes:WaitForChild("Attack", 10)
assert(attackRemote, "[Auto Target Attack] Remotes.Attack not found")
local swingRemote = remotes:WaitForChild("Swing", 5)

local isToggled = false
local lastAttack = 0
local attackCount = 0
local cooldown = 0.625

local okWin, winErr = xpcall(function()
    local Window = Lib:CreateWindow({
        Title = "Auto Target Attack",
        Theme = "Midnight",
    })

    local Tab = Window:CreateTab({
        Name = "Combat",
    })

    Tab:CreateToggle({
        Name = "Auto Attack",
        Default = false,
        Callback = function(state)
            isToggled = state
        end,
    })

    return Window
end, trace)

if not okWin then
    log("[FAIL] Window error:")
    log(tostring(winErr))
    return
end

log("[OK] Loaded! Closing this box...")

local function getEyePosition(character)
    if not character then return nil end
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    return root.Position / 3 + Vector3.new(0, 0.72, 0)
end

store.LG_AutoTargetConn = RunService.Heartbeat:Connect(function()
    if not isToggled then return end
    if tick() - lastAttack < cooldown then return end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end

    local eyePosition = getEyePosition(character)
    if not eyePosition then return end

    local closestTarget = nil
    local closestDistance = 4

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

    if not closestTarget then return end

    local targetRoot = closestTarget:FindFirstChild("HumanoidRootPart")
    if not targetRoot then return end

    local targetPosition = targetRoot.Position / 3

    local dir = targetPosition - eyePosition
    if dir.Magnitude < 1e-4 then return end

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
        crit = true,
        n = attackCount,
    })
end)

closeStatus(1.2)
print("[Auto Target Attack] Loaded via safe loader.")
