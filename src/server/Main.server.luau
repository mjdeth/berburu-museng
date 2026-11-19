-- Main: bootstrap only. Creates the remotes, builds the world, wires
-- the services together and handles players joining and leaving.
-- All game logic lives in the services.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WorldBuilder = require(ServerScriptService:WaitForChild("WorldBuilder"))
local GameState = require(ServerScriptService:WaitForChild("GameState"))
local EconomyService = require(ServerScriptService:WaitForChild("EconomyService"))
local CatchService = require(ServerScriptService:WaitForChild("CatchService"))
local StealService = require(ServerScriptService:WaitForChild("StealService"))

local function createRemotes()
	local folder = Instance.new("Folder")
	folder.Name = "BerburuMusengRemotes"
	local names = {
		{ "BuyEggFunction", "RemoteFunction" },
		{ "SellPadFunction", "RemoteFunction" },
		{ "RebirthFunction", "RemoteFunction" },
		{ "BuyUpgradeFunction", "RemoteFunction" },
		{ "GetStateFunction", "RemoteFunction" },
		{ "CashUpdated", "RemoteEvent" },
		{ "BaseUpdated", "RemoteEvent" },
		{ "WaveWarning", "RemoteEvent" },
		{ "EffectEvent", "RemoteEvent" },
	}
	for _, spec in ipairs(names) do
		local remote = Instance.new(spec[2])
		remote.Name = spec[1]
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
	return folder
end

createRemotes()

local world = WorldBuilder.Build()
GameState.SetWorld(world)

local function onCharacterAdded(player, character)
	EconomyService.ApplySpeed(player)
end

local function onPlayerAdded(player)
	task.spawn(function()
		GameState.InitPlayer(player)
		EconomyService.OnPlayerJoined(player)
		-- InitPlayer yields while the save loads, so a CharacterAdded
		-- that fired in the meantime applied the default SpeedLevel 0.
		-- Re-apply now that the loaded level is final.
		EconomyService.ApplySpeed(player)
	end)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

local function onPlayerRemoving(player)
	GameState.RemovePlayer(player)
end

-- Player wiring is connected BEFORE any service starts, and every
-- service Start is isolated behind pcall. In the first live playtest
-- this script died inside a service Start (in CatchService.Start's
-- opening population spawn): the purchase remotes were already
-- connected and kept answering, but PlayerAdded was only connected
-- after every Start, so no player was ever initialised -- purchases
-- met empty state and the field stayed unstocked. That ordering can
-- never strand players again: joins are wired first, and a failed
-- service now only costs its own feature, loudly, via warn.
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

local function startService(name, start)
	local ok, err = pcall(start)
	if not ok then
		warn("Berburu Museng: " .. name .. " failed to start: " .. tostring(err))
	end
end

startService("EconomyService", function()
	EconomyService.Start(world)
end)
startService("CatchService", function()
	CatchService.Start(world)
end)
startService("StealService", function()
	StealService.Start(world)
end)
GameState.StartAutosave()

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

print("Berburu Museng is live: world built, services running.")
