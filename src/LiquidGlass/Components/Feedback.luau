--@module LiquidGlass/Components/Feedback
--[[
        LiquidGlass · Components/Feedback
        Dialog (modal confirmation) · Loading (orbiting particles overlay)
        Called by the window: Window:Dialog{...} / Window:Loading()
]]

local Config = require(script.Parent.Parent.Core.Config)
local Util = require(script.Parent.Parent.Core.Util)
local Animator = require(script.Parent.Parent.Core.Animator)
local Elements = require(script.Parent.Parent.Core.Elements)

local UserInputService = game:GetService("UserInputService")

local Feedback = {}

--====================================================================================
-- DIALOG
--====================================================================================

function Feedback.Dialog(window, cfg)
        cfg = cfg or {}
        local ctx = window._ctx
        local panel = window._panel

        local overlay = Util.New("TextButton", {
                Name = "DialogOverlay",
                BackgroundColor3 = ctx.Color("Overlay"),
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 1, 0),
                Text = "",
                AutoButtonColor = false,
                BorderSizePixel = 0,
                ZIndex = 60,
                Parent = panel,
        })

        local card = Util.New("CanvasGroup", {
                Name = "Dialog",
                BackgroundColor3 = ctx.Color("Surface"),
                BackgroundTransparency = 0.04,
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, 0, 0.5, 0),
                Size = UDim2.fromOffset(360, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BorderSizePixel = 0,
                GroupTransparency = 1,
                ZIndex = 61,
                Parent = overlay,
        })
        Util.Corner(card, 14)
        Util.Stroke(card, ctx.Color("Stroke"), 0.3, 1)
        local grad = Util.VerticalGradient(card, ctx.Theme.ShadeTop, ctx.Theme.ShadeBottom)
        ctx.TintGradient(grad, "ShadeTop", "ShadeBottom")

        local dialogScale = Util.New("UIScale", { Scale = 0.9, Parent = card })

        -- icon (optional) -------------------------------------------------------------------
        local y = 16
        if cfg.Icon and cfg.Icon ~= "none" then
                local iconColorKey = ({ check = "Success", cross = "Danger", alert = "Warning", info = "Accent" })[cfg.Icon] or "Accent"
                local circle = Util.New("Frame", {
                        Name = "IconCircle",
                        BackgroundColor3 = ctx.Color(iconColorKey),
                        BackgroundTransparency = 0.85,
                        Position = UDim2.new(0.5, -20, 0, 16),
                        Size = UDim2.fromOffset(40, 40),
                        BorderSizePixel = 0,
                        Parent = card,
                })
                Util.Corner(circle, 20)
                Util.Stroke(circle, ctx.Color(iconColorKey), 0.4, 1)
                Elements.VectorIcon(ctx, cfg.Icon, circle, 18, iconColorKey, 2.4)
                y = 66
        end

        local title = Util.New("TextLabel", {
                Name = "Title",
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 18, 0, y),
                Size = UDim2.new(1, -36, 0, 18),
                Font = Enum.Font.GothamBold,
                Text = cfg.Title or "Are you sure?",
                TextColor3 = ctx.Color("TextPrimary"),
                TextSize = 15,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = card,
        })
        ctx.Tint(title, "TextColor3", "TextPrimary")

        local body = Util.New("TextLabel", {
                Name = "Body",
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 18, 0, y + 22),
                Size = UDim2.new(1, -36, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                Font = Enum.Font.Gotham,
                Text = cfg.Content or "",
                TextColor3 = ctx.Color("TextSecondary"),
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top,
                TextWrapped = true,
                Parent = card,
        })
        ctx.Tint(body, "TextColor3", "TextSecondary")

        -- buttons ---------------------------------------------------------------------------
        local buttons = cfg.Buttons or {
                { Text = "Cancel" },
                { Text = "Confirm", Primary = true },
        }
        local closeDialog -- forward declaration

        local buttonRow = Util.New("Frame", {
                Name = "Buttons",
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 14, 1, -46),
                Size = UDim2.new(1, -28, 0, 32),
                Parent = card,
        })
        local rowLayout = Util.New("UIListLayout", {
                Padding = UDim.new(0, 8),
                FillDirection = Enum.FillDirection.Horizontal,
                HorizontalAlignment = Enum.HorizontalAlignment.Right,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Parent = buttonRow,
        })

        local function close()
                if closeDialog then
                        closeDialog()
                end
        end

        for i, spec in ipairs(buttons) do
                local isPrimary = spec.Primary == true
                local btn = Util.New("TextButton", {
                        Name = "Btn_" .. (spec.Text or i),
                        BackgroundColor3 = isPrimary and ctx.Color("Accent") or ctx.Color("SurfaceHigh"),
                        BackgroundTransparency = isPrimary and 0.05 or 0.3,
                        Size = UDim2.fromOffset(math.max(80, 34 + #tostring(spec.Text or "") * 7), 32),
                        Text = "",
                        AutoButtonColor = false,
                        BorderSizePixel = 0,
                        LayoutOrder = i,
                        Parent = buttonRow,
                })
                Util.Corner(btn, 9)
                if isPrimary then
                        local bgrad = Util.VerticalGradient(btn, ctx.Color("Accent"), ctx.Color("Accent2"))
                        ctx.TintGradient(bgrad, "Accent", "Accent2")
                end
                local label = Util.New("TextLabel", {
                        BackgroundTransparency = 1,
                        Size = UDim2.new(1, 0, 1, 0),
                        Font = Enum.Font.GothamMedium,
                        Text = spec.Text or "OK",
                        TextColor3 = isPrimary and ctx.Color("OnAccent") or ctx.Color("TextPrimary"),
                        TextSize = 12,
                        Parent = btn,
                })
                ctx.Tint(label, "TextColor3", isPrimary and "OnAccent" or "TextPrimary")

                btn.MouseEnter:Connect(function()
                        Animator.Tween(btn, { BackgroundTransparency = isPrimary and 0 or 0.1 })
                end)
                btn.MouseLeave:Connect(function()
                        Animator.Tween(btn, { BackgroundTransparency = isPrimary and 0.05 or 0.3 })
                end)
                btn.Activated:Connect(function()
                        close()
                        if spec.Callback then
                                task.spawn(spec.Callback)
                        end
                end)
        end

        -- position button row below content ---------------------------------------------------
        task.defer(function()
                local contentBottom = body.AbsolutePosition.Y + body.AbsoluteSize.Y - card.AbsolutePosition.Y
                buttonRow.Position = UDim2.new(0, 14, 0, contentBottom + 14)
        end)

        local janitor = Util.NewJanitor()
        local closed = false
        closeDialog = function()
                if closed then
                        return
                end
                closed = true
                janitor:Clean()
                Animator.Tween(overlay, { BackgroundTransparency = 1 }, 0.15)
                Animator.Tween(card, { GroupTransparency = 1 }, 0.15)
                Animator.Spring(dialogScale, "Scale", 0.92, Config.Spring.Soft)
                task.delay(0.18, function()
                        overlay:Destroy()
                end)
        end

        janitor:Add(overlay.Activated:Connect(function()
                -- clicks that started inside the card must not dismiss the dialog
                if card:GetAttribute("PressedInside") then
                        card:SetAttribute("PressedInside", false)
                        return
                end
                close()
        end))
        janitor:Add(card.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                        or input.UserInputType == Enum.UserInputType.Touch then
                        -- stop backdrop-click from firing when pressing the card itself
                        card:SetAttribute("PressedInside", true)
                end
        end))

        -- entrance
        Animator.Tween(overlay, { BackgroundTransparency = 0.35 }, 0.18)
        Animator.Tween(card, { GroupTransparency = 0 }, 0.18)
        Animator.Spring(dialogScale, "Scale", 1, Config.Spring.Pop)
        if window._sweep then
                window._sweep()
        end

        return {
                Close = close,
                Frame = card,
        }
end

--====================================================================================
-- LOADING OVERLAY
--====================================================================================

function Feedback.Loading(window)
        local ctx = window._ctx
        local panel = window._panel

        local layer = Util.New("Frame", {
                Name = "LoadingLayer",
                BackgroundColor3 = ctx.Color("Overlay"),
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 1, 0),
                Visible = false,
                ZIndex = 70,
                Parent = panel,
        })

        local card = Util.New("CanvasGroup", {
                Name = "LoadingCard",
                BackgroundColor3 = ctx.Color("Surface"),
                BackgroundTransparency = 0.05,
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, 0, 0.5, 0),
                Size = UDim2.fromOffset(190, 130),
                BorderSizePixel = 0,
                ZIndex = 71,
                Parent = layer,
        })
        Util.Corner(card, 14)
        Util.Stroke(card, ctx.Color("InnerStroke"), 0.3, 1)
        local grad = Util.VerticalGradient(card, ctx.Theme.ShadeTop, ctx.Theme.ShadeBottom)
        ctx.TintGradient(grad, "ShadeTop", "ShadeBottom")

        -- pulsing glass ring
        local ring = Util.New("Frame", {
                Name = "Ring",
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, 0, 0.42, 0),
                Size = UDim2.fromOffset(44, 44),
                BackgroundTransparency = 1,
                Parent = card,
        })
        Util.Corner(ring, 22)
        local ringStroke = Util.Stroke(ring, ctx.Color("Accent"), 0.3, 2.5)
        ctx.Tint(ringStroke, "Color", "Accent")

        -- orbiting particles
        local orbitCenter = Util.New("Frame", {
                Name = "Orbit",
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, 0, 0.42, 0),
                Size = UDim2.fromOffset(1, 1),
                BackgroundTransparency = 1,
                Parent = card,
        })
        local particles = {}
        for i = 1, 3 do
                local dot = Util.New("Frame", {
                        Name = "Particle" .. i,
                        BackgroundColor3 = ctx.Color(i == 1 and "Accent" or (i == 2 and "Accent2" or "TextPrimary")),
                        AnchorPoint = Vector2.new(0.5, 0.5),
                        Size = UDim2.fromOffset(i == 1 and 7 or 5, i == 1 and 7 or 5),
                        BorderSizePixel = 0,
                        ZIndex = 72,
                        Parent = orbitCenter,
                })
                Util.Corner(dot, 4)
                table.insert(particles, dot)
        end

        local label = Util.New("TextLabel", {
                Name = "Label",
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(0.5, 1),
                Position = UDim2.new(0.5, 0, 1, -14),
                Size = UDim2.new(1, -20, 0, 16),
                Font = Enum.Font.GothamMedium,
                Text = "Loading…",
                TextColor3 = ctx.Color("TextSecondary"),
                TextSize = 12,
                Parent = card,
        })
        ctx.Tint(label, "TextColor3", "TextSecondary")

        local orbitConn = nil
        local pulseConn = nil
        local angle = 0

        local function startLoops()
                if orbitConn or not Config.EffectsEnabled() then
                        return
                end
                orbitConn = Animator.Loop(function(dt)
                        angle = angle + dt * 2.8
                        for i, dot in ipairs(particles) do
                                local a = angle + (i - 1) * (math.pi * 2 / 3)
                                dot.Position = UDim2.fromOffset(math.cos(a) * 27, math.sin(a) * 27)
                                dot.BackgroundTransparency = 0.1 + (math.sin(angle * 2 + i) + 1) * 0.25
                        end
                end)
                local t = 0
                pulseConn = Animator.Loop(function(dt)
                        t = t + dt
                        ringStroke.Thickness = 2 + math.sin(t * 3) * 1
                        ringStroke.Transparency = 0.25 + (math.sin(t * 3) + 1) * 0.2
                end)
        end

        local function stopLoops()
                if orbitConn then
                        orbitConn:Disconnect()
                        orbitConn = nil
                end
                if pulseConn then
                        pulseConn:Disconnect()
                        pulseConn = nil
                end
        end

        return {
                Show = function(_, text)
                        layer.Visible = true
                        label.Text = text or "Loading…"
                        if Config.MotionEnabled() then
                                Animator.Tween(layer, { BackgroundTransparency = 0.35 }, 0.2)
                                Animator.Tween(card, { GroupTransparency = 0 }, 0.2)
                        else
                                layer.BackgroundTransparency = 0.35
                                card.GroupTransparency = 0
                        end
                        startLoops()
                end,
                Hide = function()
                        stopLoops()
                        if Config.MotionEnabled() then
                                Animator.Tween(layer, { BackgroundTransparency = 1 }, 0.2)
                                Animator.Tween(card, { GroupTransparency = 1 }, 0.2)
                                task.delay(0.22, function()
                                        layer.Visible = false
                                        card.GroupTransparency = 0
                                        layer.BackgroundTransparency = 1
                                end)
                        else
                                layer.Visible = false
                        end
                end,
                SetText = function(_, text)
                        label.Text = text or ""
                end,
                Destroy = function()
                        stopLoops()
                        layer:Destroy()
                end,
        }
end

return Feedback
