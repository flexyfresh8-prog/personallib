--@module LiquidGlass/Window
--[[
        LiquidGlass · Window
        Complete window manager: materialize/contract open-close animations,
        dragging with momentum + edge snapping, resizing, minimize-to-pill,
        maximize, floating glass sidebar with spring tab indicator, status bar,
        live theme re-tinting, z-order focus, command registration.

        Create via LiquidGlass:CreateWindow({ ... }) — never call Window.new directly.
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Core.Config)
local Themes = require(script.Parent.Core.Themes)
local Util = require(script.Parent.Core.Util)
local Animator = require(script.Parent.Core.Animator)
local Elements = require(script.Parent.Core.Elements)
local Shine = require(script.Parent.Effects.Shine)
local Notify = require(script.Parent.Notify)
local TabClass = require(script.Parent.Tab)
local Feedback = require(script.Parent.Components.Feedback)

local Window = {}
Window.__index = Window

local windowCount = 0
local allWindows = {}

local M = Config.Window.Margin

--====================================================================================
-- CONSTRUCTION
--====================================================================================

function Window.new(cfg)
        cfg = cfg or {}
        windowCount = windowCount + 1

        local self = setmetatable({}, Window)
        self._tabs = {}
        self._commands = {}
        self._tintables = {}
        self._gradientTints = {}
        self._janitor = Util.NewJanitor()
        self._theme = Themes.Resolve(cfg.Theme or Config.DefaultTheme)
        self._accent = cfg.Accent
        self._accent2 = cfg.Accent2
        self._state = "closed"
        self._minimized = false
        self._maximized = false
        self._destroyed = false
        self._toggleKey = cfg.ToggleKey or Config.ToggleKey
        self._notifHistory = {}
        self._title = cfg.Title or "LiquidGlass"
        self._subtitle = cfg.Subtitle

        -- context shared by every component of this window -------------------------------
        local ctx = {}
        ctx.Window = self
        ctx.Theme = self._theme
        ctx.Janitor = self._janitor
        ctx.TooltipLayer = nil -- assigned below
        function ctx.Color(key)
                if key == "Accent" and self._accent then
                        return self._accent
                end
                if key == "Accent2" and self._accent2 then
                        return self._accent2
                end
                return self._theme[key]
        end
        function ctx.Tint(inst, prop, key)
                inst[prop] = ctx.Color(key)
                table.insert(self._tintables, { inst = inst, prop = prop, key = key })
        end
        function ctx.TintGradient(grad, topKey, bottomKey)
                Util.VerticalGradientRebuild(grad, ctx.Color(topKey), ctx.Color(bottomKey))
                table.insert(self._gradientTints, { grad = grad, topKey = topKey or "ShadeTop", bottomKey = bottomKey or "ShadeBottom" })
        end
        function ctx.Quality()
                return Config.Quality
        end
        function ctx.Motion()
                return Config.MotionEnabled()
        end
        self._ctx = ctx

        -- sizing -------------------------------------------------------------------------
        local size = cfg.Size or Config.Window.Size
        local smallScreen = Util.IsSmallViewport()
        if smallScreen then
                local cam = game:GetService("Workspace").CurrentCamera.ViewportSize
                size = UDim2.fromOffset(math.min(size.Width.Offset, cam.X - 48), math.min(size.Height.Offset, cam.Y - 48))
                self._compact = true
        else
                self._compact = cfg.Compact == true
        end
        self._size = size

        -- screen gui ----------------------------------------------------------------------
        local gui = Util.New("ScreenGui", {
                Name = "LiquidGlass_" .. self._title,
                ResetOnSpawn = false,
                ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
                IgnoreGuiInset = true,
                DisplayOrder = 1000 + windowCount * 10,
        })
        gui.Parent = Util.GetGuiParent()
        self._gui = gui

        -- root (dragged/resized container; includes shadow bleed) --------------------------
        local root = Util.New("Frame", {
                Name = "Root",
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, cfg.Position and cfg.Position.X.Offset or 0, 0.5, cfg.Position and cfg.Position.Y.Offset or 0),
                Size = UDim2.new(0, size.Width.Offset + M * 2, 0, size.Height.Offset + M * 2),
                Visible = false,
                Parent = gui,
        })
        self._root = root

        -- soft layered shadows --------------------------------------------------------------
        for _, shadowSpec in ipairs({
                { Off = 10, T = 0.72, Grow = 8 },
                { Off = 4, T = 0.6, Grow = 2 },
        }) do
                local shadow = Util.New("Frame", {
                        Name = "Shadow",
                        BackgroundColor3 = ctx.Color("Shadow"),
                        BackgroundTransparency = shadowSpec.T,
                        BorderSizePixel = 0,
                        Position = UDim2.new(0, M - shadowSpec.Grow / 2, 0, M - shadowSpec.Grow / 2 + shadowSpec.Off / 2),
                        Size = UDim2.new(1, -(M * 2) + shadowSpec.Grow, 1, -(M * 2) + shadowSpec.Grow),
                        ZIndex = 0,
                        Parent = root,
                })
                Util.Corner(shadow, Config.Window.CornerRadius + 10)
                ctx.Tint(shadow, "BackgroundColor3", "Shadow")
        end

        -- the glass panel (CanvasGroup -> whole-window fades) --------------------------------
        local panel = Util.New("CanvasGroup", {
                Name = "Panel",
                BackgroundColor3 = ctx.Color("Background"),
                BackgroundTransparency = 0.04,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(M, M),
                Size = UDim2.new(1, -M * 2, 1, -M * 2),
                GroupTransparency = 0,
                ClipsDescendants = true,
                Parent = root,
        })
        Util.Corner(panel, Config.Window.CornerRadius)
        ctx.Tint(panel, "BackgroundColor3", "Background")
        local panelGrad = Util.VerticalGradient(panel, self._theme.ShadeTop, self._theme.ShadeBottom)
        ctx.TintGradient(panelGrad, "ShadeTop", "ShadeBottom")
        local scale = Util.New("UIScale", { Scale = 1, Parent = panel })
        self._panel = panel
        self._scale = scale

        local glow = Util.Stroke(panel, ctx.Color("Accent"), 0.62, 1.4)
        ctx.Tint(glow, "Color", "Accent")
        self._glow = glow

        -- top edge light ----------------------------------------------------------------------
        local topLight = Util.New("Frame", {
                Name = "TopLight",
                BackgroundColor3 = ctx.Color("Highlight"),
                BackgroundTransparency = ctx.Theme.HighlightT + 0.04,
                Position = UDim2.new(0, 14, 0, 1),
                Size = UDim2.new(1, -28, 0, 1),
                BorderSizePixel = 0,
                ZIndex = 3,
                Parent = panel,
        })
        ctx.Tint(topLight, "BackgroundColor3", "Highlight")

        self:_buildTopBar(cfg)
        self:_buildBody()
        self:_buildStatusBar()

        -- tooltip layer (above pages, below dialogs) -------------------------------------------
        local tooltipLayer = Util.New("Frame", {
                Name = "TooltipLayer",
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 1, 0),
                ZIndex = 40,
                Parent = panel,
        })
        ctx.TooltipLayer = tooltipLayer

        self._sweep = Shine.Bind(panel, self._janitor)

        self:_setupDrag()
        self:_setupResize(cfg)
        self:_setupToggleKey()

        table.insert(allWindows, self)
        return self
