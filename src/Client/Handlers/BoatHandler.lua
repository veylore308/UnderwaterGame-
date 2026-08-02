--[[
	BoatHandler.lua
	Deep Tide Studios — Client Handler (Phase 3)
	Client-side boat driver: equips/spawns the active boat, WASD steering
	with momentum prediction (server-reconciled), anchor toggle, dock
	prompt + parking, boat recall, surface-mode seating, weather
	announcements, lost-rod recovery prompts, and Boat HUD updates.

	Server remains authoritative for all boat state; this handler predicts
	motion locally between BoatUpdated ticks (10Hz) and lerps to reconcile.
	Input keys: W/S throttle, A/D turn, Space anchor, G board/leave
	(deviation from GDD 'B' — B is taken by the collection book / bait),
	E contextual interact (park, recover rod, board), M toggle minimap.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"))

local BoatHUD = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("BoatHUD"))

local BoatHandler = {}
BoatHandler.__index = BoatHandler

local CONTROL_INTERVAL = 0.1   -- send controls at 10 Hz
local DOCK_PROMPT_RADIUS = 40  -- studs
local RECOVER_RADIUS = 12      -- studs

function BoatHandler.new(services, fishingController)
	local self = setmetatable({}, BoatHandler)
	self._services = services
	self._fishingController = fishingController
	self._boatService = services and services.BoatService
	self._fishingService = services and services.FishingService
	self._weatherService = services and services.WeatherService

	self._boatState = nil
	self._model = nil
	self._isDriver = false
	self._surfaceMode = false
	self._keys = { W = false, A = false, S = false, D = false }
	self._controlTimer = 0
	self._hud = nil
	self._lastState = nil

	self._pendingPrompt = nil
	self._pendingInteract = nil   -- function() called on E
	self._lostRodIds = {}

	self._playerName = Players.LocalPlayer.Name
	self._userId = Players.LocalPlayer.UserId

	-- Prediction state (local simulation between server ticks)
	self._predPos = nil
	self._predHeading = 0
	self._predSpeed = 0

	self:_wireInput()
	self:_wireServices()
	return self
end

-- ============================================================
-- Service wiring
-- ============================================================
function BoatHandler:_wireServices()
	local bs = self._boatService
	if not bs then return end

	-- Own boat state
	bs.Client.BoatUpdated:Connect(function(state)
		if state and state.OwnerName == self._playerName then
			self:_onOwnBoatState(state)
		elseif state then
			-- Passenger update (someone else's boat we're riding)
			self:_onPassengerState(state)
		end
	end)

	bs.Client.BoatSpawned:Connect(function(state)
		if state and state.OwnerName == self._playerName then
			self:_acquireModel(state.ModelName)
			self:_onOwnBoatState(state)
		end
	end)

	bs.Client.BoatDespawned:Connect(function(playerName)
		if playerName == self._playerName then
			self:_teardown()
		end
	end)

	bs.Client.SonarPing:Connect(function(pingData)
		if self._hud and pingData then
			-- RV sonar: fish icons appear on the minimap (prototype: log + HUD flash)
			self._hud:ShowAnnouncement("SONAR — " .. #(pingData.DetectedFish or {}) .. " fish detected", Color3.fromRGB(0, 220, 255), 1.5)
		end
	end)

	-- Weather
	local ws = self._weatherService
	if ws then
		ws.Client.WeatherChanged:Connect(function(data)
			if self._hud then
				self._hud:SetWeather(data.State)
				if data.Announcement then
					self._hud:ShowAnnouncement(data.Announcement,
						data.State == "Storm" and Color3.fromRGB(255, 80, 80)
						or data.State == "Rain" and Color3.fromRGB(150, 180, 220)
						or Color3.fromRGB(255, 230, 140), 4)
				end
			end
		end)
		ws.Client.WeatherWarning:Connect(function(data)
			if self._hud and data and data.Message then
				self._hud:ShowAnnouncement("⚠ " .. data.Message, Color3.fromRGB(255, 170, 60), 5)
			end
		end)
		ws.Client.WeatherAnnouncement:Connect(function(data)
			if self._hud and data and data.Message then
				self._hud:ShowAnnouncement(data.Message, Color3.fromRGB(255, 80, 80), 5)
			end
		end)
	end

	-- Fishing (surface bobber drift + rod loss)
	local fs = self._fishingService
	if fs then
		fs.Client.BobberDrifted:Connect(function(castId, position)
			if self._fishingController then
				self._fishingController:OnBobberDrifted(castId, position)
			end
		end)
		fs.Client.RodLost:Connect(function(rodData)
			if self._hud and rodData then
				self._hud:ShowAnnouncement("⚡ YOUR ROD WAS FLUNG INTO THE SEA! Sail downwind to recover it (5 min)", Color3.fromRGB(255, 120, 60), 6)
				self._lostRodIds[rodData.RodId] = rodData
			end
		end)
		fs.Client.RodRecovered:Connect(function(rodData)
			if self._hud and rodData then
				self._hud:ShowAnnouncement("Rod recovered!", Color3.fromRGB(120, 220, 160), 3)
				self._lostRodIds[rodData.RodId] = nil
			end
		end)
		fs.Client.RodExpired:Connect(function(rodData)
			if self._hud and rodData then
				self._hud:ShowAnnouncement("Your " .. tostring(rodData.RodKey) .. " sank forever — rebuy at the dock shop (50% cost)", Color3.fromRGB(200, 90, 90), 5)
				self._lostRodIds[rodData.RodId] = nil
			end
		end)
	end

	-- Initial equip: auto-spawn the starter Raft (players own it by default)
	task.delay(2, function()
		local state = bs.Client.GetBoatState:Call()
		if not state then
			bs.Client.EquipBoat:Call("Raft")
		elseif state.OwnerName == self._playerName then
			self:_acquireModel(state.ModelName)
			self:_onOwnBoatState(state)
		end
	end)
end

-- ============================================================
-- Input
-- ============================================================
function BoatHandler:_wireInput()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.W then self._keys.W = true
		elseif input.KeyCode == Enum.KeyCode.S then self._keys.S = true
		elseif input.KeyCode == Enum.KeyCode.A then self._keys.A = true
		elseif input.KeyCode == Enum.KeyCode.D then self._keys.D = true
		elseif input.KeyCode == Enum.KeyCode.Space then
			if self._surfaceMode then self:_toggleAnchor() end
		elseif input.KeyCode == Enum.KeyCode.G then
			self:_toggleBoard()
		elseif input.KeyCode == Enum.KeyCode.E then
			self:_doInteract()
		elseif input.KeyCode == Enum.KeyCode.M then
			if self._hud then self._hud:SetVisible(not self._hud:IsVisible()) end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.W then self._keys.W = false
		elseif input.KeyCode == Enum.KeyCode.S then self._keys.S = false
		elseif input.KeyCode == Enum.KeyCode.A then self._keys.A = false
		elseif input.KeyCode == Enum.KeyCode.D then self._keys.D = false
		end
	end)

	-- Control + prediction loop
	RunService.RenderStepped:Connect(function(dt)
		self:_update(dt)
	end)

	-- Proximity prompt loop
	task.spawn(function()
		while true do
			task.wait(0.4)
			self:_checkProximity()
		end
	end)
end

-- ============================================================
-- State handling
-- ============================================================
function BoatHandler:_onOwnBoatState(state)
	local wasSurface = self._surfaceMode
	self._boatState = state
	self._surfaceMode = true
	self._isDriver = true
	self._lastState = state

	if not wasSurface then
		if self._hud == nil then
			self._hud = BoatHUD.new()
		end
		self._hud:SetVisible(true)
		self._hud:SetWeather(self._weatherService and self._weatherService.Client.GetWeather:Call().State or "Calm")
		if self._fishingController and self._fishingController.SetSurfaceMode then
			self._fishingController:SetSurfaceMode(true)
		end
	end

	self._predPos = state.Position
	self._predHeading = state.Heading or 0
	self._predSpeed = state.Speed or 0

	if self._hud then self._hud:UpdateBoat(state) end
end

function BoatHandler:_onPassengerState(state)
	self._surfaceMode = true
	self._isDriver = false
	self._boatState = state
	self._lastState = state

	if self._hud == nil then
		self._hud = BoatHUD.new()
	end
	self._hud:SetVisible(true)
	self._predPos = state.Position
	self._predHeading = state.Heading or 0
	if self._fishingController and self._fishingController.SetSurfaceMode then
		self._fishingController:SetSurfaceMode(true)
	end
end

function BoatHandler:_teardown()
	self._boatState = nil
	self._surfaceMode = false
	self._isDriver = false
	self._model = nil
	if self._hud then
		self._hud:SetVisible(false)
	end
	if self._fishingController and self._fishingController.SetSurfaceMode then
		self._fishingController:SetSurfaceMode(false)
	end
end

-- ============================================================
-- Model acquisition
-- ============================================================
function BoatHandler:_acquireModel(modelName)
	if self._model and self._model.Name == modelName then return end
	local boatsFolder = workspace:WaitForChild("Boats", 10)
	if not boatsFolder then return end
	self._model = boatsFolder:WaitForChild(modelName, 10)
end

-- ============================================================
-- Prediction + reconciliation (RenderStepped)
-- ============================================================
function BoatHandler:_update(dt)
	-- Send controls at 10 Hz (driver only)
	self._controlTimer = self._controlTimer + dt
	if self._controlTimer >= CONTROL_INTERVAL then
		self._controlTimer = 0
		if self._isDriver and self._boatService then
			local throttle = (self._keys.W and 1 or 0) - (self._keys.S and 0.4 or 0)
			local turn = (self._keys.D and 1 or 0) - (self._keys.A and 1 or 0)
			self._boatService.Client.Control:Call({ Throttle = throttle, Turn = turn })
		end
	end

	if not self._surfaceMode or not self._boatState then return end

	-- Reconcile: lerp toward latest server state
	local state = self._boatState
	if state.Position then
		local alpha = 1 - math.pow(0.001, dt) -- fast exponential blend
		self._predPos = self._predPos:Lerp(state.Position, alpha)
		self._predHeading = self._predHeading + ((state.Heading or 0) - self._predHeading) * alpha
		self._predSpeed = self._predSpeed + ((state.Speed or 0) - self._predSpeed) * alpha
	end

	-- Apply to the replicated model (visible to everyone)
	if self._model and self._predPos then
		local cframe = CFrame.new(self._predPos.X, 0.5, self._predPos.Z) * CFrame.Angles(0, self._predHeading, 0)
		self._model:SetPivot(cframe)
	end

	-- Seat the player on the deck (surface mode)
	self:_seatPlayer(dt)
end

function BoatHandler:_seatPlayer(dt)
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not self._predPos then return end

	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
	end

	-- Deck offset (slightly above waterline, behind the helm)
	local offset = CFrame.new(self._predPos.X, 1.6, self._predPos.Z) * CFrame.Angles(0, self._predHeading, 0)
	rootPart.CFrame = offset * CFrame.new(0, 0, 1)
	rootPart.AssemblyLinearVelocity = Vector3.zero
end

-- ============================================================
-- Actions
-- ============================================================
function BoatHandler:_toggleAnchor()
	if not self._boatService then return end
	local result = self._boatService.Client.Anchor:Call()
	if self._hud and result ~= nil then
		self._hud:ShowAnnouncement(result and "⚓ ANCHORED" or "⛵ UNANCHORED",
			result and Color3.fromRGB(120, 220, 160) or Color3.fromRGB(255, 200, 120), 1.5)
	end
end

function BoatHandler:_toggleBoard()
	if not self._boatService then return end
	if self._surfaceMode then
		self._boatService.Client.LeaveBoat:Call()
		self:_teardown()
		local player = Players.LocalPlayer
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildWhichIsA("Humanoid")
			if humanoid then humanoid.WalkSpeed = 16 end
		end
	else
		-- Board the nearest boat (own boat by default)
		local target = self:_findNearbyBoat(8)
		if target then
			self._boatService.Client.Board:Call(target.UserId)
		end
	end
end

function BoatHandler:_doInteract()
	if self._pendingInteract then
		self._pendingInteract()
		self._pendingInteract = nil
		self._pendingPrompt = nil
		if self._hud then self._hud:HidePrompt() end
	end
end

-- ============================================================
-- Proximity prompts (dock park, recover rod, board)
-- ============================================================
function BoatHandler:_checkProximity()
	if not self._surfaceMode or not self._boatState then
		if self._hud then self._hud:HidePrompt() end
		self._pendingPrompt = nil
		self._pendingInteract = nil
		return
	end

	local pos = self._boatState.Position
	local newPrompt = nil
	local newInteract = nil

	-- Dock parking prompt
	if pos then
		local distToDock = Vector3.new(pos.X, 0, pos.Z).Magnitude
		if distToDock <= DOCK_PROMPT_RADIUS and not self._boatState.Docked then
			newPrompt = "E — PARK AT OUTPOST"
			newInteract = function()
				if self._boatService then self._boatService.Client.Dock:Call() end
			end
		end
	end

	-- Lost rod recovery prompt (owner)
	if not newPrompt and self._fishingService then
		local charPos = self._predPos
		if charPos then
			for rodId, rodData in pairs(self._lostRodIds) do
				local drop = rodData.DropPosition
				if drop and (drop - charPos).Magnitude <= RECOVER_RADIUS then
					newPrompt = "E — RECOVER ROD"
					newInteract = function()
						if self._fishingService then
							self._fishingService.Client.RecoverRod:Call(rodId)
						end
					end
					break
				end
			end
		end
	end

	if newPrompt ~= self._pendingPrompt then
		self._pendingPrompt = newPrompt
		self._pendingInteract = newInteract
		if self._hud then
			if newPrompt then
				self._hud:ShowPrompt(newPrompt)
			else
				self._hud:HidePrompt()
			end
		end
	end
end

function BoatHandler:_findNearbyBoat(radius)
	if not self._predPos then return nil end
	local boatsFolder = workspace:FindFirstChild("Boats")
	if not boatsFolder then return nil end
	for _, boat in ipairs(boatsFolder:GetChildren()) do
		if boat:IsA("Model") and boat.PrimaryPart then
			if (boat.PrimaryPart.Position - self._predPos).Magnitude <= radius then
				local ownerName = boat.Name:match("^Boat_(.+)$")
				if ownerName and ownerName ~= self._playerName then
					for _, p in ipairs(Players:GetPlayers()) do
						if p.Name == ownerName then return p end
					end
				end
			end
		end
	end
	return nil
end

-- ============================================================
-- Public API
-- ============================================================
function BoatHandler:IsOnBoat()
	return self._surfaceMode
end

function BoatHandler:GetBoatPosition()
	return self._predPos
end

function BoatHandler:GetBoatHeading()
	return self._predHeading
end

function BoatHandler:Destroy()
	self:_teardown()
	if self._hud then
		self._hud:Destroy()
		self._hud = nil
	end
end

return BoatHandler
