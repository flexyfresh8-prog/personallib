--@module LiquidGlass/Components/Display
--[[
        LiquidGlass · Components/Display
        CreateCard (paragraph) · CreateSection · CreateDivider · CreateBadge
        CreateProgress · CreateProgressRing · CreateImagePanel · BindTooltip
]]

local Config = require(script.Parent.Parent.Core.Config)
local Util = require(script.Parent.Parent.Core.Util)
local Animator = require(script.Parent.Parent.Core.Animator)
local Elements = require(script.Parent.Parent.Core.Elements)

local Display = {}

--====================================================================================
-- CARD (paragraph / glass panel with text)
--====================================================================================

function Display.CreateCard(tab, cfg)
        cfg = cfg or {}
        local ctx = tab._Ctx
        local card = Elements.GlassCard(ctx, tab._Page, {
                Order = tab:NextOrder(),
                AutoHeight = true,
                Corner = 10,
        })

        local titleInstance = nil
        local y = 9
        if cfg.Title then
                titleInstance = Util.New("TextLabel", {
                        Name = "CardTitle",
                        BackgroundTransparency = 1,
                        Position = UDim2.new(0, 12, 0, 9),
                        Size = UDim2.new(1, -24, 0, 16),
                        Font = Enum.Font.GothamBold,
                        Text = cfg.Title,
                        TextColor3 = ctx.Color("TextPrimary"),
                        TextSize = 13,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                        Parent = card.Frame,
                })
                ctx.Tint(titleInstance, "TextColor3", "TextPrimary")
                y = 27
        end

        local body = Util.New("TextLabel", {
                Name = "CardBody",
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 12, 0, y),
                Size = UDim2.new(1, -24, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                Font = Enum.Font.Gotham,
                Text = cfg.Content or cfg.Body or "",
                TextColor3 = ctx.Color("TextSecondary"),
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top,
                TextWrapped = true,
                RichText = cfg.RichText == true,
                Parent = card.Frame,
        })
        ctx.Tint(body, "TextColor3", "TextSecondary")

        -- bottom breathing room
        Util.Padding(card.Frame, 0, 0, 10, 0)

        return {
                Kind = "Card",
                Frame = card.Frame,
                SetTitle = function(_, text)
                        if titleInstance then
                                titleInstance.Text = tostring(text or "")
                        end
                end,
                SetContent = function(_, text)
                        body.Text = tostring(text or "")
                end,
                Destroy = function()
                        card:Destroy()
                end,
        }
end

--====================================================================================
-- SECTION (label + animated accent bar)
--====================================================================================

function Display.CreateSection(tab, cfg)
        cfg = cfg or {}
        local ctx = tab._Ctx
        local order = tab:NextOrder()
        local section = Util.New("Frame", {
                Name = "Section_" .. (cfg.Name or "?"),
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 26),
                LayoutOrder = order,
                Parent = tab._Page,
        })

        local bar = Util.New("Frame", {
                Name = "Bar",
                BackgroundColor3 = ctx.Color("Accent"),
                BackgroundTransparency = 0.15,
                Position = UDim2.new(0, 2, 0.5, -8),
                Size = UDim2.new(0, 3, 0, 16),
                BorderSizePixel = 0,
                Parent = section,
        })
        Util.Corner(bar, 2)
        ctx.Tint(bar, "BackgroundColor3", "Accent")

        local label = Util.New("TextLabel", {
                Name = "Label",
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 14, 0, 0),
                Size = UDim2.new(1, -20, 1, 0),
                Font = Enum.Font.GothamBold,
                Text = string.upper(cfg.Name or "Section"),
                TextColor3 = ctx.Color("TextMuted"),
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = section,
        })
        ctx.Tint(label, "TextColor3", "TextMuted")

        -- subtle luminous pulse on the accent bar (High quality only)
        if Config.EffectsEnabled() then
                local t = math.random() * 6
                Animator.Loop(function(dt)
                        t = t + dt
                        bar.BackgroundTransparency = 0.1 + (math.sin(t * 1.4) + 1) * 0.18
                end, tab._Janitor)
        end

        return {
                Kind = "Section",
                Frame = section,
                SetName = function(_, text)
                        label.Text = string.upper(tostring(text or ""))
                end,
                Destroy = function()
                        section:Destroy()
                end,
        }
