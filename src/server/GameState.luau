-- GameState: the single state store for Berburu Museng.
-- Every player's cash, rebirths, upgrades, base contents, carrying list
-- and lock timer lives here and nowhere else; services read and mutate
-- state only through these functions. Also owns DataStore save/load.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BrainrotData = require(Shared:WaitForChild("BrainrotData"))

local BrainrotFactory = require(ServerScriptService:WaitForChild("BrainrotFactory"))
local WorldBuilder = require(ServerScriptService:WaitForChild("WorldBuilder"))

local GameState = {}

local playerDataByPlayer = {}
local world = nil
local dataStore = nil

-- Hooks other services install (StealService uses them to attach and
-- detach steal prompts as brainrots come and go).
GameState.OnBrainrotPlaced = nil
GameState.OnBrainrotRemoved = nil

function GameState.SetWorld(worldRefs)
	world = worldRefs
end

local function getStore()
	if dataStore then
		return dataStore
	end
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		dataStore = store
	end
	return dataStore
end

function GameState.GetPlayerData(player)
	return playerDataByPlayer[player]
end

function GameState.GetAllPlayerData()
	return playerDataByPlayer
end

function GameState.GetBaseForPlayer(player)
	local data = playerDataByPlayer[player]
	if not data or not world then
		return nil
	end
	return world.Bases[data.BaseIndex]
end

local function claimFreeBase()
	if not world then
		return nil
	end
	for _, base in ipairs(world.Bases) do
		if base.Owner == nil then
			return base
		end
	end
	return nil
end

local function defaultData()
	return {
		Cash = Config.StartingCash,
		Rebirths = 0,
		SpeedLevel = 0,
		CarryLevel = 0,
		BaseIndex = nil,
		Pads = {}, -- [padIndex] = { Id = ..., Mutation = ... }
		PadModels = {}, -- [padIndex] = Model
		Carrying = {}, -- array of { Id, Mutation, Model }
		LockEnd = 0,
	}
end

local function serializeData(data)
	local pads = {}
	for padIndex, entry in pairs(data.Pads) do
		table.insert(pads, { Pad = padIndex, Id = entry.Id, Mutation = entry.Mutation })
	end
	return {
		Cash = data.Cash,
		Rebirths = data.Rebirths,
		SpeedLevel = data.SpeedLevel,
		CarryLevel = data.CarryLevel,
		Pads = pads,
	}
end

local function loadSavedData(player, data)
	local store = getStore()
	if not store then
		return
	end
	local ok, saved = pcall(function()
		return store:GetAsync("Player_" .. player.UserId)
	end)
	if not ok or type(saved) ~= "table" then
		return
	end
	data.Cash = saved.Cash or data.Cash
	data.Rebirths = saved.Rebirths or 0
	data.SpeedLevel = saved.SpeedLevel or 0
	data.CarryLevel = saved.CarryLevel or 0
	if type(saved.Pads) == "table" then
		for _, entry in ipairs(saved.Pads) do
			if entry.Pad and entry.Pad >= 1 and entry.Pad <= Config.PadsPerBase
				and entry.Id and BrainrotData.GetCharacter(entry.Id) then
				data.Pads[entry.Pad] = { Id = entry.Id, Mutation = entry.Mutation or "None" }
			end
		end
	end
end

function GameState.SavePlayer(player)
	local data = playerDataByPlayer[player]
	if not data then
		return
	end
	local store = getStore()
	if not store then
		return
	end
	local snapshot = serializeData(data)
	pcall(function()
		store:SetAsync("Player_" .. player.UserId, snapshot)
	end)
end

-- Create a player's state, claim a base, load their save and rebuild
-- the brainrots that were standing on their pads.
function GameState.InitPlayer(player)
	if playerDataByPlayer[player] then
		return playerDataByPlayer[player]
	end
	local data = defaultData()
	playerDataByPlayer[player] = data

	local base = claimFreeBase()
	if base then
		base.Owner = player
		data.BaseIndex = base.Index
		WorldBuilder.SetBaseOwner(base, player.Name)
	end

	loadSavedData(player, data)

	if base then
		for padIndex, entry in pairs(data.Pads) do
			GameState.PlaceBrainrotModel(player, padIndex, entry.Id, entry.Mutation)
		end
	end
	warn("Berburu Museng: player data ready for " .. player.Name
		.. ": cash " .. data.Cash .. ", base " .. tostring(data.BaseIndex))
	return data
end

-- Tear a player down: save, free the base, remove their models.
function GameState.RemovePlayer(player)
	local data = playerDataByPlayer[player]
	if not data then
		return
	end
	GameState.SavePlayer(player)
	for padIndex, model in pairs(data.PadModels) do
		if model then
			model:Destroy()
		end
		data.PadModels[padIndex] = nil
	end
	for _, entry in ipairs(data.Carrying) do
		if entry.Model then
			entry.Model:Destroy()
		end
	end
	local base = GameState.GetBaseForPlayer(player)
	if base then
		base.Owner = nil
		WorldBuilder.ClearBaseOwner(base)
		WorldBuilder.SetBaseLocked(base, false)
	end
	playerDataByPlayer[player] = nil
end

function GameState.AddCash(player, amount)
	local data = playerDataByPlayer[player]
	if data then
		data.Cash = data.Cash + amount
	end
end

function GameState.TrySpendCash(player, amount)
	local data = playerDataByPlayer[player]
	if not data or data.Cash < amount then
		return false
	end
	data.Cash = data.Cash - amount
	return true
end

