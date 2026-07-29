--[[
	FishingRodHandler.lua
	Deep Tide Studios — Client Handler
	Manages the fishing rod tool visual: 3D model in hand, aiming arc,
	cast animation, bobber/line, and bobber VFX (ripples, bubbles, glow).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))

local FishingRodHandler = {}
FishingRodHandler.__index = FishingRodHandler

-- ============================================================
-- Constructor
-- ============================================================
function FishingRodHandler.new()
	local self = setmetatable({}, FishingRodHandler)

	-- Visual references
	self._rodModel = nil       -- rod in player's hand
	self._rodTip = nil         -- tip attachment point
	self._bobber = nil         -- bobber part
	self._lineBeam = nil       -- beam from rod tip to bobber
	self._aimArc = nil         -- trajectory arc parts
	self._bobberRipples = nil  -- particle emitter on bobber
	self._bobberGlow = nil     -- point light on bobber

	-- State
	self._isEquipped = false
	self._isCasting = false
	self._castStartTime = 0
	self._castOrigin = nil

	return self
end

-- ============================================================
-- Rod Colors (per tier)
-- ============================================================
FishingRodHandler._ROD_COLORS = {
	BambooRod = Color3.fromRGB(180, 150, 100),  -- Bamboo brown
	CoralRod = Color3.fromRGB(255, 100, 80),    -- Coral pink
	ReefKingRod = Color3.fromRGB(80, 180, 220), -- Royal blue
}

-- ============================================================
-- Equip / Unequip
-- ============================================================

function FishingRodHandler:Equip(rodKey)
	if self._isEquipped then
		self:Unequip()
	end

	self._isEquipped = true
	self._rodKey = rodKey
	self:_createRodModel(rodKey)
end

function FishingRodHandler:Unequip()
	self._isEquipped = false
	self:_destroyRodModel()
	self:_destroyBobber()
	self:_destroyAimArc()
end

-- ============================================================
-- Build rod model in player's hand
-- ============================================================

function FishingRodHandler:_createRodModel(rodKey)
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then return end

	local rightHand = character:FindFirstChild("RightHand")
	if not rightHand then return end

	local rod = Shared.Constants.RodTiers.GetByKey(rodKey)
	local rodColor = self._ROD_COLORS[rodKey] or Color3.fromRGB(180, 150, 100)

	-- Create rod assembly
	local handle = Instance.new("Part")
	handle.Name = "RodHandle"
	handle.Size = Vector3.new(0.2, 0.3, 0.8)
	handle.Color = Color3.fromRGB(80, 50, 30)
	handle.Material = Enum.Material.Wood
	handle.Anchored = false
	handle.CanCollide = false
	handle.Parent = character

	local pole = Instance.new("Part")
	pole.Name = "RodPole"
	pole.Size = Vector3.new(0.15, 0.15, 4.5)
	pole.Color = rodColor
	pole.Material = Enum.Material.WoodPlanks
	pole.Anchored = false
	pole.CanCollide = false
	pole.Parent = character

	local tip = Instance.new("Part")
	tip.Name = "RodTip"
	tip.Size = Vector3.new(0.1, 0.1, 0.3)
	tip.Color = Color3.fromRGB(60, 60, 60)
	tip.Material = Enum.Material.Metal
	tip.Anchored = false
	tip.CanCollide = false
	tip.Parent = character

	-- Attachments for the line beam
	local rodTipAttach = Instance.new("Attachment")
	rodTipAttach.Name = "LineOrigin"
	rodTipAttach.Parent = tip

	self._rodTipAttach = rodTipAttach
	self._rodTip = tip

	-- Weld them together
	local handleWeld = Instance.new("WeldConstraint")
	handleWeld.Part0 = handle
	handleWeld.Part1 = rightHand
	handleWeld.Parent = handle

	local poleWeld = Instance.new("WeldConstraint")
	poleWeld.Part0 = pole
	poleWeld.Part1 = handle
	poleWeld.Parent = pole

	-- Position pole extending from handle
	pole.CFrame = handle.CFrame * CFrame.new(0, 0, -2.5) * CFrame.Angles(0, 0, 0)

	local tipWeld = Instance.new("WeldConstraint")
	tipWeld.Part0 = tip
	tipWeld.Part1 = pole
	tipWeld.Parent = tip

	-- Position tip at end of pole
	tip.CFrame = pole.CFrame * CFrame.new(0, 0, -2.35)

	self._rodModel = {
		Handle = handle,
		Pole = pole,
		Tip = tip,
		HandleWeld = handleWeld,
		PoleWeld = poleWeld,
		TipWeld = tipWeld,
	}

	-- Tag parts for cleanup
	CollectionService:AddTag(handle, "FishingRod")
	CollectionService:AddTag(pole, "FishingRod")
	CollectionService:AddTag(tip, "FishingRod")
