--[[
	DataStore2.lua
	Deep Tide Studios — DataStore2 Wrapper
	Simplified DataStore2 pattern for player data persistence.
	In production, replace with the full DataStore2 module from:
	https://github.com/Kampfkarren/Roblox-DataStore2
	
	This stub provides the same API surface so services compile without errors.
]]

local DataStore2 = {}
DataStore2.__index = DataStore2

-- Combined store for all players (in production, DataStore2 uses per-key DataStores)
local _mockStore = {}

--- Create a DataStore2 instance for a key and player
function DataStore2.new(key, player)
	local self = setmetatable({}, DataStore2)
	self._key = key
	self._playerKey = tostring(player.UserId) .. "_" .. key
	return self
end

--- Get the current value (returns default if not set)
function DataStore2:Get(defaultValue)
	local data = _mockStore[self._playerKey]
	if data ~= nil then
		return data
	end

	-- Initialize with default
	local default = defaultValue
	if type(defaultValue) == "table" then
		default = {}
		for k, v in pairs(defaultValue) do
			if type(v) == "table" then
				default[k] = {}
				for sk, sv in pairs(v) do
					default[k][sk] = sv
				end
			else
				default[k] = v
			end
		end
	end

	_mockStore[self._playerKey] = default
	return default
end

--- Set the value and save to DataStore
function DataStore2:Set(value)
	_mockStore[self._playerKey] = value

	-- In production: pcall the actual DataStore SetAsync
	local success, err = pcall(function()
		-- Placeholder for actual DataStore save
	end)

	if not success then
		warn("[DataStore2] Set failed:", err)
	end
end

--- Increment a numeric value
function DataStore2:Increment(amount, defaultValue)
	local current = self:Get(defaultValue or 0)
	local newValue = current + amount
	self:Set(newValue)
	return newValue
end

--- Update a value with a callback
function DataStore2:Update(callback)
	local current = self:Get()
	local newValue = callback(current)
	self:Set(newValue)
	return newValue
end

-- Module-style call
return function(key, player)
	return DataStore2.new(key, player)
end