end

--====================================================================================
-- TOP BAR
--====================================================================================

function Window:_buildTopBar(cfg)
        local ctx = self._ctx
        local topBar = Util.New("Frame", {
                Name = "TopBar",
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 48),
                ZIndex = 5,
                Parent = self._panel,
        })
        self._topBar = topBar

        local dot = Util.New("Frame", {
                Name = "AccentDot",
                BackgroundColor3 = ctx.Color("Accent"),
                BackgroundTransparency = 0.1,
                Size = UDim2.fromOffset(9, 9),
                Position = UDim2.new(0, 18, 0.5, -4.5),
                BorderSizePixel = 0,
                Parent = topBar,
        })
        Util.Corner(dot, 5)
        ctx.Tint(dot, "BackgroundColor3", "Accent")

        self._titleLabel = Util.New("TextLabel", {
                Name = "Title",
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 36, 0, 0),
                Size = UDim2.new(0.5, -40, 1, 0),
                Font = Enum.Font.GothamBold,
                Text = self._title,
                TextColor3 = ctx.Color("TextPrimary"),
                TextSize = 15,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = topBar,
        })
        ctx.Tint(self._titleLabel, "TextColor3", "TextPrimary")

        if self._subtitle then
                self._subtitleLabel = Util.New("TextLabel", {
                        Name = "Subtitle",
                        BackgroundTransparency = 1,
                        AnchorPoint = Vector2.new(1, 0.5),
                        Position = UDim2.new(1, -170, 0.5, 0),
                        Size = UDim2.new(0.3, 0, 1, 0),
                        Font = Enum.Font.Gotham,
                        Text = self._subtitle,
                        TextColor3 = ctx.Color("TextMuted"),
                        TextSize = 11,
                        TextXAlignment = Enum.TextXAlignment.Right,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                        Parent = topBar,
                })
                ctx.Tint(self._subtitleLabel, "TextColor3", "TextMuted")
        end

        -- window controls ---------------------------------------------------------------------
        local function circleButton(name, offsetX, kind, hoverColorKey)
                local btn = Util.New("TextButton", {
                        Name = name,
                        BackgroundColor3 = ctx.Color("SurfaceHigh"),
                        BackgroundTransparency = 1,
                        Size = UDim2.fromOffset(26, 26),
                        AnchorPoint = Vector2.new(0, 0.5),
                        Position = UDim2.new(1, offsetX, 0.5, 0),
                        Text = "",
                        AutoButtonColor = false,
                        BorderSizePixel = 0,
                        Parent = topBar,
                })
                Util.Corner(btn, 13)
                Elements.VectorIcon(ctx, kind, btn, 12, "TextSecondary", 2)
                self._janitor:Add(btn.MouseEnter:Connect(function()
                        Animator.Tween(btn, { BackgroundTransparency = 0.25, BackgroundColor3 = ctx.Color(hoverColorKey or "SurfaceHigh") })
                end))
                self._janitor:Add(btn.MouseLeave:Connect(function()
                        Animator.Tween(btn, { BackgroundTransparency = 1 })
                end))
                return btn
        end

        local closeBtn = circleButton("Close", -40, "cross", "Danger")
        local maxBtn = circleButton("Maximize", -70, "square")
        local minBtn = circleButton("Minimize", -100, "minus")
        local bellBtn = nil
        if cfg.NotificationCenter ~= false then
                bellBtn = Util.New("TextButton", {
                        Name = "Notifications",
                        BackgroundColor3 = ctx.Color("SurfaceHigh"),
                        BackgroundTransparency = 1,
                        Size = UDim2.fromOffset(26, 26),
                        AnchorPoint = Vector2.new(0, 0.5),
                        Position = UDim2.new(1, -130, 0.5, 0),
                        Text = "◔",
                        Font = Enum.Font.GothamBold,
                        TextSize = 14,
                        TextColor3 = ctx.Color("TextSecondary"),
                        AutoButtonColor = false,
                        BorderSizePixel = 0,
                        Parent = topBar,
                })
                Util.Corner(bellBtn, 13)
                ctx.Tint(bellBtn, "TextColor3", "TextSecondary")
                self._janitor:Add(bellBtn.MouseEnter:Connect(function()
                        Animator.Tween(bellBtn, { BackgroundTransparency = 0.25 })
                end))
                self._janitor:Add(bellBtn.MouseLeave:Connect(function()
                        Animator.Tween(bellBtn, { BackgroundTransparency = 1 })
                end))
                self._janitor:Add(bellBtn.Activated:Connect(function()
                        Notify.ToggleCenter(self)
                end))
        end

        self._janitor:Add(closeBtn.Activated:Connect(function()
                self:_closeRequested()
        end))
        self._janitor:Add(minBtn.Activated:Connect(function()
                self:Minimize()
        end))
        self._janitor:Add(maxBtn.Activated:Connect(function()
                self:ToggleMaximize()
        end))
        self._closeBtn = closeBtn
