--@module LiquidGlass/Core/Animator
--[[
        LiquidGlass · Core/Animator
        Centralized animation manager.
        - Tween(): TweenService wrapper with per-instance/property conflict cancellation
        - Spring(): true spring simulation driven by Heartbeat, with retargeting
        - Cancel(): kill every animation on an instance (called by Janitors on destroy)

        Everything respects Config quality settings and ReducedMotion automatically.
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)
local Spring = require(script.Parent.Spring)

local Animator = {}

-- Weak-keyed registries so forgotten instances can still be collected ---------------
local activeTweens = setmetatable({}, { __mode = "k" })
local activeSprings = setmetatable({}, { __mode = "k" })

--====================================================================================
-- TWEENS
--====================================================================================

--[[
        Animator.Tween(instance, props, durationOverride, easingStyle)
        Returns the Tween, or nil when motion is disabled (props applied instantly).
]]
function Animator.Tween(inst, props, durationOverride, easingStyle)
        local duration = Config.T(durationOverride or Config.Animation.Default)

        if duration <= 0 then
                for prop, value in pairs(props) do
                        inst[prop] = value
                end
                return nil
        end

        -- cancel conflicting tweens on the same properties
        local registry = activeTweens[inst]
        if registry then
                for prop in pairs(props) do
                        local old = registry[prop]
                        if old then
                                pcall(function()
                                        old:Cancel()
                                end)
                                registry[prop] = nil
                        end
                end
        end

        local info = TweenInfo.new(
                duration,
                easingStyle or Config.Animation.Easing,
                Enum.EasingDirection.Out
        )
        local tween = TweenService:Create(inst, info, props)

        if not registry then
                registry = {}
                activeTweens[inst] = registry
        end
        for prop in pairs(props) do
                registry[prop] = tween
        end

        tween.Completed:Connect(function()
                local reg = activeTweens[inst]
                if reg then
                        for prop, t in pairs(reg) do
                                if t == tween then
                                        reg[prop] = nil
                                end
                        end
                end
        end)

        tween:Play()
        return tween
end

--====================================================================================
-- SPRINGS
--====================================================================================

local function getSpringRegistry(inst)
        local reg = activeSprings[inst]
        if not reg then
                reg = {}
                activeSprings[inst] = reg
        end
        return reg
end

--[[
        Animator.Spring(instance, property, target [, springConfig])
        Springs a numeric property. Calling again while running retargets the
        existing spring instead of stacking simulations.
]]
function Animator.Spring(inst, property, target, config)
        if not Config.MotionEnabled() then
                inst[property] = target
                return nil
        end

        local registry = getSpringRegistry(inst)
        local entry = registry[property]

        if entry then
                entry.spring.Target = target
                return entry.spring
        end

        local spring = Spring.new(inst[property], config or Config.Spring.Default)
        local conn
        conn = RunService.Heartbeat:Connect(function(dt)
                local settled = spring:Step(dt)
                inst[property] = spring.Value
                if settled then
                        conn:Disconnect()
                        local reg = activeSprings[inst]
                        if reg and reg[property] == entry then
                                reg[property] = nil
                        end
                end
        end)

        entry = { spring = spring, conn = conn }
        registry[property] = entry
        return spring
end

--[[
        Animator.SpringPositionY(instance, xScale, xOffset, targetY [, config])
        Springs the vertical pixel offset of a UDim2 Position (sidebar indicator).
]]
function Animator.SpringPositionY(inst, xScale, xOffset, targetY, config)
        if not Config.MotionEnabled() then
                inst.Position = UDim2.new(xScale, xOffset, 0, targetY)
                return nil
        end

        local registry = getSpringRegistry(inst)
        local entry = registry.__posY

        if entry then
                entry.spring.Target = targetY
                entry.xScale = xScale
                entry.xOffset = xOffset
                return entry.spring
        end

        local spring = Spring.new(inst.Position.Y.Offset, config or Config.Spring.Soft)
        entry = { spring = spring, xScale = xScale, xOffset = xOffset }
        registry.__posY = entry

        local conn
        conn = RunService.Heartbeat:Connect(function(dt)
                local settled = spring:Step(dt)
                inst.Position = UDim2.new(entry.xScale, entry.xOffset, 0, spring.Value)
                if settled then
                        conn:Disconnect()
                        local reg = activeSprings[inst]
                        if reg and reg.__posY == entry then
                                reg.__posY = nil
                        end
                end
        end)
        entry.conn = conn
        return spring
end

--====================================================================================
-- LOOPS / CANCELLATION
--====================================================================================

--[[
        Animator.Loop(fn [, janitor]) — run fn(dt) every frame until it returns false.
        Register into a Janitor for automatic cleanup.
]]
function Animator.Loop(fn, janitor)
        local conn
        conn = RunService.Heartbeat:Connect(function(dt)
                if fn(dt) == false then
                        conn:Disconnect()
                end
        end)
        if janitor then
                janitor:Add(conn)
        end
        return conn
end

-- Kill every tween and spring attached to an instance --------------------------------
function Animator.Cancel(inst)
        local springs = activeSprings[inst]
        if springs then
                for _, entry in pairs(springs) do
                        pcall(function()
                                entry.conn:Disconnect()
                        end)
                end
                activeSprings[inst] = nil
        end
        local tweens = activeTweens[inst]
        if tweens then
                for _, tween in pairs(tweens) do
                        pcall(function()
                                tween:Cancel()
                        end)
                end
                activeTweens[inst] = nil
        end
end

return Animator
