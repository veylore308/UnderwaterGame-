--[[
	FishingController.lua
	Deep Tide Studios — Client Controller
	Full fishing gameplay loop: equip rod, aim, cast, hook minigame,
	reel minigame, catch/lose. Coordinates FishingRodHandler (visuals),
	FishingHUD (UI), and server-authoritative FishingService.

	Phase 2: Sonar system, bait placement, environmental hazards
	(kelp entanglement, clearing current, tentacle damage, air pockets),
	zone transition handling.
]]

local Knit = require(game:GetService("ReplicatedStorage"):WaitForChild("Knit"))
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))

local FishingRodHandler = require(script.Parent.Parent:WaitForChild("Handlers"):WaitForChild("FishingRodHandler"))
local FishingHUD = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("FishingHUD"))

local FishingController = Knit.CreateController({
	Name = "FishingController",
})

-- ============================================================
-- State
-- ============================================================
FishingController._isFishing = false
FishingController._phase = "Idle"
FishingController._castId = nil
FishingController._tension = 0
FishingController._progress = 0

FishingController._cachedEquippedRod = "BambooRod"

FishingController._aimStartTime = 0
FishingController._aimPower = 0

FishingController._reelLoop = nil
FishingController._isReeling = false
FishingController._reelTickAccumulator = 0
FishingController._lastReelTickTime = 0
FishingController._resultHandled = false

FishingController._biteTimer = nil
FishingController._biteStartTime = 0
FishingController._currentBiteDelay = 0
FishingController._pendingSpecies = nil

FishingController._rodHandler = nil
FishingController._fishingHUD = nil

-- Phase 2: Sonar state
FishingController._sonarRange = 0
FishingController._sonarLoopConnection = nil
FishingController._sonarHighlights = {} -- { FishId = { GuiObject, expiryTime } }
FishingController._lastSonarPingTime = 0
FishingController._sonarPingInterval = 3.0

-- Phase 2: Environmental hazard state
FishingController._currentZone = "SunkenShallows"
FishingController._currentDepth = 0
FishingController._isEntangled = false
FishingController._entangleTimer = 0
FishingController._inCurrent = false
FishingController._oxygenLevel = 100
FishingController._airPocketCooldowns = {} -- { [pocketName] = cooldownEndTime }
FishingController._tentacleDamageTimer = 0

-- Phase 2: Zone transition
FishingController._zoneTransitionActive = false

-- ============================================================
-- Init / Start
-- ============================================================

function FishingController:KnitStart()
	print("[FishingController] Started (Phase 2)")

	self._rodHandler = FishingRodHandler.new()
	self._fishingHUD = FishingHUD.new()

	self:_wirePlayerDataService()
	self:_equipDefaultRod()

	-- Phase 2: Start environmental monitor loop
	self:_startEnvironmentMonitor()

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		self:_handleInput(input, true)
	end)

	UserInputService.InputEnded:Connect(function(input)
		self:_handleInput(input, false)
	end)
end

function FishingController:KnitInit()
	local fishingService = self.Services.FishingService
	if not fishingService then
		warn("[FishingController] FishingService not available")
		return
	end

	fishingService.Client.FishHooked:Connect(function(fishData)
		self:_onFishHooked(fishData)
	end)

	fishingService.Client.FishCaught:Connect(function(fishData, rewards)
		self:_onFishCaught(fishData, rewards)
	end)

	fishingService.Client.LineSnapped:Connect(function()
		self:_onLineSnapped()
	end)

	fishingService.Client.FishEscaped:Connect(function(reason)
		self:_onFishEscaped(reason)
	end)

	-- Phase 2: Sonar ping handler
	fishingService.Client.SonarPing:Connect(function(pingData)
		self:_onSonarPing(pingData)
	end)

	-- Phase 2: Ink burst handler
	fishingService.Client.InkBurst:Connect(function(fishId, position, radius, duration)
		self:_onInkBurst(fishId, position, radius, duration)
	end)

	-- Phase 2: Apex presence warning
	fishingService.Client.ApexPresence:Connect(function(position, message)
		self:_onApexPresence(position, message)
	end)

	-- Phase 2: Zone transition notification
	fishingService.Client.ZoneTransition:Connect(function(oldZone, newZone, depth)
		self:_onZoneTransition(oldZone, newZone, depth)
	end)
end

-- ============================================================
-- PlayerDataService Wiring
-- ============================================================