end

--====================================================================================
-- BODY: FLOATING SIDEBAR + CONTENT
--====================================================================================

function Window:_buildBody()
        local ctx = self._ctx
        local sidebarW = self._compact and Config.Window.CompactSidebarWidth or Config.Window.SidebarWidth

        local body = Util.New("Frame", {
                Name = "Body",
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 0, 0, 48),
                Size = UDim2.new(1, 0, 1, -48 - 26),
                Parent = self._panel,
        })

        -- floating glass sidebar ---------------------------------------------------------------
        local sidebar = Util.New("Frame", {
                Name = "Sidebar",
                BackgroundColor3 = ctx.Color("Surface"),
                BackgroundTransparency = 0.2,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 10, 0, 10),
                Size = UDim2.new(0, sidebarW, 1, -20),
                ZIndex = 2,
                Parent = body,
        })
        Util.Corner(sidebar, 13)
        Util.Stroke(sidebar, ctx.Color("InnerStroke"), 0.3, 1)
        ctx.Tint(sidebar, "BackgroundColor3", "Surface")
        local sidebarGrad = Util.VerticalGradient(sidebar, self._theme.ShadeTop, self._theme.ShadeBottom)
        ctx.TintGradient(sidebarGrad, "ShadeTop", "ShadeBottom")
        self._sidebar = sidebar

        local tabList = Util.New("ScrollingFrame", {
                Name = "TabList",
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 6, 0, 8),
                Size = UDim2.new(1, -12, 1, -16),
                CanvasSize = UDim2.new(0, 0, 0, 0),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollingDirection = Enum.ScrollingDirection.Y,
                ScrollBarThickness = 2,
                ScrollBarImageColor3 = ctx.Color("Scroller"),
                ScrollBarImageTransparency = 0.4,
                Parent = sidebar,
        })
        Util.List(tabList, 4)
        self._tabList = tabList

        -- moving glass selection indicator -----------------------------------------------------
        local indicator = Util.New("Frame", {
                Name = "Indicator",
                BackgroundColor3 = ctx.Color("SurfaceHigh"),
                BackgroundTransparency = 0.35,
                Size = UDim2.new(1, -12, 0, 36),
                Position = UDim2.new(0, 6, 0, 0),
                BorderSizePixel = 0,
                ZIndex = 0,
                Visible = false,
                Parent = tabList,
        })
        Util.Corner(indicator, 9)
        Util.Stroke(indicator, ctx.Color("InnerStroke"), 0.4, 1)
        ctx.Tint(indicator, "BackgroundColor3", "SurfaceHigh")
        local indBar = Util.New("Frame", {
                Name = "IndicatorBar",
                BackgroundColor3 = ctx.Color("Accent"),
                BackgroundTransparency = 0.15,
                Size = UDim2.new(0, 3, 0, 14),
                Position = UDim2.new(0, 0, 0.5, -7),
                BorderSizePixel = 0,
                Parent = indicator,
        })
        Util.Corner(indBar, 2)
        ctx.Tint(indBar, "BackgroundColor3", "Accent")
        self._indicator = indicator

        -- content area --------------------------------------------------------------------------
        local content = Util.New("Frame", {
                Name = "Content",
                BackgroundTransparency = 1,
                Position = UDim2.new(0, sidebarW + 18, 0, 10),
                Size = UDim2.new(1, -(sidebarW + 28), 1, -20),
                ClipsDescendants = true,
                Parent = body,
        })
        self._content = content
end

--====================================================================================
-- STATUS BAR
--====================================================================================

