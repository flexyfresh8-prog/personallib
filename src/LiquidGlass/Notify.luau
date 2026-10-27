--@module LiquidGlass/Notify
--[[
	LiquidGlass · Notify
	Toast notifications (shared overlay, stack + glide animations) and the
	per-window Notification Center slide-in panel.
]]

local Config = require(script.Parent.Core.Config)
local Themes = require(script.Parent.Core.Themes)
local Util = require(script.Parent.Core.Util)
local Animator = require(script.Parent.Core.Animator)
local Elements = require(script.Parent.Core.Elements)

local Notify = {}

Notify._gui = nil
Notify._stack = {} -- oldest-last stack of active toasts

local TYPE_COLORS = {
	success = "Success",
	error = "Danger",
	danger = "Danger",
	warning = "Warning",
	warn = "Warning",
	info = "Accent",
}

local TYPE_ICONS = {
	success = "check",
	error = "cross",
	danger = "cross",
	warning = "alert",
	warn = "alert",
	info = "info",
}

--====================================================================================
-- SHARED OVERLAY GUI
--====================================================================================

local function EnsureGui()
	if Notify._gui and Notify._gui.Parent then
		return Notify._gui
	end
	local gui = Util.New("ScreenGui", {
		Name = "LiquidGlass_Toasts",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		DisplayOrder = 9000,
	})
	gui.Parent = Util.GetGuiParent()
	Notify._gui = gui
	return gui
end

--====================================================================================
-- TOASTS
--====================================================================================

