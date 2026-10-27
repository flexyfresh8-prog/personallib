--@module LiquidGlass/Effects/Shine
--[[
        LiquidGlass · Effects/Shine
        Traveling specular highlight — the "light bending through glass" illusion.
        A diagonal luminous band sweeps across a clipped surface once when invoked.
        The band instance is created lazily and reused (pooled per host).
        Disabled automatically on Low quality / ReducedMotion.
]]

local Config = require(script.Parent.Parent.Core.Config)
local Util = require(script.Parent.Parent.Core.Util)
local Animator = require(script.Parent.Parent.Core.Animator)

local Shine = {}

local function ensureBand(host)
        local band = host:FindFirstChild("__LGShine")
        if band then
                return band
        end
        local bar = Util.New("Frame", {
                Name = "__LGShine",
                BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0, -90, 0.5, 0),
                Size = UDim2.new(0, 46, 2, 0),
                Rotation = 18,
                BorderSizePixel = 0,
                ZIndex = 9,
                Parent = host,
        })
        Util.AlphaGradient(bar, Color3.fromRGB(255, 255, 255), 1, 1)
        return bar
end

--[[
        Shine.Bind(host, janitor) — prepare a host (must have ClipsDescendants = true).
        Returns a Sweep function bound to the host.
]]
function Shine.Bind(host, janitor)
        local band = nil
        local sweeping = false

        local function sweep()
                if not Config.EffectsEnabled() then
                        return
                end
                band = band or ensureBand(host)
                if sweeping then
                        return
                end
                sweeping = true
                band.Position = UDim2.new(0, -90, 0.5, 0)
                band.BackgroundTransparency = 0.35
                local width = host.AbsoluteSize.X + 180
                local tween = Animator.Tween(band, {
                        Position = UDim2.new(0, width, 0.5, 0),
                }, 0.6, Enum.EasingStyle.Linear)
                local finish
                finish = function()
                        sweeping = false
                        if band then
                                band.BackgroundTransparency = 1
                        end
                end
                if tween then
                        tween.Completed:Connect(finish)
                else
                        finish()
                end
        end

        if janitor then
                janitor:Add(function()
                        sweeping = true -- block future sweeps
                end)
        end
        return sweep
end

-- One-shot convenience: prepare (cached) and sweep immediately ------------------------
function Shine.Sweep(host)
        if not Config.EffectsEnabled() then
                return
        end
        local band = ensureBand(host)
        if band:GetAttribute("Sweeping") then
                return
        end
        band:SetAttribute("Sweeping", true)
        band.Position = UDim2.new(0, -90, 0.5, 0)
        band.BackgroundTransparency = 0.35
        local width = host.AbsoluteSize.X + 180
        local tween = Animator.Tween(band, {
                Position = UDim2.new(0, width, 0.5, 0),
        }, 0.6, Enum.EasingStyle.Linear)
        local function finish()
                band.BackgroundTransparency = 1
                band:SetAttribute("Sweeping", false)
        end
        if tween then
                tween.Completed:Connect(finish)
        else
                finish()
        end
end

return Shine
