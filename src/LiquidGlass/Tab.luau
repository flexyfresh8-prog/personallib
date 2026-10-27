--@module LiquidGlass/Tab
--[[
	LiquidGlass · Tab
	A tab is one page inside a window's content area. Component modules
	register their Create* methods directly onto this class, so:
		tab:CreateButton({ ... }), tab:CreateToggle({ ... }), etc.
]]

local Util = require(script.Parent.Core.Util)
local Elements = require(script.Parent.Core.Elements)
local Animator = require(script.Parent.Core.Animator)
local Config = require(script.Parent.Core.Config)

local Controls = require(script.Parent.Components.Controls)
local Select = require(script.Parent.Components.Select)
local Input = require(script.Parent.Components.Input)
local Display = require(script.Parent.Components.Display)
local Feedback = require(script.Parent.Components.Feedback)
local Advanced = require(script.Parent.Components.Advanced)

local TabClass = {}
TabClass.__index = TabClass

-- Register every component factory as a tab method -----------------------------------
local function registerAll(module)
	for name, fn in pairs(module) do
		TabClass[name] = fn
	end
end
registerAll(Controls)
registerAll(Select)
registerAll(Input)
registerAll(Display)
registerAll(Feedback)
registerAll(Advanced)

--====================================================================================
-- INTERNALS
--====================================================================================

function TabClass:NextOrder()
	self._Order = self._Order + 1
	return self._Order
end

-- Convenience: build a glass card in this tab's page ---------------------------------
function TabClass:_AddCard(cfg)
	cfg = cfg or {}
	cfg.Order = cfg.Order or self:NextOrder()
	return Elements.GlassCard(self._Ctx, self._Page, cfg)
end

function TabClass:GetName()
	return self._Name
end

function TabClass:GetControls()
	return self._Controls
end

-- Select/highlight state driven by the window -----------------------------------------
function TabClass:_SetSelected(state)
	local ctx = self._Ctx
	local btn = self._Button
	if state then
		Animator.Tween(btn, { BackgroundTransparency = 0.35, BackgroundColor3 = ctx.Color("SurfaceHigh") })
		Animator.Tween(self._Label, { TextColor3 = ctx.Color("TextPrimary") })
		if self._IconColor then
			Animator.Tween(self._IconColor, { ImageColor3 = ctx.Color("Accent"), TextColor3 = ctx.Color("Accent") })
		end
	else
		Animator.Tween(btn, { BackgroundTransparency = 1 })
		Animator.Tween(self._Label, { TextColor3 = ctx.Color("TextSecondary") })
		if self._IconColor then
			Animator.Tween(self._IconColor, { ImageColor3 = ctx.Color("TextSecondary"), TextColor3 = ctx.Color("TextSecondary") })
		end
	end
end

function TabClass:Destroy()
	for _, control in pairs(self._Controls) do
		pcall(function()
			control.Destroy()
		end)
	end
	self._Janitor:Clean()
	Animator.Cancel(self._Page)
	self._Page:Destroy()
	self._Button:Destroy()
end

return TabClass