end

--====================================================================================
-- DIVIDER (animated gradient separator)
--====================================================================================

function Display.CreateDivider(tab, cfg)
        local ctx = tab._Ctx
        local order = tab:NextOrder()
        local divider = Util.New("Frame", {
                Name = "Divider",
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 4),
                LayoutOrder = order,
                Parent = tab._Page,
        })
        local line = Util.New("Frame", {
                Name = "Line",
                BackgroundColor3 = ctx.Color("InnerStroke"),
                BackgroundTransparency = 0.35,
                Position = UDim2.new(0, 4, 0.5, -0.5),
                Size = UDim2.new(1, -8, 0, 1),
                BorderSizePixel = 0,
                Parent = divider,
        })
        ctx.Tint(line, "BackgroundColor3", "InnerStroke")
        local grad = Util.New("UIGradient", {
                Color = ColorSequence.new(ctx.Color("TextMuted"), ctx.Color("InnerStroke")),
                Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 1),
                        NumberSequenceKeypoint.new(0.5, 0.1),
                        NumberSequenceKeypoint.new(1, 1),
                }),
                Parent = line,
        })
        ctx.TintGradient(grad, "TextMuted", "InnerStroke")

        -- slow shimmer sweep (High quality only)
        if Config.EffectsEnabled() then
                local offset = -1
                local direction = 1
                Animator.Loop(function(dt)
                        offset = offset + dt * 0.35 * direction
                        if offset > 1 then
                                offset = 1
                                direction = -1
                        elseif offset < -1 then
                                offset = -1
                                direction = 1
                        end
                        grad.Offset = Vector2.new(offset, 0)
                end, tab._Janitor)
        end

        return {
                Kind = "Divider",
                Frame = divider,
                Destroy = function()
                        divider:Destroy()
                end,
        }
end

--====================================================================================
-- BADGE (status chip)
--====================================================================================

local VARIANTS = {
        Success = "Success",
        Danger = "Danger",
        Warning = "Warning",
        Accent = "Accent",
        Neutral = "TextMuted",
}

function Display.CreateBadge(tab, cfg)
        cfg = cfg or {}
        local ctx = tab._Ctx
        local variant = VARIANTS[cfg.Variant or "Accent"] and (cfg.Variant or "Accent") or "Accent"
        local order = tab:NextOrder()

        local holder = Util.New("Frame", {
                Name = "Badge_" .. (cfg.Text or "?"),
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 24),
                LayoutOrder = order,
                Parent = tab._Page,
        })

        local chip = Util.New("Frame", {
                Name = "Chip",
                BackgroundColor3 = ctx.Color(variant == "Neutral" and "SurfaceHigh" or variant),
                BackgroundTransparency = variant == "Neutral" and 0.4 or 0.86,
                Size = UDim2.fromOffset(60, 22),
                BorderSizePixel = 0,
                Parent = holder,
        })
        Util.Corner(chip, 11)
        Util.Stroke(chip, ctx.Color("InnerStroke"), 0.4, 1)

        local dot = Util.New("Frame", {
                Name = "Dot",
                BackgroundColor3 = ctx.Color(VARIANTS[variant]),
                Size = UDim2.fromOffset(6, 6),
                Position = UDim2.new(0, 9, 0.5, -3),
                BorderSizePixel = 0,
                Parent = chip,
        })
        Util.Corner(dot, 3)
        ctx.Tint(dot, "BackgroundColor3", VARIANTS[variant])

        local label = Util.New("TextLabel", {
                Name = "Label",
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 20, 0, 0),
                Size = UDim2.new(1, -28, 1, 0),
                Font = Enum.Font.GothamMedium,
                Text = cfg.Text or "Status",
                TextColor3 = ctx.Color(variant == "Neutral" and "TextSecondary" or VARIANTS[variant]),
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = chip,
        })
        ctx.Tint(label, "TextColor3", variant == "Neutral" and "TextSecondary" or VARIANTS[variant])

        -- chip hugs its text
        task.defer(function()
                if chip.Parent then
                        chip.Size = UDim2.fromOffset(28 + label.TextBounds.X, 22)
                end
        end)

        return {
                Kind = "Badge",
                Frame = chip,
                SetText = function(_, text)
                        label.Text = tostring(text or "")
                        chip.Size = UDim2.fromOffset(28 + label.TextBounds.X, 22)
                end,
                SetVariant = function(_, newVariant)
                        variant = VARIANTS[newVariant] and newVariant or "Accent"
                        local colorKey = VARIANTS[variant]
                        local isNeutral = variant == "Neutral"
                        chip.BackgroundColor3 = ctx.Color(isNeutral and "SurfaceHigh" or colorKey)
                        chip.BackgroundTransparency = isNeutral and 0.4 or 0.86
                        dot.BackgroundColor3 = ctx.Color(colorKey)
                        label.TextColor3 = ctx.Color(isNeutral and "TextSecondary" or colorKey)
                end,
                Destroy = function()
                        holder:Destroy()
                end,
        }
