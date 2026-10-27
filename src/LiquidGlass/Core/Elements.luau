--@module LiquidGlass/Core/Elements
--[[
        LiquidGlass · Core/Elements
        Shared visual building blocks. Every component is composed from these,
        so the design language stays consistent and code stays DRY:
          - GlassCard      : the translucent interactive surface
          - Ripple         : expanding click feedback
          - VectorIcon     : ctx-aware vector glyphs
          - RevealStagger  : staggered child entrance
]]

local Config = require(script.Parent.Config)
local Util = require(script.Parent.Util)
local Animator = require(script.Parent.Animator)
local Shine = require(script.Parent.Parent.Effects.Shine)

local Elements = {}

-- Tooltip binder is injected by Components/Display to avoid a circular require -------
local tooltipBinder = nil
function Elements.SetTooltipBinder(fn)
        tooltipBinder = fn
end

--====================================================================================
-- GLASS CARD
--====================================================================================

--[[
        Elements.GlassCard(ctx, parent, cfg)
        cfg: Name, Description, Tooltip, Height, Size, AutoHeight, Corner,
             Clickable, Order, IconGlyphless (unused here)
        Returns a card object with Frame, Stroke, Scale, Title, Desc,
        SetTitle, SetDescription, Sweep, Destroy.
]]
function Elements.GlassCard(ctx, parent, cfg)
        cfg = cfg or {}
        local janitor = Util.NewJanitor()

        local card = Util.New(cfg.Clickable and "TextButton" or "Frame", {
                Name = "Card_" .. (cfg.Name or "Element"),
                BackgroundColor3 = ctx.Color("Surface"),
                BackgroundTransparency = 0.05,
                BorderSizePixel = 0,
                Text = cfg.Clickable and "" or nil,
                AutoButtonColor = false,
                Size = cfg.Size or UDim2.new(1, 0, 0, cfg.Height or 42),
                AutomaticSize = cfg.AutoHeight and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
                LayoutOrder = cfg.Order or 0,
                ClipsDescendants = true,
                Parent = parent,
        })
        Util.Corner(card, cfg.Corner or 10)
        local stroke = Util.Stroke(card, ctx.Color("InnerStroke"), 0.35, 1)
        ctx.Tint(card, "BackgroundColor3", "Surface")
        ctx.Tint(stroke, "Color", "InnerStroke")

        -- top glass highlight ------------------------------------------------------------
        local highlight = Util.New("Frame", {
                Name = "Highlight",
                BackgroundColor3 = ctx.Color("Highlight"),
                BackgroundTransparency = ctx.Theme.HighlightT,
                Position = UDim2.new(0, 8, 0, 1),
                Size = UDim2.new(1, -16, 0, 1),
                BorderSizePixel = 0,
                ZIndex = 2,
                Parent = card,
        })
        ctx.Tint(highlight, "BackgroundColor3", "Highlight")

        -- glass shading gradient -----------------------------------------------------------
        local gradient = Util.VerticalGradient(card, ctx.Theme.ShadeTop, ctx.Theme.ShadeBottom)
        ctx.TintGradient(gradient, "ShadeTop", "ShadeBottom")

        local scale = Util.New("UIScale", { Scale = 1, Parent = card })

        local title, desc
        if cfg.Name then
                title = Util.New("TextLabel", {
                        Name = "Title",
                        BackgroundTransparency = 1,
                        Position = UDim2.new(0, 12, 0, cfg.Description and 7 or 0),
                        Size = UDim2.new(0.62, 0, 0, 16),
                        Font = Enum.Font.GothamMedium,
                        Text = cfg.Name,
                        TextColor3 = ctx.Color("TextPrimary"),
                        TextSize = 13,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                        Parent = card,
                })
                ctx.Tint(title, "TextColor3", "TextPrimary")
        end
        if cfg.Description then
                desc = Util.New("TextLabel", {
                        Name = "Description",
                        BackgroundTransparency = 1,
                        Position = UDim2.new(0, 12, 0, 23),
                        Size = UDim2.new(0.62, 0, 0, 13),
                        Font = Enum.Font.Gotham,
                        Text = cfg.Description,
                        TextColor3 = ctx.Color("TextSecondary"),
                        TextSize = 11,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                        Parent = card,
                })
                ctx.Tint(desc, "TextColor3", "TextSecondary")
        end

        -- interactive behavior --------------------------------------------------------------
        local sweep = Shine.Bind(card, janitor)
        if cfg.Clickable then
                janitor:Add(card.MouseEnter:Connect(function()
                        Animator.Tween(card, { BackgroundColor3 = ctx.Color("SurfaceHigh") })
                        Animator.Tween(stroke, { Color = ctx.Color("Stroke"), Transparency = 0.1 })
                        sweep()
                end))
                janitor:Add(card.MouseLeave:Connect(function()
                        Animator.Tween(card, { BackgroundColor3 = ctx.Color("Surface") })
                        Animator.Tween(stroke, { Color = ctx.Color("InnerStroke"), Transparency = 0.35 })
                end))
                janitor:Add(card.InputBegan:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1
                                or input.UserInputType == Enum.UserInputType.Touch then
                                Animator.Spring(scale, "Scale", 0.97, Config.Spring.Snappy)
                        end
                end))
                janitor:Add(card.InputEnded:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1
                                or input.UserInputType == Enum.UserInputType.Touch then
                                Animator.Spring(scale, "Scale", 1, Config.Spring.Snappy)
                        end
                end))
                janitor:Add(card.MouseLeave:Connect(function()
                        Animator.Spring(scale, "Scale", 1, Config.Spring.Snappy)
                end))
        end

        if cfg.Tooltip and tooltipBinder then
                tooltipBinder(ctx, card, cfg.Tooltip)
        end

        local cardObj = {
                Frame = card,
                Stroke = stroke,
                Scale = scale,
                Title = title,
                Desc = desc,
                Janitor = janitor,
                Sweep = sweep,
                SetTitle = function(self, text)
                        if title then
                                title.Text = text
                        end
                end,
                SetDescription = function(self, text)
                        if desc then
                                desc.Text = text
                        end
                end,
                Destroy = function()
                        Animator.Cancel(card)
                        janitor:Clean()
                        card:Destroy()
                end,
        }
        return cardObj
