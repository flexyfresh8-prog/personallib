--@module LiquidGlass/Components/Controls
--[[
        LiquidGlass · Components/Controls
        CreateButton · CreateToggle · CreateSlider · CreateKeybind
        Every factory: (tab, cfg) -> control object { Frame, Get/Set, Changed, Destroy }
]]

local Config = require(script.Parent.Parent.Core.Config)
local Util = require(script.Parent.Parent.Core.Util)
local Animator = require(script.Parent.Parent.Core.Animator)
local Elements = require(script.Parent.Parent.Core.Elements)
local Icons = require(script.Parent.Parent.Core.Icons)

local UserInputService = game:GetService("UserInputService")

local Controls = {}

--====================================================================================
-- BUTTON
--====================================================================================

function Controls.CreateButton(tab, cfg)
        cfg = cfg or {}
        local ctx = tab._Ctx
        local card = tab:_AddCard({
                Name = cfg.Name,
                Description = cfg.Description,
                Tooltip = cfg.Tooltip,
                Height = cfg.Description and 52 or 42,
                Clickable = true,
        })

        local chevron = Elements.VectorIcon(ctx, "chevron", card.Frame, 12, "TextMuted", 2)
        chevron.AnchorPoint = Vector2.new(1, 0.5)
        chevron.Position = UDim2.new(1, -14, 0.5, 0)
        chevron.Rotation = -90

        card.Janitor:Add(card.Frame.MouseEnter:Connect(function()
                Animator.Tween(chevron, { Position = UDim2.new(1, -10, 0.5, 0) }, 0.2, Enum.EasingStyle.Back)
        end))
        card.Janitor:Add(card.Frame.MouseLeave:Connect(function()
                Animator.Tween(chevron, { Position = UDim2.new(1, -14, 0.5, 0) }, 0.2)
        end))

        local clicked = Util.Signal()
        card.Janitor:Add(card.Frame.Activated:Connect(function(input)
                Elements.Ripple(ctx, card.Frame)
                card.Sweep()
                clicked:Fire()
                if cfg.Callback then
                        task.spawn(cfg.Callback)
                end
        end))

        local control = {
                Kind = "Button",
                Frame = card.Frame,
                Clicked = clicked,
                SetName = function(_, text)
                        card:SetTitle(text)
                end,
                Destroy = function()
                        card:Destroy()
                end,
        }
        tab._Controls[cfg.Name or "Button"] = control
        return control
end

--====================================================================================
-- TOGGLE
--====================================================================================

function Controls.CreateToggle(tab, cfg)
        cfg = cfg or {}
        local ctx = tab._Ctx
        local state = cfg.Default == true
        local card = tab:_AddCard({
                Name = cfg.Name,
                Description = cfg.Description,
                Tooltip = cfg.Tooltip,
                Height = cfg.Description and 52 or 42,
                Clickable = true,
        })

        -- track (glass inset) + illuminated fill
        local track = Util.New("Frame", {
                Name = "Track",
                BackgroundColor3 = ctx.Color("Track"),
                Size = UDim2.fromOffset(40, 22),
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -12, 0.5, -11),
                BorderSizePixel = 0,
                ZIndex = 2,
                Parent = card.Frame,
        })
        Util.Corner(track, 11)
        Util.Stroke(track, ctx.Color("InnerStroke"), 0.45, 1)
        ctx.Tint(track, "BackgroundColor3", "Track")

        local fill = Util.New("Frame", {
                Name = "Fill",
                BackgroundColor3 = ctx.Color("Accent"),
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ZIndex = 2,
                Parent = track,
        })
        Util.Corner(fill, 11)
        local fillGrad = Util.VerticalGradient(fill, ctx.Color("Accent"), ctx.Color("Accent2"))
        ctx.TintGradient(fillGrad, "Accent", "Accent2")

        local glow = Util.Stroke(fill, ctx.Color("Accent"), 1, 1.6)
        ctx.Tint(glow, "Color", "Accent")

        -- thumb
        local thumb = Util.New("Frame", {
                Name = "Thumb",
                BackgroundColor3 = ctx.Color("Knob"),
                Size = UDim2.fromOffset(18, 18),
                Position = UDim2.new(0, 2, 0.5, -9),
                BorderSizePixel = 0,
                ZIndex = 3,
                Parent = track,
        })
        Util.Corner(thumb, 9)
        Util.Stroke(thumb, ctx.Color("InnerStroke"), 0.5, 1)
        ctx.Tint(thumb, "BackgroundColor3", "Knob")
        Util.New("Frame", { -- thumb top highlight
                BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                BackgroundTransparency = 0.6,
                Size = UDim2.new(1, -6, 0, 1),
                Position = UDim2.new(0, 3, 0, 2),
                BorderSizePixel = 0,
                ZIndex = 4,
                Parent = thumb,
        })

        local changed = Util.Signal()
        local applying = false

        local function apply(value, animate)
                state = value
                applying = animate ~= false
                local thumbTarget = UDim2.new(0, value and 20 or 2, 0.5, -9)
                if applying and Config.MotionEnabled() then
                        Animator.Tween(thumb, { Position = thumbTarget }, 0.28, Enum.EasingStyle.Back)
                        Animator.Tween(fill, { BackgroundTransparency = value and 0 or 0.92 }, 0.2)
                        Animator.Tween(glow, { Transparency = value and 0.45 or 1 }, 0.25)
                else
                        thumb.Position = thumbTarget
                        fill.BackgroundTransparency = value and 0 or 0.92
                        glow.Transparency = value and 0.45 or 1
                end
                applying = false
        end

        apply(state, false)

        card.Janitor:Add(card.Frame.Activated:Connect(function()
                apply(not state, true)
                changed:Fire(state)
                if cfg.Callback then
                        task.spawn(cfg.Callback, state)
                end
        end))

        local control = {
                Kind = "Toggle",
                Frame = card.Frame,
                Changed = changed,
                Get = function()
                        return state
                end,
                Set = function(_, value, silent)
                        apply(value == true, true)
                        if not silent then
                                changed:Fire(state)
                        end
                end,
                Destroy = function()
                        card:Destroy()
                end,
        }

        -- command palette registration
        table.insert(tab._Commands, {
                Name = "Toggle: " .. (cfg.Name or "?"),
                Callback = function()
                        control:Set(not state)
                end,
        })

        tab._Controls[cfg.Name or "Toggle"] = control
        return control