function Window:_buildStatusBar()
        local ctx = self._ctx
        local bar = Util.New("Frame", {
                Name = "StatusBar",
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(0, 1),
                Position = UDim2.new(0, 0, 1, 0),
                Size = UDim2.new(1, 0, 0, 26),
                Parent = self._panel,
        })

        Util.New("Frame", {
                Name = "Divider",
                BackgroundColor3 = ctx.Color("Divider"),
                BackgroundTransparency = 0.25,
                Size = UDim2.new(1, 0, 0, 1),
                Position = UDim2.new(0, 0, 0, 0),
                BorderSizePixel = 0,
                Parent = bar,
        }).ZIndex = 4
        ctx.Tint(bar.Divider, "BackgroundColor3", "Divider")

        local themeDot = Util.New("Frame", {
                Name = "ThemeDot",
                BackgroundColor3 = ctx.Color("Accent"),
                Size = UDim2.fromOffset(6, 6),
                Position = UDim2.new(0, 14, 0.5, -3),
                BorderSizePixel = 0,
                Parent = bar,
        })
        Util.Corner(themeDot, 3)
        ctx.Tint(themeDot, "BackgroundColor3", "Accent")

        self._themeLabel = Util.New("TextLabel", {
                Name = "ThemeName",
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 26, 0, 0),
                Size = UDim2.new(0, 140, 1, 0),
                Font = Enum.Font.Gotham,
                Text = tostring(self._theme.Name or "Custom"),
                TextColor3 = ctx.Color("TextMuted"),
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = bar,
        })
        ctx.Tint(self._themeLabel, "TextColor3", "TextMuted")

        local right = Util.New("TextLabel", {
                Name = "Right",
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -12, 0, 0),
                Size = UDim2.new(0, 220, 1, 0),
                Font = Enum.Font.Gotham,
                Text = "LiquidGlass v" .. Config.Version,
                TextColor3 = ctx.Color("TextMuted"),
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Right,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = bar,
        })
        ctx.Tint(right, "TextColor3", "TextMuted")

        if Config.ShowFPS then
                local frames, seconds = 0, 0
                self._janitor:Add(RunService.Heartbeat:Connect(function(dt)
                        frames = frames + 1
                        seconds = seconds + dt
                        if seconds >= 0.5 then
                                right.Text = math.floor(frames / seconds + 0.5) .. " FPS · LiquidGlass v" .. Config.Version
                                frames, seconds = 0, 0
                        end
                end))
        end
end

--====================================================================================
-- DRAGGING (momentum + edge snapping) / RESIZING
--====================================================================================

local function clampRootPosition(root, position)
        local cam = game:GetService("Workspace").CurrentCamera
        if not cam then
                return position
        end
        local vp = cam.ViewportSize
        local halfW = root.AbsoluteSize.X / 2
        local halfH = root.AbsoluteSize.Y / 2
        local minX = math.min(140, vp.X / 2) - halfW + 60
        local maxX = vp.X / 2 - 140 + halfW - 60
        local minY = -(vp.Y / 2) + 80
        local maxY = vp.Y / 2 - 40
        local x = Util.Clamp(position.X.Offset, minX, maxX)
        local y = Util.Clamp(position.Y.Offset, minY, maxY)
        return UDim2.new(position.X.Scale, x, position.Y.Scale, y)
end

function Window:_setupDrag()
        local ctx = self._ctx
        local root = self._root
        local topBar = self._topBar
        local dragging = false
        local dragInput = nil
        local startPos = nil
        local startMouse = nil
        local lastSample = nil
        local velocity = Vector2.zero
        local momentumConn = nil

        self._janitor:Add(topBar.InputBegan:Connect(function(input)
                if input.UserInputType ~= Enum.UserInputType.MouseButton1
                        and input.UserInputType ~= Enum.UserInputType.Touch then
                        return
                end
                if self._minimized or self._maximized then
                        return
                end
                dragging = true
                dragInput = input
                startPos = root.Position
                startMouse = Vector2.new(input.Position.X, input.Position.Y)
                lastSample = { pos = startMouse, t = os.clock() }
                velocity = Vector2.zero
                self:Focus()
        end))

        self._janitor:Add(topBar.InputEnded:Connect(function(input)
                if input ~= dragInput then
                        return
                end
                dragging = false
                dragInput = nil

                -- restrained momentum -----------------------------------------------------------
                if Config.DragMomentum and Config.EffectsEnabled() and velocity.Magnitude > 150 then
                        local pos = root.Position
                        local v = velocity
                        local elapsed = 0
                        if momentumConn then
                                momentumConn:Disconnect()
                        end
                        momentumConn = RunService.Heartbeat:Connect(function(dt)
                                elapsed = elapsed + dt
                                pos = UDim2.new(pos.X.Scale, pos.X.Offset + v.X * dt, pos.Y.Scale, pos.Y.Offset + v.Y * dt)
                                root.Position = clampRootPosition(root, pos)
                                v = v * math.max(0, 1 - dt * 7)
                                if elapsed > 0.45 or v.Magnitude < 30 then
                                        self:_edgeSnap()
                                        momentumConn:Disconnect()
                                        momentumConn = nil
                                end
                        end)
                        self._janitor:Add(function()
                                if momentumConn then
                                        momentumConn:Disconnect()
                                        momentumConn = nil
                                end
                        end)
                else
                        self:_edgeSnap()
                end
        end))

        self._janitor:Add(UserInputService.InputChanged:Connect(function(input)
                if not dragging then
                        return
                end
                if input.UserInputType ~= Enum.UserInputType.MouseMovement
                        and input.UserInputType ~= Enum.UserInputType.Touch then
                        return
                end
                local mouse = Vector2.new(input.Position.X, input.Position.Y)
                local now = os.clock()
                if lastSample then
                        local dt = math.max(now - lastSample.t, 1 / 240)
                        velocity = (mouse - lastSample.pos) / dt * 0.65 + velocity * 0.35
                end
                lastSample = { pos = mouse, t = now }

                local delta = mouse - startMouse
                root.Position = clampRootPosition(root,
                        UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y))
        end))
