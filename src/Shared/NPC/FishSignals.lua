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

-- Phase 2: Fired when a Kelp Serpent spawns — zone-wide "The water grows cold..." warning
-- (position, landmark)
FishSignals.ApexPresenceWarning = "ApexPresenceWarning"

-- Phase 2: Fired when a Lantern Squid releases ink burst
-- (fishId, position, radius, duration)
FishSignals.InkBurst = "InkBurst"

-- Phase 2: Fired when sonar ping detects fish (server→client)
-- (player, pingData)
FishSignals.SonarPingResult = "SonarPingResult"

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

	-- Phase 2: Kelp Forest specific states
	Camouflaged = "Camouflaged",     -- Kelp Stalker: blended against kelp, nearly invisible
	Burrowed = "Burrowed",           -- Grotto Crab: hidden in crevice, only eyes visible
	Emerging = "Emerging",           -- Grotto Crab: emerging from crevice toward bait
	InkCloud = "InkCloud",           -- Lantern Squid: ink burst active, meter obscured
	TentacleContact = "TentacleContact", -- Void Jellyfish: player in tentacles, taking damage
	Enraged = "Enraged",             -- Kelp Serpent: accelerated after failed hook
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

	-- Phase 2 effects
	CamouflageShimmer = "CamouflageShimmer",  -- periodic shimmer on Kelp Stalker
	InkCloudVFX = "InkCloudVFX",              -- black ink sphere from Lantern Squid
	TentacleGlow = "TentacleGlow",            -- Void Jellyfish tentacle pulse
	ApexRedTint = "ApexRedTint",              -- screen-edge red tint during Apex presence
	SonarPulseVFX = "SonarPulseVFX",          -- expanding ring wave from player
	KelpEntanglementVFX = "KelpEntanglementVFX", -- kelp strands wrapping player
	AirPocketBubbles = "AirPocketBubbles",    -- bubble column in cave ceiling
	CurrentParticles = "CurrentParticles",    -- directional particle stream in The Clearing
}

return FishSignals