function FishingController:_wirePlayerDataService()
	local playerDataService = self.Services.PlayerDataService
	if not playerDataService or not playerDataService.Client then
		return
	end

	local function onPlayerDataReceived(data)
		if data and data.Gear and data.Gear.EquippedRod then
			self._cachedEquippedRod = data.Gear.EquippedRod
			if self._rodHandler then
				self._rodHandler:Equip(self._cachedEquippedRod)
			end
			-- Phase 2: Update sonar range based on equipped rod
			self:_updateSonarRange()
		end
	end

	playerDataService.Client.GetPlayerData:Connect(onPlayerDataReceived)
	playerDataService.Client.DataUpdated:Connect(onPlayerDataReceived)

	task.spawn(function()
		local player = Players.LocalPlayer
		local data = playerDataService.Client.GetPlayerData:Call(player)
		if data then
			onPlayerDataReceived(data)
		end
	end)
end

-- ============================================================
-- Rod Equip
-- ============================================================

function FishingController:_equipDefaultRod()
	self:_doEquipRod(self._cachedEquippedRod)
end

function FishingController:_doEquipRod(rodKey)
	if self._rodHandler then
		self._rodHandler:Equip(rodKey)
		print("[FishingController] Rod equipped:", rodKey)
	end
	self:_updateSonarRange()
end

-- ============================================================
-- Phase 2: Sonar Range Update
-- ============================================================
function FishingController:_updateSonarRange()
	local rodStats = self:_getRodStats()
	if rodStats and rodStats.SonarRange and rodStats.SonarRange > 0 then
		self._sonarRange = rodStats.SonarRange
		self:_startSonarLoop()
	else
		self._sonarRange = 0
		self:_stopSonarLoop()
	end
end

-- ============================================================
-- Phase 2: Sonar Loop (client-side)
-- ============================================================
function FishingController:_startSonarLoop()
	if self._sonarLoopConnection then return end

	print("[FishingController] Sonar activated, range:", self._sonarRange)

	self._sonarLoopConnection = RunService.Heartbeat:Connect(function(dt)
		if self._sonarRange <= 0 then
			self:_stopSonarLoop()
			return
		end

		self._lastSonarPingTime = self._lastSonarPingTime + dt
		if self._lastSonarPingTime >= self._sonarPingInterval then
			self._lastSonarPingTime = 0
			self:_playSonarPulseVFX()
		end

		-- Clean expired highlights
		local now = tick()
		for fishId, highlight in pairs(self._sonarHighlights) do
			if now > highlight.expiryTime then
				self:_removeSonarHighlight(fishId)
			end
		end
	end)
end

function FishingController:_stopSonarLoop()
	if self._sonarLoopConnection then
		self._sonarLoopConnection:Disconnect()
		self._sonarLoopConnection = nil
	end
	-- Clear all highlights
	for fishId, _ in pairs(self._sonarHighlights) do
		self:_removeSonarHighlight(fishId)
	end
	self._sonarHighlights = {}
end

-- ============================================================
-- Phase 2: Sonar Ping Handler (from server)
-- ============================================================
function FishingController:_onSonarPing(pingData)
	if not pingData or not pingData.DetectedFish then return end

	local now = tick()
	local highlightDuration = 1.5 -- matching GDD: silhouettes persist for 1.5s

	for _, fishData in ipairs(pingData.DetectedFish) do
		-- Skip fish already highlighted
		if not self._sonarHighlights[fishData.FishId] then
			self:_createSonarHighlight(fishData, now + highlightDuration)
		else
			-- Refresh expiry
			self._sonarHighlights[fishData.FishId].expiryTime = now + highlightDuration
		end
	end
end

function FishingController:_createSonarHighlight(fishData, expiryTime)
	-- Create a client-side highlight for a fish detected by sonar.
	-- In production, this would use Highlight instances or BillboardGuis
	-- attached to the fish model. For now, we create a simple billboard.

	local color = self:_rarityToColor(fishData.Rarity)

	-- Look for the fish model in workspace
	local fishModel = self:_findFishModel(fishData.FishId)
	if not fishModel then
		-- If we can't find the model, store it for when it appears
		self._sonarHighlights[fishData.FishId] = {
			position = fishData.Position,
			color = color,
			rarity = fishData.Rarity,
			speciesName = fishData.SpeciesName,
			distance = fishData.Distance,
			expiryTime = expiryTime,
			model = nil,
		}
		return
	end

	-- Create billboard GUI
	local highlightBillboard = Instance.new("BillboardGui")
	highlightBillboard.Name = "SonarHighlight"
	highlightBillboard.Size = UDim2.new(0, 200, 0, 50)
	highlightBillboard.StudsOffset = Vector3.new(0, 2, 0)
	highlightBillboard.AlwaysOnTop = true
	highlightBillboard.MaxDistance = 100

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundTransparency = 0.7
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = highlightBillboard

	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Size = UDim2.new(1, 0, 0.5, 0)
	rarityLabel.Text = fishData.Rarity:upper()
	rarityLabel.TextColor3 = Color3.new(1, 1, 1)
	rarityLabel.TextStrokeTransparency = 0
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Font = Enum.Font.GothamBold
	rarityLabel.TextScaled = true
	rarityLabel.Parent = frame

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
	nameLabel.Position = UDim2.new(0, 0, 0.5, 0)
	nameLabel.Text = fishData.SpeciesName
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextScaled = true
	nameLabel.Parent = frame

	highlightBillboard.Parent = fishModel

	-- Store reference
	self._sonarHighlights[fishData.FishId] = {
		billboard = highlightBillboard,
		expiryTime = expiryTime,
	}