end

--====================================================================================
-- PROGRESS BAR
--====================================================================================

function Display.CreateProgress(tab, cfg)
        cfg = cfg or {}
        local ctx = tab._Ctx
        local value = Util.Clamp(cfg.Default or 0, 0, 100)

        local card = tab:_AddCard({
                Name = cfg.Name,
                Tooltip = cfg.Tooltip,
                Height = 54,
        })

        local valueLabel = Util.New("TextLabel", {
                Name = "Value",
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -12, 0, 7),
                Size = UDim2.fromOffset(70, 16),
                Font = Enum.Font.GothamBold,
                Text = "0%",
                TextColor3 = ctx.Color("Accent"),
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent = card.Frame,
        })
        ctx.Tint(valueLabel, "TextColor3", "Accent")

        local track = Util.New("Frame", {
                Name = "Track",
                BackgroundColor3 = ctx.Color("Track"),
                Position = UDim2.new(0, 12, 1, -16),
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
        local grad = Util.VerticalGradient(fill, ctx.Color("Accent"), ctx.Color("Accent2"))
        ctx.TintGradient(grad, "Accent", "Accent2")
        local glow = Util.Stroke(fill, ctx.Color("Accent"), 0.55, 1.4)
        ctx.Tint(glow, "Color", "Accent")

        local pulseConn = nil

        local function apply(newValue, animate)
                value = Util.Clamp(newValue, 0, 100)
                if pulseConn then
                        pulseConn:Disconnect()
                        pulseConn = nil
                        fill.Position = UDim2.new(0, 0, 0, 0)
                end
                local target = UDim2.new(value / 100, 0, 1, 0)
                if animate ~= false and Config.MotionEnabled() then
                        Animator.Tween(fill, { Size = target }, 0.4)
                else
                        fill.Size = target
                end
                valueLabel.Text = math.floor(value + 0.5) .. "%"
        end

        apply(value, false)

        return {
                Kind = "Progress",
                Frame = card.Frame,
                Get = function()
                        return value
                end,
                Set = function(_, newValue)
                        apply(newValue, true)
                end,
                Pulse = function() -- indeterminate mode until Set is called again
                        if not Config.EffectsEnabled() or pulseConn then
                                return
                        end
                        local t = 0
                        pulseConn = Animator.Loop(function(dt)
                                t = t + dt
                                local cycle = (t * 0.6) % 1
                                fill.Size = UDim2.new(0.25, 0, 1, 0)
                                fill.Position = UDim2.new(cycle * 0.75, 0, 0, 0)
                                valueLabel.Text = "…"
                        end, card.Janitor)
                end,
                Destroy = function()
                        card:Destroy()
                end,
        }
end

--====================================================================================
-- PROGRESS RING (segmented circular indicator — no external assets)
--====================================================================================

function Display.CreateProgressRing(tab, cfg)
        cfg = cfg or {}
        local ctx = tab._Ctx
        local value = Util.Clamp(cfg.Default or 0, 0, 100)
        local DOTS = 12

        local card = tab:_AddCard({
                Name = cfg.Name,
                Tooltip = cfg.Tooltip,
                Height = 64,
        })

        local ring = Util.New("Frame", {
                Name = "Ring",
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -14, 0.5, 0),
                Size = UDim2.fromOffset(48, 48),
                Parent = card.Frame,
        })

        local dots = {}
        for i = 1, DOTS do
                local angle = (i / DOTS) * math.pi * 2 - math.pi / 2
                local dot = Util.New("Frame", {
                        Name = "Dot" .. i,
                        BackgroundColor3 = ctx.Color("InnerStroke"),
                        BackgroundTransparency = 0.3,
                        AnchorPoint = Vector2.new(0.5, 0.5),
                        Position = UDim2.fromOffset(24 + math.cos(angle) * 19, 24 + math.sin(angle) * 19),
                        Size = UDim2.fromOffset(4, 4),
                        BorderSizePixel = 0,
                        Parent = ring,
                })
                Util.Corner(dot, 2)
                ctx.Tint(dot, "BackgroundColor3", "InnerStroke")
                dots[i] = dot
        end

        local valueLabel = Util.New("TextLabel", {
                Name = "Value",
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 12, 0, 7),
                Size = UDim2.new(0.5, -20, 0, 16),
                Font = Enum.Font.GothamBold,
                Text = "0%",
                TextColor3 = ctx.Color("Accent"),
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = card.Frame,
        })
        ctx.Tint(valueLabel, "TextColor3", "Accent")

        local function apply(newValue)
                value = Util.Clamp(newValue, 0, 100)
                local filled = math.floor((value / 100) * DOTS + 0.5)
                for i, dot in ipairs(dots) do
                        local active = i <= filled
                        dot.BackgroundColor3 = active and ctx.Color("Accent") or ctx.Color("InnerStroke")
                        dot.Size = UDim2.fromOffset(active and 5 or 4, active and 5 or 4)
                end
                valueLabel.Text = math.floor(value + 0.5) .. "%"
        end

        apply(value, false)

        -- gentle sway on the ring (High quality only)
        if Config.EffectsEnabled() then
                local t = 0
                Animator.Loop(function(dt)
                        t = t + dt
                        ring.Rotation = math.sin(t * 0.8) * 6
                end, card.Janitor)
        end

        return {
                Kind = "ProgressRing",
                Frame = card.Frame,
                Get = function()
                        return value
                end,
                Set = function(_, newValue)
                        apply(newValue)
                end,
                Destroy = function()
                        card:Destroy()
                end,
        }