end

function FishingRodHandler:_destroyRodModel()
	if self._rodModel then
		for _, part in pairs(self._rodModel) do
			if typeof(part) == "Instance" then
				part:Destroy()
			end
		end
		self._rodModel = nil
		self._rodTipAttach = nil
		self._rodTip = nil
	end
end

-- ============================================================
-- Aim Arc (trajectory preview)
-- ============================================================

function FishingRodHandler:ShowAimArc(origin, direction, power, maxRange)
	self:_destroyAimArc()

	local arcParts = {}
	local segments = 20
	local gravity = Vector3.new(0, -workspace.Gravity * 0.3, 0) -- scaled down for water

	-- Calculate arc points
	for i = 0, segments do
		local t = i / segments
		local point = origin + direction * (power * maxRange * t)
			+ gravity * (t * t) * (maxRange * 0.2)

		local dot = Instance.new("Part")
		dot.Name = "AimDot"
		dot.Size = Vector3.new(0.12, 0.12, 0.12)
		dot.Shape = Enum.PartType.Ball
		dot.Color = Color3.fromRGB(255, 255, 255)
		dot.Material = Enum.Material.Neon
		dot.Anchored = true
		dot.CanCollide = false
		dot.Position = point
		dot.Parent = workspace

		table.insert(arcParts, dot)
	end

	-- Reticle at the end
	local reticle = Instance.new("Part")
	reticle.Name = "AimReticle"
	reticle.Size = Vector3.new(0.5, 0.05, 0.5)
	reticle.Shape = Enum.PartType.Cylinder
	reticle.Orientation = Vector3.new(0, 0, 0)
	reticle.Color = Color3.fromRGB(255, 100, 50)
	reticle.Material = Enum.Material.Neon
	reticle.Anchored = true
	reticle.CanCollide = false
	reticle.Position = arcParts[#arcParts] and arcParts[#arcParts].Position or origin
	reticle.Parent = workspace

	table.insert(arcParts, reticle)

	self._aimArc = arcParts
end

function FishingRodHandler:UpdateAimArc(origin, direction, power, maxRange)
	-- Quick update of aim arc positions
	if not self._aimArc then return end

	local gravity = Vector3.new(0, -workspace.Gravity * 0.3, 0)
	local segments = #self._aimArc - 1 -- last is reticle

	for i = 0, math.min(segments, #self._aimArc - 1) do
		local t = i / segments
		local point = origin + direction * (power * maxRange * t)
			+ gravity * (t * t) * (maxRange * 0.2)

		self._aimArc[i + 1].Position = point
	end

	-- Update reticle position
	local lastIdx = #self._aimArc
	if lastIdx > 1 and self._aimArc[lastIdx] then
		local finalT = 1.0
		local finalPoint = origin + direction * (power * maxRange * finalT)
			+ gravity * (finalT * finalT) * (maxRange * 0.2)
		self._aimArc[lastIdx].Position = finalPoint
	end
end

function FishingRodHandler:_destroyAimArc()
	if self._aimArc then
		for _, part in ipairs(self._aimArc) do
			part:Destroy()
		end
		self._aimArc = nil
	end
end

-- ============================================================
-- Cast animation
-- ============================================================

function FishingRodHandler:PlayCastAnimation(origin, target, power, onComplete)
	self._isCasting = true
	self._castOrigin = origin

	-- Animate rod: bend back, then snap forward
	self:_animateRodWindUp(power, function()
		self:_animateRodSnap(target, function()
			self._isCasting = false
			if onComplete then onComplete() end
		end)
	end)
end

function FishingRodHandler:_animateRodWindUp(power, callback)
	if not self._rodModel then
		if callback then callback() end
		return
	end

	local pole = self._rodModel.Pole
	local originalCF = pole.CFrame

	local tweenInfo = TweenInfo.new(0.3 * power, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local goal = { CFrame = originalCF * CFrame.Angles(math.rad(20 * power), 0, 0) }
	local tween = TweenService:Create(pole, tweenInfo, goal)
	tween:Play()
	tween.Completed:Connect(function()
		if callback then callback() end
	end)
end

function FishingRodHandler:_animateRodSnap(target, callback)
	if not self._rodModel then
		if callback then callback() end
		return
	end

	local pole = self._rodModel.Pole
	local originalCF = pole.CFrame

	local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local goal = { CFrame = originalCF * CFrame.Angles(math.rad(-40), 0, 0) }
	local tween = TweenService:Create(pole, tweenInfo, goal)
	tween:Play()
	tween.Completed:Connect(function()
		-- Return to rest
		local returnTween = TweenService:Create(pole,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = originalCF }
		)
		returnTween:Play()
		if callback then callback() end
	end)
end

-- ============================================================
-- Bobber & Line
-- ============================================================

function FishingRodHandler:CreateBobber(targetPosition)
	self:_destroyBobber()

	-- Bobber part
	local bobber = Instance.new("Part")
	bobber.Name = "Bobber"
	bobber.Size = Vector3.new(0.4, 0.4, 0.4)
	bobber.Shape = Enum.PartType.Ball
	bobber.Color = Color3.fromRGB(255, 80, 50) -- Red/white bobber
	bobber.Material = Enum.Material.SmoothPlastic
	bobber.Anchored = false
	bobber.CanCollide = false

	-- Start at rod tip position
	local rodTipPos = self:_getRodTipPosition()
	bobber.Position = rodTipPos or targetPosition
	bobber.Parent = workspace

	-- Bobber top marker (white half)
	local topMarker = Instance.new("Part")
	topMarker.Name = "BobberTop"
	topMarker.Size = Vector3.new(0.38, 0.2, 0.38)
	topMarker.Shape = Enum.PartType.Ball
	topMarker.Color = Color3.fromRGB(255, 255, 255)
	topMarker.Material = Enum.Material.SmoothPlastic
	topMarker.Anchored = false
	topMarker.CanCollide = false
	topMarker.Parent = bobber

	local topWeld = Instance.new("WeldConstraint")
	topWeld.Part0 = topMarker
	topWeld.Part1 = bobber
	topWeld.Parent = topMarker

	-- Attachment for line
	local bobberAttach = Instance.new("Attachment")
	bobberAttach.Name = "LineTarget"
	bobberAttach.Parent = bobber

	-- Line beam (rod tip -> bobber)
	local beam = Instance.new("Beam")
	beam.Name = "FishingLine"
	beam.Attachment0 = self._rodTipAttach
	beam.Attachment1 = bobberAttach
	beam.Color = ColorSequence.new(Color3.fromRGB(200, 200, 200))
	beam.Width0 = 0.03
	beam.Width1 = 0.02
	beam.Transparency = NumberSequence.new(0.3)
	beam.Texture = "" -- no texture, smooth line
	beam.Parent = bobber

	-- Bobber ripples particle
	local rippleEmitter = Instance.new("ParticleEmitter")
	rippleEmitter.Name = "BobberRipples"
	rippleEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	rippleEmitter.Rate = 0
	rippleEmitter.Lifetime = NumberRange.new(0.5, 1.0)
	rippleEmitter.Speed = NumberRange.new(0, 0)
	rippleEmitter.Size = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 0.5),
	}
	rippleEmitter.Transparency = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	}
	rippleEmitter.Color = ColorSequence.new(Color3.fromRGB(200, 230, 255))
	rippleEmitter.SpreadAngle = Vector2.new(0, 360)
	rippleEmitter.Enabled = false
	rippleEmitter.Parent = bobber

	-- Bobber glow (for bioluminescent fish nearby)
	local glowLight = Instance.new("PointLight")
	glowLight.Name = "BobberGlow"
	glowLight.Brightness = 0
	glowLight.Range = 4
	glowLight.Color = Color3.fromRGB(100, 200, 255)
	glowLight.Enabled = false
	glowLight.Parent = bobber

	self._bobber = bobber
	self._lineBeam = beam
	self._bobberAttach = bobberAttach
	self._bobberRipples = rippleEmitter
	self._bobberGlow = glowLight

	-- Animate bobber traveling to target
	self:_animateBobberTravel(targetPosition)
