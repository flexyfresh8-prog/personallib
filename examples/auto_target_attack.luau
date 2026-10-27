--[[
    Auto Target Attack — powered by personallib (LiquidGlass UI)
    Reviewed & corrected version — changes are marked with [FIX n]

    Fixes vs the original:
      [FIX 1] Heartbeat connection is stored and disconnected on re-execution
              (the old script stacked duplicate attack loops on every re-inject).
      [FIX 2] GUI cleanup searches gethui / CoreGui / PlayerGui recursively
              (a direct-child search of CoreGui misses gethui() holders).
      [FIX 3] Bounded WaitForChild timeouts + clear assert messages instead of
              infinite silent yield or confusing nil errors.
      [FIX 4] Swing remote uses a bounded wait instead of FindFirstChild-at-startup.
      [FIX 5] Correct loadstring URL — the bundle is at build/LiquidGlass.lua;
              there is no init.lua at the repo root (old URL returned 404).
      [FIX 6] Library load is wrapped with pcall + assert for a clear failure.
      [FIX 7] Zero-length direction vector guard (NaN .Unit would corrupt payload).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- [FIX 1] Re-execution safety: kill the previous Heartbeat loop first.
-- Destroying the old ScreenGui does NOT disconnect RunService connections,
-- so re-injecting this script used to stack duplicate attack loops.
local store = (type(getgenv) == "function" and getgenv()) or _G
if store.LG_AutoTargetConn then
    pcall(function()
        store.LG_AutoTargetConn:Disconnect()
    end)
    store.LG_AutoTargetConn = nil
end

-- [FIX 2] Robust GUI cleanup across every possible UI holder.
do
    local holders = {}
    if type(gethui) == "function" then
        pcall(function()
            holders[#holders + 1] = gethui()
        end)
    end
    pcall(function()
        holders[#holders + 1] = game:GetService("CoreGui")
    end)
    pcall(function()
        holders[#holders + 1] = player:FindFirstChildOfClass("PlayerGui")
    end)
    for _, holder in ipairs(holders) do
        local old = holder and holder:FindFirstChild("LiquidGlass_Auto Target Attack", true)
        if old then
            old:Destroy()
        end
    end
end

-- [FIX 3] Bounded waits with clear failure messages.
local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
assert(remotes, "[Auto Target Attack] ReplicatedStorage.Remotes not found")
local attackRemote = remotes:WaitForChild("Attack", 10)
assert(attackRemote, "[Auto Target Attack] Remotes.Attack not found")

-- [FIX 4] Bounded wait instead of FindFirstChild-at-startup.
local swingRemote = remotes:WaitForChild("Swing", 5)

-- [FIX 5][FIX 6] Correct URL + guarded load.
local loadOk, Lib = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/flexyfresh8-prog/personallib/main/build/LiquidGlass.lua"))()
end)
assert(loadOk and Lib and Lib.CreateWindow, "[Auto Target Attack] Failed to load personallib: " .. tostring(Lib))

local Window = Lib:CreateWindow({
    Title = "Auto Target Attack",
    Theme = "Midnight",
})

local Tab = Window:CreateTab({
    Name = "Combat",
})

local isToggled = false
local lastAttack = 0
local attackCount = 0
local cooldown = 0.625

Tab:CreateToggle({
    Name = "Auto Attack",
    Default = false,
    Callback = function(state)
        isToggled = state
    end,
})

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

-- [FIX 6] Store the connection so the next execution can disconnect it (see FIX 1).
store.LG_AutoTargetConn = RunService.Heartbeat:Connect(function()
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

    if not closestTarget then
        return
    end

    local targetRoot = closestTarget:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        return
    end

    local targetPosition = targetRoot.Position / 3

    -- [FIX 7] Zero-length direction would make .Unit return NaN.
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
        crit = true,
        n = attackCount,
    })
end)

print("[Auto Target Attack] Loaded using personallib with cleanup.")
