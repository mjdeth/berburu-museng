-- StealService: base defence and theft. Each base has a lock pedestal:
-- the owner locks their base for Config.LockDuration seconds, raising a
-- visible force-field. While a base is unlocked, any visitor with spare
-- carry capacity can grab a brainrot off its pads via the pad's steal
-- prompt and run home with it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BrainrotData = require(Shared:WaitForChild("BrainrotData"))

local GameState = require(ServerScriptService:WaitForChild("GameState"))
local WorldBuilder = require(ServerScriptService:WaitForChild("WorldBuilder"))
local CatchService = require(ServerScriptService:WaitForChild("CatchService"))
local EconomyService = require(ServerScriptService:WaitForChild("EconomyService"))

local StealService = {}

local world = nil

function StealService.TrySteal(visitor, owner, padIndex)
	if visitor == owner then
		return
	end
	local ownerData = GameState.GetPlayerData(owner)
	if not ownerData or not ownerData.Pads[padIndex] then
		return
	end
	if GameState.IsBaseLocked(owner) then
		return
	end
	local visitorData = GameState.GetPlayerData(visitor)
	if not visitorData then
		return
	end
	if #visitorData.Carrying >= GameState.GetCarryCapacity(visitor) then
		return
	end
	local entry, model = GameState.TakeFromPad(owner, padIndex)
	if not entry or not model then
		return
	end
	if not CatchService.AddCarrying(visitor, entry.Id, entry.Mutation, model) then
		-- No room after all: put it straight back.
		GameState.PlaceOnPad(owner, padIndex, entry.Id, entry.Mutation)
		model:Destroy()
		return
	end
	EconomyService.SendState(owner)
	EconomyService.SendState(visitor)
end

local function attachStealPrompt(owner, padIndex, model)
	local body = model:FindFirstChild("Body")
	if not body then
		return
	end
	local character = BrainrotData.GetCharacter(model:GetAttribute("BrainrotId"))
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StealPrompt"
	prompt.ActionText = "Steal"
	prompt.ObjectText = character and character.Name or "Brainrot"
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(function(visitor)
		StealService.TrySteal(visitor, owner, padIndex)
	end)
	prompt.Parent = body
end

local function connectLockPedestals()
	for _, base in ipairs(world.Bases) do
		base.LockPrompt.Triggered:Connect(function(player)
			if base.Owner ~= player then
				return
			end
			if GameState.IsBaseLocked(player) then
				return
			end
			GameState.SetBaseLock(player, Config.LockDuration)
			WorldBuilder.SetBaseLocked(base, true)
			EconomyService.SendState(player)
		end)
	end
end

-- Watch lock timers: drop force-fields as they expire and keep the
-- owner's HUD countdown fresh while a lock is running.
local function watchLockTimers()
	while true do
		task.wait(1)
		for player, data in pairs(GameState.GetAllPlayerData()) do
			local base = GameState.GetBaseForPlayer(player)
			if base then
				local locked = GameState.IsBaseLocked(player)
				WorldBuilder.SetBaseLocked(base, locked)
				if locked then
					EconomyService.SendState(player)
				end
			end
		end
	end
end

function StealService.Start(worldRefs)
	world = worldRefs
	GameState.OnBrainrotPlaced = function(owner, padIndex, model)
		attachStealPrompt(owner, padIndex, model)
	end
	GameState.OnBrainrotRemoved = function(owner, padIndex, model)
		-- The model is NOT always destroyed here: a steal carries it
		-- away alive, so its steal prompt must come off explicitly.
		-- Left on, the prompt's stale (owner, padIndex) closure could
		-- be triggered wherever the model ends up (e.g. dropped back
		-- into the wild by the wave) and would act on whatever brainrot
		-- now stands on that pad, stealing it from a distance.
		if model then
			local prompt = model:FindFirstChild("StealPrompt", true)
			if prompt then
				prompt:Destroy()
			end
		end
	end
	connectLockPedestals()
	task.spawn(watchLockTimers)
	warn("Berburu Museng: StealService live (lock pedestals wired, steal prompts on placement)")
end

return StealService
