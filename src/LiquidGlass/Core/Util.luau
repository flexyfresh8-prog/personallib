--@module LiquidGlass/Core/Util
--[[
        LiquidGlass · Core/Util
        Shared primitives: instance factory, glass helpers, Signal, Janitor,
        math/format helpers, safe gui parenting, environment probes.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Util = {}

--====================================================================================
-- INSTANCE FACTORY
--====================================================================================

function Util.New(class, props, children)
        local inst = Instance.new(class)
        if props then
                for prop, value in pairs(props) do
                        if prop ~= "Parent" then
                                inst[prop] = value
                        end
                end
        end
        if children then
                for _, child in ipairs(children) do
                        child.Parent = inst
                end
        end
        if props and props.Parent then
                inst.Parent = props.Parent
        end
        return inst
end

function Util.Corner(parent, radius)
        return Util.New("UICorner", {
                CornerRadius = UDim.new(0, radius),
                Parent = parent,
        })
end

function Util.Stroke(parent, color, transparency, thickness)
        return Util.New("UIStroke", {
                Color = color,
                Transparency = transparency == nil and 0.4 or transparency,
                Thickness = thickness or 1,
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                Parent = parent,
        })
end

function Util.Padding(parent, top, right, bottom, left)
        return Util.New("UIPadding", {
                PaddingTop = UDim.new(0, top or 0),
                PaddingRight = UDim.new(0, right or 0),
                PaddingBottom = UDim.new(0, bottom or 0),
                PaddingLeft = UDim.new(0, left or 0),
                Parent = parent,
        })
end

function Util.List(parent, gap)
        return Util.New("UIListLayout", {
                Padding = UDim.new(0, gap or 8),
                SortOrder = Enum.SortOrder.LayoutOrder,
                Parent = parent,
        })
end

-- Vertical glass shading gradient (multiplies the background color) -----------------
function Util.VerticalGradient(parent, top, bottom)
        return Util.New("UIGradient", {
                Rotation = 90,
                Color = ColorSequence.new(top, bottom),
                Parent = parent,
        })
end

-- Rebuild an existing gradient's colors (used by live theme switching) ---------------
function Util.VerticalGradientRebuild(grad, top, bottom)
        grad.Color = ColorSequence.new(top, bottom)
end

-- Horizontal alpha gradient (used for light sweeps / fades) -------------------------
function Util.AlphaGradient(parent, color, fromT, toT, rotation)
        return Util.New("UIGradient", {
                Rotation = rotation or 0,
                Color = ColorSequence.new(color, color),
                Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, fromT),
                        NumberSequenceKeypoint.new(1, toT),
                }),
                Parent = parent,
        })
end

--====================================================================================
-- SIGNAL (lightweight BindableEvent replacement)
--====================================================================================

function Util.Signal()
        local handlers = {}
        local sig = {}

        function sig:Connect(fn)
                local conn = { Connected = true, _fn = fn }
                function conn:Disconnect()
                        self.Connected = false
                        for i, h in ipairs(handlers) do
                                if h == conn then
                                        table.remove(handlers, i)
                                        break
                                end
                        end
                end
                table.insert(handlers, conn)
                return conn
        end

        function sig:Fire(...)
                for _, conn in ipairs(handlers) do
                        if conn.Connected then
                                task.spawn(conn._fn, ...)
                        end
                end
        end

        function sig:DisconnectAll()
                for _, conn in ipairs(handlers) do
                        conn.Connected = false
                end
                handlers = {}
        end

        return sig
end

--====================================================================================
-- JANITOR (connection/instance cleanup)
--====================================================================================

function Util.NewJanitor()
        local tasks = {}
        local janitor = {}

        function janitor:Add(item)
                table.insert(tasks, item)
                return item
        end

        function janitor:Clean()
                for i = #tasks, 1, -1 do
                        local item = tasks[i]
                        local kind = typeof(item)
                        if kind == "RBXScriptConnection" then
                                pcall(function()
                                        item:Disconnect()
                                end)
                        elseif kind == "Instance" then
                                pcall(function()
                                        item:Destroy()
                                end)
                        elseif type(item) == "function" then
                                pcall(item)
                        elseif type(item) == "table" and type(item.Destroy) == "function" then
                                pcall(function()
                                        item:Destroy()
                                end)
                        end
                        tasks[i] = nil
                end
        end

        janitor.Destroy = janitor.Clean
        return janitor
end

--====================================================================================
-- MATH / FORMAT
--====================================================================================

function Util.Round(value, increment)
        increment = increment or 1
        return math.floor(value / increment + 0.5) * increment
end

function Util.Clamp(value, lo, hi)
        return math.min(hi, math.max(lo, value))
end

-- Trim floating point noise: 16.0000 -> "16", 16.500 -> "16.5" ----------------------
function Util.FormatNumber(value)
        local s = string.format("%.3f", value)
        if string.find(s, "%.") then
                s = string.gsub(string.gsub(s, "0+$", ""), "%.$", "")
        end
        return s
end

function Util.ShallowCopy(t)
        local out = {}
        for k, v in pairs(t) do
                out[k] = v
        end
        return out
end

function Util.Lerp(a, b, alpha)
        return a + (b - a) * alpha
end

--====================================================================================
-- ENVIRONMENT
--====================================================================================

function Util.GetGuiParent()
        -- NOTE: an earlier build called the non-existent method "IsRobloxStudio"
        -- here, which crashes real clients. The real API is RunService:IsStudio.
        -- pcall-wrap so even exotic environments can never crash window creation.
        local okStudio, isStudio = pcall(function()
                return RunService:IsStudio()
        end)
        if okStudio and isStudio then
                local player = Players.LocalPlayer
                if player then
                        return player:WaitForChild("PlayerGui")
                end
                return game:GetService("CoreGui")
        end
        local ok, custom = pcall(function()
                if typeof(gethui) == "function" then
                        return gethui()
                end
                return nil
        end)
        if ok and custom ~= nil then
                return custom
        end
        local okCore, coreGui = pcall(function()
                return game:GetService("CoreGui")
        end)
        if okCore and coreGui ~= nil then
                return coreGui
        end
        local player = Players.LocalPlayer
        if player then
                return player:WaitForChild("PlayerGui")
        end
        return game:GetService("CoreGui")
end

function Util.IsTouch()
        return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

function Util.IsSmallViewport()
        local camera = game:GetService("Workspace").CurrentCamera
        if not camera then
                return false
        end
        return camera.ViewportSize.X < 720
end

function Util.MouseLocation()
        return UserInputService:GetMouseLocation()
end

return Util
