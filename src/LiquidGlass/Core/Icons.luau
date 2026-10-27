--@module LiquidGlass/Core/Icons
--[[
	LiquidGlass · Core/Icons
	Icon system. Two supported formats everywhere an `Icon` is accepted:
	  1. A glyph string, e.g. Icon = "⌂" or Icon = "✦" (rendered as text)
	  2. An image, e.g. Icon = "rbxassetid://123456789" or Icon = 123456789
	Plus reliable vector icons drawn with frames for system glyphs
	(check / cross / alert / info / chevron / minus / square / search ...) that
	never depend on font coverage.
]]

local Icons = {}

-- Curated glyph set (monochrome, broad font coverage) --------------------------------
Icons.Glyph = {
	House = "⌂",
	Settings = "⚙",
	Star = "✦",
	Gem = "◈",
	Grid = "⌗",
	Half = "◐",
	Circle = "●",
	Ring = "○",
	Target = "◎",
	Flag = "⚑",
	Pin = "⌖",
	Layers = "▤",
	Chart = "▥",
	Zap = " ✳",
	Fire = "▲",
	Moon = "☾",
	Sun = "☀",
	Key = "⚿",
	Lock = "🛡",
	Eye = "◉",
}

-- Vector icon drawing (font-independent) ----------------------------------------------
-- Returns the container frame; parent and position it as you like.
local function bar(container, color, thickness, len, x, y, rotation)
	local part = Instance.new("Frame")
	part.BackgroundColor3 = color
	part.BorderSizePixel = 0
	part.AnchorPoint = Vector2.new(0.5, 0.5)
	part.Position = UDim2.fromScale(x, y)
	part.Size = UDim2.fromOffset(thickness, math.max(2, len))
	part.Rotation = rotation
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = part
	part.Parent = container
	return part
end

function Icons.Vector(kind, parent, size, color, thickness)
	thickness = thickness or math.max(2, math.floor(size / 7))
	local container = Instance.new("Frame")
	container.Name = "Vector_" .. kind
	container.BackgroundTransparency = 1
	container.Size = UDim2.fromOffset(size, size)
	container.Parent = parent

	if kind == "check" then
		bar(container, color, thickness, size * 0.30, 0.375, 0.635, -45)
		bar(container, color, thickness, size * 0.55, 0.615, 0.52, 45)
	elseif kind == "cross" then
		bar(container, color, thickness, size * 0.72, 0.5, 0.5, 45)
		bar(container, color, thickness, size * 0.72, 0.5, 0.5, -45)
	elseif kind == "alert" then
		bar(container, color, thickness, size * 0.42, 0.5, 0.36, 0)
		local dot = bar(container, color, thickness + 1, thickness + 1, 0.5, 0.74, 0)
		dot.Size = UDim2.fromOffset(thickness + 1, thickness + 1)
	elseif kind == "info" then
		local dot = bar(container, color, thickness + 1, thickness + 1, 0.5, 0.22, 0)
		dot.Size = UDim2.fromOffset(thickness + 1, thickness + 1)
		bar(container, color, thickness, size * 0.42, 0.5, 0.6, 0)
	elseif kind == "minus" then
		bar(container, color, thickness, size * 0.6, 0.5, 0.5, 90)
	elseif kind == "square" then
		local box = Instance.new("Frame")
		box.BackgroundColor3 = color
		box.BackgroundTransparency = 1
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(0.5, 0.5)
		box.Size = UDim2.fromOffset(size * 0.52, size * 0.52)
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = thickness
		stroke.Parent = box
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, math.floor(size / 8))
		corner.Parent = box
		box.Parent = container
	elseif kind == "chevron" then
		bar(container, color, thickness, size * 0.42, 0.355, 0.42, -45)
		bar(container, color, thickness, size * 0.42, 0.645, 0.42, 45)
	elseif kind == "plus" then
		bar(container, color, thickness, size * 0.6, 0.5, 0.5, 90)
		bar(container, color, thickness, size * 0.6, 0.5, 0.5, 0)
	elseif kind == "search" then
		local lens = Instance.new("Frame")
		lens.BackgroundColor3 = color
		lens.BackgroundTransparency = 1
		lens.Size = UDim2.fromOffset(size * 0.55, size * 0.55)
		lens.Position = UDim2.fromScale(0.06, 0.06)
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = thickness
		stroke.Parent = lens
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = lens
		lens.Parent = container
		bar(container, color, thickness, size * 0.32, 0.72, 0.72, 45)
	elseif kind == "dot" then
		local dot = Instance.new("Frame")
		dot.BackgroundColor3 = color
		dot.BorderSizePixel = 0
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5, 0.5)
		dot.Size = UDim2.fromOffset(size, size)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = dot
		dot.Parent = container
	end
	return container
end

-- Normalize an icon spec to ("glyph", text) or ("image", id) ---------------------------
function Icons.Parse(spec)
	if spec == nil then
		return nil
	end
	if type(spec) == "number" then
		return { Kind = "image", Value = spec }
	end
	if type(spec) == "string" then
		if string.find(spec, "rbxassetid", 1, true) or string.find(spec, "rbxthumb", 1, true) then
			return { Kind = "image", Value = spec }
		end
		return { Kind = "glyph", Value = spec }
	end
	return nil
end

return Icons
