--[[
	FishSignals.lua
	Deep Tide Studios — Shared NPC Signal Definitions
	Defines all client-server signals for NPC fish communication.
	Server-authoritative fish NPCs use these to notify clients of state changes.
]]

local FishSignals = {}

-- ============================================================
-- Server -> Client signals
-- These are fired by the server via Knit to notify all/nearby clients
-- ============================================================

-- Fired when a new fish NPC is spawned and should be created on clients
-- (fishId, speciesKey, position, zoneKey)
FishSignals.FishSpawned = "FishSpawned"

-- Fired when a fish is despawned/removed
-- (fishId)
FishSignals.FishDespawned = "FishDespawned"

-- Fired when a fish transitions to a new visual state
-- (fishId, newState, data?) — data is state-specific
FishSignals.FishStateChanged = "FishStateChanged"

-- Fired when a fish is hooked by a player
-- (fishId, playerId)
FishSignals.FishHookedByPlayer = "FishHookedByPlayer"

-- Fired when a fish escapes / line snaps
-- (fishId, reason) — "Fled", "LineSnap", "LowTension", "Escaped"
FishSignals.FishReleased = "FishReleased"

-- Fired when a fish is caught
-- (fishId, playerId, fishData)
FishSignals.FishCaught = "FishCaught"

-- Fired when a rare/legendary fish spawns (for particle bloom)
-- (position, speciesKey, rarity)
FishSignals.RareFishSpawned = "RareFishSpawned"

-- Fired when fish AI needs a client-side visual-only effect
-- (fishId, effectType, params?)
-- effectTypes: "CuriousGlow", "HookedFlash", "TrailParticles", "LeviathanAura"
FishSignals.FishVFX = "FishVFX"

-- ============================================================
-- Client -> Server signal (for querying nearby fish)
-- ============================================================

-- Client requests which fish are near a bobber position
-- Server responds with list of fish in range and their states
-- (bobberPosition, playerId) -> { Fish = { id, species, state, distance } }
FishSignals.QueryNearbyFish = "QueryNearbyFish"

-- ============================================================
-- FSM State enum (shared so client can match states)
-- ============================================================
FishSignals.FishState = {
	Idle = "Idle",
	Patrol = "Patrol",
	Investigate = "Investigate",
	Curious = "Curious",
	ReadyToBite = "ReadyToBite",
	Biting = "Biting",
	Hooked = "Hooked",
	Fighting = "Fighting",
	Fleeing = "Fleeing",
	Despawning = "Despawning",
}

-- ============================================================
-- VFX effect types
-- ============================================================
FishSignals.VFXType = {
	CuriousGlow = "CuriousGlow",       -- subtle outline when Curious
	HookedFlash = "HookedFlash",       -- bright flash when Hooked
	TrailParticles = "TrailParticles", -- bioluminescent trail behind rare+
	LeviathanAura = "LeviathanAura",   -- large glowing aura for rare spawns
	DespawnEffect = "DespawnEffect",   -- particle burst on despawn/catch
}

return FishSignals