end

--====================================================================================
-- SLIDER
--====================================================================================

function Controls.CreateSlider(tab, cfg)
        cfg = cfg or {}
        local ctx = tab._Ctx
        local min = cfg.Min or 0
        local max = cfg.Max or 100
        local increment = cfg.Increment or 1
        local suffix = cfg.Suffix and (" " .. cfg.Suffix) or ""
        local value = Util.Clamp(cfg.Default or min, min, max)

        local card = tab:_AddCard({
                Name = cfg.Name,
                Tooltip = cfg.Tooltip,
                Height = 58,
        })

        local valueLabel = Util.New("TextLabel", {
                Name = "Value",
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -12, 0, 7),
                Size = UDim2.new(0, 120, 0, 16),
                Font = Enum.Font.GothamBold,
                Text = "",
                TextColor3 = ctx.Color("Accent"),
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent = card.Frame,
        })
        ctx.Tint(valueLabel, "TextColor3", "Accent")

        local track = Util.New("TextButton", {
                Name = "Track",
                Text = "",
                AutoButtonColor = false,
                BackgroundColor3 = ctx.Color("Track"),
                Position = UDim2.new(0, 12, 1, -18),
                Size = UDim2.new(1, -24, 0, 6),
                BorderSizePixel = 0,
                Parent = card.Frame,
        })
        Util.Corner(track, 3)
        Util.Stroke(track, ctx.Color("InnerStroke"), 0.6, 1)
        ctx.Tint(track, "BackgroundColor3", "Track")

        local fill = Util.New("Frame", {
                Name = "Fill",
                BackgroundColor3 = ctx.Color("Accent"),
                Size = UDim2.new(0, 0, 1, 0),
                BorderSizePixel = 0,
                Parent = track,
        })
        Util.Corner(fill, 3)
        local fillGrad = Util.VerticalGradient(fill, ctx.Color("Accent"), ctx.Color("Accent2"))
        ctx.TintGradient(fillGrad, "Accent", "Accent2")
        local fillGlow = Util.Stroke(fill, ctx.Color("Accent"), 0.55, 1.4)
        ctx.Tint(fillGlow, "Color", "Accent")

        local thumb = Util.New("Frame", {
                Name = "Thumb",
                BackgroundColor3 = ctx.Color("Knob"),
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0, 0, 0.5, 0),
                Size = UDim2.fromOffset(16, 16),
                BorderSizePixel = 0,
                ZIndex = 3,
                Parent = track,
        })
        Util.Corner(thumb, 8)
        Util.Stroke(thumb, ctx.Color("InnerStroke"), 0.4, 1)
        ctx.Tint(thumb, "BackgroundColor3", "Knob")

        local thumbScale = Util.New("UIScale", { Scale = 1, Parent = thumb })

        local changed = Util.Signal()

        local function displayText()
                return Util.FormatNumber(value) .. suffix
        end

        local function apply(newValue, fire)
                value = Util.Clamp(Util.Round(newValue, increment), min, max)
                local alpha = (max - min) ~= 0 and (value - min) / (max - min) or 0
                fill.Size = UDim2.new(alpha, 0, 1, 0)
                thumb.Position = UDim2.new(alpha, 0, 0.5, 0)
                valueLabel.Text = displayText()
                if fire then
                        changed:Fire(value)
                        if cfg.Callback then
                                task.spawn(cfg.Callback, value)
                        end
                end
        end

        local dragging = false
        local function updateFromX(x, fire)
                local alpha = Util.Clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
                apply(min + alpha * (max - min), fire)
        end

        card.Janitor:Add(track.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                        or input.UserInputType == Enum.UserInputType.Touch then
                        dragging = true
                        Animator.Spring(thumbScale, "Scale", 1.25, Config.Spring.Snappy)
                        updateFromX(input.Position.X, true)
                end
        end))
        card.Janitor:Add(UserInputService.InputChanged:Connect(function(input)
                if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                        or input.UserInputType == Enum.UserInputType.Touch) then
                        updateFromX(input.Position.X, true)
                end
        end))
        card.Janitor:Add(UserInputService.InputEnded:Connect(function(input)
                if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
                        or input.UserInputType == Enum.UserInputType.Touch) then
                        dragging = false
                        Animator.Spring(thumbScale, "Scale", 1, Config.Spring.Snappy)
                end
        end))

        local thumbScale = Util.New("UIScale", { Scale = 1, Parent = thumb })
        apply(value, false)

        local control = {
                Kind = "Slider",
                Frame = card.Frame,
                Changed = changed,
                Get = function()
                        return value
                end,
                Set = function(_, newValue, silent)
                        apply(newValue or min, false)
                        if not silent then
                                changed:Fire(value)
                        end
                end,
                SetRange = function(_, newMin, newMax)
                        min = newMin
                        max = newMax
                        apply(value, false)
                end,
                Destroy = function()
                        card:Destroy()
                end,
        }
        tab._Controls[cfg.Name or "Slider"] = control
        return control
