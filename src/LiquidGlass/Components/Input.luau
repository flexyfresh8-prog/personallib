--@module LiquidGlass/Components/Input
--[[
	LiquidGlass · Components/Input
	CreateTextInput · CreateSearchField
	Focus transitions illuminate the field; submitted/changed events provided.
]]

local Config = require(script.Parent.Parent.Core.Config)
local Util = require(script.Parent.Parent.Core.Util)
local Animator = require(script.Parent.Parent.Core.Animator)
local Elements = require(script.Parent.Parent.Core.Elements)
local Icons = require(script.Parent.Parent.Core.Icons)

local Input = {}

local function buildField(tab, cfg, isSearch)
	local ctx = tab._Ctx
	local card = tab:_AddCard({
		Name = cfg.Name,
		Tooltip = cfg.Tooltip,
		Height = 64,
	})

	local field = Util.New("Frame", {
		Name = "Field",
		BackgroundColor3 = ctx.Color("Track"),
		Position = UDim2.new(0, 12, 0, 26),
		Size = UDim2.new(1, -24, 0, 30),
		BorderSizePixel = 0,
		Parent = card.Frame,
	})
	Util.Corner(field, 8)
	local fieldStroke = Util.Stroke(field, ctx.Color("InnerStroke"), 0.4, 1)
	ctx.Tint(field, "BackgroundColor3", "Track")
	ctx.Tint(fieldStroke, "Color", "InnerStroke")

	local textBox = Util.New("TextBox", {
		Name = "Input",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, isSearch and 32 or 10, 0, 0),
		Size = UDim2.new(1, isSearch and -64 or -20, 1, 0),
		Font = Enum.Font.Gotham,
		Text = cfg.Default or "",
		PlaceholderText = cfg.Placeholder or (isSearch and "Search…" or "Type here…"),
		PlaceholderColor3 = ctx.Color("TextMuted"),
		TextColor3 = ctx.Color("TextPrimary"),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		ClipsDescendants = true,
		Parent = field,
	})
	ctx.Tint(textBox, "TextColor3", "TextPrimary")
	ctx.Tint(textBox, "PlaceholderColor3", "TextMuted")

	local changed = Util.Signal()
	local submitted = Util.Signal()

	if isSearch then
		Icons.Vector("search", field, 14, ctx.Color("TextMuted"), 2)
		local searchIcon = field:FindFirstChild("Vector_search")
		if searchIcon then
			searchIcon.Position = UDim2.new(0, 10, 0.5, -7)
			ctx.Tint(searchIcon:FindFirstChildOfClass("UIStroke"), "Color", "TextMuted")
		end

		local clearBtn = Util.New("TextButton", {
			Name = "Clear",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(22, 22),
			Text = "",
			AutoButtonColor = false,
			Visible = false,
			Parent = field,
		})
		Elements.VectorIcon(ctx, "cross", clearBtn, 9, "TextMuted", 2)
		clearBtn.Activated:Connect(function()
			textBox.Text = ""
			clearBtn.Visible = false
			changed:Fire("")
			if cfg.Callback then
				task.spawn(cfg.Callback, "")
			end
			textBox:CaptureFocus()
		end)
		textBox:GetPropertyChangedSignal("Text"):Connect(function()
			clearBtn.Visible = textBox.Text ~= ""
		end)
	end

	local function onFocus(state)
		if state then
			Animator.Tween(fieldStroke, { Color = ctx.Color("Accent"), Transparency = 0.05 }, 0.18)
			Animator.Tween(field, { BackgroundColor3 = ctx.Color("SurfaceHigh") }, 0.18)
		else
			Animator.Tween(fieldStroke, { Color = ctx.Color("InnerStroke"), Transparency = 0.4 }, 0.18)
			Animator.Tween(field, { BackgroundColor3 = ctx.Color("Track") }, 0.18)
		end
	end

	card.Janitor:Add(textBox.Focused:Connect(function()
		onFocus(true)
	end))
	card.Janitor:Add(textBox.FocusLost:Connect(function(enterPressed)
		onFocus(false)
		submitted:Fire(textBox.Text, enterPressed)
		if cfg.Callback then
			task.spawn(cfg.Callback, textBox.Text, enterPressed)
		end
	end))
	card.Janitor:Add(textBox:GetPropertyChangedSignal("Text"):Connect(function()
		changed:Fire(textBox.Text)
	end))

	return {
		Kind = isSearch and "SearchField" or "TextInput",
		Frame = card.Frame,
		Changed = changed,
		Submitted = submitted,
		Get = function()
			return textBox.Text
		end,
		Set = function(_, text)
			textBox.Text = tostring(text or "")
		end,
		Clear = function()
			textBox.Text = ""
		end,
		Focus = function()
			textBox:CaptureFocus()
		end,
		SetPlaceholder = function(_, text)
			textBox.PlaceholderText = tostring(text or "")
		end,
		Destroy = function()
			card:Destroy()
		end,
	}
end

function Input.CreateTextInput(tab, cfg)
	cfg = cfg or {}
	local control = buildField(tab, cfg, false)
	tab._Controls[cfg.Name or "TextInput"] = control
	return control
end

function Input.CreateSearchField(tab, cfg)
	cfg = cfg or {}
	local control = buildField(tab, cfg, true)
	tab._Controls[cfg.Name or "SearchField"] = control
	return control
end

return Input
