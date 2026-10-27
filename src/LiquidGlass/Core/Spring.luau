--@module LiquidGlass/Core/Spring
--[[
	LiquidGlass · Core/Spring
	Semi-implicit Euler damped harmonic oscillator.
	Used by the Animator for spring-like property motion.
]]

local Spring = {}
Spring.__index = Spring

function Spring.new(target, config)
	config = config or {}
	return setmetatable({
		Target = target,
		Value = target,
		Velocity = 0,
		Stiffness = config.Stiffness or 190,
		Damping = config.Damping or 13,
		Precision = config.Precision or 0.001,
	}, Spring)
end

-- Advance the simulation; returns true when settled --------------------------------
function Spring:Step(dt)
	dt = math.min(dt, 1 / 30)
	local force = (self.Target - self.Value) * self.Stiffness
	local drag = -self.Velocity * self.Damping
	self.Velocity = self.Velocity + (force + drag) * dt
	self.Value = self.Value + self.Velocity * dt
	local settled = math.abs(self.Target - self.Value) < self.Precision
		and math.abs(self.Velocity) < self.Precision
	if settled then
		self.Value = self.Target
		self.Velocity = 0
	end
	return settled
end

-- Teleport (no motion) ----------------------------------------------------------------
function Spring:JumpTo(value)
	self.Target = value
	self.Value = value
	self.Velocity = 0
end

return Spring
