--[[
	WeatherService.lua
	Deep Tide Studios — Server Service
	Server-wide weather state machine. Rotates Calm/Rain/Storm on weighted
	intervals, broadcasts announcements (UI popup + chat), issues a 60s
	storm warning, exposes wind vectors, and pushes spawn-table modifiers
	to the FishSpawner via ZoneService.

	Phase 3: storm warning grace window, "Something huge is riding the storm…"
	hint, weather announcement broadcast, wind vector for boat drift / bobber
	drift. All durations/modifiers come from Shared.Constants.WeatherConfigs.
]]

local Knit = require(game:GetService("ReplicatedStorage"):WaitForChild("Knit"))
local C = require(game:GetService("ReplicatedStorage").Shared.Constants.WeatherConfigs)
local Players = game:GetService("Players")

local S = Knit.CreateService({
	Name = "WeatherService",
	Client = {
		WeatherChanged = Knit.CreateSignal(),    -- { State, EndsAt, Config, Announcement }
		WeatherWarning = Knit.CreateSignal(),    -- { State, IncomingAt, Message } (storm grace)
		WeatherAnnouncement = Knit.CreateSignal(), -- { Message, State } (e.g. storm hint)
		GetWeather = Knit.CreateSignal(),        -- () -> { State, EndsAt, Config }
	},
})

S.State = "Calm"      -- current applied state
S.EndsAt = 0          -- os.time() when current state expires
S.PendingState = nil  -- storm waiting out its warning window
S.PendingAt = 0       -- os.time() when pending storm applies
S.WindAngle = 0       -- radians; direction weather pushes unanchored boats / bobbers

-- ============================================================
-- Lifecycle
-- ============================================================
function S:KnitInit()
	self.Client.GetWeather:Connect(function(player)
		return {
			State = self.State,
			EndsAt = self.EndsAt,
			PendingState = self.PendingState,
			PendingAt = self.PendingAt,
			Config = C.States[self.State],
		}
	end)
end

function S:KnitStart()
	self:RollWeather()
	task.spawn(function()
		while true do
			task.wait(1)
			self:Update()
		end
	end)
	print("[WeatherService] Started — weather cycle active")
end

-- ============================================================
-- Cycle: every 12-18 min (per-state durations from WeatherConfigs,
-- whose Min/Max average 12.5 min; storm gets a 60s warning window)
-- ============================================================
function S:Update()
	local now = os.time()

	-- Apply a pending storm after its warning window
	if self.PendingState and now >= self.PendingAt then
		local pending = self.PendingState
		self.PendingState = nil
		self.PendingAt = 0
		self:ApplyWeather(pending)
		return
	end

	-- Roll the next state when the current one expires
	if self.EndsAt > 0 and now >= self.EndsAt then
		self:RollWeather()
	end
end

-- ============================================================
-- Roll next state (weighted, no immediate repeats)
-- ============================================================
function S:RollWeather()
	local names = {}
	for n in pairs(C.States) do
		if n ~= self.State or not C.NoRepeatStates then
			names[#names + 1] = n
		end
	end
	if #names == 0 then names = { self.State } end

	local total = 0
	for _, n in ipairs(names) do total = total + C.States[n].Weight end
	local pick = math.random() * total
	local chosen = names[1]
	for _, n in ipairs(names) do
		pick = pick - C.States[n].Weight
		if pick <= 0 then chosen = n break end
	end

	local cfg = C.States[chosen]
	local now = os.time()

	if chosen == "Storm" and self.State ~= "Storm" then
		-- Storm grace window: warn the server, apply shortly
		local warnSec = cfg.WarningSeconds or 60
		self.PendingState = chosen
		self.PendingAt = now + warnSec
		self.Client.WeatherWarning:FireAll({
			State = chosen,
			IncomingAt = self.PendingAt,
			Message = "A squall line is moving in… batten down!",
		})
		self:BroadcastChat("⚠ " .. "A squall line is moving in… batten down!")
	else
		self:ApplyWeather(chosen)
	end
end

-- ============================================================
-- Apply a weather state and notify everyone
-- ============================================================
function S:ApplyWeather(state)
	local cfg = C.States[state]
	self.State = state
	self.EndsAt = os.time() + math.random(cfg.MinDuration, cfg.MaxDuration)
	self.WindAngle = math.random() * math.pi * 2

	local announcement = state == "Storm" and "THE STORM ARRIVES — something huge is riding the storm…"
		or state == "Rain" and "Rain moves in — fish are stirring…"
		or "The seas are calm."

	self.Client.WeatherChanged:FireAll({
		State = state,
		EndsAt = self.EndsAt,
		Config = cfg,
		Announcement = announcement,
	})

	self:BroadcastChat("☀ " .. announcement)

	if state == "Storm" then
		-- Storm visual hint + the Marlin tease (GDD 4.6.4.8)
		self.Client.WeatherAnnouncement:FireAll({
			Message = "Something huge is riding the storm…",
			State = "Storm",
		})
	end

	-- Push spawn-table modifiers to the surface spawner
	local zoneService = self.Services and self.Services.ZoneService
	if zoneService and zoneService.SetWeatherForZones then
		zoneService:SetWeatherForZones(state, cfg.SpawnMods)
	end

	print("[WeatherService] Weather changed to " .. state .. " until " .. self.EndsAt)
end

-- ============================================================
-- Queries
-- ============================================================
function S:GetState()
	return self.State, C.States[self.State]
end

function S:GetSurfaceSpawnMods()
	return C.States[self.State].SpawnMods
end

--- Wind vector in studs/s for the current state (unanchored boats, bobbers)
function S:GetWindVector()
	local cfg = C.States[self.State]
	local push = cfg.WindPush or 0
	return Vector3.new(math.cos(self.WindAngle), 0, math.sin(self.WindAngle)) * push
end

--- Wind push scalar for the current state
function S:GetWindPush()
	return C.States[self.State].WindPush or 0
end

-- ============================================================
-- Chat broadcast (guarded — legacy Chat API; popup is the primary channel)
-- ============================================================
function S:BroadcastChat(message)
	pcall(function()
		local chat = game:GetService("Chat")
		for _, p in ipairs(Players:GetPlayers()) do
			local char = p.Character
			if char and char.PrimaryPart then
				chat:Chat(char.PrimaryPart, message, Enum.ChatColor.White)
			end
		end
	end)
end

return S
