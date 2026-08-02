--[[
	SurfaceFishAI.lua
	Deep Tide Studios — Server Surface Fish NPC (Phase 3)
	Lightweight fish AI for the shared ocean layer. Fish move on the 2D
	surface plane (y ≈ -0.5..-8, waterline 0), run school/churn/swarm/glide/
	patrol behaviors, react to boats (flee / part / curious), and drive the
	same bobber → bite → hook → reel loop as the underwater FishNPC.

	API-compatible with FishNPC where FishSpawner / FishingService need it:
	  new / Initialize / Destroy / _transitionTo / OnBobberNearby /
	  OnHookAttempt / OnLineSnap / OnEscape / OnCaught / IsBiteReady /
	  IsHooked / GetState / GetInterestRadius / GetPosition /
	  SetDespawnTimer / CheckDespawn / SetZone
	Schooling fields (_isSchoolLeader, _school, _isSchoolFollower,
	_schoolLeader, _state) match FishSpawner's school propagation logic.

	Movement is server-driven via SetPivot on an anchored model (no physics
	solver) — cheap at 30 fish/server.
]]

local HttpService = game:GetService("HttpService")
local FishSignals = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("NPC"):WaitForChild("FishSignals"))

local SurfaceFishAI = {}
SurfaceFishAI.__index = SurfaceFishAI

local UPDATE_INTERVAL = 0.5    -- 2 Hz update (30 fish = 60 ticks/s)
local WATERLINE = 0

-- Species-specific behavior profiles (driven by FishSpecies data + these rules)
local GLIDERS = { FlyingFish = true }                      -- periodic burst + rise
local CHURNERS = { SilverSkipjack = true, BlueSardine = true } -- school churn/swarm
local STRIKERS = { Bonito = true }                         -- fast patrol, instant strike
local WARY = { Sailfish = true }                           -- flee if boat within 30
local STORM_APEX = { StormMarlin = true }                  -- leave server on failed hook
local UNFAZED = { Moonfish = true }                        -- never flees

-- ============================================================
-- Constructor
-- ============================================================
function SurfaceFishAI.new(species, spawnPosition, config)
	config = config or {}
	local self = setmetatable({}, SurfaceFishAI)

	self.Id = HttpService:GenerateGUID(false)
	self.Species = species
	self.SpeciesKey = species.Key

	self.Position = spawnPosition
	self.TargetPosition = spawnPosition
	self.Velocity = Vector3.zero
	self.Rotation = 0

	self._state = FishSignals.FishState.Idle
	self._previousState = nil
	self._stateEnterTime = tick()
	self._stateTimer = 0

	self._patrolWaypoints = config.Waypoints or {}
	self._patrolIndex = 1
	self._wanderTarget = nil

	self._biteReady = false
	self._biteDelayUntil = 0
	self._investigateTarget = nil

	self._fleeUntil = 0
	self._despawnAt = nil
	self._resurfacePos = nil
	self._alive = false

	-- Glide timing (Flying Fish)
	self._glidePhase = 0
	self._glideCooldown = 0

	-- Schooling
	self._isSchoolLeader = false
	self._isSchoolFollower = false
	self._school = nil
	self._schoolLeader = nil

	-- Bobber memory (to keep interest while waiting)
	self._nearbyBobber = nil

	self._model = nil
	self._spawner = nil
	self._currentZone = config.Zone or "Surface"

	return self
end

-- ============================================================
-- Initialize: anchor the model, start the update loop
-- ============================================================
function SurfaceFishAI:Initialize(model, spawnerRef)
	self._model = model
	self._spawner = spawnerRef

	-- Surface fish are fully server-driven: anchor all parts
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end
	model.PrimaryPart = model.PrimaryPart or model:FindFirstChild("Body")
	self:_applyModel()

	self._alive = true
	task.spawn(function()
		while self._alive and self._model and self._model.Parent do
			self:Update(UPDATE_INTERVAL)
			task.wait(UPDATE_INTERVAL)
		end
	end)
end