end

function FishingController:_removeSonarHighlight(fishId)
	local highlight = self._sonarHighlights[fishId]
	if not highlight then return end

	if highlight.billboard then
		highlight.billboard:Destroy()
	end
	self._sonarHighlights[fishId] = nil
end

-- ============================================================
-- Phase 2: Sonar Pulse VFX (expanding ring wave from player)
-- ============================================================
function FishingController:_playSonarPulseVFX()
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	-- Create expanding ring
	local ring = Instance.new("Part")
	ring.Name = "SonarPulseRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(1, 0.1, 1)
	ring.Position = rootPart.Position
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(0, 200, 255) -- Cyan-white
	ring.Transparency = 0.5
	ring.Parent = workspace

	-- Animate the ring expanding
	local startTime = tick()
	local duration = 1.0
	local maxRange = self._sonarRange

	local connection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local progress = elapsed / duration

		if progress >= 1.0 then
			ring:Destroy()
			connection:Disconnect()
			return
		end

		local currentRadius = progress * maxRange
		ring.Size = Vector3.new(currentRadius * 2, 0.1, currentRadius * 2)
		ring.Transparency = 0.5 + progress * 0.5
		ring.Position = rootPart.Position
	end)

	-- Play ping sound
	self:_playSound("SonarPing")
end

-- ============================================================
-- Phase 2: Environmental Monitor (depth, hazards, zone transitions)
-- ============================================================
function FishingController:_startEnvironmentMonitor()
	task.spawn(function()
		while true do
			task.wait(0.25) -- check 4x per second

			local player = Players.LocalPlayer
			local character = player.Character
			if not character then continue end

			local rootPart = character:FindFirstChild("HumanoidRootPart")
			if not rootPart then continue end

			self._currentDepth = math.abs(rootPart.Position.Y)
			self:_checkZoneTransition()
			self:_checkEnvironmentalHazards()
		end
	end)
end

-- ============================================================
-- Phase 2: Zone transition
-- ============================================================
function FishingController:_checkZoneTransition()
	local depth = self._currentDepth
	local oldZone = self._currentZone
	local newZone = oldZone

	if depth <= 50 then
		newZone = "SunkenShallows"
	elseif depth > 50 and depth <= 150 then
		newZone = "KelpForest"
	elseif depth > 150 then
		newZone = "AbyssalTrench"
	end

	if newZone ~= oldZone then
		self._currentZone = newZone
		self:_onZoneTransition(oldZone, newZone, depth)
	end
end

function FishingController:_onZoneTransition(oldZone, newZone, depth)
	if oldZone == "SunkenShallows" and newZone == "KelpForest" then
		-- Descending into Kelp Forest
		print("[FishingController] Entering Kelp Forest at", depth, "m")

		-- Check unlock requirements (handled server-side, but client shows feedback)
		-- Darker lighting: signal AtmosphereHandler
		if self.Controllers and self.Controllers.AtmosphereHandler then
			self.Controllers.AtmosphereHandler:TransitionToKelpForest(depth)
		end

		-- Show zone entry UI
		if self._fishingHUD then
			self._fishingHUD:ShowPopupText("THE KELP FOREST", Color3.fromRGB(40, 180, 100), 3.0)
		end

	elseif oldZone == "KelpForest" and newZone == "SunkenShallows" then
		-- Ascending back to Shallows
		print("[FishingController] Returning to Sunken Shallows at", depth, "m")

		if self.Controllers and self.Controllers.AtmosphereHandler then
			self.Controllers.AtmosphereHandler:TransitionToShallows(depth)
		end
	end
end

-- ============================================================
-- Phase 2: Environmental Hazard Checks
-- ============================================================
function FishingController:_checkEnvironmentalHazards()
	if self._currentZone ~= "KelpForest" then return end

	local player = Players.LocalPlayer
	local character = player.Character
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local pos = rootPart.Position
	local depth = self._currentDepth

	-- Check kelp entanglement (50-75m: Kelp Canopy area)
	self:_checkKelpEntanglement(rootPart, depth)

	-- Check clearing current (75-100m)
	self:_checkClearingCurrent(rootPart, depth)

	-- Check tentacle damage (Void Jellyfish proximity)
	self:_checkTentacleDamage(rootPart)

	-- Check air pockets (100-130m: Rocky Grotto)
	self:_checkAirPockets(rootPart, depth)