end

-- Magnetic snap: align to screen edges when released close to them --------------------
function Window:_edgeSnap()
        local cam = game:GetService("Workspace").CurrentCamera
        if not cam then
                return
        end
        local vp = cam.ViewportSize
        local abs = self._root.AbsolutePosition
        local size = self._root.AbsoluteSize
        local current = self._root.Position
        local target = nil
        local margin = 12

        if abs.X < 18 then
                target = UDim2.new(0, margin + size.X / 2 - vp.X / 2, current.Y.Scale, current.Y.Offset)
        elseif abs.X + size.X > vp.X - 18 then
                target = UDim2.new(0, vp.X / 2 - margin - size.X / 2, current.Y.Scale, current.Y.Offset)
        elseif abs.Y < 18 then
                target = UDim2.new(current.X.Scale, current.X.Offset, 0, margin + size.Y / 2 - vp.Y / 2)
        end
        if target then
                Animator.Tween(self._root, { Position = target }, 0.3, Enum.EasingStyle.Back)
        end
end

function Window:_setupResize(cfg)
        if Util.IsTouch() and Util.IsSmallViewport() then
                return
        end
        local root = self._root
        local minW = Config.Window.MinSize.X + M * 2
        local minH = Config.Window.MinSize.Y + M * 2

        local function grip(width, height, anchor, position, cursor)
                local g = Util.New("Frame", {
                        Name = "ResizeGrip",
                        BackgroundTransparency = 1,
                        Size = UDim2.new(width.Scale, width.Offset, height.Scale, height.Offset),
                        AnchorPoint = anchor,
                        Position = position,
                        ZIndex = 8,
                        Parent = root,
                })
                return g
        end

        local cornerGrip = grip(UDim2.new(0, 20, 0, 20), Vector2.new(1, 1), UDim2.new(1, 0, 1, 0))
        local rightGrip = grip(UDim2.new(0, 8, 1, -20), Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, -10))
        local bottomGrip = grip(UDim2.new(1, -20, 0, 8), Vector2.new(0.5, 1), UDim2.new(0.5, -10, 1, 0))

        -- visible corner dots
        for i = 0, 2 do
                Util.New("Frame", {
                        Name = "GripDot",
                        BackgroundColor3 = self._ctx.Color("TextMuted"),
                        BackgroundTransparency = 0.5,
                        BorderSizePixel = 0,
                        Position = UDim2.new(1, -14 - i * 5, 1, -14 + i * 5),
                        Size = UDim2.fromOffset(3, 3),
                        Rotation = 45,
                        ZIndex = 9,
                        Parent = root,
                })
        end

        local function startResize(input, dirX, dirY)
                local startSize = root.Size
                local startMouse = Vector2.new(input.Position.X, input.Position.Y)
                local resizeConn
                local endConn
                resizeConn = UserInputService.InputChanged:Connect(function(changed)
                        if changed.UserInputType ~= Enum.UserInputType.MouseMovement
                                and changed.UserInputType ~= Enum.UserInputType.Touch then
                                return
                        end
                        local delta = Vector2.new(changed.Position.X - startMouse.X, changed.Position.Y - startMouse.Y)
                        local w = startSize.Width.Offset + (dirX and delta.X or 0)
                        local h = startSize.Height.Offset + (dirY and delta.Y or 0)
                        root.Size = UDim2.fromOffset(
                                math.max(minW, math.min(w, 2400)),
                                math.max(minH, math.min(h, 1600)))
                end)
                endConn = UserInputService.InputEnded:Connect(function(ended)
                        if ended.UserInputType == Enum.UserInputType.MouseButton1
                                or ended.UserInputType == Enum.UserInputType.Touch then
                                resizeConn:Disconnect()
                                endConn:Disconnect()
                        end
                end)
        end

        for _, spec in ipairs({
                { g = cornerGrip, x = true, y = true },
                { g = rightGrip, x = true, y = false },
                { g = bottomGrip, x = false, y = true },
        }) do
                self._janitor:Add(spec.g.InputBegan:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1
                                or input.UserInputType == Enum.UserInputType.Touch then
                                startResize(input, spec.x, spec.y)
                        end
                end))
        end
end

function Window:_setupToggleKey()
        self._janitor:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
                if gameProcessed then
                        return
                end
                if self._toggleKey and input.KeyCode == self._toggleKey then
                        self:Toggle()
                end
        end))
end

--====================================================================================
-- TABS
--====================================================================================

local function page_animate(page)
        page.Position = UDim2.new(0, 0, 0, 16)
        Animator.Tween(page, { Position = UDim2.new(0, 0, 0, 0) }, 0.35)
end