end

--====================================================================================
-- IMAGE PANEL
--====================================================================================

function Display.CreateImagePanel(tab, cfg)
        cfg = cfg or {}
        local ctx = tab._Ctx
        local card = Elements.GlassCard(ctx, tab._Page, {
                Order = tab:NextOrder(),
                AutoHeight = true,
                Name = cfg.Name,
        })

        local image = Util.New("ImageLabel", {
                Name = "Image",
                BackgroundColor3 = ctx.Color("Track"),
                BackgroundTransparency = 0.2,
                Position = UDim2.new(0, 10, 0, cfg.Name and 30 or 10),
                Size = UDim2.new(1, -20, 0, cfg.Height or 120),
                Image = cfg.Image or "",
                ScaleType = Enum.ScaleType.Crop,
                BorderSizePixel = 0,
                Parent = card.Frame,
        })
        Util.Corner(image, 8)
        ctx.Tint(image, "BackgroundColor3", "Track")

        local caption
        if cfg.Caption then
                caption = Util.New("TextLabel", {
                        Name = "Caption",
                        BackgroundTransparency = 1,
                        Position = UDim2.new(0, 12, 0, cfg.Name and (30 + (cfg.Height or 120) + 6) or (10 + (cfg.Height or 120) + 6)),
                        Size = UDim2.new(1, -24, 0, 16),
                        Font = Enum.Font.Gotham,
                        Text = cfg.Caption,
                        TextColor3 = ctx.Color("TextSecondary"),
                        TextSize = 11,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Parent = card.Frame,
                })
                ctx.Tint(caption, "TextColor3", "TextSecondary")
                Util.Padding(card.Frame, 0, 0, 28, 0)
        else
                Util.Padding(card.Frame, 0, 0, 16, 0)
        end

        return {
                Kind = "ImagePanel",
                Frame = card.Frame,
                SetImage = function(_, asset)
                        image.Image = asset
                end,
                Destroy = function()
                        card:Destroy()
                end,
        }
