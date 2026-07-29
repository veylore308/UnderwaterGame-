--[[
	FishNPC.lua
	Deep Tide Studios — Server-Authoritative Fish NPC
	10-state FSM (extended to 16 states for Phase 2) driving all fish behavior.
	Uses AlignPosition + AlignOrientation for smooth server-side movement.
	Species parameters from FishSpecies.lua.

	States:
		MVP (10): Idle → Patrol → Investigate → Curious → ReadyToBite → Biting →
		          Hooked → Fighting → Fleeing → Despawning
		Phase 2 (+6): Camouflaged, Burrowed, Emerging, InkCloud, TentacleContact, Enraged

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
	self._investigateTarget = nil
	self._curiousTarget = nil
	self._biteDelayTimer = 0
	self._biteDelayTarget = 0
	self._fleeTimer = 0
	self._fleeDirection = Vector3.zero
	self._fleeCooldownUntil = 0
	self._despawnTimer = 0
	self._despawnAt = nil

	-- Awareness
	self._lastBobberCheck = 0
	self._nearbyBobbers = {}
	self._hookedPlayerId = nil

	-- Animation
	self._swimPhase = math.random() * math.pi * 2
	self._swimAnimConnection = nil

	-- Visual state (replicated flags)
	self._isCurious = false
	self._isGlowing = false

	-- Phase 2: Kelp Forest — species-specific state
	self._clingTarget = nil          -- Frilled Seahorse: stalk position being clung to
	self._clingTimer = 0             -- Seahorse: time remaining on current cling
	self._coverFrond = nil           -- Kelp Darter: frond cluster position
	self._coverStealthActive = false -- Kelp Darter: currently concealed in frond
	self._camouflageTransparency = 0 -- Kelp Stalker: current blend level (0-0.85)
	self._camouflageStalk = nil     -- Kelp Stalker: kelp stalk being matched
	self._shimmerTimer = 0           -- Kelp Stalker: time until next shimmer
	self._sonarRevealedUntil = 0    -- Kelp Stalker: revealed by sonar until this time
	self._camouflageCooldown = 0    -- Kelp Stalker: 3s cooldown after reveal before re-camo
	self._burrowCrevice = nil       -- Grotto Crab: crevice position
	self._baitPosition = nil        -- Grotto Crab: bait placed by player
	self._baitTimer = 0             -- Grotto Crab: time since bait placed
	self._inkBurstActive = false    -- Lantern Squid: currently in ink cloud
	self._inkBurstEndTime = 0       -- Lantern Squid: when ink cloud ends
	self._tentacleHazardActive = false -- Void Jellyfish: player in tentacles
	self._apexAlertTimer = 0        -- Kelp Serpent: time since last apex alert broadcast
	self._enragedTimer = 0          -- Kelp Serpent: time remaining in enraged state
	self._apexPosition = nil        -- Kelp Serpent patrol: zone-wide figure-eight path
	self._apexPatrolPhase = 0       -- Kelp Serpent: patrol phase angle

	-- Zone awareness
	self._currentZone = config.Zone or "SunkenShallows"

	-- Register state callbacks
	self:_registerStates()

	return self
end

-- ============================================================
-- State registration (extended with Phase 2 states)
-- ============================================================
function FishNPC:_registerStates()
	local s = FishSignals.FishState
	self._stateCallbacks[s.Idle] = {
		enter = function() self:_enterIdle() end,
		update = function(dt, now) self:_updateIdle(dt, now) end,
		exit = function() self:_exitIdle() end,
	}
	self._stateCallbacks[s.Patrol] = {
		enter = function() self:_enterPatrol() end,
		update = function(dt, now) self:_updatePatrol(dt, now) end,
		exit = function() self:_exitPatrol() end,
	}
	self._stateCallbacks[s.Investigate] = {
		enter = function(d) self:_enterInvestigate(d) end,
		update = function(dt, now) self:_updateInvestigate(dt, now) end,
		exit = function() self:_exitInvestigate() end,
	}
	self._stateCallbacks[s.Curious] = {
		enter = function(d) self:_enterCurious(d) end,
		update = function(dt, now) self:_updateCurious(dt, now) end,
		exit = function() self:_exitCurious() end,
	}
	self._stateCallbacks[s.ReadyToBite] = {
		enter = function() self:_enterReadyToBite() end,
		update = function(dt, now) self:_updateReadyToBite(dt, now) end,
		exit = function() self:_exitReadyToBite() end,
	}
	self._stateCallbacks[s.Biting] = {
		enter = function() self:_enterBiting() end,
		update = function(dt, now) self:_updateBiting(dt, now) end,
		exit = function() self:_exitBiting() end,
	}
	self._stateCallbacks[s.Hooked] = {
		enter = function(d) self:_enterHooked(d) end,
		update = function(dt, now) self:_updateHooked(dt, now) end,
		exit = function() self:_exitHooked() end,
	}
	self._stateCallbacks[s.Fighting] = {
		enter = function(d) self:_enterFighting(d) end,
		update = function(dt, now) self:_updateFighting(dt, now) end,
		exit = function() self:_exitFighting() end,
	}
	self._stateCallbacks[s.Fleeing] = {
		enter = function(d) self:_enterFleeing(d) end,
		update = function(dt, now) self:_updateFleeing(dt, now) end,
		exit = function() self:_exitFleeing() end,
	}
	self._stateCallbacks[s.Despawning] = {
		enter = function() self:_enterDespawning() end,
		update = function(dt, now) self:_updateDespawning(dt, now) end,
		exit = function() self:_exitDespawning() end,
	}

	-- Phase 2: Camouflaged (Kelp Stalker)
	self._stateCallbacks[s.Camouflaged] = {
		enter = function() self:_enterCamouflaged() end,
		update = function(dt, now) self:_updateCamouflaged(dt, now) end,
		exit = function() self:_exitCamouflaged() end,
	}
	-- Phase 2: Burrowed (Grotto Crab in crevice)
	self._stateCallbacks[s.Burrowed] = {
		enter = function() self:_enterBurrowed() end,
		update = function(dt, now) self:_updateBurrowed(dt, now) end,
		exit = function() self:_exitBurrowed() end,
	}
	-- Phase 2: Emerging (Grotto Crab coming out for bait)
	self._stateCallbacks[s.Emerging] = {
		enter = function(d) self:_enterEmerging(d) end,
		update = function(dt, now) self:_updateEmerging(dt, now) end,
		exit = function() self:_exitEmerging() end,
	}
	-- Phase 2: InkCloud (Lantern Squid ink burst)
	self._stateCallbacks[s.InkCloud] = {
		enter = function() self:_enterInkCloud() end,
		update = function(dt, now) self:_updateInkCloud(dt, now) end,
		exit = function() self:_exitInkCloud() end,
	}
	-- Phase 2: TentacleContact (Void Jellyfish player damage)
	self._stateCallbacks[s.TentacleContact] = {
		enter = function(d) self:_enterTentacleContact(d) end,
		update = function(dt, now) self:_updateTentacleContact(dt, now) end,
		exit = function() self:_exitTentacleContact() end,
	}
	-- Phase 2: Enraged (Kelp Serpent after failed hook)
	self._stateCallbacks[s.Enraged] = {
		enter = function() self:_enterEnraged() end,
		update = function(dt, now) self:_updateEnraged(dt, now) end,
		exit = function() self:_exitEnraged() end,
	}
end

-- ============================================================
-- Lifecycle: initialize the physical model
-- ============================================================
function FishNPC:Initialize(model, spawnerRef)
	self._model = model
	self._rootPart = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
	self._spawner = spawnerRef

	if not self._rootPart then
		warn("[FishNPC] No root part found for fish:", self.Id)
		return
	end

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

	self._rootPart.Position = self.Position
	self:_startUpdateLoop()

	-- Determine initial state based on species behavior
	if self.Species.Behavior == "Camouflage" then
		self:_transitionTo(FishSignals.FishState.Camouflaged)
	elseif self.Species.Behavior == "Burrower" then
		self:_transitionTo(FishSignals.FishState.Idle) -- starts walking then burrows when player near
	elseif self.Species.Behavior == "ApexRoaming" then
		self:_transitionTo(FishSignals.FishState.Patrol)
	elseif self.Species.Behavior == "Drifter" then
		self:_transitionTo(FishSignals.FishState.Patrol) -- drift = patrol for Jellyfish
	else
		self:_transitionTo(FishSignals.FishState.Idle)
	end
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

			local cb = self._stateCallbacks[self._state]
			if cb and cb.update then
				cb.update(dt, now)
			end

			self:_applyMovement(dt)
			self:_updateSwimAnimation(dt)

			task.wait(UPDATE_INTERVAL)
		end
	end)
end

function FishNPC:_applyMovement(dt)
	if not self._rootPart or not self._alignPosition then return end

	local targetCFrame = CFrame.lookAt(self.Position, self.Position + (self.Velocity.Magnitude > 0.1 and self.Velocity.Unit or Vector3.new(0, 0, -1)))

	if self._alignOrientation then
		self._alignOrientation.Attachment0.WorldCFrame = targetCFrame
	end

	self._rootPart.AssemblyLinearVelocity = (self.Position - self._rootPart.Position) / math.max(dt, 0.01)
end

function FishNPC:_updateSwimAnimation(dt)
	if not self._model then return end
	local speed = self.Velocity.Magnitude
	self._swimPhase = self._swimPhase + dt * SWIM_ANIMATION_FREQUENCY * math.min(speed / 4, 2)

	local parts = self._model:GetDescendants()
	local bodyParts = {}
	for _, part in ipairs(parts) do
		if part:IsA("BasePart") and part ~= self._rootPart and part.Name:find("Body") then
			table.insert(bodyParts, part)
		end
	end

	if #bodyParts == 0 and self._rootPart and speed > 0.5 then
		local swayAngle = math.sin(self._swimPhase) * SWIM_ANIMATION_AMPLITUDE * (speed / math.max(self.Species.PatrolSpeed, 1))
		if self._alignOrientation then
			local baseCFrame = self._alignOrientation.Attachment0.WorldCFrame
			local swayCFrame = baseCFrame * CFrame.Angles(0, swayAngle, 0)
			self._alignOrientation.Attachment0.WorldCFrame = swayCFrame
		end
	end

	for i, part in ipairs(bodyParts) do
		local segmentPhase = self._swimPhase + (i * 0.5)
		local amplitude = SWIM_ANIMATION_AMPLITUDE * (i / #bodyParts) * math.min(speed / 4, 1.5)
		local rotation = CFrame.Angles(0, math.sin(segmentPhase) * amplitude, 0)
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
	if self._state == FishSignals.FishState.Despawning then return end

	local oldState = self._state

	local oldCb = self._stateCallbacks[oldState]
	if oldCb and oldCb.exit then
		oldCb.exit()
	end

	self._previousState = oldState
	self._state = newState
	self._stateEnterTime = tick()
	self._stateTimer = 0

	local newCb = self._stateCallbacks[newState]
	if newCb and newCb.enter then
		newCb.enter(data)
	end

	if self._spawner and self._spawner.OnFishStateChanged then
		self._spawner:OnFishStateChanged(self, oldState, newState)
	end
end

-- ============================================================
-- IDLE state (extended for Kelp species: Clinger, Cover, BottomFeeder)
-- ============================================================
function FishNPC:_enterIdle()
	self._idleTimer = 2 + math.random() * 4
	self.Velocity = Vector3.zero

	-- Frilled Seahorse: cling behavior
	if self.Species.Behavior == "Clinger" then
		local clingMin = self.Species.ClingDuration and self.Species.ClingDuration.Min or 10
		local clingMax = self.Species.ClingDuration and self.Species.ClingDuration.Max or 30
		self._idleTimer = clingMin + math.random() * (clingMax - clingMin)
		self._clingTarget = self.Position
	end

	-- Kelp Darter: hide in frond
	if self.Species.Behavior == "CoverUser" then
		local interval = self.Species.FrondPositionUpdateInterval or { Min = 2, Max = 4 }
		self._idleTimer = interval.Min + math.random() * (interval.Max - interval.Min)
		self._coverStealthActive = true
		self._coverFrond = self.Position
	end

	-- Copper Scaleback: stay on sea floor
	if self.Species.Behavior == "BottomFeeder" and self.Species.MaxHeightFromFloor then
		self.Position = Vector3.new(self.Position.X, self.Species.MaxHeightFromFloor, self.Position.Z)
	end
end

function FishNPC:_updateIdle(dt, now)
	self._idleTimer = self._idleTimer - dt

	if self:_shouldInvestigate(now) then return end
	if self:_shouldFlee(nil) then return end

	-- Clinger: stay on kelp stalk, sway with it
	if self.Species.Behavior == "Clinger" then
		local hoverOffset = math.sin(now * 1.0 + self._swimPhase) * 0.1 -- gentle sway
		self.Position = self._clingTarget + Vector3.new(hoverOffset * dt, 0, 0)
	else
		local hoverOffset = math.sin(now * 1.5 + self._swimPhase) * 0.2
		self.Position = self.Position + Vector3.new(0, hoverOffset * dt, 0)
	end

	if self._idleTimer <= 0 then
		-- Kelp Stalker: re-camouflage when idle expires
		if self.Species.Behavior == "Camouflage" then
			self:_transitionTo(FishSignals.FishState.Camouflaged)
		-- Grotto Crab: patrol, but check if player is nearby to burrow
		elseif self.Species.Behavior == "Burrower" then
			if self:_shouldBurrow() then
				self:_transitionTo(FishSignals.FishState.Burrowed)
			else
				self:_transitionTo(FishSignals.FishState.Patrol)
			end
		else
			self:_transitionTo(FishSignals.FishState.Patrol)
		end
	end
end

function FishNPC:_exitIdle()
	if self.Species.Behavior == "CoverUser" then
		self._coverStealthActive = false
	end
	self._clingTarget = nil
end

-- ============================================================
-- PATROL state (extended for Apex, Drifter, Clinger)
-- ============================================================
function FishNPC:_enterPatrol()
	if self.Species.Behavior == "ApexRoaming" then
		-- Kelp Serpent: zone-wide figure-eight patrol
		self:_advanceApexPatrol()
	elseif self.Species.Behavior == "Drifter" then
		-- Void Jellyfish: lazy loop
		if #self._patrolWaypoints == 0 then
			self.TargetPosition = self.Position + Vector3.new(
				(math.random() - 0.5) * 40,
				(math.random() - 0.5) * 8,
				(math.random() - 0.5) * 40
			)
		else
			self._patrolIndex = (self._patrolIndex % #self._patrolWaypoints) + 1
			self.TargetPosition = self._patrolWaypoints[self._patrolIndex]
		end
	elseif #self._patrolWaypoints == 0 then
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

function FishNPC:_advanceApexPatrol()
	-- Figure-eight patrol: use Lissajous curve around zone center
	self._apexPatrolPhase = self._apexPatrolPhase + 0.3
	local center = self._apexPosition or Vector3.zero
	local amplitude = 50
	self.TargetPosition = center + Vector3.new(
		math.sin(self._apexPatrolPhase) * amplitude,
		math.sin(self._apexPatrolPhase * 2) * 15,
		math.cos(self._apexPatrolPhase * 0.5) * amplitude * 0.7
	)
end

function FishNPC:_updatePatrol(dt, now)
	if self:_shouldInvestigate(now) then return end
	if self:_shouldFlee(nil) then return end

	local speed = self.Species.PatrolSpeed

	-- Copper Scaleback: stay near floor
	if self.Species.Behavior == "BottomFeeder" and self.Species.MaxHeightFromFloor then
		self.TargetPosition = Vector3.new(self.TargetPosition.X, math.min(self.TargetPosition.Y, self.Species.MaxHeightFromFloor), self.TargetPosition.Z)
	end

	-- Kelp Serpent: update figure-eight path
	if self.Species.Behavior == "ApexRoaming" then
		self:_advanceApexPatrol()
		-- Broadcast apex presence zone-wide
		if (now - self._apexAlertTimer) > 15 then
			self._apexAlertTimer = now
			self:_broadcastApexPresence()
		end
	end

	local toTarget = self.TargetPosition - self.Position
	local dist = toTarget.Magnitude

	if dist < 3 then
		if self.Species.Behavior == "ApexRoaming" then
			-- Never stop patrolling
			self:_advanceApexPatrol()
		elseif math.random() < 0.4 then
			self:_transitionTo(FishSignals.FishState.Idle)
		else
			self:_transitionTo(FishSignals.FishState.Patrol)
		end
		return
	end

	local direction = toTarget.Unit
	self.Velocity = direction * speed
	self.Position = self.Position + self.Velocity * dt

	-- Erratic behavior (Reef Dart, Kelp Darter)
	if (self.Species.Behavior == "Erratic" or self.Species.Behavior == "CoverUser") and math.random() < 0.15 then
		local burstAngle = (math.random() - 0.5) * math.pi * 0.8
		local burstDir = Vector3.new(
			math.cos(burstAngle) * direction.X - math.sin(burstAngle) * direction.Z,
			direction.Y + (math.random() - 0.5) * 0.4,
			math.sin(burstAngle) * direction.X + math.cos(burstAngle) * direction.Z
		).Unit
		self.TargetPosition = self.Position + burstDir * (8 + math.random() * 15)
	end
end

function FishNPC:_exitPatrol() end

-- ============================================================
-- INVESTIGATE state (extended: Light-attracted Squid)
-- ============================================================
function FishNPC:_enterInvestigate(data)
	self._investigateTarget = data and data.position or self._nearbyBobbers[1] and self._nearbyBobbers[1].position
	self._stateTimer = 0
end

function FishNPC:_updateInvestigate(dt, now)
	if not self._investigateTarget then
		self:_transitionTo(FishSignals.FishState.Idle)
		return
	end

	if self:_shouldFlee(nil) then return end

	local toTarget = self._investigateTarget - self.Position
	local dist = toTarget.Magnitude

	local direction = toTarget.Unit

	-- Light-attracted species (Lantern Squid): faster approach if sonar active
	if self.Species.LightAttracted then
		local speed = self.Species.PatrolSpeed * 0.5
		if self.Species.SonarAttractionMultiplier and self:_isSonarNearby() then
			speed = speed * self.Species.SonarAttractionMultiplier
		end
		self.Velocity = direction * speed
	else
		self.Velocity = direction * (self.Species.PatrolSpeed * 0.5)
	end
	self.Position = self.Position + self.Velocity * dt

	local interestRadius = self.Species.BobberInterestRadius or 8
	if dist <= interestRadius * 1.5 then
		self:_transitionTo(FishSignals.FishState.Curious, { target = self._investigateTarget })
		return
	end

	if dist > (self.Species.AwarenessRadius or 20) * 2 then
		self:_transitionTo(FishSignals.FishState.Idle)
		return
	end

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

	if self:_shouldFlee(nil) then return end

	local toTarget = self._curiousTarget - self.Position
	local dist = toTarget.Magnitude
	local interestRadius = self.Species.BobberInterestRadius or 8

	if dist > 2 then
		local direction = toTarget.Unit
		local speed = math.min(self.Species.PatrolSpeed * 0.6, 5)
		self.Velocity = direction * speed
		self.Position = self.Position + self.Velocity * dt
	else
		self.Velocity = Vector3.zero
		self._biteDelayTimer = self._biteDelayTimer + dt
		local biteMin = self.Species.BiteDelayMin or 1
		local biteMax = self.Species.BiteDelayMax or 3
		local biteDelay = biteMin + math.random() * (biteMax - biteMin)

		if self._biteDelayTimer >= biteDelay then
			self:_transitionTo(FishSignals.FishState.ReadyToBite)
		end
	end

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
-- ============================================================
function FishNPC:_enterReadyToBite()
	self._stateTimer = 0
end

function FishNPC:_updateReadyToBite(dt, now)
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

	if self:_shouldFlee(nil) then return end

	self._stateTimer = self._stateTimer + dt
	if self._stateTimer > 10 then
		self:_transitionTo(FishSignals.FishState.Idle)
	end
end

function FishNPC:_exitReadyToBite() end

-- ============================================================
-- BITING state
-- ============================================================
function FishNPC:_enterBiting()
	self._stateTimer = 0
end

function FishNPC:_updateBiting(dt, now)
	self.Velocity = Vector3.zero
	self._stateTimer = self._stateTimer + dt

	if self._stateTimer > 6 then
		self:_transitionTo(FishSignals.FishState.Idle)
	end
end

function FishNPC:_exitBiting() end

-- ============================================================
-- HOOKED state
-- ============================================================
function FishNPC:_enterHooked(data)
	self._hookedPlayerId = data and data.playerId

	-- Lantern Squid: trigger ink burst on hook
	if self.Species.InkMechanic then
		self:_triggerInkBurst()
	end

	self:_transitionTo(FishSignals.FishState.Fighting, data)
end

function FishNPC:_updateHooked(dt, now)
	self:_transitionTo(FishSignals.FishState.Fighting)
end

function FishNPC:_exitHooked() end

-- ============================================================
-- FIGHTING state
-- ============================================================
function FishNPC:_enterFighting(data)
	self._hookedPlayerId = data and data.playerId
	self.Velocity = Vector3.zero
end

function FishNPC:_updateFighting(dt, now)
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

function FishNPC:_exitFighting() end

-- ============================================================
-- FLEEING state
-- ============================================================
function FishNPC:_enterFleeing(data)
	local threatPos = data and data.threatPosition or self.Position + Vector3.new(0, 0, 20)

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

	self._fleeTimer = 2 + math.random() * 3
	self._fleeCooldownUntil = tick() + (self.Species.FleeCooldown or 8)
	self._isCurious = false
end

function FishNPC:_updateFleeing(dt, now)
	local speed = self.Species.FleeSpeed or 10
	self.Velocity = self._fleeDirection * speed
	self.Position = self.Position + self.Velocity * dt
	self._fleeTimer = self._fleeTimer - dt

	if self._fleeTimer <= 0 then
		self:_transitionTo(FishSignals.FishState.Idle)
	end
end

function FishNPC:_exitFleeing()
	self._fleeDirection = Vector3.zero
end

-- ============================================================
-- DESPAWNING state
-- ============================================================
function FishNPC:_enterDespawning()
	self._despawnTimer = 0.5
end

function FishNPC:_updateDespawning(dt, now)
	self.Velocity = Vector3.zero
	self._despawnTimer = self._despawnTimer - dt
	if self._despawnTimer <= 0 then
		self:Destroy()
	end
end

function FishNPC:_exitDespawning() end

-- ============================================================
-- PHASE 2: CAMOUFLAGED state (Kelp Stalker)
-- Fish blends against kelp stalk at 85% transparency.
-- Only revealed by sonar ping or player within 8 studs.
-- After reveal, 3s cooldown before re-camouflaging.
-- ============================================================
function FishNPC:_enterCamouflaged()
	self._camouflageTransparency = self.Species.CamouflageTransparency and self.Species.CamouflageTransparency.Far or 0.85
	self._camouflageStalk = self.Position
	self._sonarRevealedUntil = 0
	self._camouflageCooldown = 0

	local ambushMin = self.Species.AmbushDuration and self.Species.AmbushDuration.Min or 30
	local ambushMax = self.Species.AmbushDuration and self.Species.AmbushDuration.Max or 90
	self._idleTimer = ambushMin + math.random() * (ambushMax - ambushMin)

	local shimmerMin = self.Species.ShimmerInterval and self.Species.ShimmerInterval.Min or 3
	local shimmerMax = self.Species.ShimmerInterval and self.Species.ShimmerInterval.Max or 5
	self._shimmerTimer = shimmerMin + math.random() * (shimmerMax - shimmerMin)

	self.Velocity = Vector3.zero

	-- Apply visual camouflage to model (transparency)
	self:_updateCamouflageVisuals()
end

function FishNPC:_updateCamouflaged(dt, now)
	self.Velocity = Vector3.zero

	-- Check if revealed by sonar
	if now < self._sonarRevealedUntil then
		self._camouflageTransparency = 0.20 -- near-level visibility
		self._camouflageCooldown = 3.0 -- 3s cooldown after sonar reveal ends
		self:_updateCamouflageVisuals()
	end

	-- Check player proximity for reveal
	local players = self:_getPlayersInRange()
	for _, playerData in ipairs(players) do
		local dist = (playerData.position - self.Position).Magnitude
		if dist <= 8 then
			self._camouflageTransparency = 0.20 -- near: 20% blended
			self._camouflageCooldown = 3.0
			self:_updateCamouflageVisuals()
		end
	end

	-- Cooldown tick: if no sonar and no player within 8 studs, count down cooldown
	if now >= self._sonarRevealedUntil then
		if self._camouflageCooldown > 0 then
			self._camouflageCooldown = self._camouflageCooldown - dt
			if self._camouflageCooldown <= 0 then
				-- Re-camouflage
				self._camouflageTransparency = 0.85
				self:_updateCamouflageVisuals()
			end
		end
	end

	-- Check for bobbers
	if self:_shouldInvestigate(now) then return end

	-- Player within 4 studs without casting → dart away
	if self._camouflageTransparency <= 0.20 then
		for _, playerData in ipairs(players) do
			if (playerData.position - self.Position).Magnitude <= (self.Species.FleeTriggerDistance or 4) then
				-- Check if this player has an active bobber nearby
				if self._spawner and self._spawner.GetNearbyBobbers then
					local bobbers = self._spawner:GetNearbyBobbers(self.Position, 12)
					local hasBobber = false
					for _, b in ipairs(bobbers) do
						if b.playerId == playerData.playerId then
							hasBobber = true
							break
						end
					end
					if not hasBobber then
						self:_transitionTo(FishSignals.FishState.Fleeing, { threatPosition = playerData.position })
						return
					end
				end
			end
		end
	end

	-- Shimmy timer: periodic visual shimmer as a tell
	self._shimmerTimer = self._shimmerTimer - dt
	if self._shimmerTimer <= 0 then
		-- Trigger shimmer effect (client picks up via state change)
		self._shimmerTimer = (self.Species.ShimmerInterval and self.Species.ShimmerInterval.Min or 3) + math.random() * 2
	end

	-- Ambush duration expired → move to new stalk
	self._idleTimer = self._idleTimer - dt
	if self._idleTimer <= 0 then
		-- Drift to a new stalk position
		if #self._patrolWaypoints > 0 then
			self._patrolIndex = (self._patrolIndex % #self._patrolWaypoints) + 1
			self.Position = self._patrolWaypoints[self._patrolIndex]
		else
			self.Position = self.Position + Vector3.new(
				(math.random() - 0.5) * 20,
				(math.random() - 0.5) * 4,
				(math.random() - 0.5) * 20
			)
		end
		self:_transitionTo(FishSignals.FishState.Camouflaged) -- re-enter to reset timers
	end
end

function FishNPC:_exitCamouflaged()
	self._camouflageTransparency = 0
	self._camouflageCooldown = 0
	self:_updateCamouflageVisuals()
end

function FishNPC:_updateCamouflageVisuals()
	if not self._model then return end
	for _, part in ipairs(self._model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = self._camouflageTransparency
		end
	end
end

-- ============================================================
-- PHASE 2: BURROWED state (Grotto Crab)
-- Crab hides in rocky crevice. Only glowing eyes visible.
-- Player must place bait to lure it out.
-- ============================================================
function FishNPC:_enterBurrowed()
	self._burrowCrevice = self.Position
	self.Velocity = Vector3.zero
	self._idleTimer = 0 -- unlimited, stays until bait or player leaves
end

function FishNPC:_updateBurrowed(dt, now)
	self.Velocity = Vector3.zero

	-- Check if bait has been placed nearby
	if self._baitPosition then
		local baitDist = (self._baitPosition - self.Position).Magnitude
		local placementRadius = self.Species.BaitPlacementRadius or 5
		if baitDist <= placementRadius then
			self._baitTimer = (self._baitTimer or 0) + dt
			local emergeMin = self.Species.EmergeOnBaitDelay and self.Species.EmergeOnBaitDelay.Min or 5
			local emergeMax = self.Species.EmergeOnBaitDelay and self.Species.EmergeOnBaitDelay.Max or 10
			local emergeDelay = emergeMin + math.random() * (emergeMax - emergeMin)

			if self._baitTimer >= emergeDelay then
				self:_transitionTo(FishSignals.FishState.Emerging, { baitPosition = self._baitPosition })
				return
			end
		end
	end

	-- Check if player has moved far away → emerge and patrol
	local players = self:_getPlayersInRange(30) -- wider radius to detect player leaving
	if #players == 0 then
		-- Player left, crab comes out
		self:_transitionTo(FishSignals.FishState.Idle)
	end
end

function FishNPC:_exitBurrowed()
	self._baitTimer = 0
	self._burrowCrevice = nil
end

-- ============================================================
-- PHASE 2: EMERGING state (Grotto Crab)
-- Crab is coming out of crevice toward bait.
-- Player must time click when claws open (0.8s window).
-- ============================================================
function FishNPC:_enterEmerging(data)
	self._baitPosition = data and data.baitPosition or self._baitPosition
	self._stateTimer = 0
	self._biteDelayTimer = 0

	-- Move toward bait position slowly
	if self._baitPosition then
		self.TargetPosition = self._baitPosition
	end
end

function FishNPC:_updateEmerging(dt, now)
	if not self._baitPosition then
		self:_transitionTo(FishSignals.FishState.Burrowed)
		return
	end

	local toTarget = self._baitPosition - self.Position
	local dist = toTarget.Magnitude

	if dist > 1 then
		local direction = toTarget.Unit
		local speed = self.Species.PatrolSpeed or 4
		self.Velocity = direction * speed
		self.Position = self.Position + self.Velocity * dt
	else
		self.Velocity = Vector3.zero
		-- Crab has reached bait — ready for timing hook
		self:_transitionTo(FishSignals.FishState.ReadyToBite)
	end

	-- Timeout after 15 seconds
	self._stateTimer = self._stateTimer + dt
	if self._stateTimer > 15 then
		self:_transitionTo(FishSignals.FishState.Burrowed) -- gave up
	end
end

function FishNPC:_exitEmerging()
	-- Bait consumed when exiting to ReadyToBite
end

-- ============================================================
-- PHASE 2: INK CLOUD state (Lantern Squid)
-- Squid releases ink burst — server spawns black sphere, 10-stud radius, 3s.
-- Client tension meter is obscured.
-- ============================================================
function FishNPC:_enterInkCloud()
	self._inkBurstActive = true
	self._inkBurstEndTime = tick() + (self.Species.InkBurstDuration or 3.0)

	-- Notify spawner to broadcast ink burst to clients within range
	if self._spawner and self._spawner.OnInkBurst then
		self._spawner:OnInkBurst(self, self.Position, 10, self.Species.InkBurstDuration or 3.0)
	end
end

function FishNPC:_updateInkCloud(dt, now)
	self.Velocity = Vector3.zero

	-- Ink cloud fades after duration
	if now >= self._inkBurstEndTime then
		self._inkBurstActive = false
		-- Return to previous state (typically Fighting, as ink is triggered during reel)
		if self._previousState == FishSignals.FishState.Fighting then
			self:_transitionTo(FishSignals.FishState.Fighting)
		else
			self:_transitionTo(FishSignals.FishState.Idle)
		end
	end
end

function FishNPC:_exitInkCloud()
	self._inkBurstActive = false
end

-- ============================================================
-- PHASE 2: TENTACLE CONTACT state (Void Jellyfish)
-- Player has swum into tentacles. Jellyfish doesn't flee — it's a hazard.
-- Player takes 10% oxygen damage per second for 3s.
-- Jellyfish pulse accelerates (cosmetic).
-- ============================================================
function FishNPC:_enterTentacleContact(data)
	self._tentacleHazardActive = true
	self._stateTimer = 0
end

function FishNPC:_updateTentacleContact(dt, now)
	self._stateTimer = self._stateTimer + dt

	-- Check if players are still in tentacles
	local tentacleLength = self.Species.TentacleLength
	local tentacleMin = tentacleLength and tentacleLength.Min or 30
	local players = self:_getPlayersInRange(tentacleMin)

	local stillInTentacles = false
	for _, playerData in ipairs(players) do
		-- Check if player is below the bell within tentacle range
		local verticalDist = self.Position.Y - playerData.position.Y -- Jellyfish above, player below
		if verticalDist > 0 and verticalDist <= tentacleMin then
			stillInTentacles = true
			break
		end
	end

	if not stillInTentacles or self._stateTimer > (self.Species.TentacleOxygenPenaltyDuration or 3.0) then
		self._tentacleHazardActive = false
		-- Return to patrol
		self:_transitionTo(FishSignals.FishState.Patrol)
	end
end

function FishNPC:_exitTentacleContact()
	self._tentacleHazardActive = false
end

-- ============================================================
-- PHASE 2: ENRAGED state (Kelp Serpent)
-- After failed hook, Serpent accelerates and leaves the area.
-- ============================================================
function FishNPC:_enterEnraged()
	local enragedDuration = self.Species.EnragedDuration or 20
	self._enragedTimer = enragedDuration

	-- Pick a direction away from any nearby players
	local fleeDir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
	local players = self:_getPlayersInRange(self.Species.AwarenessRadius or 50)
	if #players > 0 then
		fleeDir = (self.Position - players[1].position).Unit
		if fleeDir.Magnitude < 0.1 then
			fleeDir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
		end
	end
	self._fleeDirection = fleeDir
end

function FishNPC:_updateEnraged(dt, now)
	local speed = self.Species.EnragedAcceleration or 12
	self.Velocity = self._fleeDirection * speed
	self.Position = self.Position + self.Velocity * dt

	self._enragedTimer = self._enragedTimer - dt
	if self._enragedTimer <= 0 then
		-- Calmed down, return to patrol
		self:_transitionTo(FishSignals.FishState.Patrol)
	end
end

function FishNPC:_exitEnraged() end

-- ============================================================
-- Helper: Trigger ink burst (called on hook for Lantern Squid)
-- ============================================================
function FishNPC:_triggerInkBurst()
	self:_transitionTo(FishSignals.FishState.InkCloud)
end

-- ============================================================
-- Helper: Check if player should trigger burrow (Grotto Crab)
-- ============================================================
function FishNPC:_shouldBurrow()
	if self.Species.Behavior ~= "Burrower" then return false end
	local fleeDist = self.Species.FleeTriggerDistance or 15
	local players = self:_getPlayersInRange(fleeDist)
	return #players > 0
end

-- ============================================================
-- Helper: Check if sonar is nearby (for light-attracted squid)
-- ============================================================
function FishNPC:_isSonarNearby()
	if not self._spawner then return false end
	if self._spawner.IsSonarActive then
		return self._spawner:IsSonarActive(self.Position, 25)
	end
	return false
end

-- ============================================================
-- Helper: Broadcast apex presence to zone
-- ============================================================
function FishNPC:_broadcastApexPresence()
	if not self.Species.ApexPresence then return end
	if self._spawner and self._spawner.OnApexPresence then
		self._spawner:OnApexPresence(self, self.Position, self.Species.ApexAlertRadius or 40)
	end
end

-- ============================================================
-- Helper: Get players within range
-- ============================================================
function FishNPC:_getPlayersInRange(maxRadius)
	if self._spawner and self._spawner.GetNearbyPlayers then
		return self._spawner:GetNearbyPlayers(self.Position, maxRadius or self.Species.AwarenessRadius or 15)
	end
	return {}
end

-- ============================================================
-- Awareness checks (extended for Phase 2 species)
-- ============================================================
function FishNPC:_shouldInvestigate(now)
	if now - self._lastBobberCheck < 0.5 then return false end
	self._lastBobberCheck = now

	-- Skip if in states where investigation is blocked
	if self._state == FishSignals.FishState.Fleeing
		or self._state == FishSignals.FishState.Hooked
		or self._state == FishSignals.FishState.Fighting
		or self._state == FishSignals.FishState.Despawning
		or self._state == FishSignals.FishState.Burrowed
		or self._state == FishSignals.FishState.Enraged
		or self._state == FishSignals.FishState.InkCloud
		or self._state == FishSignals.FishState.TentacleContact then
		return false
	end

	-- Camouflaged Kelp Stalker: only investigate if revealed (transparency < 50%)
	if self._state == FishSignals.FishState.Camouflaged and self._camouflageTransparency > 0.50 then
		return false -- still too blended to notice bobbers
	end

	-- Burrower / Grotto Crab: doesn't investigate bobbers, uses bait
	if self.Species.Behavior == "Burrower" and self.Species.CatchMechanic == "Bait" then
		return false
	end

	-- Light-attracted (Lantern Squid): attracted to player light/sonar
	if self.Species.LightAttracted then
		-- Check for nearby players (attracted to player light)
		local players = self:_getPlayersInRange(self.Species.CuriosityRadius or 20)
		if #players > 0 then
			self:_transitionTo(FishSignals.FishState.Investigate, { position = players[1].position })
			return true
		end
		return false
	end

	-- Standard bobber check
	if self._spawner and self._spawner.GetNearbyBobbers then
		self._nearbyBobbers = self._spawner:GetNearbyBobbers(self.Position, self.Species.AwarenessRadius or 15)
	else
		self._nearbyBobbers = {}
	end

	for _, bobber in ipairs(self._nearbyBobbers) do
		local dist = (bobber.position - self.Position).Magnitude
		local interestRadius = self.Species.BobberInterestRadius or 8

		if dist <= interestRadius then
			self:_transitionTo(FishSignals.FishState.Investigate, { position = bobber.position })
			return true
		elseif dist <= (self.Species.AwarenessRadius or 15) then
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
	-- Species that never flee (Apex, PassiveHazard, Drifter, Luring)
	if self.Species.Temperament == "Apex" or self.Species.Temperament == "PassiveHazard" then
		return false
	end
	if self.Species.Behavior == "Drifter" then return false end -- Void Jellyfish: unfazed
	if self.Species.FleeSpeed == 0 or self.Species.FleeTriggerDistance == 0 then
		if self.Species.Behavior == "Ambush" and threatPosition then
			local dist = (threatPosition - self.Position).Magnitude
			local dimDist = self.Species.DimDistance or 8
			if dist <= dimDist then
				if self._spawner and self._spawner.OnAnglerDimmed then
					self._spawner:OnAnglerDimmed(self)
				end
			end
		end
		return false
	end

	if tick() < self._fleeCooldownUntil then return false end

	if self._state == FishSignals.FishState.Fleeing
		or self._state == FishSignals.FishState.Hooked
		or self._state == FishSignals.FishState.Fighting
		or self._state == FishSignals.FishState.Despawning
		or self._state == FishSignals.FishState.Enraged
		or self._state == FishSignals.FishState.Burrowed then
		return false
	end

	local fleeDist = self.Species.FleeTriggerDistance or 5

	if threatPosition then
		local dist = (threatPosition - self.Position).Magnitude
		if dist <= fleeDist then
			-- Super-fast flee for camouflage species discovered up close
			if self.Species.Behavior == "Camouflage" then
				self:_transitionTo(FishSignals.FishState.Fleeing, { threatPosition = threatPosition })
				return true
			end
			self:_transitionTo(FishSignals.FishState.Fleeing, { threatPosition = threatPosition })
			return true
		end
	end

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

function FishNPC:OnBobberNearby(bobberPosition, playerId)
	if self._state == FishSignals.FishState.Curious
		or self._state == FishSignals.FishState.ReadyToBite
		or self._state == FishSignals.FishState.Biting then
		return
	end

	-- Burrower ignores bobbers
	if self.Species.Behavior == "Burrower" and self.Species.CatchMechanic == "Bait" then
		return
	end

	-- Camouflaged: only investigate if revealed
	if self._state == FishSignals.FishState.Camouflaged and self._camouflageTransparency > 0.50 then
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

-- Called when bait is placed (Grotto Crab mechanic)
function FishNPC:OnBaitPlaced(baitPosition)
	if self.Species.Behavior == "Burrower" then
		self._baitPosition = baitPosition
		self._baitTimer = 0
		-- If burrowed, immediately begin countdown
		if self._state == FishSignals.FishState.Burrowed then
			-- Will be detected in _updateBurrowed
		elseif self._state == FishSignals.FishState.Idle or self._state == FishSignals.FishState.Patrol then
			self:_transitionTo(FishSignals.FishState.Burrowed)
		end
	end
end

-- Called by sonar ping to reveal camouflaged fish
function FishNPC:OnSonarPing()
	if self.Species.Behavior == "Camouflage" or self.Species.SonarDetectable then
		self._sonarRevealedUntil = tick() + 1.5 -- revealed for 1.5s (matching sonar highlight duration)
		if self._state == FishSignals.FishState.Camouflaged then
			self._camouflageTransparency = 0.20
			self._camouflageCooldown = 3.0
			self:_updateCamouflageVisuals()
		end
	end
end

-- Called to force fish into fleeing state (Apex Presence)
function FishNPC:OnApexNearby(apexPosition)
	if self.Species.Temperament == "Apex" or self.Species.Temperament == "PassiveHazard" then
		return -- apex ignores other apex, jellyfish ignores serpent
	end
	if self._state == FishSignals.FishState.Hooked
		or self._state == FishSignals.FishState.Fighting
		or self._state == FishSignals.FishState.Despawning
		or self._state == FishSignals.FishState.Burrowed then
		return
	end
	self:_transitionTo(FishSignals.FishState.Fleeing, { threatPosition = apexPosition })
end

-- Tentacle collision check (called by spawner periodically)
function FishNPC:CheckTentacleCollision(playerPosition)
	if self.Species.Behavior ~= "Drifter" then return false end
	if not self.Species.TentacleLength then return false end

	local tentacleMin = self.Species.TentacleLength.Min or 30
	local tentacleMax = self.Species.TentacleLength.Max or 40

	-- Player must be below the Jellyfish bell within tentacle range
	local verticalDist = self.Position.Y - playerPosition.Y
	local horizontalDist = Vector2.new(
		playerPosition.X - self.Position.X,
		playerPosition.Z - self.Position.Z
	).Magnitude

	if verticalDist > 0 and verticalDist <= tentacleMax and horizontalDist <= 8 then
		if self._state ~= FishSignals.FishState.TentacleContact then
			self:_transitionTo(FishSignals.FishState.TentacleContact, { playerPosition = playerPosition })
		end
		return true
	end
	return false
end

-- Kelp Serpent warning display check
function FishNPC:CheckWarningDisplay(playerPosition)
	if self.Species.Behavior ~= "ApexRoaming" then return false end
	local warningDist = self.Species.WarningDisplayDistance or 10
	local dist = (playerPosition - self.Position).Magnitude
	return dist <= warningDist
end

function FishNPC:OnHookAttempt(success)
	if success then
		-- Lantern Squid: ink burst on hook
		if self.Species.InkMechanic then
			self:_triggerInkBurst()
		end
		self:_transitionTo(FishSignals.FishState.Hooked)
	else
		-- Kelp Serpent: enrage on failed hook
		if self.Species.Behavior == "ApexRoaming" then
			self:_transitionTo(FishSignals.FishState.Enraged)
		else
			self:_transitionTo(FishSignals.FishState.Fleeing, {
				threatPosition = self.Position + Vector3.new(0, 0, -10),
			})
		end
	end
end

function FishNPC:OnLineSnap()
	self._hookedPlayerId = nil
	self:_transitionTo(FishSignals.FishState.Fleeing, {
		threatPosition = self.Position + Vector3.new(0, 0, -15),
	})
end

function FishNPC:OnEscape()
	self._hookedPlayerId = nil
	self:_transitionTo(FishSignals.FishState.Fleeing, {
		threatPosition = self.Position + Vector3.new(0, 0, -15),
	})
end

function FishNPC:OnCaught()
	self:_transitionTo(FishSignals.FishState.Despawning)
end

function FishNPC:OnPlayerNearby(playerPosition)
	self:_shouldFlee(playerPosition)
end

function FishNPC:IsBiteReady()
	return self._state == FishSignals.FishState.ReadyToBite
		or self._state == FishSignals.FishState.Biting
end

function FishNPC:IsHooked()
	return self._state == FishSignals.FishState.Hooked
		or self._state == FishSignals.FishState.Fighting
end

function FishNPC:GetState()
	return self._state
end

function FishNPC:GetInterestRadius()
	return self.Species.BobberInterestRadius or 8
end

function FishNPC:GetPosition()
	return self.Position
end

function FishNPC:SetWaypoints(waypoints)
	self._patrolWaypoints = waypoints or {}
	self._patrolIndex = 1
end

function FishNPC:SetDespawnTimer(seconds)
	self._despawnAt = tick() + seconds
end

function FishNPC:CheckDespawn(now)
	now = now or tick()
	if self._despawnAt and now >= self._despawnAt then
		self:_transitionTo(FishSignals.FishState.Despawning)
		return true
	end
	return false
end

-- ============================================================
-- Zone awareness
-- ============================================================
function FishNPC:SetZone(zoneKey)
	self._currentZone = zoneKey
end

function FishNPC:SetApexCenter(centerPosition)
	self._apexPosition = centerPosition
end

-- ============================================================
-- Cleanup
-- ============================================================
function FishNPC:Destroy()
	self._alive = false

	if self._alignPosition then
		self._alignPosition:Destroy()
		self._alignPosition = nil
	end
	if self._alignOrientation then
		self._alignOrientation:Destroy()
		self._alignOrientation = nil
	end

	if self._model then
		self._model:Destroy()
		self._model = nil
	end

	self._rootPart = nil
	self._spawner = nil
end

return FishNPC
