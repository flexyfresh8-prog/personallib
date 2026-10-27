--@module LiquidGlass/Components/Advanced
--[[
        LiquidGlass · Components/Advanced
        CreateContextMenu · CreateCommandPalette (Ctrl+K) · CreateDock
        CreateFAB · CreateRadialMenu
        All functions accept a window OR a tab as their first argument.
]]

local Config = require(script.Parent.Parent.Core.Config)
local Util = require(script.Parent.Parent.Core.Util)
local Animator = require(script.Parent.Parent.Core.Animator)
local Elements = require(script.Parent.Parent.Core.Elements)
local Icons = require(script.Parent.Parent.Core.Icons)

local UserInputService = game:GetService("UserInputService")

local Advanced = {}

local function toWindow(obj)
        return obj._Window or obj
end

local Display_tooltip -- forward declaration (dock hover tooltips)

--====================================================================================
-- CONTEXT MENU
--====================================================================================

function Advanced.CreateContextMenu(obj, target, cfg)
        cfg = cfg or {}
        local window = toWindow(obj)
        local ctx = window._ctx
        local panel = window._panel
        local janitor = Util.NewJanitor()
        window._janitor:Add(janitor)

        local menu = Util.New("Frame", {
                Name = "ContextMenu",
                BackgroundColor3 = ctx.Color("Surface"),
                BackgroundTransparency = 0.04,
                BorderSizePixel = 0,
                Size = UDim2.fromOffset(190, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                Visible = false,
                ZIndex = 46,
                Parent = panel,
        })
        Util.Corner(menu, 10)
        Util.Stroke(menu, ctx.Color("Stroke"), 0.3, 1)
        local grad = Util.VerticalGradient(menu, ctx.Theme.ShadeTop, ctx.Theme.ShadeBottom)
        ctx.TintGradient(grad, "ShadeTop", "ShadeBottom")
        Util.Padding(menu, 4, 4, 4, 4)

        local catcher = Util.New("TextButton", {
                Name = "Catcher",
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 1, 0),
                Text = "",
                AutoButtonColor = false,
                Visible = false,
                ZIndex = 45,
                Parent = panel,
        })

        local function buildItems()
                for _, child in ipairs(menu:GetChildren()) do
                        if child:IsA("TextButton") or child:IsA("Frame") then
                                child:Destroy()
                        end
                end
                local index = 0
                for _, item in ipairs(cfg.Items or {}) do
                        index = index + 1
                        if item.Divider then
                                local line = Util.New("Frame", {
                                        Name = "Divider",
                                        BackgroundColor3 = ctx.Color("Divider"),
                                        BackgroundTransparency = 0.3,
                                        Size = UDim2.new(1, 0, 0, 1),
                                        LayoutOrder = index,
                                        BorderSizePixel = 0,
                                        Parent = menu,
                                })
                                ctx.Tint(line, "BackgroundColor3", "Divider")
                        else
                                local btn = Util.New("TextButton", {
                                        Name = "Item_" .. (item.Name or index),
                                        BackgroundColor3 = ctx.Color("SurfaceHigh"),
                                        BackgroundTransparency = 1,
                                        Size = UDim2.new(1, 0, 0, 30),
                                        Text = "",
                                        AutoButtonColor = false,
                                        LayoutOrder = index,
                                        Parent = menu,
                                })
                                Util.Corner(btn, 7)
                                local label = Util.New("TextLabel", {
                                        BackgroundTransparency = 1,
                                        Position = UDim2.new(0, 10, 0, 0),
                                        Size = UDim2.new(1, -20, 1, 0),
                                        Font = Enum.Font.Gotham,
                                        Text = item.Name or "?",
                                        TextColor3 = ctx.Color("TextSecondary"),
                                        TextSize = 12,
                                        TextXAlignment = Enum.TextXAlignment.Left,
                                        Parent = btn,
                                })
                                ctx.Tint(label, "TextColor3", "TextSecondary")
                                btn.MouseEnter:Connect(function()
                                        Animator.Tween(btn, { BackgroundTransparency = 0.5 })
                                        Animator.Tween(label, { TextColor3 = ctx.Color("TextPrimary") }, 0.12)
                                end)
                                btn.MouseLeave:Connect(function()
                                        Animator.Tween(btn, { BackgroundTransparency = 1 })
                                        Animator.Tween(label, { TextColor3 = ctx.Color("TextSecondary") }, 0.12)
                                end)
                                btn.Activated:Connect(function()
                                        menuObj:Close()
                                        if item.Callback then
                                                task.spawn(item.Callback)
                                        end
                                end)
                        end
                end
        end

        local menuObj
        menuObj = {
                Open = function(_, position)
                        buildItems()
                        catcher.Visible = true
                        menu.Visible = true
                        local pos = position or Util.MouseLocation()
                        local panelAbs = panel.AbsolutePosition
                        local x = Util.Clamp(pos.X - panelAbs.X + 2, 4, panel.AbsoluteSize.X - 200)
                        local y = Util.Clamp(pos.Y - panelAbs.Y + 2, 4, panel.AbsoluteSize.Y - menu.AbsoluteSize.Y - 8)
                        menu.Position = UDim2.fromOffset(x, y)
                        -- staggered item entrance
                        if Config.EffectsEnabled() then
                                local delay = 0.02
                                for _, child in ipairs(menu:GetChildren()) do
                                        if child:IsA("TextButton") then
                                                child.BackgroundTransparency = 1
                                                for _, lbl in ipairs(child:GetChildren()) do
                                                        if lbl:IsA("TextLabel") then
                                                                lbl.TextTransparency = 1
                                                                local l = lbl
                                                                task.delay(delay, function()
                                                                        Animator.Tween(l, { TextTransparency = 0 }, 0.15)
                                                                end)
                                                        end
                                                end
                                                Animator.Tween(child, { BackgroundTransparency = 1 }, 0.1)
                                                delay = delay + 0.025
                                        end
                                end
                        end
                end,
                Close = function()
                        catcher.Visible = false
                        menu.Visible = false
                end,
                Destroy = function()
                        janitor:Clean()
                        catcher:Destroy()
                        menu:Destroy()
                end,
        }

        janitor:Add(target.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton2 then
                        menuObj:Open()
                end
        end))
        janitor:Add(catcher.Activated:Connect(function()
                menuObj:Close()
        end))
        janitor:Add(function()
                catcher:Destroy()
                menu:Destroy()
        end)

        return menuObj
