-- Config: every tuning constant for Berburu Museng in one place.
-- World layout numbers here are the same ones WorldBuilder builds from,
-- so the client (Effects) can reason about the field bounds too.

local Config = {}

-- Fresh profiles start here (loaded saves always overwrite this in
-- GameState.loadSavedData). 150 covers the first Telur Kardus (100)
-- with change, so a new player's first purchase is always available.
Config.StartingCash = 150

-- Tsunami wave hazard.
Config.WavePeriod = 80 -- seconds between wave starts (warning included)
Config.WaveWarningTime = 10 -- seconds of siren/banner before the wall moves
Config.WaveCrossTime = 9 -- seconds the wall takes to cross the field

-- Bases.
Config.BaseCount = 8
Config.PadsPerBase = 10
Config.LockDuration = 60 -- seconds a base lock force-field stays up

-- Wild field population.
Config.WildCount = 14
Config.WildRarityOdds = { Common = 62, Rare = 26, Epic = 9, Legendary = 3 }
Config.WildMutationOdds = { Gold = 5, Diamond = 1.5, Galaxy = 0.5 }
Config.HatchMutationOdds = { Gold = 8, Diamond = 3, Galaxy = 1 }

-- Selling a placed brainrot (or auto-selling a hatch into a full base)
-- pays this fraction of the character's price.
Config.SellFraction = 0.5

-- Rebirth: cost = RebirthBaseCost * RebirthCostGrowth ^ rebirths,
-- income multiplier = 2 ^ rebirths.
Config.RebirthBaseCost = 10000
Config.RebirthCostGrowth = 6

-- Upgrades.
Config.BaseWalkSpeed = 16
Config.SpeedPerLevel = 4
Config.SpeedUpgradeCosts = { 500, 2500, 10000 }
Config.CarryUpgradeCosts = { 2000, 15000 } -- carry 2, then carry 3

-- Wild field bounds (the tsunami only threatens carriers inside these).
Config.Field = { MinX = -170, MaxX = 170, MinZ = -160, MaxZ = 20 }

-- DataStore.
Config.DataStoreName = "BerburuMuseng_v1"
Config.AutosavePeriod = 120

return Config