end

--====================================================================================
-- KEYBIND
--====================================================================================

function Controls.CreateKeybind(tab, cfg)
        cfg = cfg or {}
        local ctx = tab._Ctx
        local bind = cfg.Default or nil
        local listening = false
        local pulseConn = nil

        local card = tab:_AddCard({
                Name = cfg.Name,
                Description = cfg.Description,
                Tooltip = cfg.Tooltip,
                Height = cfg.Description and 52 or 42,
                Clickable = true,
        })

        local chip = Util.New("TextLabel", {
                Name = "BindChip",
                BackgroundColor3 = ctx.Color("Track"),
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -12, 0.5, 0),
                Size = UDim2.fromOffset(84, 24),
                Font = Enum.Font.GothamMedium,
                Text = bind and bind.Name or "None",
                TextColor3 = ctx.Color("TextSecondary"),
                TextSize = 11,
                BorderSizePixel = 0,
                Parent = card.Frame,
        })
        Util.Corner(chip, 7)
        Util.Stroke(chip, ctx.Color("InnerStroke"), 0.4, 1)
        ctx.Tint(chip, "BackgroundColor3", "Track")

        local chipStroke = chip:FindFirstChildOfClass("UIStroke")
        local changed = Util.Signal()
        local pressed = Util.Signal()

        local function setBind(key)
                bind = key
                chip.Text = key and key.Name or "None"
                changed:Fire(key)
        end

        local function stopListening()
                listening = false
                chip.Text = bind and bind.Name or "None"
                chip.TextColor3 = ctx.Color("TextSecondary")
                if pulseConn then
                        pulseConn:Disconnect()
                        pulseConn = nil
                end
        end

        card.Janitor:Add(card.Frame.Activated:Connect(function()
                listening = true
                chip.Text = "Press a key"
                chip.TextColor3 = ctx.Color("Accent")
                if Config.EffectsEnabled() and not pulseConn then
                        local t = 0
                        pulseConn = Animator.Loop(function(dt)
                                t = t + dt
                                chipStroke.Transparency = 0.2 + math.abs(math.sin(t * 4)) * 0.5
                        end)
                end
        end))

        card.Janitor:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
                if UserInputService:GetFocusedTextBox() then
                        return
                end
                if listening then
                        if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then
                                setBind(nil)
                        elseif input.KeyCode ~= Enum.KeyCode.Unknown then
                                setBind(input.KeyCode)
                        end
                        stopListening()
                elseif bind and input.KeyCode == bind and not gameProcessed then
                        pressed:Fire()
                        if cfg.Callback then
                                task.spawn(cfg.Callback)
                        end
                end
        end))

        local control = {
                Kind = "Keybind",
                Frame = card.Frame,
                Changed = changed,
                Pressed = pressed,
                GetBind = function()
                        return bind
                end,
                SetBind = function(_, key)
                        setBind(key)
                end,
                Destroy = function()
                        stopListening()
                        card:Destroy()
                end,
        }
        tab._Controls[cfg.Name or "Keybind"] = control
        return control
end

return Controls