end

--====================================================================================
-- RIPPLE
--====================================================================================

function Elements.Ripple(ctx, card, worldPos)
        if not Config.EffectsEnabled() then
                return
        end
        local position
        if worldPos then
                local rel = card.AbsolutePosition
                position = UDim2.fromOffset(worldPos.X - rel.X, worldPos.Y - rel.Y)
        else
                position = UDim2.new(0.5, 0, 0.5, 0)
        end
        local dim = math.max(card.AbsoluteSize.X, card.AbsoluteSize.Y)
        local circle = Util.New("Frame", {
                Name = "Ripple",
                BackgroundColor3 = ctx.Color("TextPrimary"),
                BackgroundTransparency = 0.84,
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = position,
                Size = UDim2.fromOffset(10, 10),
                BorderSizePixel = 0,
                ZIndex = 6,
                Parent = card,
        })
        Util.Corner(circle, 5)
        local tween = Animator.Tween(circle, {
                Size = UDim2.fromOffset(dim * 2.1, dim * 2.1),
                BackgroundTransparency = 1,
        }, 0.5, Enum.EasingStyle.Quad)
        if tween then
                tween.Completed:Connect(function()
                        circle:Destroy()
                end)
        else
                circle:Destroy()
        end
end

--====================================================================================
-- VECTOR ICONS (ctx-aware, theme-tinted)
--====================================================================================