-- ============================================================
-- FSM
-- ============================================================
function SurfaceFishAI:_transitionTo(newState, data)
	if self._state == newState then return end
	self._previousState = self._state
	self._state = newState
	self._stateEnterTime = tick()
	self._stateTimer = 0
	self._transitionData = data
end

function SurfaceFishAI:GetState() return self._state end

function SurfaceFishAI:IsBiteReady()
	return self._state == FishSignals.FishState.ReadyToBite
		or self._state == FishSignals.FishState.Biting
end

function SurfaceFishAI:IsHooked()
	return self._state == FishSignals.FishState.Hooked
		or self._state == FishSignals.FishState.Fighting
end

function SurfaceFishAI:GetInterestRadius()
	return self.Species.BobberInterestRadius or 8
end

function SurfaceFishAI:GetPosition() return self.Position end

-- ============================================================
-- Main update (2 Hz)
-- ============================================================
function SurfaceFishAI:Update(dt)
	local now = tick()
	self._stateTimer = self._stateTimer + dt

	-- Despawn timer
	if self._despawnAt and now >= self._despawnAt then
		self._state = FishSignals.FishState.Despawning
		return
	end

	-- Glide phase for Flying Fish
	if GLIDERS[self.SpeciesKey] and now >= self._glideCooldown then
		self._glidePhase = 1.0
		self._glideCooldown = now + 5 + math.random() * 5
	end
	if self._glidePhase > 0 then
		self._glidePhase = math.max(0, self._glidePhase - dt)
	end

	local state = self._state

	if state == FishSignals.FishState.Despawning then return end

	if state == FishSignals.FishState.Hooked or state == FishSignals.FishState.Fighting then
		-- Follow the bobber/boat while hooked (visual only; reel math is server-side)
		if self._nearbyBobber then
			self:MoveToward(self._nearbyBobber, self.Species.FleeSpeed or 8, dt)
		end
		self:_applyModel()
		return
	end

	-- Fleeing: move away, then resurface elsewhere
	if state == FishSignals.FishState.Fleeing then
		if now < self._fleeUntil then
			local away = (self.Position - (self._fleeFrom or self.Position)).Unit
			self.Position = self.Position + away * (self.Species.FleeSpeed or 12) * dt
			self.Position = Vector3.new(self.Position.X, math.max(-10, self.Position.Y - 2 * dt), self.Position.Z)
			self:_applyModel()
			return
		end
		-- Resurface 30-50 studs away after fleeing
		local angle = math.random() * math.pi * 2
		local dist = 30 + math.random() * 20
		self.Position = Vector3.new(
			math.clamp(self.Position.X + math.cos(angle) * dist, -1400, 1400),
			-2,
			math.clamp(self.Position.Z + math.sin(angle) * dist, -1400, 1400)
		)
		self:_transitionTo(FishSignals.FishState.Idle)
		self:_applyModel()
		return
	end

	-- Boat awareness (players are a good proxy for boat positions)
	if not UNFAZED[self.SpeciesKey] then
		if self:_checkBoatThreat() then return end
	end

	if state == FishSignals.FishState.Investigate then
		if self._investigateTarget then
			self:MoveToward(self._investigateTarget, self.Species.PatrolSpeed or 6, dt)
			if now >= self._biteDelayUntil then
				self._biteReady = true
				self:_transitionTo(FishSignals.FishState.ReadyToBite)
			end
		else
			self:_transitionTo(FishSignals.FishState.Patrol)
		end
	elseif state == FishSignals.FishState.ReadyToBite or state == FishSignals.FishState.Biting then
		-- Hold near the bobber, churn
		if self._nearbyBobber then
			local to = (self._nearbyBobber - self.Position)
			local dist = to.Magnitude
			if dist > 3 then
				self:MoveToward(self._nearbyBobber, self.Species.PatrolSpeed or 4, dt)
			else
				-- churn: orbit the bobber
				local orbit = Vector3.new(-to.Z, 0, to.X).Unit
				self.Position = self.Position + orbit * 1.5 * dt
			end
		end
		self._biteReady = true
	else
		-- Idle / Patrol / school movement
		self:_updatePatrol(dt, now)
	end

	self:_applyModel()