end

function FishingRodHandler:_animateBobberTravel(targetPosition)
	if not self._bobber then return end

	local startPos = self._bobber.Position
	local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local tween = TweenService:Create(self._bobber, tweenInfo, {
		Position = targetPosition,
	})

	tween:Play()
	tween.Completed:Connect(function()
		-- Bobber idle bobbing
		self:_startBobberIdle(targetPosition)

		-- Enable ripples
		if self._bobberRipples then
			self._bobberRipples.Enabled = true
			self._bobberRipples.Rate = 4
		end
	end)
end

function FishingRodHandler:_startBobberIdle(basePosition)
	if not self._bobber then return end

	self._bobberIdleConnection = RunService.Heartbeat:Connect(function(dt)
		if not self._bobber then
			self._bobberIdleConnection:Disconnect()
			return
		end

		-- Gentle bobbing
		local bobOffset = math.sin(tick() * 3) * 0.15
		self._bobber.Position = basePosition + Vector3.new(0, bobOffset, 0)
	end)
end

function FishingRodHandler:PlayBobberBite()
	-- Rapid bobbing when fish approaches
	if not self._bobber then return end

	-- Increase ripple rate
	if self._bobberRipples then
		self._bobberRipples.Rate = 12
	end

	-- Rapid bob animation
	local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out, -1, true)
	if self._bobber then
		local tween = TweenService:Create(self._bobber, tweenInfo, {
			Position = self._bobber.Position + Vector3.new(0, 0.3, 0),
		})
		tween:Play()
	end
