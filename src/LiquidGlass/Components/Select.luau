--@module LiquidGlass/Components/Select
--[[
        LiquidGlass · Components/Select
        CreateDropdown (single + multi select) · CreateColorPicker
        Dropdowns unfold inline with staggered item entrances.
]]

local Config = require(script.Parent.Parent.Core.Config)
local Util = require(script.Parent.Parent.Core.Util)
local Animator = require(script.Parent.Parent.Core.Animator)
local Elements = require(script.Parent.Parent.Core.Elements)

local UserInputService = game:GetService("UserInputService")

local Select = {}

local OPTION_HEIGHT = 30
local MAX_LIST_HEIGHT = 150

--====================================================================================
-- DROPDOWN
--====================================================================================

function Select.CreateDropdown(tab, cfg)
        cfg = cfg or {}
        local ctx = tab._Ctx
        local multi = cfg.Multi == true
        local options = {}
        for _, opt in ipairs(cfg.Options or {}) do
                table.insert(options, tostring(opt))
        end

        -- selection state -----------------------------------------------------------------
        local selectedSingle = nil
        local selectedMulti = {}
        if multi then
                if type(cfg.Default) == "table" then
                        for _, v in ipairs(cfg.Default) do
                                selectedMulti[tostring(v)] = true
                        end
                elseif cfg.Default ~= nil then
                        selectedMulti[tostring(cfg.Default)] = true
                end
        else
                selectedSingle = cfg.Default ~= nil and tostring(cfg.Default) or nil
        end

        -- wrapper hosts card + unfolding options panel --------------------------------------
        local wrapper = Util.New("Frame", {
                Name = "Dropdown_" .. (cfg.Name or "?"),
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                LayoutOrder = tab:NextOrder(),
                Parent = tab._Page,
        })
        Util.List(wrapper, 8)

        local card = Elements.GlassCard(ctx, wrapper, {
                Name = cfg.Name,
                Tooltip = cfg.Tooltip,
                Height = 42,
                Clickable = true,
                Order = 0,
        })

        local valueLabel = Util.New("TextLabel", {
                Name = "Value",
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -34, 0.5, 0),
                Size = UDim2.new(0.5, -50, 1, 0),
                Font = Enum.Font.Gotham,
                Text = "",
                TextColor3 = ctx.Color("TextSecondary"),
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Right,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = card.Frame,
        })
        ctx.Tint(valueLabel, "TextColor3", "TextSecondary")

        local chevron = Elements.VectorIcon(ctx, "chevron", card.Frame, 12, "TextMuted", 2)
        chevron.AnchorPoint = Vector2.new(1, 0.5)
        chevron.Position = UDim2.new(1, -14, 0.5, 0)

        -- unfolding options panel -------------------------------------------------------------
        local listHeight = math.min(#options * OPTION_HEIGHT + 8, MAX_LIST_HEIGHT)
        local holder = Util.New("ScrollingFrame", {
                Name = "Options",
                BackgroundColor3 = ctx.Color("Surface"),
                BackgroundTransparency = 0.06,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.None,
                CanvasSize = UDim2.new(0, 0, 0, 0),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollingDirection = Enum.ScrollingDirection.Y,
                ScrollBarThickness = 2,
                ScrollBarImageColor3 = ctx.Color("Scroller"),
                ScrollBarImageTransparency = 0.4,
                ClipsDescendants = true,
                LayoutOrder = 1,
                Visible = false,
                Parent = wrapper,
        })
        Util.Corner(holder, 10)
        Util.Stroke(holder, ctx.Color("InnerStroke"), 0.35, 1)
        ctx.Tint(holder, "BackgroundColor3", "Surface")
        Util.Padding(holder, 4, 4, 4, 4)
        Util.List(holder, 2)

        local expanded = false
        local changed = Util.Signal()
        local optionButtons = {} -- name -> button
        local setExpanded -- forward declaration (options close themselves on pick)

        local function valueText()
                if multi then
                        local count = 0
                        local names = {}
                        for name in pairs(selectedMulti) do
                                count = count + 1
                                table.insert(names, name)
                        end
                        if count == 0 then
                                return "None"
                        end
                        table.sort(names)
                        if count <= 3 then
                                return table.concat(names, ", ")
                        end
                        return count .. " selected"
                end
                return selectedSingle or "None"
        end

        local function refreshDots()
                for name, btn in pairs(optionButtons) do
                        local isSelected = multi and selectedMulti[name] or (name == selectedSingle)
                        btn.dot.Visible = isSelected
                        Animator.Tween(btn.label, {
                                TextColor3 = isSelected and ctx.Color("Accent") or ctx.Color("TextSecondary"),
                        }, 0.15)
                end
                valueLabel.Text = valueText()
        end

        local function buildOptions()
                for _, child in ipairs(holder:GetChildren()) do
                        if child:IsA("TextButton") then
                                child:Destroy()
                        end
                end
                optionButtons = {}
                for i, name in ipairs(options) do
                        local opt = Util.New("TextButton", {
                                Name = "Opt_" .. name,
                                BackgroundColor3 = ctx.Color("SurfaceHigh"),
                                BackgroundTransparency = 1,
                                Size = UDim2.new(1, 0, 0, OPTION_HEIGHT),
                                Text = "",
                                AutoButtonColor = false,
                                BorderSizePixel = 0,
                                LayoutOrder = i,
                                Parent = holder,
                        })
                        Util.Corner(opt, 7)
                        local label = Util.New("TextLabel", {
                                BackgroundTransparency = 1,
                                Position = UDim2.new(0, 10, 0, 0),
                                Size = UDim2.new(1, -34, 1, 0),
                                Font = Enum.Font.Gotham,
                                Text = name,
                                TextColor3 = ctx.Color("TextSecondary"),
                                TextSize = 12,
                                TextXAlignment = Enum.TextXAlignment.Left,
                                TextTruncate = Enum.TextTruncate.AtEnd,
                                Parent = opt,
                        })
                        ctx.Tint(label, "TextColor3", "TextSecondary")
                        local dot = Elements.VectorIcon(ctx, "dot", opt, 8, "Accent", 2)
                        dot.AnchorPoint = Vector2.new(1, 0.5)
                        dot.Position = UDim2.new(1, -10, 0.5, 0)
                        dot.Visible = false
                        optionButtons[name] = { button = opt, label = label, dot = dot }

                        opt.MouseEnter:Connect(function()
                                Animator.Tween(opt, { BackgroundTransparency = 0.5 })
                        end)
                        opt.MouseLeave:Connect(function()
                                Animator.Tween(opt, { BackgroundTransparency = 1 })
                        end)
                        opt.Activated:Connect(function()
                                if multi then
                                        selectedMulti[name] = not selectedMulti[name] or nil
                                        refreshDots()
                                        changed:Fire(Util.ShallowCopy(selectedMulti))
                                        if cfg.Callback then
                                                task.spawn(cfg.Callback, Util.ShallowCopy(selectedMulti))
                                        end
                                else
                                        selectedSingle = name
                                        refreshDots()
                                        setExpanded(false)
                                        changed:Fire(name)
                                        if cfg.Callback then
                                                task.spawn(cfg.Callback, name)
                                        end
                                end
                        end)
                end
                refreshDots()
        end

        function setExpanded(state)
                if expanded == state then
                        return
                end
                expanded = state
                holder.Visible = true
                Animator.Tween(holder, { Size = UDim2.new(1, 0, 0, state and listHeight or 0) }, 0.3, Enum.EasingStyle.Quint)
                Animator.Tween(chevron, { Rotation = state and 180 or 0 }, 0.3, Enum.EasingStyle.Back)

                if state and Config.EffectsEnabled() then
                        -- staggered item entrance
                        local delay = 0.03
                        for i, name in ipairs(options) do
                                local btn = optionButtons[name]
                                if btn then
                                        btn.label.TextTransparency = 1
                                        btn.dot.Visible = false
                                        task.delay(delay * i, function()
                                                if btn.label.Parent then
                                                        Animator.Tween(btn.label, { TextTransparency = 0 }, 0.2)
                                                        refreshDots()
                                                end
                                        end)
                                end
                        end
                elseif state then
                        for _, btn in pairs(optionButtons) do
                                btn.label.TextTransparency = 0
                        end
                        refreshDots()
                end

                if not state then
                        task.delay(0.32, function()
                                if not expanded and holder.Parent then
                                        holder.Visible = false
                                end
                        end)
                end
        end

        card.Janitor:Add(card.Frame.Activated:Connect(function()
                setExpanded(not expanded)
        end))
        card.Janitor:Add(card.Frame.MouseLeave:Connect(function()
                task.defer(function()
                        -- close when the pointer leaves both card and holder
                        local mouse = Util.MouseLocation()
                        local cardAbs = card.Frame.AbsolutePosition
                        local cardSize = card.Frame.AbsoluteSize
                        local hAbs = holder.AbsolutePosition
                        local hSize = holder.AbsoluteSize
                        local inCard = mouse.X >= cardAbs.X and mouse.X <= cardAbs.X + cardSize.X
                                and mouse.Y >= cardAbs.Y and mouse.Y <= cardAbs.Y + cardSize.Y
                        local inHolder = expanded and mouse.X >= hAbs.X and mouse.X <= hAbs.X + hSize.X
                                and mouse.Y >= hAbs.Y and mouse.Y <= hAbs.Y + hSize.Y
                        if expanded and not inCard and not inHolder then
                                setExpanded(false)
                        end
                end)
        end))

        buildOptions()
        valueLabel.Text = valueText()

        local control = {
                Kind = "Dropdown",
                Frame = card.Frame,
                Changed = changed,
                Get = function()
                        if multi then
                                return Util.ShallowCopy(selectedMulti)
                        end
                        return selectedSingle
                end,
                Set = function(_, value, silent)
                        if multi then
                                selectedMulti = {}
                                if type(value) == "table" then
                                        for v in pairs(value) do
                                                selectedMulti[tostring(v)] = true
                                        end
                                elseif value ~= nil then
                                        selectedMulti[tostring(value)] = true
                                end
                        else
                                selectedSingle = value ~= nil and tostring(value) or nil
                        end
                        refreshDots()
                        if not silent then
                                changed:Fire(multi and Util.ShallowCopy(selectedMulti) or selectedSingle)
                        end
                end,
                Refresh = function(_, newOptions)
                        options = {}
                        for _, opt in ipairs(newOptions or {}) do
                                table.insert(options, tostring(opt))
                        end
                        listHeight = math.min(#options * OPTION_HEIGHT + 8, MAX_LIST_HEIGHT)
                        if expanded then
                                Animator.Tween(holder, { Size = UDim2.new(1, 0, 0, listHeight) }, 0.25)
                        end
                        buildOptions()
                end,
                Destroy = function()
                        card:Destroy()
                        wrapper:Destroy()
                end,
        }
        tab._Controls[cfg.Name or "Dropdown"] = control
        return control
end

--====================================================================================
-- COLOR PICKER
--====================================================================================

function Select.CreateColorPicker(tab, cfg)
        cfg = cfg or {}
        local ctx = tab._Ctx
        local hue, sat, val = 0.55, 0.8, 1
        if cfg.Default then
                hue, sat, val = cfg.Default:ToHSV()
        end

        local wrapper = Util.New("Frame", {
                Name = "ColorPicker_" .. (cfg.Name or "?"),
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                LayoutOrder = tab:NextOrder(),
                Parent = tab._Page,
        })
        Util.List(wrapper, 8)

        local card = Elements.GlassCard(ctx, wrapper, {
                Name = cfg.Name,
                Tooltip = cfg.Tooltip,
                Height = 46,
                Clickable = true,
                Order = 0,
        })

        local swatch = Util.New("Frame", {
                Name = "Swatch",
                BackgroundColor3 = Color3.fromHSV(hue, sat, val),
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -38, 0.5, -10),
                Size = UDim2.fromOffset(20, 20),
                BorderSizePixel = 0,
                Parent = card.Frame,
        })
        Util.Corner(swatch, 6)
        Util.Stroke(swatch, ctx.Color("InnerStroke"), 0.3, 1)

        local hexLabel = Util.New("TextLabel", {
                Name = "Hex",
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -48, 0.5, 0),
                Size = UDim2.fromOffset(70, 20),
                Font = Enum.Font.Code,
                Text = "#FFFFFF",
                TextColor3 = ctx.Color("TextMuted"),
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent = card.Frame,
        })
        ctx.Tint(hexLabel, "TextColor3", "TextMuted")

        local chevron = Elements.VectorIcon(ctx, "chevron", card.Frame, 12, "TextMuted", 2)
        chevron.AnchorPoint = Vector2.new(1, 0.5)
        chevron.Position = UDim2.new(1, -14, 0.5, 0)

        -- expanding editor -----------------------------------------------------------------
        local bodyHeight = 150
        local body = Util.New("Frame", {
                Name = "Editor",
                BackgroundColor3 = ctx.Color("Surface"),
                BackgroundTransparency = 0.06,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 0),
                ClipsDescendants = true,
                LayoutOrder = 1,
                Visible = false,
                Parent = wrapper,
        })
        Util.Corner(body, 10)
        Util.Stroke(body, ctx.Color("InnerStroke"), 0.35, 1)
        ctx.Tint(body, "BackgroundColor3", "Surface")

        local sv = Util.New("Frame", {
                Name = "SatVal",
                BackgroundColor3 = Color3.fromHSV(hue, 1, 1),
                Position = UDim2.new(0, 12, 0, 12),
                Size = UDim2.new(1, -52, 0, 96),
                BorderSizePixel = 0,
                ClipsDescendants = true,
                Parent = body,
        })
        Util.Corner(sv, 8)

        -- white overlay (left -> transparent)
        local whiteLayer = Util.New("Frame", {
                Name = "White",
                BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                Size = UDim2.new(1, 0, 1, 0),
                BorderSizePixel = 0,
                Parent = sv,
        })
        Util.New("UIGradient", {
                Rotation = 0,
                Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255)),
                Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0),
                        NumberSequenceKeypoint.new(1, 1),
                }),
                Parent = whiteLayer,
        })

        -- black overlay (transparent -> bottom black)
        local blackLayer = Util.New("Frame", {
                Name = "Black",
                BackgroundColor3 = Color3.fromRGB(0, 0, 0),
                Size = UDim2.new(1, 0, 1, 0),
                BorderSizePixel = 0,
                Parent = sv,
        })
        Util.New("UIGradient", {
                Rotation = 90,
                Color = ColorSequence.new(Color3.fromRGB(0, 0, 0), Color3.fromRGB(0, 0, 0)),
                Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 1),
                        NumberSequenceKeypoint.new(1, 0),
                }),
                Parent = blackLayer,
        })

        local svCursor = Util.New("Frame", {
                Name = "Cursor",
                BackgroundColor3 = Color3.fromHSV(hue, sat, val),
                AnchorPoint = Vector2.new(0.5, 0.5),
                Size = UDim2.fromOffset(12, 12),
                BorderSizePixel = 0,
                ZIndex = 4,
                Parent = sv,
        })
        Util.Corner(svCursor, 6)
        Util.Stroke(svCursor, Color3.fromRGB(255, 255, 255), 0.1, 2)

        -- hue bar
        local hueBar = Util.New("Frame", {
                Name = "Hue",
                Position = UDim2.new(1, -28, 0, 12),
                Size = UDim2.fromOffset(16, 96),
                BorderSizePixel = 0,
                Parent = body,
        })
        Util.Corner(hueBar, 8)
        Util.New("UIGradient", {
                Rotation = 90,
                Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
                        ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 220, 60)),
                        ColorSequenceKeypoint.new(0.33, Color3.fromRGB(80, 255, 80)),
                        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(60, 230, 255)),
                        ColorSequenceKeypoint.new(0.67, Color3.fromRGB(80, 90, 255)),
                        ColorSequenceKeypoint.new(0.83, Color3.fromRGB(230, 70, 255)),
                        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 60)),
                }),
                Parent = hueBar,
        })
        local hueCursor = Util.New("Frame", {
                Name = "HueCursor",
                BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                AnchorPoint = Vector2.new(0.5, 0.5),
                Size = UDim2.new(1, -4, 0, 4),
                Position = UDim2.new(0.5, 0, 0, 0),
                BorderSizePixel = 0,
                ZIndex = 3,
                Parent = hueBar,
        })
        Util.Corner(hueCursor, 2)
        Util.Stroke(hueCursor, Color3.fromRGB(0, 0, 0), 0.5, 1)

        local rgbLabel = Util.New("TextLabel", {
                Name = "RGB",
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 12, 1, -26),
                Size = UDim2.new(1, -24, 0, 16),
                Font = Enum.Font.Code,
                Text = "255, 255, 255",
                TextColor3 = ctx.Color("TextMuted"),
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = body,
        })
        ctx.Tint(rgbLabel, "TextColor3", "TextMuted")

        local changed = Util.Signal()

        local function currentColor()
                return Color3.fromHSV(hue, sat, val)
        end

        local function updateVisuals(fire)
                local color = currentColor()
                swatch.BackgroundColor3 = color
                sv.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
                svCursor.BackgroundColor3 = color
                svCursor.Position = UDim2.new(sat, 0, 1 - val, 0)
                hueCursor.Position = UDim2.new(0.5, 0, hue, 0)
                hexLabel.Text = string.format("#%02X%02X%02X",
                        math.floor(color.R * 255 + 0.5),
                        math.floor(color.G * 255 + 0.5),
                        math.floor(color.B * 255 + 0.5))
                rgbLabel.Text = string.format("%d, %d, %d",
                        math.floor(color.R * 255 + 0.5),
                        math.floor(color.G * 255 + 0.5),
                        math.floor(color.B * 255 + 0.5))
                if fire then
                        changed:Fire(color)
                        if cfg.Callback then
                                task.spawn(cfg.Callback, color)
                        end
                end
        end

        -- dragging --------------------------------------------------------------------------
        local function bindDrag(frame, handler)
                local dragging = false
                frame.InputBegan:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1
                                or input.UserInputType == Enum.UserInputType.Touch then
                                dragging = true
                                handler(input.Position.X, input.Position.Y)
                        end
                end)
                UserInputService.InputChanged:Connect(function(input)
                        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                                or input.UserInputType == Enum.UserInputType.Touch) then
                                handler(input.Position.X, input.Position.Y)
                        end
                end)
                UserInputService.InputEnded:Connect(function(input)
                        if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
                                or input.UserInputType == Enum.UserInputType.Touch) then
                                dragging = false
                        end
                end)
        end

        card.Janitor:Add(bindDrag(sv, function(x, y)
                sat = Util.Clamp((x - sv.AbsolutePosition.X) / math.max(sv.AbsoluteSize.X, 1), 0, 1)
                val = 1 - Util.Clamp((y - sv.AbsolutePosition.Y) / math.max(sv.AbsoluteSize.Y, 1), 0, 1)
                updateVisuals(true)
        end))
        card.Janitor:Add(bindDrag(hueBar, function(x, y)
                hue = Util.Clamp((y - hueBar.AbsolutePosition.Y) / math.max(hueBar.AbsoluteSize.Y, 1), 0, 1)
                updateVisuals(true)
        end))

        local expanded = false
        local function setExpanded(state)
                if expanded == state then
                        return
                end
                expanded = state
                body.Visible = true
                Animator.Tween(body, { Size = UDim2.new(1, 0, 0, state and bodyHeight or 0) }, 0.32, Enum.EasingStyle.Quint)
                Animator.Tween(chevron, { Rotation = state and 180 or 0 }, 0.3, Enum.EasingStyle.Back)
                if not state then
                        task.delay(0.34, function()
                                if not expanded and body.Parent then
                                        body.Visible = false
                                end
                        end)
                end
        end

        card.Janitor:Add(card.Frame.Activated:Connect(function()
                setExpanded(not expanded)
        end))
        updateVisuals(false)

        local control = {
                Kind = "ColorPicker",
                Frame = card.Frame,
                Changed = changed,
                Get = function()
                        return currentColor()
                end,
                Set = function(_, color, silent)
                        if typeof(color) == "Color3" then
                                hue, sat, val = color:ToHSV()
                                updateVisuals(false)
                                if not silent then
                                        changed:Fire(currentColor())
                                end
                        end
                end,
                Destroy = function()
                        card:Destroy()
                        wrapper:Destroy()
                end,
        }
        tab._Controls[cfg.Name or "ColorPicker"] = control
        return control
end

return Select