--[[
        Elements.VectorIcon(ctx, kind, parent, size [, colorKey] [, thickness])
        kind: check | cross | alert | info | minus | square | chevron | plus | search | dot
        colorKey: theme key (default "TextSecondary"); every part is registered for re-tinting.
]]
function Elements.VectorIcon(ctx, kind, parent, size, colorKey, thickness)
        colorKey = colorKey or "TextSecondary"
        thickness = thickness or math.max(2, math.floor(size / 7))
        local container = Util.New("Frame", {
                Name = "Icon_" .. kind,
                BackgroundTransparency = 1,
                Size = UDim2.fromOffset(size, size),
                Parent = parent,
        })

        local function part(len, x, y, rotation, extra)
                local p = Util.New("Frame", {
                        AnchorPoint = Vector2.new(0.5, 0.5),
                        Position = UDim2.fromScale(x, y),
                        Size = UDim2.fromOffset(thickness, math.max(2, len)),
                        Rotation = rotation or 0,
                        BorderSizePixel = 0,
                        Parent = container,
                })
                Util.Corner(p, math.max(1, math.floor(thickness / 2)))
                ctx.Tint(p, "BackgroundColor3", colorKey)
                return p
        end

        if kind == "check" then
                part(size * 0.30, 0.375, 0.635, -45)
                part(size * 0.55, 0.615, 0.52, 45)
        elseif kind == "cross" then
                part(size * 0.72, 0.5, 0.5, 45)
                part(size * 0.72, 0.5, 0.5, -45)
        elseif kind == "alert" then
                part(size * 0.42, 0.5, 0.36, 0)
                local dot = part(thickness + 1, 0.5, 0.74, 0)
                dot.Size = UDim2.fromOffset(thickness + 1, thickness + 1)
        elseif kind == "info" then
                local dot = part(thickness + 1, 0.5, 0.22, 0)
                dot.Size = UDim2.fromOffset(thickness + 1, thickness + 1)
                part(size * 0.42, 0.5, 0.6, 0)
        elseif kind == "minus" then
                part(size * 0.6, 0.5, 0.5, 90)
        elseif kind == "chevron" then
                part(size * 0.42, 0.355, 0.42, -45)
                part(size * 0.42, 0.645, 0.42, 45)
        elseif kind == "plus" then
                part(size * 0.6, 0.5, 0.5, 90)
                part(size * 0.6, 0.5, 0.5, 0)
        elseif kind == "square" then
                local box = Util.New("Frame", {
                        AnchorPoint = Vector2.new(0.5, 0.5),
                        Position = UDim2.fromScale(0.5, 0.5),
                        Size = UDim2.fromOffset(size * 0.52, size * 0.52),
                        BackgroundTransparency = 1,
                        Parent = container,
                })
                local stroke = Util.Stroke(box, ctx.Color(colorKey), 0, thickness)
                ctx.Tint(stroke, "Color", colorKey)
                Util.Corner(box, math.floor(size / 8))
        elseif kind == "search" then
                local lens = Util.New("Frame", {
                        Size = UDim2.fromOffset(size * 0.55, size * 0.55),
                        Position = UDim2.fromScale(0.06, 0.06),
                        BackgroundTransparency = 1,
                        Parent = container,
                })
                local stroke = Util.Stroke(lens, ctx.Color(colorKey), 0, thickness)
                ctx.Tint(stroke, "Color", colorKey)
                Util.Corner(lens, 999)
                part(size * 0.32, 0.72, 0.72, 45)
        elseif kind == "dot" then
                local dot = Util.New("Frame", {
                        AnchorPoint = Vector2.new(0.5, 0.5),
                        Position = UDim2.fromScale(0.5, 0.5),
                        Size = UDim2.fromOffset(size, size),
                        BorderSizePixel = 0,
                        Parent = container,
                })
                Util.Corner(dot, 999)
                ctx.Tint(dot, "BackgroundColor3", colorKey)
        end
        return container
end

--====================================================================================
-- STAGGERED REVEAL
--====================================================================================

-- Fade+rise every card inside a page, sequenced left-to-right timing ------------------
function Elements.RevealStagger(page)
        if not Config.EffectsEnabled() then
                return
        end
        if page:GetAttribute("Revealing") then
                return
        end
        page:SetAttribute("Revealing", true)

        local delay = 0
        for _, child in ipairs(page:GetChildren()) do
                if child:IsA("Frame") or child:IsA("TextButton") or child:IsA("CanvasGroup") then
                        local scale = child:FindFirstChildOfClass("UIScale")
                        local stroke = child:FindFirstChildOfClass("UIStroke")
                        local baseTransparency = child:GetAttribute("BaseTransparency") or child.BackgroundTransparency

                        if scale then
                                scale.Scale = 0.96
                                Animator.Spring(scale, "Scale", 1, Config.Spring.Soft)
                        end
                        child.BackgroundTransparency = math.min(1, baseTransparency + 0.75)
                        if stroke then
                                stroke.Transparency = 1
                        end

                        task.delay(delay, function()
                                if not child.Parent then
                                        return
                                end
                                Animator.Tween(child, { BackgroundTransparency = baseTransparency }, 0.3)
                                if stroke then
                                        Animator.Tween(stroke, { Transparency = 0.35 }, 0.3)
                                end
                        end)
                        delay = delay + 0.03
                end
        end

        task.delay(delay + 0.35, function()
                page:SetAttribute("Revealing", false)
        end)
end

return Elements