function Window:CreateTab(tabCfg)
        tabCfg = tabCfg or {}
        local ctx = self._ctx
        local index = #self._tabs + 1
        local name = tabCfg.Name or ("Tab " .. index)

        local btn = Util.New("TextButton", {
                Name = "Tab_" .. name,
                BackgroundColor3 = ctx.Color("SurfaceHigh"),
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 36),
                Text = "",
                AutoButtonColor = false,
                BorderSizePixel = 0,
                LayoutOrder = index,
                ZIndex = 1,
                Parent = self._tabList,
        })
        Util.Corner(btn, 9)

        local iconLabel = nil
        local iconSpec = nil
        if tabCfg.Icon ~= nil then
                iconSpec = require(script.Parent.Core.Icons).Parse(tabCfg.Icon)
        end
        if iconSpec then
                if iconSpec.Kind == "image" then
                        iconLabel = Util.New("ImageLabel", {
                                Name = "Icon",
                                Image = iconSpec.Value,
                                BackgroundTransparency = 1,
                                Size = UDim2.fromOffset(17, 17),
                                Position = UDim2.new(0, 11, 0.5, -8.5),
                                ImageColor3 = ctx.Color("TextSecondary"),
                                Parent = btn,
                        })
                        ctx.Tint(iconLabel, "ImageColor3", "TextSecondary")
                else
                        iconLabel = Util.New("TextLabel", {
                                Name = "Icon",
                                BackgroundTransparency = 1,
                                Text = iconSpec.Value,
                                Font = Enum.Font.Gotham,
                                TextSize = 14,
                                TextColor3 = ctx.Color("TextSecondary"),
                                Size = UDim2.fromOffset(20, 20),
                                Position = UDim2.new(0, 9, 0.5, -10),
                                Parent = btn,
                        })
                        ctx.Tint(iconLabel, "TextColor3", "TextSecondary")
                end
        end

        local label = Util.New("TextLabel", {
                Name = "Label",
                BackgroundTransparency = 1,
                Position = UDim2.new(0, iconSpec and 36 or 14, 0, 0),
                Size = UDim2.new(1, iconSpec and -44 or -24, 1, 0),
                Font = Enum.Font.GothamMedium,
                Text = name,
                TextColor3 = ctx.Color("TextSecondary"),
                TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Visible = not self._compact,
                Parent = btn,
        })
        ctx.Tint(label, "TextColor3", "TextSecondary")

        local page = Util.New("ScrollingFrame", {
                Name = "Page_" .. name,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 1, 0),
                Position = UDim2.new(0, 0, 0, 0),
                Visible = false,
                CanvasSize = UDim2.new(0, 0, 0, 0),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollingDirection = Enum.ScrollingDirection.Y,
                ScrollBarThickness = 3,
                ScrollBarImageColor3 = ctx.Color("Scroller"),
                ScrollBarImageTransparency = 0.4,
                Parent = self._content,
        })
        Util.List(page, 8)
        Util.Padding(page, 4, 12, 12, 12)

        local tab = setmetatable({
                _Window = self,
                _Ctx = ctx,
                _Page = page,
                _Order = 0,
                _Name = name,
                _Button = btn,
                _Label = label,
                _IconColor = iconLabel,
                _Index = index,
                _Controls = {},
                _Commands = {},
                _Janitor = Util.NewJanitor(),
        }, TabClass)

        table.insert(self._tabs, tab)

        self._janitor:Add(btn.MouseEnter:Connect(function()
                if self._selectedTab ~= index then
                        Animator.Tween(btn, { BackgroundTransparency = 0.7 })
                end
        end))
        self._janitor:Add(btn.MouseLeave:Connect(function()
                if self._selectedTab ~= index then
                        Animator.Tween(btn, { BackgroundTransparency = 1 })
                end
        end))
        self._janitor:Add(btn.Activated:Connect(function()
                self:SelectTab(index)
        end))

        if index == 1 then
                task.defer(function()
                        if not self._destroyed then
                                self:SelectTab(1)
                        end
                end)
        end
        return tab
end

function Window:SelectTab(index)
        local tabs = self._tabs
        if not tabs[index] then
                return
        end
        self._selectedTab = index

        for i, tab in ipairs(tabs) do
                local active = (i == index)
                tab._Page.Visible = active
                tab:_SetSelected(active)
                if active then
                        -- move the glass indicator under the selected tab
                        local btn = tab._Button
                        local y = btn.AbsolutePosition.Y - self._tabList.AbsolutePosition.Y + self._tabList.CanvasPosition.Y
                        self._indicator.Visible = true
                        Animator.Tween(self._indicator, { BackgroundTransparency = 0.35 }, 0.2)
                        Animator.SpringPositionY(self._indicator, 0, 6, y, Config.Spring.Soft)
                        -- slide page in from below + stagger the cards
                        if Config.MotionEnabled() then
                                page_animate(tab._Page)
                        end
                        Elements.RevealStagger(tab._Page)
                end
        end
end

function Window:GetTab(nameOrIndex)
        if type(nameOrIndex) == "number" then
                return self._tabs[nameOrIndex]
        end
        for _, tab in ipairs(self._tabs) do
                if tab._Name == nameOrIndex then
                        return tab
                end
        end
        return nil
end

--====================================================================================
-- LIFECYCLE: OPEN / CLOSE / MINIMIZE / MAXIMIZE
--====================================================================================

function Window:Show()
        if self._destroyed or self._state ~= "closed" then
                return
        end
        self._state = "open"
        self._minimized = false
        self._root.Visible = true

        if Config.MotionEnabled() then
                self._scale.Scale = 0.05
                self._panel.GroupTransparency = 1
                Animator.Spring(self._scale, "Scale", 1, { Stiffness = 220, Damping = 13 })
                Animator.Tween(self._panel, { GroupTransparency = 0 }, 0.32)
                self._glow.Thickness = 5
                self._glow.Transparency = 0.15
                Animator.Tween(self._glow, { Thickness = 1.4, Transparency = 0.62 }, 0.6)
                task.delay(0.15, function()
                        if not self._destroyed and self._sweep then
                                self._sweep()
                        end
                end)
        else
                self._scale.Scale = 1
                self._panel.GroupTransparency = 0
        end