end

-- ============================================================
-- Patrol / school movement
-- ============================================================
function SurfaceFishAI:_updatePatrol(dt, now)
	local species = self.Species

	-- School followers track the leader
	if self._isSchoolFollower and self._schoolLeader and self._schoolLeader.Position then
		local leader = self._schoolLeader
		local offset = self._schoolOffset or Vector3.new(1, 0, 0)
		local target = leader.Position + offset
		local speed = species.PatrolSpeed or 2
		if self._glidePhase > 0 then speed = speed * 1.6 end
		self:MoveToward(target, speed, dt)
		return
	end

	-- Leader / solo patrol along waypoints or a wandering target
	local waypoints = self._patrolWaypoints
	if #waypoints > 0 then
		local wp = waypoints[self._patrolIndex]
		if wp then
			local to = wp - self.Position
			local dist = to.Magnitude
			local speed = species.PatrolSpeed or 4
			if self._glidePhase > 0 then speed = speed * 1.6 end
			-- Churners orbit their waypoint in a loose circle
			if CHURNERS[self.SpeciesKey] then
				local orbit = Vector3.new(-to.Z, 0, to.X).Unit
				self.Position = self.Position + orbit * (species.PatrolSpeed or 4) * dt * 0.5
				speed = speed * 0.6
			end
			self:MoveToward(wp, speed, dt)
			if dist < 4 then
				self._patrolIndex = (self._patrolIndex % #waypoints) + 1
				-- Leader drifts the school: followers get offsets around leader
				if self._school then
					for i, follower in ipairs(self._school) do
						if follower ~= self then
							local ang = (i / #self._school) * math.pi * 2
							follower._schoolOffset = Vector3.new(math.cos(ang) * 3, 0, math.sin(ang) * 3)
						end
					end
				end
			end
			return
		end
	end

	-- Wander fallback
	if not self._wanderTarget or (self.Position - self._wanderTarget).Magnitude < 5 then
		local ang = math.random() * math.pi * 2
		local dist = 20 + math.random() * 30
		self._wanderTarget = Vector3.new(
			math.clamp(self.Position.X + math.cos(ang) * dist, -1400, 1400),
			-2,
			math.clamp(self.Position.Z + math.sin(ang) * dist, -1400, 1400)
		)
	end
	self:MoveToward(self._wanderTarget, species.PatrolSpeed or 3, dt)
end

-- ============================================================
-- Boat / player threat
-- ============================================================
function SurfaceFishAI:_checkBoatThreat()
	local spawner = self._spawner
	if not spawner or not spawner.GetNearbyPlayers then return false end

	local radius = self.Species.AwarenessRadius or 15
	local nearby = spawner:GetNearbyPlayers(self.Position, radius)
	if #nearby == 0 then return false end

	-- Wary species flee at a distance; others only when close
	local fleeRadius = WARY[self.SpeciesKey] and math.max(radius, 30) or radius
	local flee = false
	for _, entry in ipairs(nearby) do
		if entry.distance <= fleeRadius then
			-- Skittish rule: anchored approaches keep schools calm (spawner tracks
			-- all players; boats at speed count as threats). For the prototype,
			-- any player inside the flee radius triggers a dive.
			flee = true
			break
		end
	end

	if flee and self._state ~= FishSignals.FishState.Fleeing then
		self:_flee(nearby[1] and nearby[1].position or self.Position)
		return true
	end
	return false
end

function SurfaceFishAI:_flee(fromPosition)
	self._fleeFrom = fromPosition
	self._fleeUntil = tick() + 8   -- dive for 8s, then resurface (GDD: 30-50 studs away)
	self._biteReady = false
	self._nearbyBobber = nil
	self._transitionTo(FishSignals.FishState.Fleeing)
end

-- ============================================================
-- Bobber interaction
-- ============================================================
function SurfaceFishAI:OnBobberNearby(bobberPosition, playerId)
	if self:IsHooked() then return end
	if self._state == FishSignals.FishState.Fleeing then return end

	local dx = bobberPosition.X - self.Position.X
	local dz = bobberPosition.Z - self.Position.Z
	local dist = math.sqrt(dx * dx + dz * dz)
	local interest = self:GetInterestRadius()

	if dist <= interest then
		self._nearbyBobber = bobberPosition
		-- Bite delay per species (GDD 4.6.5; Bonito strikes instantly with bait)
		local minB, maxB = self.Species.BiteDelayMin or 1, self.Species.BiteDelayMax or 3
		self._biteDelayUntil = tick() + minB + math.random() * (maxB - minB)
		self._investigateTarget = bobberPosition
		if self._state ~= FishSignals.FishState.ReadyToBite
			and self._state ~= FishSignals.FishState.Biting
			and self._state ~= FishSignals.FishState.Investigate then
			self:_transitionTo(FishSignals.FishState.Investigate)
		end
	end
end

-- ============================================================
-- Hook lifecycle (called by FishingService)
-- ============================================================
function SurfaceFishAI:OnHookAttempt(success)
	if success then
		self._biteReady = false
		self:_transitionTo(FishSignals.FishState.Hooked)
	else
		-- Failed hook: Storm Marlin leaves the server for the rest of the storm
		if STORM_APEX[self.SpeciesKey] then
			self._despawnAt = tick()  -- despawn immediately
			self._state = FishSignals.FishState.Despawning
			return
		end
		self:_flee(self.Position)
		self._fleeUntil = tick() + 4
	end
end

function SurfaceFishAI:OnLineSnap()
	if self._state == FishSignals.FishState.Hooked or self._state == FishSignals.FishState.Fighting then
		self:_flee(self.Position)
	end
end

function SurfaceFishAI:OnEscape()
	if self._state == FishSignals.FishState.Hooked or self._state == FishSignals.FishState.Fighting then
		self:_flee(self.Position)
	end
end

function SurfaceFishAI:OnCaught()
	self._state = FishSignals.FishState.Despawning
end

-- ============================================================
-- Movement helpers
-- ============================================================
function SurfaceFishAI:MoveToward(target, speed, dt)
	local to = target - self.Position
	to = Vector3.new(to.X, 0, to.Z)
	local dist = to.Magnitude
	if dist < 0.5 then return end

	local dir = to / dist
	local step = speed * dt
	local newX = self.Position.X + dir.X * step
	local newZ = self.Position.Z + dir.Z * step

	-- Gliders briefly rise above the water (leap)
	local y = self.Position.Y
	if GLIDERS[self.SpeciesKey] and self._glidePhase > 0.5 then
		y = -0.3
	else
		y = math.clamp(y, -8, -1.5)
	end

	self.Position = Vector3.new(
		math.clamp(newX, -1400, 1400),
		y,
		math.clamp(newZ, -1400, 1400)
	)
	self.Velocity = dir * speed
	self.Rotation = math.atan2(dir.X, dir.Z)
end

function SurfaceFishAI:_applyModel()
	if not self._model then return end
	local y = self.Position.Y
	-- Model body sits at the fish position; churners show as surface splashes
	local cframe = CFrame.new(self.Position.X, y, self.Position.Z) * CFrame.Angles(0, self.Rotation, 0)
	self._model:SetPivot(cframe)
end

-- ============================================================
-- Despawn / zone / cleanup
-- ============================================================
function SurfaceFishAI:SetDespawnTimer(seconds)
	self._despawnAt = tick() + seconds
end

function SurfaceFishAI:CheckDespawn(now)
	now = now or tick()
	if self._despawnAt and now >= self._despawnAt then
		self._state = FishSignals.FishState.Despawning
		return true
	end
	return false
end

function SurfaceFishAI:SetZone(zoneKey)
	self._currentZone = zoneKey
end

function SurfaceFishAI:Destroy()
	self._alive = false
	if self._model then
		self._model:Destroy()
		self._model = nil
	end
end

return SurfaceFishAI
