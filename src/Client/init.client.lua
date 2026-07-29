--[[
	init.client.lua
	Deep Tide Studios — Client Bootstrap
	Loads Knit, registers all controllers and handlers, and starts the framework.

	Bootstrap order:
	  1. Knit framework
	  2. Shared constants
	  3. Handlers (AtmosphereHandler, FishingRodHandler, FishingHUD)
	     — loaded by controllers but pre-cached for clarity
	  4. Controllers: Camera → UI → Fishing
	  5. Knit.Start() → KnitInit (wiring) → KnitStart (activation)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for Knit to be available
local Knit = require(ReplicatedStorage:WaitForChild("Knit"))

-- Pre-load Shared (validates Rojo sync)
local Shared = require(ReplicatedStorage:WaitForChild("Shared"))
print("[Client] Shared module loaded")

-- Pre-load handlers (controllers will use these, pre-caching ensures no race conditions)
local Handlers = script.Parent.Handlers
local AtmosphereHandler = require(Handlers:WaitForChild("AtmosphereHandler"))
local FishingRodHandler = require(Handlers:WaitForChild("FishingRodHandler"))
print("[Client] Handlers loaded — AtmosphereHandler, FishingRodHandler")

-- Pre-load UI modules
local UI = script.Parent.UI
local FishingHUD = require(UI:WaitForChild("FishingHUD"))
local CollectionBook = require(UI:WaitForChild("CollectionBook"))
local ShopScreen = require(UI:WaitForChild("ShopScreen"))
print("[Client] UI modules loaded — FishingHUD, CollectionBook, ShopScreen")

-- Load all controllers
local Controllers = script.Parent.Controllers
local FishingController = require(Controllers:WaitForChild("FishingController"))
local UIController = require(Controllers:WaitForChild("UIController"))
local CameraController = require(Controllers:WaitForChild("CameraController"))

-- Start Knit on the client
Knit.Start():andThen(function()
	print("========================================")
	print(" Deep Tide Studios — Client Initialized")
	print("========================================")
	print(" Controllers:")
	print("   - CameraController    (depth, fog, fishing cam)")
	print("   - UIController        (HUD, shop, collection)")
	print("   - FishingController   (cast, hook, reel)")
	print(" Handlers:")
	print("   - AtmosphereHandler   (god rays, caustics, VFX)")
	print("   - FishingRodHandler   (rod model, bobber, line)")
	print("========================================")
end):catch(function(err)
	warn("[DeepTide] Failed to start client:", err)
end)