end

function Window:_closeRequested()
        if self._closeBehavior == "Destroy" then
                self:Destroy()
        else
                self:Hide()
        end
end

function Window:Hide()
        if self._destroyed or self._state ~= "open" then
                return
        end
        self._state = "animating"
        local finished = false
        local function finish()
                if finished or self._destroyed then
                        return
                end
                finished = true
                self._root.Visible = false
                self._state = "closed"
                if self._minimizedPill then
                        self._minimizedPill:Destroy()
                        self._minimizedPill = nil
                end
                self._minimized = false
        end
        if Config.MotionEnabled() then
                Animator.Spring(self._scale, "Scale", 0.94, Config.Spring.Soft)
                Animator.Tween(self._panel, { GroupTransparency = 1 }, 0.2)
                task.delay(0.2, finish)
        else
                finish()
        end
end

function Window:Toggle()
        if self._state == "open" then
                self:Hide()
        else
                self:Show()
        end
end

function Window:Minimize()
        if self._destroyed or self._minimized then
                return
        end
        self._minimized = true

        -- collapse the panel
        if Config.MotionEnabled() then
                Animator.Spring(self._scale, "Scale", 0.05, { Stiffness = 260, Damping = 17 })
                Animator.Tween(self._panel, { GroupTransparency = 1 }, 0.25)
        end

        -- spawn a floating glass pill with the window title
        local ctx = self._ctx
        local pill = Util.New("TextButton", {
                Name = "MinimizedPill",
                BackgroundColor3 = ctx.Color("Surface"),
                BackgroundTransparency = 0.12,
                Size = UDim2.fromOffset(170, 38),
                Position = UDim2.new(0.5, -85, 1, 60),
                Text = "",
                AutoButtonColor = false,
                BorderSizePixel = 0,
                Parent = self._gui,
        })
        Util.Corner(pill, 19)
        Util.Stroke(pill, ctx.Color("InnerStroke"), 0.3, 1)
        local dot = Util.New("Frame", {
                BackgroundColor3 = ctx.Color("Accent"),
                Size = UDim2.fromOffset(8, 8),
                Position = UDim2.new(0, 14, 0.5, -4),
                BorderSizePixel = 0,
                Parent = pill,
        })
        Util.Corner(dot, 4)
        ctx.Tint(dot, "BackgroundColor3", "Accent")
        Util.New("TextLabel", {
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 30, 0, 0),
                Size = UDim2.new(1, -40, 1, 0),
                Font = Enum.Font.GothamMedium,
                Text = self._title,
                TextColor3 = ctx.Color("TextPrimary"),
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = pill,
        })

        local pillScale = Util.New("UIScale", { Scale = 1, Parent = pill })

        self._janitor:Add(pill.Activated:Connect(function()
                self:Restore()
        end))
        self._janitor:Add(pill.MouseEnter:Connect(function()
                Animator.Spring(pillScale, "Scale", 1.05, Config.Spring.Snappy)
        end))
        self._janitor:Add(pill.MouseLeave:Connect(function()
                Animator.Spring(pillScale, "Scale", 1, Config.Spring.Snappy)
        end))

        self._minimizedPill = {
                Frame = pill,
                Destroy = function()
                        Animator.Cancel(pill)
                        pill:Destroy()
                end,
        }

        -- spring the pill up from the bottom
        task.defer(function()
                Animator.Tween(pill, { Position = UDim2.new(0.5, -85, 1, -66) }, 0.45, Enum.EasingStyle.Back)
        end)
end

function Window:Restore()
        if self._destroyed or not self._minimized then
                return
        end
        self._minimized = false
        if self._minimizedPill then
                local pillControl = self._minimizedPill
                self._minimizedPill = nil
                if pillControl.Frame then
                        Animator.Tween(pillControl.Frame, { Position = UDim2.new(0.5, -85, 1, 60) }, 0.25)
                end
                task.delay(0.25, function()
                        pillControl:Destroy()
                end)
        end
        self._state = "open"
        self._root.Visible = true
        self._scale.Scale = 0.9
        self._panel.GroupTransparency = 1
        if Config.MotionEnabled() then
                Animator.Spring(self._scale, "Scale", 1, Config.Spring.Pop)
                Animator.Tween(self._panel, { GroupTransparency = 0 }, 0.25)
                if self._sweep then
                        task.delay(0.1, function()
                                if self._sweep then
                                        self._sweep()
                                end
                        end)
                end
        else
                self._scale.Scale = 1
                self._panel.GroupTransparency = 0
        end
end

function Window:ToggleMaximize()
        if self._destroyed or self._minimized then
                return
        end
        local root = self._root
        local cam = game:GetService("Workspace").CurrentCamera
        if not cam then
                return
        end
        local vp = cam.ViewportSize
        if not self._maximized then
                self._normalRect = { Position = root.Position, Size = root.Size }
                local margin = Config.Window.MaximizeMargin
                Animator.Tween(root, {
                        Size = UDim2.new(0, vp.X - margin * 2 - M * 2, 0, vp.Y - margin * 2 - M * 2),
                        Position = UDim2.new(0.5, 0, 0.5, 0),
                }, 0.35)
                self._maximized = true
        else
                local rect = self._normalRect or { Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, self._size.Width.Offset + M * 2, 0, self._size.Height.Offset + M * 2) }
                Animator.Tween(root, { Size = rect.Size, Position = rect.Position }, 0.35)
                self._maximized = false
        end