end

-- ============================================================
-- Kelp Entanglement (Kelp Canopy: 50-75m)
-- ============================================================
function FishingController:_checkKelpEntanglement(rootPart, depth)
	if depth < 50 or depth > 75 then
		self._inCurrent = false
		return
	end

	if self._isEntangled then
		self._entangleTimer = self._entangleTimer - 0.25
		if self._entangleTimer <= 0 then
			self._isEntangled = false
			-- Clear entanglement VFX
			if self._fishingHUD then
				self._fishingHUD:ClearKelpEntanglement()
			end
		end
		return
	end

	-- Check if player is sprint-swimming through kelp
	local humanoid = character:FindFirstChildWhichIsA("Humanoid") if not humanoid then
		-- Try the rootPart's parent
		local char = rootPart.Parent
		humanoid = char and char:FindFirstChildWhichIsA("Humanoid")
	end
	-- Actually, we detect sprint via the client's own sprint state
	-- For now: if player is moving fast (>10 studs/s), trigger entanglement chance
	local velocity = rootPart.AssemblyLinearVelocity
	local speed = velocity.Magnitude

	if speed > 10 and math.random() < 0.08 then -- ~8% chance per tick at high speed
		self._isEntangled = true
		self._entangleTimer = 1.5 -- 1.5s snare
		-- Force player to stop
		rootPart.AssemblyLinearVelocity = Vector3.zero
		-- Show entanglement VFX
		if self._fishingHUD then
			self._fishingHUD:ShowKelpEntanglement(1.5)
		end
		self:_playSound("KelpSnare")
	end
end

-- ============================================================
-- The Clearing Current (75-100m, diagonal push)
-- ============================================================
function FishingController:_checkClearingCurrent(rootPart, depth)
	if depth < 75 or depth > 100 then
		self._inCurrent = false
		return
	end

	self._inCurrent = true

	-- Get current resistance from equipped suit
	local currentResistance = self:_getCurrentResistance()
	local pushStrength = 8.0 -- studs/s base
	if currentResistance > 0 then
		pushStrength = 5.2 -- with 35% Deep Diver Suit resistance
	end

	-- Diagonal NW→SE push
	local currentDirection = Vector3.new(1, 0, -1).Unit
	local pushVelocity = currentDirection * pushStrength * 0.25 -- per tick

	-- Apply push (add to existing velocity)
	rootPart.AssemblyLinearVelocity = rootPart.AssemblyLinearVelocity + pushVelocity
end

function FishingController:_getCurrentResistance()
	local rodStats = self:_getRodStats() -- we need suit stats actually
	-- Check PlayerDataService for equipped suit
	local data = self.Services.PlayerDataService and self.Services.PlayerDataService:GetData(Players.LocalPlayer)
	if data and data.Gear and data.Gear.EquippedSuit then
		local suit = Shared.Constants.SuitTiers.GetByKey(data.Gear.EquippedSuit)
		if suit and suit.CurrentResistance then
			return suit.CurrentResistance
		end
	end
	return 0
end

-- ============================================================
-- Tentacle Damage (Void Jellyfish proximity in Kelp Canopy / Abyss Edge)
-- ============================================================
function FishingController:_checkTentacleDamage(rootPart)
	-- Client-side check: look for Void Jellyfish models in workspace
	-- For now, a simplified check based on Jellyfish NPC positions (from sonar data)
	-- Real implementation would query the server or track NPC positions
end

-- ============================================================
-- Air Pockets (Rocky Grotto: 100-130m)
-- ============================================================
function FishingController:_checkAirPockets(rootPart, depth)
	if depth < 100 or depth > 130 then return end

	local grottoAirPockets = {
		{ name = "Grotto North Cave", pos = Vector3.new(-20, -108, -5), radius = 5 },
		{ name = "Grotto South Crevice", pos = Vector3.new(-8, -112, -18), radius = 5 },
	}

	for _, pocket in ipairs(grottoAirPockets) do
		local dist = (rootPart.Position - pocket.pos).Magnitude
		if dist <= pocket.radius then
			local now = tick()
			local cooldownEnd = self._airPocketCooldowns[pocket.name] or 0
			if now >= cooldownEnd then
				-- Refill 30% oxygen
				self._oxygenLevel = math.min(100, self._oxygenLevel + 30)
				self._airPocketCooldowns[pocket.name] = now + 120 -- 2 min cooldown

				-- Show bubble VFX
				self:_playAirPocketVFX(pocket.pos)
				if self._fishingHUD then
					self._fishingHUD:ShowPopupText("+30% OXYGEN", Color3.fromRGB(100, 200, 255), 1.5)
				end
				self:_playSound("AirPocket")
			end
			break
		end
	end
end