end

function FishingRodHandler:SetBobberGlow(enabled, color)
	if not self._bobberGlow then return end
	self._bobberGlow.Enabled = enabled
	self._bobberGlow.Brightness = enabled and 2 or 0
	if color then
		self._bobberGlow.Color = color
	end
end

function FishingRodHandler:UpdateLineTension(tensionPercent)
	if not self._lineBeam then return end

	-- Visual line sag based on tension
	-- Low tension = saggy, high tension = straight
	local transparency = 0.3 + (tensionPercent / 100) * 0.4 -- more opaque when tight
	self._lineBeam.Transparency = NumberSequence.new(transparency)

	-- Width changes with tension
	local width = 0.02 + (tensionPercent / 100) * 0.03
	self._lineBeam.Width0 = width
	self._lineBeam.Width1 = width * 0.8
end

function FishingRodHandler:_destroyBobber()
	if self._bobberIdleConnection then
		self._bobberIdleConnection:Disconnect()
		self._bobberIdleConnection = nil
	end
	if self._bobber then
		self._bobber:Destroy()
		self._bobber = nil
		self._lineBeam = nil
		self._bobberAttach = nil
		self._bobberRipples = nil
		self._bobberGlow = nil
	end
end

-- ============================================================
-- Utility
-- ============================================================

function FishingRodHandler:_getRodTipPosition()
	if not self._rodTip then return nil end
	return self._rodTip.Position
end

function FishingRodHandler:GetBobberPosition()
	if self._bobber then
		return self._bobber.Position
	end
	return nil
end

function FishingRodHandler:Destroy()
	self:Unequip()
end

return FishingRodHandler