end

function Window:Focus()
        if self._destroyed then
                return
        end
        windowCount = windowCount + 1
        self._gui.DisplayOrder = 1000 + windowCount * 10
end

--====================================================================================
-- THEME / PROPERTIES
--====================================================================================

function Window:SetTheme(spec)
        if self._destroyed then
                return self
        end
        local theme = Themes.Resolve(spec)
        self._theme = theme
        self._ctx.Theme = theme
        self._themeLabel.Text = tostring(theme.Name or "Custom")

        for _, tintable in ipairs(self._tintables) do
                local ok = pcall(function()
                        Animator.Tween(tintable.inst, { [tintable.prop] = self._ctx.Color(tintable.key) }, 0.3)
                end)
                if not ok then
                        tintable.inst[tintable.prop] = self._ctx.Color(tintable.key)
                end
        end
        for _, g in ipairs(self._gradientTints) do
                Util.VerticalGradientRebuild(g.grad, theme[g.topKey], theme[g.bottomKey])
        end
        return self
end

function Window:SetAccent(color, color2)
        self._accent = color
        if color2 then
                self._accent2 = color2
        end
        for _, tintable in ipairs(self._tintables) do
                if tintable.key == "Accent" or tintable.key == "Accent2" then
                        pcall(function()
                                Animator.Tween(tintable.inst, { [tintable.prop] = self._ctx.Color(tintable.key) }, 0.3)
                        end)
                end
        end
        return self
end

function Window:SetTitle(text)
        self._title = text
        self._titleLabel.Text = text
        return self
end

function Window:SetSubtitle(text)
        self._subtitle = text
        if self._subtitleLabel then
                self._subtitleLabel.Text = text or ""
        end
        return self
end

function Window:SetCompact(compact)
        self._compact = compact
        local width = compact and Config.Window.CompactSidebarWidth or Config.Window.SidebarWidth
        Animator.Tween(self._sidebar, { Size = UDim2.new(0, width, 1, -20) }, 0.3)
        for _, tab in ipairs(self._tabs) do
                tab._Label.Visible = not compact
        end
        -- reflow content position
        local body = self._sidebar.Parent
        if body and body:FindFirstChild("Content") then
                Animator.Tween(body.Content, {
                        Position = UDim2.new(0, width + 18, 0, 10),
                        Size = UDim2.new(1, -(width + 28), 1, -20),
                }, 0.3)
        end
        return self
end

--====================================================================================
-- DELEGATED SYSTEMS
--====================================================================================

function Window:Notify(cfg)
        cfg = cfg or {}
        table.insert(self._notifHistory, {
                Title = cfg.Title or "Notification",
                Description = cfg.Description,
                Type = cfg.Type or "info",
                At = os.time(),
        })
        if #self._notifHistory > 40 then
                table.remove(self._notifHistory, 1)
        end
        return Notify.Show(cfg, self)
end

function Window:Dialog(cfg)
        return Feedback.Dialog(self, cfg)
end

function Window:Alert(cfg)
        cfg = cfg or {}
        cfg.Buttons = cfg.Buttons or { { Text = "OK", Primary = true } }
        return Feedback.Dialog(self, cfg)
end

function Window:RegisterCommand(cmd)
        table.insert(self._commands, cmd)
        return self
end

function Window:GetCommands()
        local list = {}
        for _, cmd in ipairs(self._commands) do
                table.insert(list, cmd)
        end
        for _, tab in ipairs(self._tabs) do
                for _, cmd in ipairs(tab._Commands or {}) do
                        table.insert(list, cmd)
                end
        end
        return list
end

function Window:Loading()
        return Feedback.Loading(self)
end

-- Advanced floating widgets (lazy-required to keep startup light) -----------------------
local function advancedModule()
        return require(script.Parent.Components.Advanced)
end

function Window:CommandPalette()
        if not self._palette then
                self._palette = advancedModule().CreateCommandPalette(self)
        end
        return self._palette
end

function Window:CreateContextMenu(target, cfg)
        return advancedModule().CreateContextMenu(self, target, cfg)
end

function Window:CreateDock(cfg)
        return advancedModule().CreateDock(self, cfg)
end

function Window:CreateFAB(cfg)
        return advancedModule().CreateFAB(self, cfg)
end

function Window:CreateRadialMenu(cfg)
        return advancedModule().CreateRadialMenu(self, cfg)
end

--====================================================================================
-- DESTROY
--====================================================================================

function Window:Destroy()
        if self._destroyed then
                return
        end
        self._destroyed = true

        for _, tab in ipairs(self._tabs) do
                pcall(function()
                        tab:Destroy()
                end)
        end
        if self._minimizedPill then
                pcall(function()
                        self._minimizedPill.Destroy()
                end)
        end
        if self._centerPanel then
                pcall(function()
                        self._centerPanel:Destroy()
                end)
        end
        Animator.Cancel(self._root)
        Animator.Cancel(self._panel)
        self._janitor:Clean()

        for i, win in ipairs(allWindows) do
                if win == self then
                        table.remove(allWindows, i)
                        break
                end
        end
        self._gui:Destroy()
end

function Window:IsDestroyed()
        return self._destroyed
end

function Window.GetWindows()
        return allWindows
end

return Window