function GameState.GetIncomeMultiplier(player)
	local data = playerDataByPlayer[player]
	if not data then
		return 1
	end
	return 2 ^ data.Rebirths
end

function GameState.GetCarryCapacity(player)
	local data = playerDataByPlayer[player]
	if not data then
		return 1
	end
	return 1 + data.CarryLevel
end

-- Total $/s from placed brainrots, mutation and rebirth included.
function GameState.GetIncomePerSecond(player)
	local data = playerDataByPlayer[player]
	if not data then
		return 0
	end
	local total = 0
	for _, entry in pairs(data.Pads) do
		total = total + BrainrotData.GetEffectiveRate(entry.Id, entry.Mutation)
	end
	return total * GameState.GetIncomeMultiplier(player)
end

function GameState.GetFreePad(player)
	local data = playerDataByPlayer[player]
	if not data then
		return nil
	end
	for padIndex = 1, Config.PadsPerBase do
		if not data.Pads[padIndex] then
			return padIndex
		end
	end
	return nil
end

function GameState.CountPlaced(player)
	local data = playerDataByPlayer[player]
	if not data then
		return 0
	end
	local count = 0
	for _ in pairs(data.Pads) do
		count = count + 1
	end
	return count
end

-- Build the model for a pad entry and stand it on the pad.
function GameState.PlaceBrainrotModel(player, padIndex, id, mutation)
	local data = playerDataByPlayer[player]
	local base = GameState.GetBaseForPlayer(player)
	if not data or not base then
		return nil
	end
	local padPosition = base.PadPositions[padIndex]
	if not padPosition then
		return nil
	end
	local model = BrainrotFactory.BuildCharacter(id, mutation, CFrame.new(padPosition))
	if not model then
		return nil
	end
	-- Same anchoring contract as the wild models: an anchored,
	-- non-colliding root, so a placed brainrot can never fall through
	-- its pad or be shoved off it.
	local root = model.PrimaryPart or model:FindFirstChild("Body")
	if root then
		root.Anchored = true
		root.CanCollide = false
	end
	model.Parent = workspace
	data.PadModels[padIndex] = model
	if GameState.OnBrainrotPlaced then
		GameState.OnBrainrotPlaced(player, padIndex, model)
	end
	return model
end

-- Record a brainrot on a pad and build its model.
function GameState.PlaceOnPad(player, padIndex, id, mutation)
	local data = playerDataByPlayer[player]
	if not data or data.Pads[padIndex] then
		return false
	end
	data.Pads[padIndex] = { Id = id, Mutation = mutation }
	-- The build is pcall'd: a factory failure can be a nil return OR
	-- a throw (the live place's PivotOffset bug threw), and either
	-- way the pad entry recorded above must not survive it.
	local built, model = pcall(GameState.PlaceBrainrotModel, player, padIndex, id, mutation)
	if not built or not model then
		-- Leave no ghost entry behind. A recorded pad with no model
		-- would pay income for a brainrot that does not exist, and a
		-- caller that charges for the placement (BuyEgg) relies on
		-- this false to keep the player's cash.
		if not built then
			warn("Berburu Museng: brainrot build failed for pad " .. padIndex .. ": " .. tostring(model))
		end
		data.Pads[padIndex] = nil
		return false
	end
	return true
end

-- Take a brainrot off a pad WITHOUT destroying its model; the caller
-- decides whether the model is destroyed (sell) or kept (steal).
function GameState.TakeFromPad(player, padIndex)
	local data = playerDataByPlayer[player]
	if not data then
		return nil, nil
	end
	local entry = data.Pads[padIndex]
	local model = data.PadModels[padIndex]
	data.Pads[padIndex] = nil
	data.PadModels[padIndex] = nil
	if entry and GameState.OnBrainrotRemoved then
		GameState.OnBrainrotRemoved(player, padIndex, model)
	end
	return entry, model
end

-- Remove every placed brainrot (rebirth). Models are destroyed.
function GameState.ClearBase(player)
	local data = playerDataByPlayer[player]
	if not data then
		return
	end
	local indices = {}
	for padIndex in pairs(data.Pads) do
		table.insert(indices, padIndex)
	end
	for _, padIndex in ipairs(indices) do
		local _, model = GameState.TakeFromPad(player, padIndex)
		if model then
			model:Destroy()
		end
	end
end

function GameState.IsBaseLocked(player)
	local data = playerDataByPlayer[player]
	if not data then
		return false
	end
	return data.LockEnd > os.clock()
end

function GameState.GetLockSecondsLeft(player)
	local data = playerDataByPlayer[player]
	if not data then
		return 0
	end
	return math.max(0, data.LockEnd - os.clock())
end

function GameState.SetBaseLock(player, seconds)
	local data = playerDataByPlayer[player]
	if data then
		data.LockEnd = os.clock() + seconds
	end
end

function GameState.GetRebirthCost(player)
	local data = playerDataByPlayer[player]
	local rebirths = data and data.Rebirths or 0
	return Config.RebirthBaseCost * (Config.RebirthCostGrowth ^ rebirths)
end

-- Periodic autosave for everyone in the game.
function GameState.StartAutosave()
	task.spawn(function()
		while true do
			task.wait(Config.AutosavePeriod)
			for player in pairs(playerDataByPlayer) do
				GameState.SavePlayer(player)
			end
		end
	end)
	if not RunService:IsStudio() then
		game:BindToClose(function()
			for player in pairs(playerDataByPlayer) do
				GameState.SavePlayer(player)
			end
		end)
	end
end

return GameState
