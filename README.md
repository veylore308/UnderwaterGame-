# Deep Tide — Roblox Project

**Deep Tide Studios** — Premium deep-sea exploration and fishing experience on Roblox.

## Project Structure

```
deep-tide/
├── default.project.json         # Rojo project configuration
├── wally.toml                    # Wally package dependencies
├── README.md                     # This file
├── place/
│   ├── master-setup.lua          # MASTER: terrain + atmosphere in one script
│   ├── setup.lua                 # Legacy: terrain only (kept for reference)
│   └── atmosphere-setup.lua      # Legacy: VFX only (kept for reference)
└── src/
    ├── Shared/                   # ReplicatedStorage — shared between client & server
    │   ├── init.lua              # Shared module (re-exports all constants)
    │   ├── Knit.lua              # Knit framework stub (with GetSignal for cross-svc comms)
    │   ├── Constants/
    │   │   ├── FishSpecies.lua   # 6 fish species with AI/hook/reel params
    │   │   ├── RodTiers.lua      # 5 rod tiers (3 MVP + 2 future)
    │   │   ├── SuitTiers.lua     # 3 suit tiers (2 MVP + 1 future)
    │   │   ├── RarityTiers.lua   # Rarity definitions, colors, XP values
    │   │   └── ZoneConfigs.lua   # Zone definitions, landmarks, populations
    │   └── NPC/
    │       └── FishSignals.lua   # Shared FSM state enum + signal definitions
    ├── Server/                   # ServerScriptService
    │   ├── init.server.lua       # Server bootstrap (pre-loads NPC + services)
    │   ├── DataStore2.lua        # DataStore2 stub (in-memory persistence)
    │   ├── Services/
    │   │   ├── PlayerDataService.lua  # Player data, inventory, collection log
    │   │   ├── EconomyService.lua     # Buy/sell/equip/upgrade transactions
    │   │   ├── ZoneService.lua        # Zone state, fish population, spawner mgmt
    │   │   └── FishingService.lua     # Authoritative fishing logic (NPC-integrated)
    │   └── NPC/
    │       ├── FishNPC.lua       # 10-state FSM: Idle→Patrol→Investigate→...→Despawning
    │       └── FishSpawner.lua   # Population management, spawn cycles, rare conditions
    └── Client/                   # StarterPlayerScripts
        ├── init.client.lua       # Client bootstrap (pre-loads handlers + UI + controllers)
        ├── Controllers/
        │   ├── CameraController.lua   # Depth fog, camera bob, fishing cam transitions
        │   ├── FishingController.lua  # Cast, aim, hook minigame, reel loop
        │   └── UIController.lua       # Persistent HUD, shop, collection book
        ├── Handlers/
        │   ├── AtmosphereHandler.lua  # God rays, caustics, plankton, marine snow, player VFX
        │   └── FishingRodHandler.lua  # 3D rod model, bobber, line beam, aim arc
        └── UI/
            ├── FishingHUD.lua         # Hook circle, tension meter, progress bar, showcase
            ├── CollectionBook.lua     # Species grid, detail view, discovery popups
            └── ShopScreen.lua         # Rods, consumables, gamepasses, purchase flow
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLIENT                                    │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐ │
│  │ CameraController │  │  UIController    │  │FishingControl.│ │
│  │  • depth fog     │  │  • HUD overlay   │  │ • cast/hook/  │ │
│  │  • camera bob    │  │  • CollectionBook│  │   reel loop   │ │
│  │  • fishing cam   │  │  • ShopScreen    │  │ • FishingHUD  │ │
│  └────────┬─────────┘  └────────┬─────────┘  │ • RodHandler  │ │
│           │                     │              └───────┬───────┘ │
│  ┌────────┴─────────────────────┴──────────────────────┴───────┐ │
│  │                   AtmosphereHandler                          │ │
│  │  god rays • caustics • marine snow • plankton • bubble VFX  │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                  │
└──────────────────────────────┬───────────────────────────────────┘
                               │ Knit Signals
┌──────────────────────────────┴───────────────────────────────────┐
│                        SERVER                                     │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐ │
│  │ PlayerDataService│  │ EconomyService   │  │  ZoneService  │ │
│  │ • AddFish()      │  │ • BuyItem()      │  │ • GetZone()   │ │
│  │ • AddCoins/Gems  │  │ • SellFish()     │  │ • Spawner mgmt│ │
│  │ • GrantRod/Suit  │  │ • EquipRod()     │  │ • Bobber reg  │ │
│  │ • DataStore2     │  │ • ProcessBuy     │  │ • Pop loop    │ │
│  └────────┬─────────┘  └────────┬─────────┘  └───────┬───────┘ │
│           │                     │                     │          │
│  ┌────────┴─────────────────────┴─────────────────────┴───────┐ │
│  │                    FishingService                           │ │
│  │  ProcessCast() → ProcessHook() → ProcessReelTick()         │ │
│  │  _resolveBitingFish() integrates with real FishNPC system  │ │
│  └────────────────────────┬───────────────────────────────────┘ │
│                           │                                      │
│  ┌────────────────────────┴───────────────────────────────────┐ │
│  │                    FishSpawner • FishNPC                    │ │
│  │  10-state FSM • school behavior • rare spawn conditions    │ │
│  │  _fireRareSpawnBloom() → Knit.GetSignal("RareFishSpawned") │ │
│  └────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

### Signal Flow

```
Rare Fish Spawn Bloom:
  FishSpawner._fireRareSpawnBloom()
    → Knit.GetSignal("RareFishSpawned"):Fire(position, name, rarity)
      → AtmosphereHandler.PlayRareSpawnBloom(position, rarity)