function FishingController:_playAirPocketVFX(pocketPos)
	-- Create rising bubble column
	for i = 1, 8 do
		local bubble = Instance.new("Part")
		bubble.Name = "AirBubble"
		bubble.Shape = Enum.PartType.Ball
		bubble.Size = Vector3.new(0.3, 0.3, 0.3)
		bubble.Position = pocketPos + Vector3.new(
			(math.random() - 0.5) * 3,
			math.random() * 2,
			(math.random() - 0.5) * 3
		)
		bubble.Anchored = true
		bubble.CanCollide = false
		bubble.Material = Enum.Material.Glass
		bubble.Color = Color3.fromRGB(180, 220, 255)
		bubble.Transparency = 0.3
		bubble.Parent = workspace

		task.delay(2.0, function()
			if bubble and bubble.Parent then
				bubble:Destroy()
			end
		end)
	end
end

-- ============================================================
-- Phase 2: Ink Burst Handler (Lantern Squid)
-- ============================================================
function FishingController:_onInkBurst(fishId, position, radius, duration)
	-- Create black sphere at position
	local inkSphere = Instance.new("Part")
	inkSphere.Name = "InkCloud"
	inkSphere.Shape = Enum.PartType.Ball
	inkSphere.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	inkSphere.Position = position
	inkSphere.Anchored = true
	inkSphere.CanCollide = false
	inkSphere.Material = Enum.Material.SmoothPlastic
	inkSphere.Color = Color3.new(0, 0, 0)
	inkSphere.Transparency = 0.7
	inkSphere.Parent = workspace

	-- Obscure tension meter on HUD
	if self._fishingHUD then
		self._fishingHUD:SetTensionMeterObscured(true, duration)
	end

	-- Fade out
	task.delay(duration, function()
		if inkSphere and inkSphere.Parent then
			inkSphere:Destroy()
		end
	end)
end

-- ============================================================
-- Phase 2: Apex Presence Handler
-- ============================================================
function FishingController:_onApexPresence(position, message)
	-- Show "The water grows cold..." zone-wide message
	if self._fishingHUD then
		self._fishingHUD:ShowPopupText(message or "The water grows cold...", Color3.fromRGB(200, 50, 50), 3.0)
	end

	-- Apply subtle red tint at screen edges
	self:_applyScreenEdgeTint(Color3.fromRGB(255, 50, 30), 0.15, 5.0)

	self:_playSound("ApexWarning")
end

function FishingController:_applyScreenEdgeTint(color, intensity, duration)
	-- Create a ScreenGui with a gradient vignette
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ApexVignette"
	screenGui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundTransparency = 1
	frame.Parent = screenGui

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.8, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, color),
	})
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.8, 1),
		NumberSequenceKeypoint.new(1, 1 - intensity),
	})
	gradient.Parent = frame

	task.delay(duration, function()
		if screenGui and screenGui.Parent then
			screenGui:Destroy()
		end
	end)
end

-- ============================================================
-- Phase 2: Bait placement
-- ============================================================
function FishingController:_placeBait()
	if self._phase ~= "Idle" then return end

	local targetPosition = self:_getFloorTarget()
	if not targetPosition then return end

	local fishingService = self.Services.FishingService
	if not fishingService then return end

	local result = fishingService.Client.PlaceBait:Call(targetPosition)
	if result and result.Success then
		print("[FishingController] Bait placed at", targetPosition)
		self:_playSound("BaitPlace")
		-- Show bait visual (downward arrow or glow at position)
	else
		print("[FishingController] Bait placement failed:", result and result.Message)
		if self._fishingHUD and result then
			self._fishingHUD:ShowPopupText(result.Message or "Cannot place bait", Color3.fromRGB(255, 80, 80), 2.0)
		end
	end
end

function FishingController:_getFloorTarget()
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { workspace }

	local raycastResult = workspace:Raycast(ray.Origin, ray.Direction * 500, raycastParams)
	if raycastResult then
		return raycastResult.Position
	end
	return nil
end

-- ============================================================
-- (Input handling, aiming, casting, waiting, hook, reel — unchanged from MVP)
-- ============================================================

function FishingController:_handleInput(input, isBegin)
	if self._isEntangled then return end -- can't act while entangled in kelp

	-- Phase 2: B key for bait placement
	if input.KeyCode == Enum.KeyCode.B and isBegin then
		self:_placeBait()
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if isBegin then
			self:_onClickPress()
		else
			self:_onClickRelease()
		end
	end
end

function FishingController:_onClickPress()
	if self._phase == "Idle" then
		if not self._rodHandler or not self._rodHandler._isEquipped then
			return
		end
		self._phase = "Aiming"
		self:_startAiming()

	elseif self._phase == "Biting" then
		if self._fishingHUD then
			self._fishingHUD:OnHookClick()
		end

	elseif self._phase == "Reeling" then
		self._isReeling = true
	end
