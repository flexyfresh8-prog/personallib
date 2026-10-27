--@module LiquidGlass/Core/Config
--[[
	LiquidGlass · Core/Config
	Central configuration. Every module reads runtime settings from here.
	Change values through LiquidGlass:Configure({ ... }) at runtime.
]]

local Config = {
	Version = "1.0.0",

	-- Appearance ------------------------------------------------------------
	DefaultTheme = "Midnight", -- Midnight | Arctic | Aurora | Sunset | Obsidian | custom

	-- Quality ----------------------------------------------------------------
	-- "High"     : every effect enabled (shine sweeps, ripples, orbit particles)
	-- "Balanced" : interactive effects only, no idle loops
	-- "Low"      : all decorative effects off, instant transitions
	Quality = "High",
	ReducedMotion = false, -- accessibility: kills all animation
	DragMomentum = true,   -- restrained inertia after releasing a drag
	ShowFPS = false,       -- fps readout in the status bar
	EnableCommandPalette = true,
	ToggleKey = Enum.KeyCode.RightShift,

	-- Window -----------------------------------------------------------------
	Window = {
		Size = UDim2.fromOffset(720, 480),
		MinSize = Vector2.new(560, 400),
		MaximizeMargin = 16,
		CornerRadius = 16,
		SidebarWidth = 176,
		CompactSidebarWidth = 58,
		Margin = 22, -- shadow bleed around the panel
	},

	-- Animation ---------------------------------------------------------------
	Animation = {
		Speed = 1, -- global duration multiplier
		Fast = 0.15,
		Default = 0.25,
		Slow = 0.45,
		Easing = Enum.EasingStyle.Quint,
	},

	-- Spring presets ------------------------------------------------------------
	Spring = {
		Default = { Stiffness = 190, Damping = 13 }, -- gentle overshoot
		Soft = { Stiffness = 120, Damping = 17 },    -- smooth settle
		Snappy = { Stiffness = 340, Damping = 20 },  -- quick compress/rebound
		Pop = { Stiffness = 260, Damping = 12 },     -- playful pop
	},

	-- Notifications ---------------------------------------------------------------
	Notify = {
		MaxVisible = 5,
		DefaultDuration = 4,
		Width = 300,
		Margin = 18,
	},

	Tooltips = {
		Delay = 0.35,
	},
}

-- Quality rank: 0 = low, 1 = balanced, 2 = high ----------------------------------
function Config.QualityRank()
	if Config.Quality == "Low" then
		return 0
	elseif Config.Quality == "Balanced" then
		return 1
	end
	return 2
end

-- Decorative/idle effects (shine sweeps, orbit particles, loops) allowed? --------
function Config.EffectsEnabled()
	return Config.QualityRank() >= 1 and not Config.ReducedMotion
end

-- Should anything animate at all? --------------------------------------------------
function Config.MotionEnabled()
	return not Config.ReducedMotion and Config.Quality ~= "Low"
end

-- Scale a duration by the global speed, collapsing to 0 when motion is off --------
function Config.T(duration)
	if not Config.MotionEnabled() then
		return 0
	end
	return duration * Config.Animation.Speed
end

-- Merge user overrides --------------------------------------------------------------
local DEEP_KEYS = { Window = true, Animation = true, Spring = true, Notify = true, Tooltips = true }

function Config.Apply(overrides)
	for key, value in pairs(overrides or {}) do
		if DEEP_KEYS[key] then
			for innerKey, innerValue in pairs(value) do
				Config[key][innerKey] = innerValue
			end
		else
			Config[key] = value
		end
	end
	return Config
end

return Config