Fishing Loop:
  FishingController.CastLine:Call(targetPos)
    → FishingService.ProcessCast()
      → ZoneService.RegisterBobber()
        → FishSpawner.RegisterBobber()
          → fish:OnBobberNearby() → transitions through FSM states
  
  FishingController.HookAttempt:Call(castId, timingQuality)
    → FishingService.ProcessHook()
      → ZoneService.GetFishNearBobber() → resolves real NPC fish
      → fish:OnHookAttempt(success)
        → Client: FishHooked event

  FishingController.ReelUpdate:Call(castId, isReeling)
    → FishingService.ProcessReelTick()
      → tension/progress update → fish:OnCaught() / OnLineSnap() / OnEscape()
        → PlayerDataService.AddFish() → Client: FishCaught event

Shop:
  UIController.OnBuyClicked → EconomyService.BuyItem:Call()
    → EconomyService.ProcessBuyRequest()
      → PlayerDataService.GrantRod / GrantSuit
        → Client: DataUpdated → _refreshHUD()

Equip Rod:
  ShopScreen._equipRod → SetEquipCallback → UIController._onRodEquipped
    → EconomyService.EquipRod:Call(rodKey)
      → PlayerDataService.EquipRod()
        → Client: DataUpdated → _refreshHUD()
```

## Setup Instructions

### Prerequisites

1. [Roblox Studio](https://create.roblox.com/)
2. [Rojo](https://rojo.space/) v7+ installed
3. [Wally](https://wally.run/) (optional — for production Knit + DataStore2)

### Quick Start (Development)

1. **Open the project in Roblox Studio:**
   - Create a new Baseplate place
   - Save it to `deep-tide/place/DeepTide.rbxl`

2. **Sync with Rojo:**
   ```bash
   cd deep-tide
   rojo serve
   ```
   In Roblox Studio, connect the Rojo plugin to `localhost`.

3. **Run the master setup script:**
   - Paste the contents of `place/master-setup.lua` into the Roblox Studio Command Bar
   - Press Enter — this creates all terrain, structures, lighting, and VFX in one step
   - The script is idempotent — safe to re-run (skips existing objects)

4. **Verify Rojo sync:**
   - Check Output for `[Server] Shared module loaded — 6 fish species`
   - You should see `ReplicatedStorage.Shared`, `ServerScriptService.Server`, etc.

5. **Press Play** — you should see:
   ```
   ========================================
    Deep Tide Studios — Server Initialized
   ========================================
    Services:
      - PlayerDataService   (data persistence)
      - EconomyService      (transactions)
      - ZoneService         (zones + FishSpawner)
      - FishingService      (authoritative fishing)
      - FishNPC system      (10-state FSM)
   ========================================
   ```

### What to Expect at Play

1. **Atmosphere activates** — god rays, caustic lights, marine snow, plankton particles
2. **Fish spawn** — Glowfin Minnows (schools), Coral Snappers, Reef Darts populate the zone
3. **HUD appears** — top bar (coins/gems), oxygen gauge, depth meter, rod display, quick-access buttons
4. **Dive underwater** — camera transitions, fog deepens, bubble trail follows player
5. **Cast your rod** — click to aim (hold for power), release to cast
6. **Hook minigame** — click when the circle reaches the sweet zone
7. **Reel minigame** — hold click to reel, release to let tension drop
8. **Catch fish** — rarity reveal, collection book updates, coins awarded
9. **Open shop** (S key) — buy rods, consumables, gamepasses
10. **Open collection** (B key) — view caught species, weights, completion progress

### Production Setup (with real Knit + DataStore2)

1. Install dependencies:
   ```bash
   wally install
   ```
   Downloads Knit, Promise, and Signal to `Packages/`.

2. Update `default.project.json` to point Knit to Wally packages:
   ```json
   "Knit": { "$path": "Packages/_Index/sleitnick_knit@1.x.x/knit" }
   ```

3. Replace `src/Shared/Knit.lua` with the real Knit module path.

4. Replace `src/Server/DataStore2.lua` with full DataStore2 module from:
   https://github.com/Kampfkarren/Roblox-DataStore2

## Integration Points (for developers)

### Adding a new fish species
1. Add entry to `Shared/Constants/FishSpecies.lua` with full stats
2. Add to landmark's `PrimaryFish` in `ZoneConfigs.lua` if needed
3. FishSpawner automatically includes it via `GetSpawnTable()`

### Adding a new zone
1. Add entry to `Shared/Constants/ZoneConfigs.lua`
2. ZoneService auto-initializes it if `IsMVP = true`

### Adding a new UI screen
1. Create screen module in `Client/UI/`
2. Register in `UIController:KnitInit()` (like CollectionBook/ShopScreen)
3. Add keyboard shortcut in `_wireKeyboardShortcuts()`

### Knit.GetSignal — cross-service communication
Used for signals that don't belong to any single service. Currently:
- `"RareFishSpawned"` — FishSpawner (server) → AtmosphereHandler (client) for rare spawn bloom VFX

## Known Limitations

| Limitation | Impact | Workaround |
|---|---|---|
| Knit stub — signals are local, not networked | Works in Studio Play Solo; won't work in multiplayer | Replace with real Knit via Wally for production |
| DataStore2 stub — in-memory only | Data lost on server restart | Replace with real DataStore2 for production |
| No swimming/oxygen system | Player can't actually dive underwater without Character controller | Place spawn at depth or add swimming controller |
| CameraController + AtmosphereHandler both modify Lighting | Slight visual jitter on Bloom/DoF per frame | Acceptable for MVP; consolidate in future |
| Fish models are simple Parts | No mesh models — fish are colored blocks | Add mesh assets in future; FSM + movement works regardless |
| FishingController._getRodStats always returns BambooRod | Rod upgrades don't affect client-side calculations | Server-side uses correct rod stats; client display only |
| No audio/SFX wired | FishingController._playSound is a stub | Add Sound objects in future iteration |

## MVP Scope Checklist

- [x] Project structure (Rojo + Knit stub)
- [x] 4 Knit services (PlayerData, Economy, Zone, Fishing)
- [x] 3 Knit controllers (Fishing, UI, Camera)
- [x] 6 fish species with full AI/hook/reel stats
- [x] FishNPC 10-state FSM (Idle→Patrol→Investigate→Curious→ReadyToBite→Biting→Hooked→Fighting→Fleeing→Despawning)
- [x] FishSpawner with population management, schooling, rare spawn conditions
- [x] Rod tiers 1-3 (MVP) + 4-5 (future) defined
- [x] Suit tiers 1-2 (MVP) + 3 (future) defined
- [x] Rarity system with colors and XP
- [x] Zone config with all 4 landmarks + Sandy Plains
- [x] Economy: coins, gems, shop, consumables, gamepasses
- [x] Collection milestones with rewards
- [x] Data persistence (DataStore2 stub)
- [x] Authoritative fishing logic (cast, hook, reel, catch) — integrated with real FishNPC
- [x] Persistent HUD overlay (coins, gems, oxygen, depth, rod, quick-access buttons)
- [x] Collection Book UI (species grid, detail view, discovery notifications)
- [x] Shop Screen UI (rods, consumables, gamepasses, purchase confirm dialog)
- [x] Fishing HUD (hook circle, tension meter, progress bar, rarity showcase)
- [x] Atmosphere handler (god rays, caustics, marine snow, plankton, landmark VFX, player VFX)
- [x] Camera controller (depth fog, camera bob, fishing cam transitions, surface breach/submerge)
- [x] Master setup script (terrain + atmosphere combined, idempotent)
- [x] All systems integrated — signal chains verified
- [ ] Place file with underwater terrain (run `place/master-setup.lua` in Studio)
- [ ] Real Knit networking (Wally install for multiplayer)
- [ ] Swimming/oxygen controller (player movement system)
- [ ] Audio/SFX system
- [ ] Fish mesh models (currently colored block parts)
