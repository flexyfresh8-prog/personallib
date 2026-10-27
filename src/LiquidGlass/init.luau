--@module LiquidGlass
--[[
	██████╗ ██╗  ██╗██╗   ██╗██████╗ ███████╗██████╗ ██╗
	██╔══██╗██║  ██║██║   ██║██╔══██╗██╔════╝██╔══██╗██║
	██████╔╝███████║██║   ██║██████╔╝█████╗  ██║  ██║██║
	██╔═══╝ ██╔══██║██║   ██║██╔══██╗██╔══╝  ██║  ██║██║
	██║     ██║  ██║╚██████╔╝██║  ██║███████╗██████╔╝██║
	╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═════╝ ╚═╝

	LiquidGlass · Premium Roblox GUI Library
	Apple-inspired Liquid Glass design language for Roblox.

	Quick start:
		local LiquidGlass = require(path.to.LiquidGlass)
		local Window = LiquidGlass:CreateWindow({
			Title = "LiquidGlass",
			Subtitle = "Premium Interface",
			Theme = "Midnight",
			AnimationStyle = "Spring",
		})
		local Tab = Window:CreateTab({ Name = "General", Icon = "⌂" })
		Tab:CreateButton({ Name = "Hello", Callback = function() print("hi") end })
]]

local Config = require(script.Core.Config)
local Themes = require(script.Core.Themes)
local Util = require(script.Core.Util)
local Animator = require(script.Core.Animator)
local WindowClass = require(script.Window)
local Notify = require(script.Notify)

local LiquidGlass = {}
LiquidGlass.Version = Config.Version
LiquidGlass.Config = Config
LiquidGlass.Themes = Themes
LiquidGlass._windows = {}

--====================================================================================
-- API
--====================================================================================

--[[
	LiquidGlass:CreateWindow(config)
	config:
		Title        string   = "LiquidGlass"
		Subtitle     string   = nil
		Size         UDim2    = 720 x 480
		Position     UDim2    = centered (offsets only)
		Theme        string|table  = "Midnight" | theme name | overrides table
		Accent       Color3   = nil (override accent)
		Accent2      Color3   = nil (secondary accent for gradients)
		Icon         string|number = nil (glyph or rbxassetid)
		ToggleKey    Enum.KeyCode = RightShift
		Compact      bool     = false (icon-only sidebar)
		ShowOnCreate bool     = true
		CloseBehavior string  = "Hide" | "Destroy"
		NotificationCenter bool = true (bell button)
	Returns a Window object.
]]
function LiquidGlass:CreateWindow(cfg)
	cfg = cfg or {}
	local window = WindowClass.new(cfg)
	table.insert(self._windows, window)
	if cfg.ShowOnCreate ~= false then
		window:Show()
	end
	return window
end

-- Runtime configuration --------------------------------------------------------------
function LiquidGlass:Configure(overrides)
	return Config.Apply(overrides)
end

function LiquidGlass:SetQuality(quality)
	assert(quality == "High" or quality == "Balanced" or quality == "Low",
		"[LiquidGlass] Quality must be High, Balanced or Low")
	Config.Quality = quality
	return self
end

function LiquidGlass:SetReducedMotion(enabled)
	Config.ReducedMotion = enabled == true
	return self
end

-- Themes ------------------------------------------------------------------------------
function LiquidGlass:RegisterTheme(name, overrides)
	Themes.Register(name, overrides)
	return self
end

function LiquidGlass:GetThemeNames()
	return Themes.Names()
end

-- Global notifications (outside any window theme) --------------------------------------
function LiquidGlass:Notify(cfg)
	return Notify.Show(cfg, nil)
end

-- Cleanup --------------------------------------------------------------------------------
function LiquidGlass:GetWindows()
	return self._windows
end

function LiquidGlass:DestroyAll()
	for _, window in ipairs(Util.ShallowCopy(self._windows)) do
		window:Destroy()
	end
	self._windows = {}
end

return LiquidGlass