end

--====================================================================================
-- TOOLTIP
--====================================================================================

--[[
        Display.BindTooltip(ctx, host, text)
        Glass bubble appears above the host after a short delay, springs in.
        Registered into Elements so GlassCard can honor cfg.Tooltip.
]]
function Display.BindTooltip(ctx, host, text)
        local token = 0
        local bubble = nil

        local function hide()
                token = token + 1
                if bubble then
                        local b = bubble
                        bubble = nil
                        Animator.Tween(b, { GroupTransparency = 1 }, 0.12)
                        task.delay(0.14, function()
                                b:Destroy()
                        end)
                end
        end

        host.MouseEnter:Connect(function()
                token = token + 1
                local myToken = token
                task.delay(Config.Tooltips.Delay, function()
                        if myToken ~= token or not host.Parent or bubble then
                                return
                        end
                        local layer = ctx.TooltipLayer
                        if not layer then
                                return
                        end
                        bubble = Util.New("CanvasGroup", {
                                Name = "Tooltip",
                                BackgroundColor3 = ctx.Color("SurfaceHigh"),
                                BackgroundTransparency = 0.08,
                                BorderSizePixel = 0,
                                GroupTransparency = 1,
                                ZIndex = 50,
                                Parent = layer,
                        })
                        Util.Corner(bubble, 8)
                        Util.Stroke(bubble, ctx.Color("Stroke"), 0.25, 1)
                        local label = Util.New("TextLabel", {
                                BackgroundTransparency = 1,
                                Position = UDim2.new(0, 10, 0, 6),
                                Size = UDim2.new(1, -20, 0, 0),
                                AutomaticSize = Enum.AutomaticSize.Y,
                                Font = Enum.Font.Gotham,
                                Text = text,
                                TextColor3 = ctx.Color("TextPrimary"),
                                TextSize = 11,
                                TextWrapped = true,
                                Parent = bubble,
                        })
                        Util.Padding(bubble, 0, 0, 6, 0)

                        task.defer(function()
                                if not bubble then
                                        return
                                end
                                local hostAbs = host.AbsolutePosition
                                local layerAbs = layer.AbsolutePosition
                                local w = bubble.AbsoluteSize.X
                                local h = bubble.AbsoluteSize.Y
                                bubble.Size = UDim2.fromOffset(math.max(w, 40), h)
                                local x = Util.Clamp(hostAbs.X - layerAbs.X + host.AbsoluteSize.X / 2 - w / 2, 8, layer.AbsoluteSize.X - w - 8)
                                local y = hostAbs.Y - layerAbs.Y - h - 10
                                if y < 8 then
                                        y = hostAbs.Y - layerAbs.Y + host.AbsoluteSize.Y + 10
                                end
                                bubble.Position = UDim2.fromOffset(x, y)
                                local scale = Util.New("UIScale", { Scale = 0.85, Parent = bubble })
                                Animator.Tween(bubble, { GroupTransparency = 0 }, 0.12)
                                Animator.Spring(scale, "Scale", 1, Config.Spring.Pop)
                        end)
                end)
        end)
        host.MouseLeave:Connect(hide)
        host.AncestryChanged:Connect(function()
                if not host.Parent then
                        hide()
                end
        end)
end

-- Register the tooltip binder (Elements avoids a circular require) --------------------
Elements.SetTooltipBinder(Display.BindTooltip)

return Display