end

function FishingController:_onClickRelease()
	if self._phase == "Aiming" then
		self:_performCast()

	elseif self._phase == "Reeling" then
		self._isReeling = false
	end
end

function FishingController:_startAiming()
	print("[FishingController] Aiming...")
	self._aimStartTime = tick()
	self._aimPower = 0

	local rodStats = self:_getRodStats()
	local maxRange = rodStats and rodStats.CastRange or 15

	if self.Controllers and self.Controllers.CameraController then
		self.Controllers.CameraController:TransitionToFishingCam()
	end

	self._aimLoop = RunService.RenderStepped:Connect(function(dt)
		if self._phase ~= "Aiming" then
			self._aimLoop:Disconnect()
			self._aimLoop = nil
			return
		end

		local holdDuration = tick() - self._aimStartTime
		self._aimPower = math.clamp(holdDuration / 1.5, 0.2, 1.0)

		local origin, direction = self:_getCastOriginAndDirection()
		if origin and direction then
			if self._rodHandler then
				self._rodHandler:UpdateAimArc(origin, direction, self._aimPower, maxRange)
			end
		end
	end)

	local origin, direction = self:_getCastOriginAndDirection()
	if origin and direction and self._rodHandler then
		self._rodHandler:ShowAimArc(origin, direction, self._aimPower, maxRange)
	end
end

function FishingController:_getCastOriginAndDirection()
	local camera = workspace.CurrentCamera
	if not camera then return nil, nil end
	return camera.CFrame.Position, camera.CFrame.LookVector
end

function FishingController:_performCast()
	local targetPosition = self:_getAimTarget()

	if self._aimLoop then
		self._aimLoop:Disconnect()
		self._aimLoop = nil
	end

	if not targetPosition then
		self._phase = "Idle"
		return
	end

	self._phase = "Casting"

	local origin, _ = self:_getCastOriginAndDirection()

	if self._rodHandler then
		self._rodHandler:PlayCastAnimation(origin, targetPosition, self._aimPower, function()
			self:_sendCastToServer(targetPosition)
		end)
	else
		self:_sendCastToServer(targetPosition)
	end
end

function FishingController:_sendCastToServer(targetPosition)
	local fishingService = self.Services.FishingService
	if not fishingService then
		self._phase = "Idle"
		return
	end

	local result = fishingService.Client.CastLine:Call(targetPosition)

	if result and result.Success then
		self._castId = result.CastId
		self._phase = "Waiting"

		if self._rodHandler then
			self._rodHandler:CreateBobber(targetPosition)
		end

		self:_playSound("Cast")
		self:_startWaitingForBite()
		print("[FishingController] Cast successful, waiting for bite...")
	else
		self._phase = "Idle"
		warn("[FishingController] Cast failed:", result and result.Message or "unknown")
	end
end

function FishingController:_getAimTarget()
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { workspace }

	local raycastResult = workspace:Raycast(ray.Origin, ray.Direction * 500, raycastParams)
	if raycastResult then
		return raycastResult.Position
	end

	return ray.Origin + ray.Direction * 50
end

function FishingController:_startWaitingForBite()
	local minDelay = 1.5
	local maxDelay = 3.5
	self._currentBiteDelay = minDelay + math.random() * (maxDelay - minDelay)
	self._biteStartTime = tick()
	self:_pollBiteReady()
end

function FishingController:_pollBiteReady()
	if self._phase ~= "Waiting" then return end

	local elapsed = tick() - self._biteStartTime
	if elapsed >= self._currentBiteDelay then
		self:_onFishBiting()
	else
		task.wait(0.1)
		self:_pollBiteReady()
	end
end

function FishingController:_onFishBiting()
	if self._phase ~= "Waiting" then return end
	self._phase = "Biting"

	if self._rodHandler then
		self._rodHandler:PlayBobberBite()
		self._rodHandler:SetBobberGlow(true, Color3.fromRGB(100, 200, 255))
	end

	self:_playSound("Bite")

	task.delay(0.3, function()
		if self._phase ~= "Biting" then return end
		self:_startHookMinigame()
	end)
end

function FishingController:_startHookMinigame()
	if self._phase ~= "Biting" then return end

	local rodStats = self:_getRodStats()
	local hookWindowSize = rodStats and rodStats.HookWindow or 0.40

	if self._fishingHUD then
		self._fishingHUD:StartHookMinigame(hookWindowSize, function(timingQuality)
			self:_onHookResolved(timingQuality)
		end)
	end
end

