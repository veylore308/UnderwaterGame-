--[[
	FishNPC.lua
	Deep Tide Studios — Server-Authoritative Fish NPC
	10-state FSM driving all fish behavior. Uses AlignPosition + AlignOrientation
	for smooth server-side movement. Species parameters from FishSpecies.lua.

	States: Idle → Patrol → Investigate → Curious → ReadyToBite → Biting →
	        Hooked → Fighting → Fleeing → Despawning

	Each state has enter/update/exit callbacks. The update loop runs at ~4Hz
	per fish to keep perf low at 25 fish max.
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local FishSignals = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("NPC"):WaitForChild("FishSignals"))

local FishNPC = {}
FishNPC.__index = FishNPC

-- ============================================================
-- Internal constants
-- ============================================================
local UPDATE_INTERVAL = 0.25        -- 4 Hz update loop
local ALIGN_POSITION_RIGIDITY = 80  -- how snappy movement is
local ALIGN_ORIENTATION_RIGIDITY = 60
local ALIGN_MAX_FORCE = 4000
local ALIGN_MAX_VELOCITY = 60
local SWIM_ANIMATION_AMPLITUDE = 0.3 -- sinusoidal body wave amplitude
local SWIM_ANIMATION_FREQUENCY = 3   -- body waves per second

-- ============================================================
-- Constructor
-- ============================================================
function FishNPC.new(species, spawnPosition, config)
	config = config or {}

	local self = setmetatable({}, FishNPC)

	-- Identity
	self.Id = HttpService:GenerateGUID(false)
	self.Species = species
	self.SpeciesKey = species.Key

	-- Position / Movement
	self.Position = spawnPosition
	self.TargetPosition = spawnPosition
	self.Velocity = Vector3.zero
	self.Rotation = CFrame.identity

	-- FSM State
	self._state = FishSignals.FishState.Idle
	self._previousState = nil
	self._stateEnterTime = tick()
	self._stateTimer = 0
	self._stateCallbacks = {} -- { [stateName] = { enter, update, exit } }

	-- Movement constraints
	self._alignPosition = nil
	self._alignOrientation = nil
	self._rootPart = nil
	self._model = nil

	-- Behavior timers
	self._idleTimer = 0
	self._patrolIndex = 1
	self._patrolWaypoints = config.Waypoints or {}
	self._investigateTarget = nil  -- Vector3 or CFrame of what we're investigating
	self._curiousTarget = nil
	self._biteDelayTimer = 0
	self._biteDelayTarget = 0
	self._fleeTimer = 0
	self._fleeDirection = Vector3.zero
	self._fleeCooldownUntil = 0
	self._despawnTimer = 0
	self._despawnAt = nil           -- absolute time for auto-despawn

	-- Awareness
	self._lastBobberCheck = 0
	self._nearbyBobbers = {}       -- { position, playerId }
	self._hookedPlayerId = nil

	-- Animation
	self._swimPhase = math.random() * math.pi * 2
	self._swimAnimConnection = nil

	-- Visual state (replicated flags)
	self._isCurious = false
	self._isGlowing = false

	-- Register state callbacks
	self:_registerStates()

	return self
end

-- ============================================================
-- State registration
-- ============================================================
function FishNPC:_registerStates()
	local s = FishSignals.FishState
	self._stateCallbacks[s.Idle] = {
		enter = function() self:_enterIdle() end,
		update = function() self:_updateIdle() end,
		exit = function() self:_exitIdle() end,
	}
	self._stateCallbacks[s.Patrol] = {
		enter = function() self:_enterPatrol() end,
		update = function() self:_updatePatrol() end,
		exit = function() self:_exitPatrol() end,
	}
	self._stateCallbacks[s.Investigate] = {
		enter = function() self:_enterInvestigate() end,
		update = function() self:_updateInvestigate() end,
		exit = function() self:_exitInvestigate() end,
	}
	self._stateCallbacks[s.Curious] = {
		enter = function() self:_enterCurious() end,
		update = function() self:_updateCurious() end,
		exit = function() self:_exitCurious() end,
	}
	self._stateCallbacks[s.ReadyToBite] = {
		enter = function() self:_enterReadyToBite() end,
		update = function() self:_updateReadyToBite() end,
		exit = function() self:_exitReadyToBite() end,
	}
	self._stateCallbacks[s.Biting] = {
		enter = function() self:_enterBiting() end,
		update = function() self:_updateBiting() end,
		exit = function() self:_exitBiting() end,
	}
	self._stateCallbacks[s.Hooked] = {
		enter = function() self:_enterHooked() end,
		update = function() self:_updateHooked() end,
		exit = function() self:_exitHooked() end,
	}
	self._stateCallbacks[s.Fighting] = {
		enter = function() self:_enterFighting() end,
		update = function() self:_updateFighting() end,
		exit = function() self:_exitFighting() end,
	}
	self._stateCallbacks[s.Fleeing] = {
		enter = function() self:_enterFleeing() end,
		update = function() self:_updateFleeing() end,
		exit = function() self:_exitFleeing() end,
	}
	self._stateCallbacks[s.Despawning] = {
		enter = function() self:_enterDespawning() end,
		update = function() self:_updateDespawning() end,
		exit = function() self:_exitDespawning() end,
	}
end

-- ============================================================
-- Lifecycle: initialize the physical model
-- Called by FishSpawner once the model is created
-- ============================================================
function FishNPC:Initialize(model, spawnerRef)
	self._model = model
	self._rootPart = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
	self._spawner = spawnerRef

	if not self._rootPart then
		warn("[FishNPC] No root part found for fish:", self.Id)
		return
	end

	-- Create AlignPosition for smooth movement
	local alignPos = Instance.new("AlignPosition")
	alignPos.Name = "FishAlignPosition"
	alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPos.MaxForce = ALIGN_MAX_FORCE
	alignPos.MaxVelocity = ALIGN_MAX_VELOCITY
	alignPos.Responsiveness = ALIGN_POSITION_RIGIDITY
	alignPos.RigidityEnabled = true
	alignPos.Attachment0 = self._rootPart:FindFirstChild("AlignAttachment") or self:_ensureAttachment(self._rootPart, "AlignAttachment")
	alignPos.Parent = self._rootPart
	self._alignPosition = alignPos

	-- Create AlignOrientation for smooth rotation
	local alignOrient = Instance.new("AlignOrientation")
	alignOrient.Name = "FishAlignOrientation"
	alignOrient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrient.MaxTorque = ALIGN_MAX_FORCE
	alignOrient.MaxAngularVelocity = ALIGN_MAX_VELOCITY
	alignOrient.Responsiveness = ALIGN_ORIENTATION_RIGIDITY
	alignOrient.RigidityEnabled = true
	alignOrient.Attachment0 = self._rootPart:FindFirstChild("AlignOrientAttachment") or self:_ensureAttachment(self._rootPart, "AlignOrientAttachment")
	alignOrient.Parent = self._rootPart
	self._alignOrientation = alignOrient

	-- Set initial position
	self._rootPart.Position = self.Position

	-- Start the update loop
	self:_startUpdateLoop()

	-- Enter initial state
	self:_transitionTo(FishSignals.FishState.Idle)
end

function FishNPC:_ensureAttachment(part, name)
	local att = part:FindFirstChild(name)
	if not att then
		att = Instance.new("Attachment")
		att.Name = name
		att.Parent = part
	end
	return att
end

-- ============================================================
-- Update loop (~4 Hz)
-- ============================================================
function FishNPC:_startUpdateLoop()
	self._alive = true

	task.spawn(function()
		while self._alive and self._rootPart and self._rootPart.Parent do
			local dt = UPDATE_INTERVAL
			local now = tick()

			-- Run current state update
			local cb = self._stateCallbacks[self._state]
			if cb and cb.update then
				cb.update(dt, now)
			end

			-- Update physical position (move toward target)
			self:_applyMovement(dt)

			-- Update swim animation
			self:_updateSwimAnimation(dt)

			task.wait(UPDATE_INTERVAL)
		end
	end)
end

-- ============================================================
-- Movement application — use AlignPosition target
-- ============================================================
function FishNPC:_applyMovement(dt)
	if not self._rootPart or not self._alignPosition then return end

	-- The AlignPosition target is set by each state.
	-- We position an invisible anchor part at the target and point AlignPosition at it.
	-- For simplicity, we directly set the align position target via a CFrame.
	-- Since AlignPosition.OneAttachment uses a single attachment,
	-- we set the attachment's world CFrame.

	local targetCFrame = CFrame.lookAt(self.Position, self.Position + (self.Velocity.Magnitude > 0.1 and self.Velocity.Unit or Vector3.new(0, 0, -1)))

	-- Apply orientation
	if self._alignOrientation then
		self._alignOrientation.Attachment0.WorldCFrame = targetCFrame
	end

	-- Move root part position via physics
	self._rootPart.AssemblyLinearVelocity = (self.Position - self._rootPart.Position) / math.max(dt, 0.01)
end

-- ============================================================
-- Swim animation — sinusoidal body wave
-- ============================================================
function FishNPC:_updateSwimAnimation(dt)
	if not self._model then return end

	local speed = self.Velocity.Magnitude
	self._swimPhase = self._swimPhase + dt * SWIM_ANIMATION_FREQUENCY * math.min(speed / 4, 2)

	-- Apply sinusoidal rotation to the fish body for swimming effect
	-- Find body segments (parts after the head)
	local parts = self._model:GetDescendants()
	local bodyParts = {}
	for _, part in ipairs(parts) do
		if part:IsA("BasePart") and part ~= self._rootPart and part.Name:find("Body") then
			table.insert(bodyParts, part)
		end
	end

	-- Simple tail wag for root part if no body segments
	if #bodyParts == 0 and self._rootPart and speed > 0.5 then
		local swayAngle = math.sin(self._swimPhase) * SWIM_ANIMATION_AMPLITUDE * (speed / self.Species.PatrolSpeed)
		-- Apply subtle rotation offset — done via AlignOrientation's target
		if self._alignOrientation then
			local baseCFrame = self._alignOrientation.Attachment0.WorldCFrame
			local swayCFrame = baseCFrame * CFrame.Angles(0, swayAngle, 0)
			self._alignOrientation.Attachment0.WorldCFrame = swayCFrame
		end
	end

	-- For multi-part fish, animate each body segment
	for i, part in ipairs(bodyParts) do
		local segmentPhase = self._swimPhase + (i * 0.5)
		local amplitude = SWIM_ANIMATION_AMPLITUDE * (i / #bodyParts) * math.min(speed / 4, 1.5)
		local rotation = CFrame.Angles(0, math.sin(segmentPhase) * amplitude, 0)
		-- Apply slight rotation via TweenService for smoothness
		-- (Only apply significant changes to avoid per-frame tweens)
		if math.abs(math.sin(segmentPhase) * amplitude) > 0.01 then
			part.CFrame = part.CFrame:Lerp(part.CFrame * rotation, 0.3)
		end
	end
end

-- ============================================================
-- State transition
-- ============================================================
function FishNPC:_transitionTo(newState, data)
	if self._state == newState then return end
	if self._state == FishSignals.FishState.Despawning then return end -- can't leave despawning

	local oldState = self._state

	-- Call exit on old state
	local oldCb = self._stateCallbacks[oldState]
	if oldCb and oldCb.exit then
		oldCb.exit()
	end

	self._previousState = oldState
	self._state = newState
	self._stateEnterTime = tick()
	self._stateTimer = 0

	-- Call enter on new state
	local newCb = self._stateCallbacks[newState]
	if newCb and newCb.enter then
		newCb.enter(data)
	end

	-- Notify spawner of state change (for FishingService integration)
	if self._spawner and self._spawner.OnFishStateChanged then
		self._spawner:OnFishStateChanged(self, oldState, newState)
	end
end

-- ============================================================
-- IDLE state
-- Fish hovers in place with subtle idle animation
-- ============================================================
function FishNPC:_enterIdle()
	self._idleTimer = 2 + math.random() * 4 -- 2-6 seconds (GDD)
	self.Velocity = Vector3.zero
end

function FishNPC:_updateIdle(dt, now)
	self._idleTimer = self._idleTimer - dt

	-- Check for bobbers nearby (trigger investigate)
	if self:_shouldInvestigate(now) then
		return
	end

	-- Check for threats (trigger flee)
	if self:_shouldFlee(nil) then
		return
	end

	-- Gentle hover bobbing
	local hoverOffset = math.sin(now * 1.5 + self._swimPhase) * 0.2
	self.Position = self.Position + Vector3.new(0, hoverOffset * dt, 0)

	-- Idle timer expired → Patrol
	if self._idleTimer <= 0 then
		self:_transitionTo(FishSignals.FishState.Patrol)
	end
end

function FishNPC:_exitIdle()
	-- Nothing to clean up
end

-- ============================================================
-- PATROL state
-- Fish follows waypoints at species patrol speed
-- ============================================================
function FishNPC:_enterPatrol()
	-- Pick next waypoint
	if #self._patrolWaypoints == 0 then
		-- No waypoints: generate a random nearby point
		self.TargetPosition = self.Position + Vector3.new(
			(math.random() - 0.5) * 20,
			(math.random() - 0.5) * 8,
			(math.random() - 0.5) * 20
		)
	else
		self._patrolIndex = (self._patrolIndex % #self._patrolWaypoints) + 1
		self.TargetPosition = self._patrolWaypoints[self._patrolIndex]
	end
end

function FishNPC:_updatePatrol(dt, now)
	-- Check for bobbers
	if self:_shouldInvestigate(now) then
		return
	end

	-- Check for threats
	if self:_shouldFlee(nil) then
		return
	end

	local speed = self.Species.PatrolSpeed
	local toTarget = self.TargetPosition - self.Position
	local dist = toTarget.Magnitude

	if dist < 3 then
		-- Reached waypoint → Idle or next waypoint
		if math.random() < 0.4 then
			self:_transitionTo(FishSignals.FishState.Idle)
		else
			self:_transitionTo(FishSignals.FishState.Patrol)
		end
		return
	end

	-- Move toward target
	local direction = toTarget.Unit
	self.Velocity = direction * speed
	self.Position = self.Position + self.Velocity * dt

	-- Reef Dart erratic behavior: random direction changes
	if self.Species.Behavior == "Erratic" and math.random() < 0.15 then
		-- Sudden direction change
		local burstAngle = (math.random() - 0.5) * math.pi * 0.8
		local burstDir = Vector3.new(
			math.cos(burstAngle) * direction.X - math.sin(burstAngle) * direction.Z,
			direction.Y + (math.random() - 0.5) * 0.4,
			math.sin(burstAngle) * direction.X + math.cos(burstAngle) * direction.Z
		).Unit
		self.TargetPosition = self.Position + burstDir * (8 + math.random() * 15)
	end
end

function FishNPC:_exitPatrol()
	-- Nothing to clean up
end

-- ============================================================
-- INVESTIGATE state
-- Fish notices bobber/player and turns toward it
-- ============================================================
function FishNPC:_enterInvestigate(data)
	self._investigateTarget = data and data.position or self._nearbyBobbers[1] and self._nearbyBobbers[1].position
	self._stateTimer = 0
end

function FishNPC:_updateInvestigate(dt, now)
	-- If no investigate target, go back to idle
	if not self._investigateTarget then
		self:_transitionTo(FishSignals.FishState.Idle)
		return
	end

	-- Check for threats (player too close)
	if self:_shouldFlee(nil) then
		return
	end

	local toTarget = self._investigateTarget - self.Position
	local dist = toTarget.Magnitude

	-- Turn toward the bobber (slow rotation)
	local direction = toTarget.Unit
	self.Velocity = direction * (self.Species.PatrolSpeed * 0.5) -- half speed while investigating
	self.Position = self.Position + self.Velocity * dt

	-- If close enough, transition to Curious
	local interestRadius = self.Species.BobberInterestRadius or 8
	if dist <= interestRadius * 1.5 then
		self:_transitionTo(FishSignals.FishState.Curious, { target = self._investigateTarget })
		return
	end

	-- Timeout: if too far from bobber, give up
	if dist > (self.Species.AwarenessRadius or 20) * 2 then
		self:_transitionTo(FishSignals.FishState.Idle)
		return
	end

	-- Max investigation time: 5 seconds
	self._stateTimer = self._stateTimer + dt
	if self._stateTimer > 5 then
		self:_transitionTo(FishSignals.FishState.Idle)
	end
end

function FishNPC:_exitInvestigate()
	self._investigateTarget = nil
end

-- ============================================================
-- CURIOUS state
-- Fish moves toward bobber slowly, within bite range
-- ============================================================
function FishNPC:_enterCurious(data)
	self._curiousTarget = data and data.target
	self._biteDelayTimer = 0
	self._isCurious = true
end

function FishNPC:_updateCurious(dt, now)
	if not self._curiousTarget then
		self:_transitionTo(FishSignals.FishState.Idle)
		return
	end

	-- Check threats
	if self:_shouldFlee(nil) then
		return
	end

	local toTarget = self._curiousTarget - self.Position
	local dist = toTarget.Magnitude
	local interestRadius = self.Species.BobberInterestRadius or 8

	-- Move toward bobber at reduced speed
	if dist > 2 then
		local direction = toTarget.Unit
		local speed = math.min(self.Species.PatrolSpeed * 0.6, 5)
		self.Velocity = direction * speed
		self.Position = self.Position + self.Velocity * dt
	else
		self.Velocity = Vector3.zero
		-- At bobber: wait for bite delay, then transition to ReadyToBite
		self._biteDelayTimer = self._biteDelayTimer + dt
		local biteMin = self.Species.BiteDelayMin or 1
		local biteMax = self.Species.BiteDelayMax or 3
		local biteDelay = biteMin + math.random() * (biteMax - biteMin)

		if self._biteDelayTimer >= biteDelay then
			self:_transitionTo(FishSignals.FishState.ReadyToBite)
		end
	end

	-- If bobber moved away too far
	if dist > interestRadius * 3 then
		self:_transitionTo(FishSignals.FishState.Idle)
	end
end

function FishNPC:_exitCurious()
	self._curiousTarget = nil
	self._isCurious = false
end

-- ============================================================
-- READY_TO_BITE state
-- Fish is at bobber, waiting for player to hook
-- ============================================================
function FishNPC:_enterReadyToBite()
	self._stateTimer = 0
end

function FishNPC:_updateReadyToBite(dt, now)
	-- Stay near bobber position
	if self._curiousTarget then
		local dist = (self._curiousTarget - self.Position).Magnitude
		if dist > 3 then
			local direction = (self._curiousTarget - self.Position).Unit
			self.Velocity = direction * 2
			self.Position = self.Position + self.Velocity * dt
		else
			self.Velocity = Vector3.zero
		end
	end

	-- Check threats
	if self:_shouldFlee(nil) then
		return
	end

	-- Timeout: if no hook attempt for 10 seconds, go back to idle
	self._stateTimer = self._stateTimer + dt
	if self._stateTimer > 10 then
		self:_transitionTo(FishSignals.FishState.Idle)
	end
end

function FishNPC:_exitReadyToBite()
	-- Nothing
end

-- ============================================================
-- BITING state
-- Fish is actively biting, hook window is open
-- ============================================================
function FishNPC:_enterBiting()
	self._stateTimer = 0
end

function FishNPC:_updateBiting(dt, now)
	-- Minimal movement, slight bob at bobber
	self.Velocity = Vector3.zero

	-- The actual bite resolution is driven by FishingService.
	-- Fish stays here until Hooked or Fleeing.
	self._stateTimer = self._stateTimer + dt

	-- Timeout: bite window closes after a few seconds
	if self._stateTimer > 6 then
		self:_transitionTo(FishSignals.FishState.Idle)
	end
end

function FishNPC:_exitBiting()
	-- Nothing
end

-- ============================================================
-- HOOKED state
-- Fish is on the line, flash effect played
-- ============================================================
function FishNPC:_enterHooked(data)
	self._hookedPlayerId = data and data.playerId
	-- Hooked is a brief transition state; move to Fighting immediately
	self:_transitionTo(FishSignals.FishState.Fighting, data)
end

function FishNPC:_updateHooked(dt, now)
	-- Shouldn't stay here long
	self:_transitionTo(FishSignals.FishState.Fighting)
end

function FishNPC:_exitHooked()
	-- Nothing
end

-- ============================================================
-- FIGHTING state
-- Fish is in the reel minigame. Controlled by FishingService.
-- ============================================================
function FishNPC:_enterFighting(data)
	self._hookedPlayerId = data and data.playerId
	self.Velocity = Vector3.zero
end

function FishNPC:_updateFighting(dt, now)
	-- Fish stays near the hooked position, thrashing occasionally
	-- The reel system controls the outcome.
	-- Periodically thrash: random position jitter
	if math.random() < 0.3 then
		local jitter = Vector3.new(
			(math.random() - 0.5) * 3,
			(math.random() - 0.5) * 3,
			(math.random() - 0.5) * 3
		)
		self.Position = self.Position + jitter * dt
	end
	self.Velocity = Vector3.zero
end

function FishNPC:_exitFighting()
	-- Cleaned up by FishingService
end

-- ============================================================
-- FLEEING state
-- Fish sprints away from threat
-- ============================================================
function FishNPC:_enterFleeing(data)
	local threatPos = data and data.threatPosition or self.Position + Vector3.new(0, 0, 20)

	-- Calculate flee direction: away from threat with some randomness
	local awayDir = (self.Position - threatPos)
	if awayDir.Magnitude < 0.1 then
		awayDir = Vector3.new(math.random() - 0.5, math.random() - 0.3, math.random() - 0.5)
	end
	local randomAngle = (math.random() - 0.5) * math.pi * 0.5
	self._fleeDirection = Vector3.new(
		math.cos(randomAngle) * awayDir.X - math.sin(randomAngle) * awayDir.Z,
		awayDir.Y + (math.random() - 0.5) * 0.5,
		math.sin(randomAngle) * awayDir.X + math.cos(randomAngle) * awayDir.Z
	).Unit

	self._fleeTimer = 2 + math.random() * 3 -- 2-5 seconds (GDD)
	self._fleeCooldownUntil = tick() + (self.Species.FleeCooldown or 8)
	self._isCurious = false
end

function FishNPC:_updateFleeing(dt, now)
	local speed = self.Species.FleeSpeed or 10
	self.Velocity = self._fleeDirection * speed
	self.Position = self.Position + self.Velocity * dt

	self._fleeTimer = self._fleeTimer - dt

	if self._fleeTimer <= 0 then
		-- Return to patrol at new position
		self:_transitionTo(FishSignals.FishState.Idle)
	end
end

function FishNPC:_exitFleeing()
	self._fleeDirection = Vector3.zero
end

-- ============================================================
-- DESPAWNING state
-- Fish is being removed. Cleanup with particle effect.
-- ============================================================
function FishNPC:_enterDespawning()
	self._despawnTimer = 0.5 -- brief window for effect
end

function FishNPC:_updateDespawning(dt, now)
	self.Velocity = Vector3.zero
	self._despawnTimer = self._despawnTimer - dt

	if self._despawnTimer <= 0 then
		self:Destroy()
	end
end

function FishNPC:_exitDespawning()
	-- Nothing
end

-- ============================================================
-- Awareness checks
-- ============================================================

-- Check if we should investigate nearby bobbers
function FishNPC:_shouldInvestigate(now)
	-- Don't check too frequently
	if now - self._lastBobberCheck < 0.5 then return false end
	self._lastBobberCheck = now

	-- Skip if fleeing or in combat
	if self._state == FishSignals.FishState.Fleeing
		or self._state == FishSignals.FishState.Hooked
		or self._state == FishSignals.FishState.Fighting
		or self._state == FishSignals.FishState.Despawning then
		return false
	end

	-- Get nearby bobbers from spawner
	if self._spawner and self._spawner.GetNearbyBobbers then
		self._nearbyBobbers = self._spawner:GetNearbyBobbers(self.Position, self.Species.AwarenessRadius or 15)
	else
		self._nearbyBobbers = {}
	end

	-- Filter bobbers that are within bobber interest radius
	for _, bobber in ipairs(self._nearbyBobbers) do
		local dist = (bobber.position - self.Position).Magnitude
		local interestRadius = self.Species.BobberInterestRadius or 8

		if dist <= interestRadius then
			-- Bobber within interest radius → Investigate
			self:_transitionTo(FishSignals.FishState.Investigate, { position = bobber.position })
			return true
		elseif dist <= (self.Species.AwarenessRadius or 15) then
			-- Bobber within awareness but not in interest range
			-- Species with curiosity approach
			if self.Species.CuriosityRadius and self.Species.CuriosityRadius > 0 then
				if dist <= self.Species.CuriosityRadius then
					self:_transitionTo(FishSignals.FishState.Investigate, { position = bobber.position })
					return true
				end
			end
		end
	end

	return false
end

-- Check if we should flee
function FishNPC:_shouldFlee(threatPosition)
	-- Species that don't flee
	if self.Species.FleeSpeed == 0 or self.Species.FleeTriggerDistance == 0 then
		-- Sunken Angler: doesn't flee, but dims lure if player too close
		if self.Species.Behavior == "Ambush" and threatPosition then
			local dist = (threatPosition - self.Position).Magnitude
			local dimDist = self.Species.DimDistance or 8
			if dist <= dimDist then
				-- Signal dimming (handled by spawner)
				if self._spawner and self._spawner.OnAnglerDimmed then
					self._spawner:OnAnglerDimmed(self)
				end
			end
		end
		return false
	end

	-- On flee cooldown
	if tick() < self._fleeCooldownUntil then return false end

	-- Skip if already fleeing or in combat
	if self._state == FishSignals.FishState.Fleeing
		or self._state == FishSignals.FishState.Hooked
		or self._state == FishSignals.FishState.Fighting
		or self._state == FishSignals.FishState.Despawning then
		return false
	end

	local fleeDist = self.Species.FleeTriggerDistance or 5

	-- Check threat position if given
	if threatPosition then
		local dist = (threatPosition - self.Position).Magnitude
		if dist <= fleeDist then
			self:_transitionTo(FishSignals.FishState.Fleeing, { threatPosition = threatPosition })
			return true
		end
	end

	-- Check nearby players (via spawner)
	if self._spawner and self._spawner.GetNearbyPlayers then
		local players = self._spawner:GetNearbyPlayers(self.Position, fleeDist)
		for _, playerData in ipairs(players) do
			self:_transitionTo(FishSignals.FishState.Fleeing, { threatPosition = playerData.position })
			return true
		end
	end

	return false
end

-- ============================================================
-- Public API — called by spawner / FishingService
-- ============================================================

-- Called when a player casts a bobber near this fish
function FishNPC:OnBobberNearby(bobberPosition, playerId)
	-- Already in bite chain
	if self._state == FishSignals.FishState.Curious
		or self._state == FishSignals.FishState.ReadyToBite
		or self._state == FishSignals.FishState.Biting then
		return
	end

	local dist = (bobberPosition - self.Position).Magnitude
	local interestRadius = self.Species.BobberInterestRadius or 8

	if dist <= interestRadius then
		self:_transitionTo(FishSignals.FishState.Investigate, {
			position = bobberPosition,
			playerId = playerId,
		})
	end
end

-- Called when a player makes a hook attempt on this fish
function FishNPC:OnHookAttempt(success)
	if success then
		-- Player hooked successfully
		self:_transitionTo(FishSignals.FishState.Hooked)
	else
		-- Failed hook → flee
		self:_transitionTo(FishSignals.FishState.Fleeing, {
			threatPosition = self.Position + Vector3.new(0, 0, -10),
		})
	end
end

-- Called when line snaps during fighting
function FishNPC:OnLineSnap()
	self._hookedPlayerId = nil
	self:_transitionTo(FishSignals.FishState.Fleeing, {
		threatPosition = self.Position + Vector3.new(0, 0, -15),
	})
end

-- Called when fish escapes the hook
function FishNPC:OnEscape()
	self._hookedPlayerId = nil
	self:_transitionTo(FishSignals.FishState.Fleeing, {
		threatPosition = self.Position + Vector3.new(0, 0, -15),
	})
end

-- Called when fish is successfully caught
function FishNPC:OnCaught()
	self:_transitionTo(FishSignals.FishState.Despawning)
end

-- Called when a player gets too close (sprint-swim trigger)
function FishNPC:OnPlayerNearby(playerPosition)
	self:_shouldFlee(playerPosition)
end

-- Check if this fish is in a bite-ready state
function FishNPC:IsBiteReady()
	return self._state == FishSignals.FishState.ReadyToBite
		or self._state == FishSignals.FishState.Biting
end

-- Check if this fish is currently hooked
function FishNPC:IsHooked()
	return self._state == FishSignals.FishState.Hooked
		or self._state == FishSignals.FishState.Fighting
end

-- Get current state
function FishNPC:GetState()
	return self._state
end

-- Get bobber interest radius for this species
function FishNPC:GetInterestRadius()
	return self.Species.BobberInterestRadius or 8
end

-- Set patrol waypoints (reconfigured by spawner)
function FishNPC:SetWaypoints(waypoints)
	self._patrolWaypoints = waypoints or {}
	self._patrolIndex = 1
end

-- Set auto-despawn timer (e.g., Abyssal Leviathan 60s)
function FishNPC:SetDespawnTimer(seconds)
	self._despawnAt = tick() + seconds
end

-- Check auto-despawn
function FishNPC:CheckDespawn(now)
	now = now or tick()
	if self._despawnAt and now >= self._despawnAt then
		self:_transitionTo(FishSignals.FishState.Despawning)
		return true
	end
	return false
end

-- ============================================================
-- Cleanup
-- ============================================================
function FishNPC:Destroy()
	self._alive = false

	-- Clean up physics attachments
	if self._alignPosition then
		self._alignPosition:Destroy()
		self._alignPosition = nil
	end
	if self._alignOrientation then
		self._alignOrientation:Destroy()
		self._alignOrientation = nil
	end

	-- Destroy model
	if self._model then
		self._model:Destroy()
		self._model = nil
	end

	self._rootPart = nil
	self._spawner = nil
end

return FishNPC