end

--====================================================================================
-- COMMAND PALETTE
--====================================================================================

function Advanced.CreateCommandPalette(obj)
        local window = toWindow(obj)
        local ctx = window._ctx
        local panel = window._panel
        local janitor = Util.NewJanitor()
        window._janitor:Add(janitor)

        local overlay = Util.New("TextButton", {
                Name = "PaletteOverlay",
                BackgroundColor3 = ctx.Color("Overlay"),
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 1, 0),
                Text = "",
                AutoButtonColor = false,
                Visible = false,
                ZIndex = 55,
                Parent = panel,
        })

        local palette = Util.New("CanvasGroup", {
                Name = "CommandPalette",
                BackgroundColor3 = ctx.Color("Surface"),
                BackgroundTransparency = 0.03,
                AnchorPoint = Vector2.new(0.5, 0),
                Position = UDim2.new(0.5, 0, 0, 60),
                Size = UDim2.fromOffset(460, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BorderSizePixel = 0,
                GroupTransparency = 1,
                ZIndex = 56,
                Parent = overlay,
        })
        Util.Corner(palette, 12)
        Util.Stroke(palette, ctx.Color("Stroke"), 0.3, 1)
        local grad = Util.VerticalGradient(palette, ctx.Theme.ShadeTop, ctx.Theme.ShadeBottom)
        ctx.TintGradient(grad, "ShadeTop", "ShadeBottom")

        local searchField = Util.New("TextBox", {
                Name = "Search",
                BackgroundColor3 = ctx.Color("Track"),
                Position = UDim2.new(0, 10, 0, 10),
                Size = UDim2.new(1, -20, 0, 32),
                Font = Enum.Font.Gotham,
                Text = "",
                PlaceholderText = "Type a command…",
                PlaceholderColor3 = ctx.Color("TextMuted"),
                TextColor3 = ctx.Color("TextPrimary"),
                TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Left,
                ClearTextOnFocus = false,
                Parent = palette,
        })
        Util.Corner(searchField, 8)
        local searchStroke = Util.Stroke(searchField, ctx.Color("InnerStroke"), 0.4, 1)
        ctx.Tint(searchField, "BackgroundColor3", "Track")
        Util.Padding(searchField, 0, 10, 0, 10)

        local list = Util.New("ScrollingFrame", {
                Name = "List",
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 10, 0, 48),
                Size = UDim2.new(1, -20, 0, 0),
                CanvasSize = UDim2.new(0, 0, 0, 0),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollingDirection = Enum.ScrollingDirection.Y,
                ScrollBarThickness = 2,
                ScrollBarImageColor3 = ctx.Color("Scroller"),
                Parent = palette,
        })
        Util.List(list, 2)

        local isOpen = false
        local filtered = {}
        local selected = 1
        local itemButtons = {}

        local function rebuild(query)
                query = string.lower(query or "")
                filtered = {}
                for _, cmd in ipairs(window:GetCommands()) do
                        if query == "" or string.find(string.lower(cmd.Name or ""), query, 1, true) then
                                table.insert(filtered, cmd)
                        end
                end
                if #filtered > 8 then
                        -- trim displayed, keep full list scrollable
                end
                selected = Util.Clamp(selected, 1, math.max(#filtered, 1))

                for _, child in ipairs(list:GetChildren()) do
                        if child:IsA("TextButton") then
                                child:Destroy()
                        end
                end
                itemButtons = {}
                for i, cmd in ipairs(filtered) do
                        local btn = Util.New("TextButton", {
                                Name = "Cmd_" .. (cmd.Name or i),
                                BackgroundColor3 = ctx.Color("SurfaceHigh"),
                                BackgroundTransparency = (i == selected) and 0.4 or 1,
                                Size = UDim2.new(1, 0, 0, 30),
                                Text = "",
                                AutoButtonColor = false,
                                LayoutOrder = i,
                                Parent = list,
                        })
                        Util.Corner(btn, 7)
                        local label = Util.New("TextLabel", {
                                BackgroundTransparency = 1,
                                Position = UDim2.new(0, 10, 0, 0),
                                Size = UDim2.new(1, -20, 1, 0),
                                Font = Enum.Font.Gotham,
                                Text = cmd.Name or "?",
                                TextColor3 = (i == selected) and ctx.Color("TextPrimary") or ctx.Color("TextSecondary"),
                                TextSize = 12,
                                TextXAlignment = Enum.TextXAlignment.Left,
                                TextTruncate = Enum.TextTruncate.AtEnd,
                                Parent = btn,
                        })
                        ctx.Tint(label, "TextColor3", "TextSecondary")
                        itemButtons[i] = { button = btn, label = label }
                        btn.MouseEnter:Connect(function()
                                selected = i
                                refresh()
                        end)
                        btn.Activated:Connect(function()
                                runCommand(i)
                        end)
                end
                list.Size = UDim2.new(1, -20, 0, math.min(#filtered * 32, 240))
        end

        local function refresh()
                for i, entry in ipairs(itemButtons) do
                        Animator.Tween(entry.button, { BackgroundTransparency = (i == selected) and 0.4 or 1 }, 0.1)
                        Animator.Tween(entry.label, { TextColor3 = (i == selected) and ctx.Color("TextPrimary") or ctx.Color("TextSecondary") }, 0.1)
                end
        end

        local function runCommand(i)
                local cmd = filtered[i]
                paletteObj:Close()
                if cmd and cmd.Callback then
                        task.spawn(cmd.Callback)
                end
        end

        local function moveSelection(delta)
                if #filtered == 0 then
                        return
                end
                selected = Util.Clamp(selected + delta, 1, #filtered)
                refresh()
        end

        local paletteScale = Util.New("UIScale", { Scale = 0.96, Parent = palette })

        local paletteObj
        paletteObj = {
                Open = function()
                        if isOpen then
                                return
                        end
                        isOpen = true
                        overlay.Visible = true
                        rebuild("")
                        searchField.Text = ""
                        selected = 1
                        Animator.Tween(overlay, { BackgroundTransparency = 0.3 }, 0.15)
                        Animator.Tween(palette, { GroupTransparency = 0 }, 0.15)
                        Animator.Spring(paletteScale, "Scale", 1, Config.Spring.Pop)
                        task.defer(function()
                                if searchField.Parent then
                                        searchField:CaptureFocus()
                                end
                        end)
                end,
                Close = function()
                        if not isOpen then
                                return
                        end
                        isOpen = false
                        Animator.Tween(overlay, { BackgroundTransparency = 1 }, 0.12)
                        Animator.Tween(palette, { GroupTransparency = 1 }, 0.12)
                        Animator.Spring(paletteScale, "Scale", 0.96, Config.Spring.Soft)
                        task.delay(0.14, function()
                                if not isOpen and overlay.Parent then
                                        overlay.Visible = false
                                end
                        end)
                end,
                Toggle = function()
                        if isOpen then
                                paletteObj.Close()
                        else
                                paletteObj.Open()
                        end
                end,
                Destroy = function()
                        janitor:Clean()
                        overlay:Destroy()
                end,
        }

        janitor:Add(searchField:GetPropertyChangedSignal("Text"):Connect(function()
                selected = 1
                rebuild(searchField.Text)
        end))
        janitor:Add(searchField.FocusLost:Connect(function(enterPressed)
                if enterPressed then
                        runCommand(selected)
                end
        end))
        janitor:Add(UserInputService.InputBegan:Connect(function(input)
                if not isOpen then
                        return
                end
                local key = input.KeyCode
                if key == Enum.KeyCode.Escape then
                        paletteObj.Close()
                elseif key == Enum.KeyCode.Up then
                        moveSelection(-1)
                elseif key == Enum.KeyCode.Down then
                        moveSelection(1)
                elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
                        runCommand(selected)
                end
        end))
        janitor:Add(overlay.Activated:Connect(function()
                paletteObj.Close()
        end))

        -- Ctrl+K binding
        if Config.EnableCommandPalette then
                janitor:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
                        if gameProcessed or UserInputService:GetFocusedTextBox() then
                                return
                        end
                        if input.KeyCode == Enum.KeyCode.K
                                and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
                                        or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
                                paletteObj.Toggle()
                        end
                end))
        end

        return paletteObj
end

--====================================================================================
-- DOCK
--====================================================================================

function Advanced.CreateDock(obj, cfg)
        cfg = cfg or {}
        local window = toWindow(obj)
        local ctx = window._ctx
        local janitor = Util.NewJanitor()
        window._janitor:Add(janitor)

        local dock = Util.New("CanvasGroup", {
                Name = "Dock",
                BackgroundColor3 = ctx.Color("Surface"),
                BackgroundTransparency = 0.1,
                AnchorPoint = Vector2.new(0.5, 1),
                Position = UDim2.new(0.5, 0, 1, 60),
                Size = UDim2.fromOffset(60 + #cfg.Items * 46, 52),
                BorderSizePixel = 0,
                GroupTransparency = 0,
                ZIndex = 30,
                Parent = window._root,
        })
        Util.Corner(dock, 26)
        Util.Stroke(dock, ctx.Color("InnerStroke"), 0.25, 1)
        local grad = Util.VerticalGradient(dock, ctx.Theme.ShadeTop, ctx.Theme.ShadeBottom)
        ctx.TintGradient(grad, "ShadeTop", "ShadeBottom")
        Util.Padding(dock, 0, 6, 0, 6)
        Util.New("UIListLayout", {
                Padding = UDim.new(0, 6),
                FillDirection = Enum.FillDirection.Horizontal,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                HorizontalAlignment = Enum.HorizontalAlignment.Center,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Parent = dock,
        })

        for i, item in ipairs(cfg.Items or {}) do
                local btn = Util.New("TextButton", {
                        Name = "Dock_" .. (item.Name or i),
                        BackgroundColor3 = ctx.Color("SurfaceHigh"),
                        BackgroundTransparency = 0.5,
                        Size = UDim2.fromOffset(40, 40),
                        Text = "",
                        AutoButtonColor = false,
                        LayoutOrder = i,
                        Parent = dock,
                })
                Util.Corner(btn, 20)
                local btnScale = Util.New("UIScale", { Scale = 1, Parent = btn })
                local iconSpec = Icons.Parse(item.Icon)
                if iconSpec and iconSpec.Kind == "image" then
                        Util.New("ImageLabel", {
                                Image = iconSpec.Value,
                                BackgroundTransparency = 1,
                                Size = UDim2.fromOffset(18, 18),
                                Position = UDim2.new(0.5, -9, 0.5, -9),
                                ImageColor3 = ctx.Color("TextSecondary"),
                                Parent = btn,
                        })
                elseif iconSpec then
                        Util.New("TextLabel", {
                                BackgroundTransparency = 1,
                                Size = UDim2.new(1, 0, 1, 0),
                                Font = Enum.Font.Gotham,
                                Text = iconSpec.Value,
                                TextColor3 = ctx.Color("TextSecondary"),
                                TextSize = 16,
                                Parent = btn,
                        })
                end
                btn.MouseEnter:Connect(function()
                        Animator.Spring(btnScale, "Scale", 1.22, Config.Spring.Pop)
                        Animator.Tween(btn, { BackgroundTransparency = 0.15 })
                        if item.Name then
                                Display_tooltip(window, btn, item.Name)
                        end
                end)
                btn.MouseLeave:Connect(function()
                        Animator.Spring(btnScale, "Scale", 1, Config.Spring.Pop)
                        Animator.Tween(btn, { BackgroundTransparency = 0.5 })
                end)
                btn.Activated:Connect(function()
                        Elements.Ripple(ctx, btn)
                        if item.Callback then
                                task.spawn(item.Callback)
                        end
                end)
        end

        -- entrance
        task.defer(function()
                Animator.Tween(dock, { Position = UDim2.new(0.5, 0, 1, -16) }, 0.5, Enum.EasingStyle.Back)
        end)

        local dockObj = {
                Frame = dock,
                Show = function()
                        dock.Visible = true
                        Animator.Tween(dock, { Position = UDim2.new(0.5, 0, 1, -16) }, 0.45, Enum.EasingStyle.Back)
                end,
                Hide = function()
                        Animator.Tween(dock, { Position = UDim2.new(0.5, 0, 1, 60) }, 0.3)
                end,
                Destroy = function()
                        janitor:Clean()
                        dock:Destroy()
                end,
        }
        return dockObj
end

function Display_tooltip(window, host, text)
        -- lightweight inline tooltip for dock items
        local layer = window._ctx.TooltipLayer
        if not layer or not Config.EffectsEnabled() then
                return
        end
        local bubble = Util.New("CanvasGroup", {
                Name = "DockTooltip",
                BackgroundColor3 = window._ctx.Color("SurfaceHigh"),
                BackgroundTransparency = 0.08,
                BorderSizePixel = 0,
                GroupTransparency = 1,
                ZIndex = 50,
                Parent = layer,
        })
        Util.Corner(bubble, 8)
        Util.Stroke(bubble, window._ctx.Color("Stroke"), 0.25, 1)
        local label = Util.New("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 1, 0),
                Font = Enum.Font.Gotham,
                Text = text,
                TextColor3 = window._ctx.Color("TextPrimary"),
                TextSize = 11,
                Parent = bubble,
        })
        task.defer(function()
                local hostAbs = host.AbsolutePosition
                local layerAbs = layer.AbsolutePosition
                bubble.Size = UDim2.fromOffset(math.max(label.TextBounds.X + 20, 40), 24)
                local w = bubble.AbsoluteSize.X
                local x = Util.Clamp(hostAbs.X - layerAbs.X + host.AbsoluteSize.X / 2 - w / 2, 8, layer.AbsoluteSize.X - w - 8)
                bubble.Position = UDim2.fromOffset(x, hostAbs.Y - layerAbs.Y - 32)
                Animator.Tween(bubble, { GroupTransparency = 0 }, 0.12)
        end)
        task.delay(1.4, function()
                if bubble.Parent then
                        Animator.Tween(bubble, { GroupTransparency = 1 }, 0.15)
                        task.delay(0.16, function()
                                bubble:Destroy()
                        end)
                end
        end)
end

--====================================================================================
-- FLOATING ACTION BUTTON
--====================================================================================

function Advanced.CreateFAB(obj, cfg)
        cfg = cfg or {}
        local window = toWindow(obj)
        local ctx = window._ctx
        local janitor = Util.NewJanitor()
        window._janitor:Add(janitor)

        local fab = Util.New("TextButton", {
                Name = "FAB",
                BackgroundColor3 = ctx.Color("Accent"),
                AnchorPoint = Vector2.new(1, 1),
                Position = cfg.Position or UDim2.new(1, -26, 1, -26),
                Size = UDim2.fromOffset(52, 52),
                Text = "",
                AutoButtonColor = false,
                BorderSizePixel = 0,
                ZIndex = 30,
                Parent = window._root,
        })
        Util.Corner(fab, 26)
        local grad = Util.VerticalGradient(fab, ctx.Color("Accent"), ctx.Color("Accent2"))
        ctx.TintGradient(grad, "Accent", "Accent2")
        local glow = Util.Stroke(fab, ctx.Color("Accent"), 0.55, 2)
        ctx.Tint(glow, "Color", "Accent")
        local fabScale = Util.New("UIScale", { Scale = 1, Parent = fab })

        local iconSpec = Icons.Parse(cfg.Icon)
        if iconSpec and iconSpec.Kind == "image" then
                Util.New("ImageLabel", {
                        Image = iconSpec.Value,
                        BackgroundTransparency = 1,
                        Size = UDim2.fromOffset(22, 22),
                        Position = UDim2.new(0.5, -11, 0.5, -11),
                        ImageColor3 = ctx.Color("OnAccent"),
                        Parent = fab,
                })
        elseif iconSpec then
                Util.New("TextLabel", {
                        BackgroundTransparency = 1,
                        Size = UDim2.new(1, 0, 1, 0),
                        Font = Enum.Font.GothamBold,
                        Text = iconSpec.Value,
                        TextColor3 = ctx.Color("OnAccent"),
                        TextSize = 20,
                        Parent = fab,
                })
        else
                Elements.VectorIcon(ctx, "plus", fab, 20, "OnAccent", 2.4)
        end

        -- idle glow pulse (High quality only)
        if Config.EffectsEnabled() then
                local t = 0
                Animator.Loop(function(dt)
                        t = t + dt
                        glow.Thickness = 2 + math.sin(t * 2.2) * 1.2
                        glow.Transparency = 0.5 + (math.sin(t * 2.2) + 1) * 0.2
                end, janitor)
        end

        janitor:Add(fab.MouseEnter:Connect(function()
                Animator.Spring(fabScale, "Scale", 1.08, Config.Spring.Pop)
        end))
        janitor:Add(fab.MouseLeave:Connect(function()
                Animator.Spring(fabScale, "Scale", 1, Config.Spring.Pop)
        end))
        janitor:Add(fab.Activated:Connect(function()
                Elements.Ripple(ctx, fab)
                if cfg.Callback then
                        task.spawn(cfg.Callback)
                end
        end))

        return {
                Frame = fab,
                Destroy = function()
                        janitor:Clean()
                        fab:Destroy()
                end,
        }
end

--====================================================================================
-- RADIAL MENU
--====================================================================================

function Advanced.CreateRadialMenu(obj, cfg)
        cfg = cfg or {}
        local window = toWindow(obj)
        local ctx = window._ctx
        local panel = window._panel
        local items = cfg.Items or {}
        local radius = cfg.Radius or 84
        local janitor = Util.NewJanitor()
        window._janitor:Add(janitor)

        local layer = Util.New("TextButton", {
                Name = "RadialLayer",
                BackgroundColor3 = ctx.Color("Overlay"),
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 1, 0),
                Text = "",
                AutoButtonColor = false,
                Visible = false,
                ZIndex = 58,
                Parent = panel,
        })

        local hub = Util.New("Frame", {
                Name = "Hub",
                BackgroundColor3 = ctx.Color("Accent"),
                AnchorPoint = Vector2.new(0.5, 0.5),
                Size = UDim2.fromOffset(42, 42),
                BorderSizePixel = 0,
                ZIndex = 59,
                Parent = layer,
        })
        Util.Corner(hub, 21)
        local hubGrad = Util.VerticalGradient(hub, ctx.Color("Accent"), ctx.Color("Accent2"))
        ctx.TintGradient(hubGrad, "Accent", "Accent2")
        Elements.VectorIcon(ctx, "cross", hub, 14, "OnAccent", 2.4)

        local itemButtons = {}
        for i, item in ipairs(items) do
                local btn = Util.New("TextButton", {
                        Name = "Radial_" .. (item.Name or i),
                        BackgroundColor3 = ctx.Color("Surface"),
                        BackgroundTransparency = 0.05,
                        AnchorPoint = Vector2.new(0.5, 0.5),
                        Size = UDim2.fromOffset(48, 48),
                        Text = "",
                        AutoButtonColor = false,
                        BorderSizePixel = 0,
                        ZIndex = 59,
                        Parent = layer,
                })
                Util.Corner(btn, 24)
                Util.Stroke(btn, ctx.Color("Stroke"), 0.25, 1)
                local btnScale = Util.New("UIScale", { Scale = 1, Parent = btn })
                local iconSpec = Icons.Parse(item.Icon)
                if iconSpec and iconSpec.Kind == "image" then
                        Util.New("ImageLabel", {
                                Image = iconSpec.Value,
                                BackgroundTransparency = 1,
                                Size = UDim2.fromOffset(20, 20),
                                Position = UDim2.new(0.5, -10, 0.5, -10),
                                ImageColor3 = ctx.Color("TextPrimary"),
                                Parent = btn,
                        })
                elseif iconSpec then
                        Util.New("TextLabel", {
                                BackgroundTransparency = 1,
                                Size = UDim2.new(1, 0, 1, 0),
                                Font = Enum.Font.GothamBold,
                                Text = iconSpec.Value,
                                TextColor3 = ctx.Color("TextPrimary"),
                                TextSize = 17,
                                Parent = btn,
                        })
                end
                btn.MouseEnter:Connect(function()
                        Animator.Spring(btnScale, "Scale", 1.16, Config.Spring.Pop)
                        Animator.Tween(btn, { BackgroundColor3 = ctx.Color("SurfaceHigh") }, 0.12)
                end)
                btn.MouseLeave:Connect(function()
                        Animator.Spring(btnScale, "Scale", 1, Config.Spring.Pop)
                        Animator.Tween(btn, { BackgroundColor3 = ctx.Color("Surface") }, 0.12)
                end)
                btn.Activated:Connect(function()
                        radialObj:Close()
                        if item.Callback then
                                task.spawn(item.Callback)
                        end
                end)
                table.insert(itemButtons, btn)
        end

        local isOpen = false
        local radialObj
        radialObj = {
                Open = function(_, position)
                        if isOpen then
                                return
                        end
                        isOpen = true
                        layer.Visible = true
                        local pos = position or Util.MouseLocation()
                        local center = UDim2.fromOffset(
                                Util.Clamp(pos.X - panel.AbsolutePosition.X, 110, panel.AbsoluteSize.X - 110),
                                Util.Clamp(pos.Y - panel.AbsolutePosition.Y, 110, panel.AbsoluteSize.Y - 110))

                        Animator.Tween(layer, { BackgroundTransparency = 0.25 }, 0.15)
                        hub.Position = center
                        hub.Size = UDim2.fromOffset(8, 8)

                        for i, btn in ipairs(itemButtons) do
                                local angle = (-90 + (i - 1) * (360 / math.max(#itemButtons, 1))) * math.pi / 180
                                local target = UDim2.fromOffset(
                                        center.X.Offset + math.cos(angle) * radius,
                                        center.Y.Offset + math.sin(angle) * radius)
                                btn.Position = center
                                Animator.Tween(btn, { Position = target }, 0.35, Enum.EasingStyle.Back)
                        end
                        -- spring hub size properly (Size is UDim2 -> animate via tween)
                        Animator.Tween(hub, { Size = UDim2.fromOffset(42, 42) }, 0.3, Enum.EasingStyle.Back)
                end,
                Close = function()
                        if not isOpen then
                                return
                        end
                        isOpen = false
                        Animator.Tween(layer, { BackgroundTransparency = 1 }, 0.15)
                        for _, btn in ipairs(itemButtons) do
                                Animator.Tween(btn, { Position = hub.Position }, 0.2)
                        end
                        task.delay(0.22, function()
                                if not isOpen and layer.Parent then
                                        layer.Visible = false
                                end
                        end)
                end,
                Toggle = function()
                        if isOpen then
                                radialObj.Close()
                        else
                                radialObj.Open()
                        end
                end,
                Destroy = function()
                        janitor:Clean()
                        layer:Destroy()
                end,
        }

        janitor:Add(layer.Activated:Connect(function()
                radialObj.Close()
        end))
        janitor:Add(UserInputService.InputBegan:Connect(function(input)
                if isOpen and input.KeyCode == Enum.KeyCode.Escape then
                        radialObj.Close()
                end
        end))

        return radialObj
end

return Advanced