function FishingController:_onHookResolved(timingQuality)
	local fishingService = self.Services.FishingService
	if not fishingService or not self._castId then
		self:_endFishing()
		return
	end

	local result = fishingService.Client.HookAttempt:Call(self._castId, timingQuality)
	if not result then
		self:_endFishing()
		return
	end

	if result.Result == "Hooked" then
		self._phase = "Reeling"
		self._tension = result.Tension or 0
		self._progress = 0

		if self._fishingHUD then
			self._fishingHUD:CancelHook()
			self._fishingHUD:ShowReelUI()
		end

		if self._rodHandler then
			self._rodHandler:SetBobberGlow(false)
		end

		self:_startReelLoop()

		if timingQuality == "Perfect" then
			self:_playSound("Perfect")
		else
			self:_playSound("HookSuccess")
		end

	elseif result.Result == "TooSoon" then
		self._phase = "Waiting"
		self._biteStartTime = tick()
		self._currentBiteDelay = 1.0 + math.random() * 2.0

		if self._fishingHUD then
			self._fishingHUD:CancelHook()
		end
		self:_pollBiteReady()

	else
		self:_playSound("FishFlee")
		self:_endFishing()
	end
end

function FishingController:_startReelLoop()
	self._isReeling = false
	self._reelTickAccumulator = 0
	self._lastReelTickTime = tick()
	self._lastTugTime = tick()
	self._tugCooldown = 0
	self._resultHandled = false

	self._reelLoop = RunService.Heartbeat:Connect(function(dt)
		if self._phase ~= "Reeling" then return end

		self._reelTickAccumulator = self._reelTickAccumulator + dt
		local tickRate = Shared.Fishing.TensionTickRate

		while self._reelTickAccumulator >= tickRate do
			self._reelTickAccumulator = self._reelTickAccumulator - tickRate
			self:_sendReelTick()
		end

		if self._fishingHUD then
			self._fishingHUD:UpdateTension(self._tension, self:_getTensionZone())
			self._fishingHUD:UpdateProgress(self._progress)
		end

		if self._rodHandler then
			self._rodHandler:UpdateLineTension(self._tension)
		end

		self:_checkTugShake(dt)
	end)
end

function FishingController:_sendReelTick()
	local fishingService = self.Services.FishingService
	if not fishingService or not self._castId then return end

	local result = fishingService.Client.ReelUpdate:Call(self._castId, self._isReeling)
	if not result then
		self:_endFishing()
		return
	end

	self._tension = result.Tension or 0
	self._progress = result.Progress or 0

	if self._tension > 60 and (tick() - (self._lastTugDetectTime or 0)) > 0.5 then
		self:_onFishTug()
		self._lastTugDetectTime = tick()
	end

	if result.State == "Caught" then
		self._endReelLoop()
		self._resultHandled = true
	elseif result.State == "LineSnapped" then
		self._endReelLoop()
		self._resultHandled = true
		self:_onLineSnapped()
	elseif result.State == "FishEscaped" then
		self._endReelLoop()
		self._resultHandled = true
		self:_onFishEscaped(result.Reason)
	elseif result.State == "InventoryFull" then
		self._endReelLoop()
		self._resultHandled = true
		self:_playSound("InventoryFull")
		self:_endFishing()
	elseif result.State == "InvalidSession" then
		self:_endReelLoop()
		self:_endFishing()
	end
end

function FishingController:_onFishTug()
	self:_applyScreenShake(0.3, 2.0)
	self:_playSound("Tug")
end

function FishingController:_checkTugShake(dt)
	if self._tension > 85 then
		self:_applyScreenShake(0.1, 1.0)
	end
end

function FishingController:_applyScreenShake(intensity, duration)
	local camera = workspace.CurrentCamera
	if not camera then return end

	local originalCFrame = camera.CFrame
	local startTime = tick()

	local shakeConnection
	shakeConnection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		if elapsed > duration then
			shakeConnection:Disconnect()
			return
		end

		local decay = 1 - (elapsed / duration)
		local offset = Vector3.new(
			(math.random() - 0.5) * intensity * decay * 2,
			(math.random() - 0.5) * intensity * decay * 2,
			(math.random() - 0.5) * intensity * decay * 0.5
		)
		camera.CFrame = originalCFrame * CFrame.new(offset)
	end)
end

function FishingController:_onFishHooked(fishData)
	print("[FishingController] Fish hooked:", fishData.SpeciesName)

	self._phase = "Reeling"
	self._tension = 0
	self._progress = 0

	if self._fishingHUD then
		self._fishingHUD:CancelHook()
		self._fishingHUD:ShowReelUI()
	end

	if self._rodHandler then
		self._rodHandler:SetBobberGlow(false)
	end

	self:_startReelLoop()
end