function Notify.Show(cfg, window)
	cfg = cfg or {}
	local theme = (window and window._theme) or Themes.Get(Config.DefaultTheme)
	local ctxColor = function(key)
		return theme[key]
	end
	local gui = EnsureGui()
	local width = cfg.Width or Config.Notify.Width

	local toast = Util.New("CanvasGroup", {
		Name = "Toast",
		BackgroundColor3 = ctxColor("Surface"),
		BackgroundTransparency = 0.04,
		Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(1, 80, 0, Config.Notify.Margin),
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Parent = gui,
	})
	Util.Corner(toast, 14)
	Util.Stroke(toast, ctxColor("Stroke"), 0.4, 1)
	Util.VerticalGradient(toast, ctxColor("ShadeTop"), ctxColor("ShadeBottom"))

	local variantKey = TYPE_COLORS[string.lower(cfg.Type or "info")] or "Accent"
	local iconKind = TYPE_ICONS[string.lower(cfg.Type or "info")] or "info"

	-- icon badge
	local circle = Util.New("Frame", {
		Name = "IconBadge",
		BackgroundColor3 = ctxColor(variantKey),
		BackgroundTransparency = 0.86,
		Position = UDim2.new(0, 12, 0, 12),
		Size = UDim2.fromOffset(30, 30),
		BorderSizePixel = 0,
		Parent = toast,
	})
	Util.Corner(circle, 15)
	Util.Stroke(circle, ctxColor(variantKey), 0.45, 1)
	Elements.VectorIcon({ Color = ctxColor, Tint = function() end }, iconKind, circle, 15, variantKey, 2.2)

	local title = Util.New("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 52, 0, 10),
		Size = UDim2.new(1, -52 - 30, 0, 16),
		Font = Enum.Font.GothamMedium,
		Text = cfg.Title or "Notification",
		TextColor3 = ctxColor("TextPrimary"),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = toast,
	})

	local description = nil
	if cfg.Description then
		description = Util.New("TextLabel", {
			Name = "Description",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 52, 0, 28),
			Size = UDim2.new(1, -52 - 30, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Font = Enum.Font.Gotham,
			Text = cfg.Description,
			TextColor3 = ctxColor("TextSecondary"),
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			Parent = toast,
		})
	end

	-- close button
	local closeBtn = Util.New("TextButton", {
		Name = "Close",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(20, 20),
		Text = "",
		AutoButtonColor = false,
		Parent = toast,
	})
	Elements.VectorIcon({ Color = ctxColor, Tint = function() end }, "cross", closeBtn, 9, "TextMuted", 2)

	-- progress line
	local progressTrack = Util.New("Frame", {
		Name = "Progress",
		BackgroundColor3 = ctxColor("Track"),
		BackgroundTransparency = 0.2,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -6),
		Size = UDim2.new(1, -24, 0, 2),
		BorderSizePixel = 0,
		Parent = toast,
	})
	Util.Corner(progressTrack, 1)
	local progressFill = Util.New("Frame", {
		Name = "ProgressFill",
		BackgroundColor3 = ctxColor(variantKey),
		Size = UDim2.new(1, 0, 1, 0),
		BorderSizePixel = 0,
		Parent = progressTrack,
	})
	Util.Corner(progressFill, 1)

	Util.Padding(toast, 0, 0, 12, 0)

	local entry = { toast = toast, height = 60 }
	local dismissed = false

	local function relayout()
		local y = Config.Notify.Margin
		for _, e in ipairs(Notify._stack) do
			Animator.Tween(e.toast, { Position = UDim2.new(1, -Config.Notify.Margin, 0, y) }, 0.3, Enum.EasingStyle.Quint)
			y = y + (e.height or 60) + 8
		end
	end

	local function dismiss()
		if dismissed then
			return
		end
		dismissed = true
		for i, e in ipairs(Notify._stack) do
			if e == entry then
				table.remove(Notify._stack, i)
				break
			end
		end
		Animator.Tween(toast, { GroupTransparency = 1, Position = UDim2.new(1, 60, toast.Position.Y.Scale, toast.Position.Y.Offset) }, 0.22)
		task.delay(0.24, function()
			toast:Destroy()
		end)
		relayout()
	end

	closeBtn.Activated:Connect(dismiss)
	toast.MouseEnter:Connect(function()
		Animator.Tween(toast, { BackgroundTransparency = 0 }, 0.12)
	end)
	toast.MouseLeave:Connect(function()
		Animator.Tween(toast, { BackgroundTransparency = 0.04 }, 0.12)
	end)

	-- register & stack
	table.insert(Notify._stack, 1, entry)
	while #Notify._stack > Config.Notify.MaxVisible do
		local oldest = Notify._stack[#Notify._stack]
		if oldest and oldest.dismiss then
			oldest.dismiss()
		else
			table.remove(Notify._stack)
		end
	end

	-- enter animation
	task.defer(function()
		entry.height = toast.AbsoluteSize.Y
		toast.Position = UDim2.new(1, 80, 0, Config.Notify.Margin)
		Animator.Tween(toast, { GroupTransparency = 0 }, 0.25)
		relayout()
		-- progress countdown
		local duration = cfg.Duration
		if duration == nil then
			duration = Config.Notify.DefaultDuration
		end
		if duration and duration > 0 then
			if Config.MotionEnabled() then
				Animator.Tween(progressFill, { Size = UDim2.new(0, 0, 1, 0) }, duration, Enum.EasingStyle.Linear)
			end
			task.delay(duration, dismiss)
		end
	end)

	entry.dismiss = dismiss
	return {
		Dismiss = dismiss,
		Frame = toast,
	}
end

--====================================================================================
-- NOTIFICATION CENTER (per window)
--====================================================================================

local function formatAge(seconds)
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		return math.floor(seconds / 60) .. "m ago"
	else
		return math.floor(seconds / 3600) .. "h ago"
	end
end

function Notify.ToggleCenter(window)
	local ctx = window._ctx
	local panel = window._panel

	if window._centerOpen and window._centerPanel then
		window._centerOpen = false
		Animator.Tween(window._centerPanel.Frame, { Position = UDim2.new(1, 10, 0, 50) }, 0.3, Enum.EasingStyle.Quint)
		return
	end

	if not window._centerPanel then
		local body = Util.New("Frame", {
			Name = "NotifCenter",
			BackgroundColor3 = ctx.Color("Surface"),
			BackgroundTransparency = 0.08,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 10, 0, 50),
			Size = UDim2.new(0, 262, 1, -80),
			BorderSizePixel = 0,
			ZIndex = 45,
			Parent = panel,
		})
		Util.Corner(body, 12)
		Util.Stroke(body, ctx.Color("InnerStroke"), 0.3, 1)
		local grad = Util.VerticalGradient(body, ctx.Theme.ShadeTop, ctx.Theme.ShadeBottom)
		ctx.TintGradient(grad, "ShadeTop", "ShadeBottom")

		local header = Util.New("TextLabel", {
			Name = "Header",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 14, 0, 10),
			Size = UDim2.new(1, -90, 0, 18),
			Font = Enum.Font.GothamBold,
			Text = "Notifications",
			TextColor3 = ctx.Color("TextPrimary"),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = body,
		})
		ctx.Tint(header, "TextColor3", "TextPrimary")

		local clearBtn = Util.New("TextButton", {
			Name = "Clear",
			BackgroundColor3 = ctx.Color("SurfaceHigh"),
			BackgroundTransparency = 0.4,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 9),
			Size = UDim2.fromOffset(58, 22),
			Font = Enum.Font.GothamMedium,
			Text = "Clear",
			TextColor3 = ctx.Color("TextSecondary"),
			TextSize = 11,
			AutoButtonColor = false,
			Parent = body,
		})
		Util.Corner(clearBtn, 7)
		ctx.Tint(clearBtn, "BackgroundColor3", "SurfaceHigh")

		local list = Util.New("ScrollingFrame", {
			Name = "List",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 8, 0, 40),
			Size = UDim2.new(1, -16, 1, -48),
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = ctx.Color("Scroller"),
			BorderSizePixel = 0,
			Parent = body,
		})
		Util.List(list, 6)

		local function rebuild()
			for _, child in ipairs(list:GetChildren()) do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end
			if #window._notifHistory == 0 then
				local empty = Util.New("TextLabel", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 60),
					Font = Enum.Font.Gotham,
					Text = "No notifications yet",
					TextColor3 = ctx.Color("TextMuted"),
					TextSize = 12,
					LayoutOrder = 1,
					Parent = list,
				})
				ctx.Tint(empty, "TextColor3", "TextMuted")
				return
			end
			-- newest first
			for i = #window._notifHistory, 1, -1 do
				local entryData = window._notifHistory[i]
				local variantKey = TYPE_COLORS[string.lower(entryData.Type or "info")] or "Accent"
				local row = Util.New("Frame", {
					Name = "Notif_" .. i,
					BackgroundColor3 = ctx.Color("SurfaceHigh"),
					BackgroundTransparency = 0.55,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					LayoutOrder = #window._notifHistory - i,
					BorderSizePixel = 0,
					Parent = list,
				})
				Util.Corner(row, 8)
				ctx.Tint(row, "BackgroundColor3", "SurfaceHigh")

				local dot = Util.New("Frame", {
					BackgroundColor3 = ctx.Color(variantKey),
					Size = UDim2.fromOffset(6, 6),
					Position = UDim2.new(0, 10, 0, 12),
					BorderSizePixel = 0,
					Parent = row,
				})
				Util.Corner(dot, 3)
				ctx.Tint(dot, "BackgroundColor3", variantKey)

				local t = Util.New("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 24, 0, 6),
					Size = UDim2.new(1, -34, 0, 15),
					Font = Enum.Font.GothamMedium,
					Text = entryData.Title or "Notification",
					TextColor3 = ctx.Color("TextPrimary"),
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Parent = row,
				})
				ctx.Tint(t, "TextColor3", "TextPrimary")

				local age = Util.New("TextLabel", {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -10, 0, 7),
					Size = UDim2.fromOffset(60, 13),
					Font = Enum.Font.Gotham,
					Text = formatAge(os.time() - (entryData.At or os.time())),
					TextColor3 = ctx.Color("TextMuted"),
					TextSize = 10,
					TextXAlignment = Enum.TextXAlignment.Right,
					Parent = row,
				})
				ctx.Tint(age, "TextColor3", "TextMuted")

				if entryData.Description then
					local d = Util.New("TextLabel", {
						BackgroundTransparency = 1,
						Position = UDim2.new(0, 24, 0, 22),
						Size = UDim2.new(1, -34, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Font = Enum.Font.Gotham,
						Text = entryData.Description,
						TextColor3 = ctx.Color("TextSecondary"),
						TextSize = 11,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextWrapped = true,
						Parent = row,
					})
					ctx.Tint(d, "TextColor3", "TextSecondary")
					Util.Padding(row, 0, 0, 8, 0)
				else
					row.Size = UDim2.new(1, 0, 0, 34)
				end
			end
		end

		clearBtn.Activated:Connect(function()
			window._notifHistory = {}
			rebuild()
		end)

		window._centerPanel = {
			Frame = body,
			Rebuild = rebuild,
			Destroy = function()
				body:Destroy()
			end,
		}
	end

	window._centerOpen = true
	window._centerPanel.Rebuild()
	Animator.Tween(window._centerPanel.Frame, { Position = UDim2.new(1, -8, 0, 50) }, 0.35, Enum.EasingStyle.Back)
end

return Notify