function FishingController:_onFishCaught(fishData, rewards)
	if self._resultHandled then return end
	self._resultHandled = true

	print("[FishingController] Fish caught:", fishData.SpeciesName, fishData.Rarity)

	self:_endReelLoop()
	self._phase = "Showcase"

	self:_playSound("CatchFanfare")

	if self._fishingHUD then
		self._fishingHUD:HideReelUI()
		self._fishingHUD:ShowRarityReveal(fishData)
	end

	if self._rodHandler then
		self._rodHandler:SetBobberGlow(false)
	end

	task.delay(4.0, function()
		self:_endFishing()
	end)
end

function FishingController:_onLineSnapped()
	if self._resultHandled then return end
	self._resultHandled = true

	print("[FishingController] Line snapped!")

	self:_endReelLoop()
	self:_playSound("LineSnap")

	if self._fishingHUD then
		self._fishingHUD:HideReelUI()
		self._fishingHUD:ShowPopupText("LINE SNAPPED!", Color3.fromRGB(255, 60, 60), 2.0)
	end

	if self._rodHandler then
		self._rodHandler:SetBobberGlow(false)
	end

	task.delay(1.5, function()
		self:_endFishing()
	end)
end

function FishingController:_onFishEscaped(reason)
	if self._resultHandled then return end
	self._resultHandled = true

	print("[FishingController] Fish escaped:", reason or "unknown")

	self:_endReelLoop()

	if self._fishingHUD then
		self._fishingHUD:HideReelUI()
		if reason == "LowTension" then
			self._fishingHUD:ShowPopupText("NOT ENOUGH TENSION!", Color3.fromRGB(255, 170, 50), 2.0)
		else
			self._fishingHUD:ShowPopupText("FISH ESCAPED!", Color3.fromRGB(255, 170, 50), 2.0)
		end
	end

	self:_playSound("FishFlee")

	if self._rodHandler then
		self._rodHandler:SetBobberGlow(false)
	end

	task.delay(1.5, function()
		self:_endFishing()
	end)
end

-- ============================================================
-- Sound Events
-- ============================================================

function FishingController:_playSound(event)
	if not self._soundCache then
		self._soundCache = {}
	end
	-- Production: wire to actual Roblox Sound objects
	-- "SonarPing", "KelpSnare", "AirPocket", "ApexWarning", "BaitPlace"
end

-- ============================================================
-- Helpers: find fish model, color mapping
-- ============================================================
function FishingController:_findFishModel(fishId)
	-- Search workspace for models with matching name containing fishId
	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") and model.Name:find(fishId, 1, true) then
			return model
		end
	end
	return nil
end

function FishingController:_rarityToColor(rarity)
	if rarity == "Common" then return Color3.fromRGB(150, 150, 150) end
	if rarity == "Uncommon" then return Color3.fromRGB(100, 200, 100) end -- green
	if rarity == "Rare" then return Color3.fromRGB(50, 150, 250) end -- blue
	if rarity == "Legendary" then return Color3.fromRGB(255, 200, 50) end -- gold
	return Color3.fromRGB(200, 200, 200)
end

-- ============================================================
-- Cleanup & Utilities
-- ============================================================

function FishingController:_endReelLoop()
	if self._reelLoop then
		self._reelLoop:Disconnect()
		self._reelLoop = nil
	end
	self._isReeling = false
end

function FishingController:_endFishing()
	local fishingService = self.Services.FishingService
	if self._castId and fishingService then
		pcall(function()
			fishingService.Client.CancelFishing:Call(self._castId)
		end)
	end

	self:_endReelLoop()

	if self._aimLoop then
		self._aimLoop:Disconnect()
		self._aimLoop = nil
	end

	self._biteTimer = nil

	if self._fishingHUD then
		self._fishingHUD:HideAll()
	end

	if self._rodHandler then
		self._rodHandler:SetBobberGlow(false)
	end

	if self.Controllers and self.Controllers.CameraController then
		self.Controllers.CameraController:TransitionToNormalCam()
	end

	self._phase = "Idle"
	self._castId = nil
	self._tension = 0
	self._progress = 0
	self._isFishing = false
	self._aimPower = 0
	self._pendingSpecies = nil
end

function FishingController:_getRodStats()
	local rodKey = self._cachedEquippedRod or "BambooRod"
	return Shared.Constants.RodTiers.GetByKey(rodKey)
end

function FishingController:_getTensionZone()
	if self._tension < Shared.Fishing.TensionGreenZone then return "Green"
	elseif self._tension < Shared.Fishing.TensionYellowZone then return "Yellow"
	else return "Red" end
end

-- ============================================================
-- Public API
-- ============================================================

function FishingController:CancelFishing()
	self:_endFishing()
end

function FishingController:IsFishing()
	return self._phase ~= "Idle"
end

function FishingController:GetPhase()
	return self._phase
end

-- Phase 2: Get current zone
function FishingController:GetCurrentZone()
	return self._currentZone
end

return FishingController
