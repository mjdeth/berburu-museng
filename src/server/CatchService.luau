-- CatchService: the wild hunt. A spawn director keeps the field stocked
-- with wandering brainrots; players catch them by prompt or touch and
-- carry them on their heads; a periodic tsunami sweeps the field and
-- knocks carried brainrots loose from anyone caught out in the open;
-- stepping onto your own base deposits everything you carry.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BrainrotData = require(Shared:WaitForChild("BrainrotData"))

local BrainrotFactory = require(ServerScriptService:WaitForChild("BrainrotFactory"))
local GameState = require(ServerScriptService:WaitForChild("GameState"))
local WorldBuilder = require(ServerScriptService:WaitForChild("WorldBuilder"))
local EconomyService = require(ServerScriptService:WaitForChild("EconomyService"))

local CatchService = {}

local world = nil
local wildFolder = nil -- Folder under Workspace holding every wild model
local wildBrainrots = {} -- array of { Id, Mutation, Model, TargetPos, Speed, Caught }
local wildEntryByModel = {} -- [Model] = its current wild entry (a model can be re-wilded under a new entry)
local touchDebounce = {} -- [player] = os.clock() of last touch catch

-- FindFirstChild only: a WaitForChild on an event path can yield a
-- catch/wave callback forever if the child is ever missing, silently.
local function findRemote(name)
	local folder = ReplicatedStorage:FindFirstChild("BerburuMusengRemotes")
	if not folder then
		return nil
	end
	return folder:FindFirstChild(name)
end

local function fireEffect(player, kind, position)
	local remote = findRemote("EffectEvent")
	if remote then
		remote:FireClient(player, kind, position)
	end
end

local function randomFieldPosition()
	local field = Config.Field
	-- Spawns and wander targets are biased to the two-thirds of the
	-- field nearest the plaza, where players enter. A uniform scatter
	-- put most brainrots 200+ studs away, where a 4-stud model is a
	-- speck and its label is past MaxDistance: the field read empty.
	local nearMinZ = field.MaxZ - math.floor((field.MaxZ - field.MinZ) * 2 / 3)
	return Vector3.new(
		math.random(field.MinX + 8, field.MaxX - 8),
		0.15,
		math.random(nearMinZ + 8, field.MaxZ - 8)
	)
end

local function isInsideField(position)
	local field = Config.Field
	return position.X >= field.MinX and position.X <= field.MaxX
		and position.Z >= field.MinZ and position.Z <= field.MaxZ
end

local function isOnHighGround(position)
	local mesa = world.MesaBounds
	return position.X >= mesa.MinX and position.X <= mesa.MaxX
		and position.Z >= mesa.MinZ and position.Z <= mesa.MaxZ
		and position.Y >= mesa.TopY - 3
end

local function isSafeFromWave(position)
	if not isInsideField(position) then
		return true
	end
	if isOnHighGround(position) then
		return true
	end
	for _, base in ipairs(world.Bases) do
		if WorldBuilder.IsInsideBase(base, position) then
			return true
		end
	end
	return false
end

local function removeWildEntry(entry)
	for i, candidate in ipairs(wildBrainrots) do
		if candidate == entry then
			table.remove(wildBrainrots, i)
			return
		end
	end
end

local function attachCatchPrompt(entry)
	local body = entry.Model:FindFirstChild("Body")
	if not body then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CatchPrompt"
	prompt.ActionText = "Catch"
	prompt.ObjectText = entry.Model.Name
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(function(player)
		CatchService.TryCatch(player, entry)
	end)
	prompt.Parent = body
end

-- Connect the touch-to-catch handler on a model's Body, once per model.
-- The handler resolves the model's CURRENT wild entry from
-- wildEntryByModel at touch time: binding it to the entry that existed
-- when the model first spawned would go stale the moment the model is
-- caught, carried and dropped back into the wild under a new entry
-- (the old entry stays Caught forever, so touch-catch would silently
-- never fire again for that model).
local function wireTouchCatch(model)
	if model:GetAttribute("TouchCatchWired") then
		return
	end
	local body = model:FindFirstChild("Body")
	if not body then
		return
	end
	model:SetAttribute("TouchCatchWired", true)
	body.Touched:Connect(function(hit)
		local entry = wildEntryByModel[model]
		if not entry or entry.Caught then
			return
		end
		local characterModel = hit and hit.Parent
		local humanoid = characterModel and characterModel:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local player = Players:GetPlayerFromCharacter(characterModel)
		if not player then
			return
		end
		local now = os.clock()
		if touchDebounce[player] and now - touchDebounce[player] < 1 then
			return
		end
		touchDebounce[player] = now
		CatchService.TryCatch(player, entry)
	end)
end

-- Wild brainrots must read from across the field: scale the model up
-- and give its label a much longer reach than the pad label it was
-- built with. ScaleTo is absolute, so re-applying it to a model that
-- cycles wild -> carried -> wild never compounds. Pad models are
-- built fresh by GameState at the same scale (PLACED_SCALE); only
-- the longer label reach is wild-only.
local WILD_SCALE = 1.6

local function emphasizeWildModel(model)
	model:ScaleTo(WILD_SCALE)
	local label = model:FindFirstChild("BrainrotLabel")
	if label then
		label.Size = UDim2.fromOffset(320, 128)
		label.MaxDistance = 420
	end
end

-- The whole visibility contract for a brainrot model, enforced at
-- every entry point (wild spawn, wave re-wild, pad placement): the
-- root part is Anchored, so gravity can never take it, and it does
-- not collide, so physics can never shove it. Movement is PivotTo
-- only, which is exactly what an anchored assembly needs.
local function enforceRootAnchored(model)
	local root = model.PrimaryPart or model:FindFirstChild("Body")
	if root then
		root.Anchored = true
		root.CanCollide = false
	end
end

local function spawnWildBrainrot()
	local rarity = BrainrotData.RollRarityFromOdds(Config.WildRarityOdds)
	local character = BrainrotData.RandomCharacterOfRarity(rarity)
	local mutation = BrainrotData.RollMutation(Config.WildMutationOdds)
	local position = randomFieldPosition()
	-- A random yaw, not a lookAt: the two-vector CFrame.new form this
	-- used before is the one call in the startup path that a strict
	-- Luau runtime rejects outright, and it throws in Roblox too if
	-- the rolled direction ever degenerates. A yaw cannot degenerate.
	local facing = CFrame.new(position) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	local model = BrainrotFactory.BuildCharacter(character.Id, mutation, facing)
	if not model then
		return nil
	end
	emphasizeWildModel(model)
	enforceRootAnchored(model)
	-- Parent into the dedicated folder under Workspace (created in
	-- Start): the parent chain model -> WildBrainrots -> Workspace is
	-- what makes a wild brainrot render, and it is checkable at a
	-- glance in the Explorer and in the headless harness.
	model.Parent = wildFolder or Workspace
	local entry = {
		Id = character.Id,
		Mutation = mutation,
		Model = model,
		TargetPos = randomFieldPosition(),
		GroundY = position.Y,
		Speed = math.random(30, 50) / 10,
		Caught = false,
	}
	table.insert(wildBrainrots, entry)
	wildEntryByModel[model] = entry
	attachCatchPrompt(entry)
	wireTouchCatch(model)
	return entry
end
local function maintainWildPopulation()
	-- Prune entries whose models are gone (destroyed while listed)
	-- or have fallen out of the world (root below Y = -5: through
	-- the floor and on their way to FallenPartsDestroyHeight), so
	-- the top-up count below reflects brainrots actually alive and
	-- visible in the field. A model that merely lost its Parent is
	-- destroyed nowhere; a fallen one is destroyed here so its entry
	-- cannot be carried by the wander loop at the bottom of the map.
	for i = #wildBrainrots, 1, -1 do
		local entry = wildBrainrots[i]
		local model = entry.Model
		local lost = not model or not model.Parent
		local fallen = false
		if model and model.Parent then
			if model:GetPivot().Position.Y < -5 then
				fallen = true
			end
		end
		if lost or fallen then
			if model then
				wildEntryByModel[model] = nil
				if fallen then
					warn("Berburu Museng: wild brainrot fell out of the world, respawning it")
					model:Destroy()
				end
			end
			table.remove(wildBrainrots, i)
		end
	end
	while #wildBrainrots < Config.WildCount do
		if not spawnWildBrainrot() then
			break
		end
	end
end

-- Put a brainrot (already built) onto a player's carrying stack.
function CatchService.AddCarrying(player, id, mutation, model)
	local data = GameState.GetPlayerData(player)
	if not data then
		return false
	end
	if #data.Carrying >= GameState.GetCarryCapacity(player) then
		return false
	end
	table.insert(data.Carrying, { Id = id, Mutation = mutation, Model = model })
	return true
end

function CatchService.TryCatch(player, entry)
	if entry.Caught then
		return
	end
	local data = GameState.GetPlayerData(player)
	if not data then
		return
	end
	if #data.Carrying >= GameState.GetCarryCapacity(player) then
		return
	end
	entry.Caught = true
	removeWildEntry(entry)
	local prompt = entry.Model:FindFirstChild("CatchPrompt", true)
	if prompt then
		prompt:Destroy()
	end
	if not CatchService.AddCarrying(player, entry.Id, entry.Mutation, entry.Model) then
		-- Capacity filled between the check and the catch: put it back.
		entry.Caught = false
		table.insert(wildBrainrots, entry)
		attachCatchPrompt(entry)
		return
	end
	wildEntryByModel[entry.Model] = nil
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		fireEffect(player, "Catch", rootPart.Position)
	end
	EconomyService.SendState(player)
	task.spawn(function()
		task.wait(2)
		maintainWildPopulation()
	end)
end

-- A carried brainrot goes back to the wild (the wave knocked it loose).
local function respawnCarriedAsWild(entry)
	local position = randomFieldPosition()
	entry.Model:PivotTo(CFrame.new(position))
	-- A pad-born model arrives at pad scale with the small pad label;
	-- as a wild brainrot it gets the wild treatment (idempotent).
	emphasizeWildModel(entry.Model)
	enforceRootAnchored(entry.Model)
	entry.Model.Parent = wildFolder or Workspace
	local wildEntry = {
		Id = entry.Id,
		Mutation = entry.Mutation,
		Model = entry.Model,
		TargetPos = randomFieldPosition(),
		GroundY = position.Y,
		Speed = math.random(30, 50) / 10,
		Caught = false,
	}
	table.insert(wildBrainrots, wildEntry)
	wildEntryByModel[entry.Model] = wildEntry
	attachCatchPrompt(wildEntry)
	wireTouchCatch(entry.Model)
end

local function dropAllCarriedToWave(player)
	local data = GameState.GetPlayerData(player)
	if not data or #data.Carrying == 0 then
		return
	end
	local carried = data.Carrying
	data.Carrying = {}
	for _, entry in ipairs(carried) do
		respawnCarriedAsWild(entry)
	end
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		fireEffect(player, "WaveDrop", rootPart.Position)
	end
	EconomyService.SendState(player)
end

-- The wave physically hits a player caught in the open: thrown ahead
-- of the wall and tripped flat for a second, so the hit is felt even
-- with empty hands. (Carried brainrots are dropped separately by
-- dropAllCarriedToWave.) The player is never killed.
local function knockPlayerByWave(player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end
	-- The wall travels in +X, so it throws the player in +X and up.
	rootPart.AssemblyLinearVelocity = Vector3.new(34, 24, 0)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		task.delay(1, function()
			if player.Character == character and humanoid.Parent then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
	end
	fireEffect(player, "WaveHit", rootPart.Position)
end

local function depositCarriedAtBase(player)
	local data = GameState.GetPlayerData(player)
	if not data or #data.Carrying == 0 then
		return
	end
	local deposited = false
	while #data.Carrying > 0 do
		local freePad = GameState.GetFreePad(player)
		if not freePad then
			break
		end
		local entry = table.remove(data.Carrying, 1)
		if entry.Model then
			entry.Model:Destroy()
		end
		GameState.PlaceOnPad(player, freePad, entry.Id, entry.Mutation)
		deposited = true
	end
	if deposited then
		local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			fireEffect(player, "Deposit", rootPart.Position)
		end
		EconomyService.SendState(player)
	end
end

local function updateWildWander(dt)
	for _, entry in ipairs(wildBrainrots) do
		if not entry.Caught and entry.Model and entry.Model.Parent then
			local pivot = entry.Model:GetPivot()
			local pos = pivot.Position
			-- Wander is anchored to the entry's fixed ground height,
			-- NEVER to the model's current pivot Y. The old code aimed
			-- at (TargetPos.X, pos.Y, TargetPos.Z) and then ADDED the
			-- bob onto a pivot that already contained last frame's bob:
			-- the bob integrated frame over frame into an unbounded
			-- random walk, so pivots slowly sank through the floor
			-- (or floated metres up) and the watchdog kept reading
			-- genuine models as "fallen" and churning the whole
			-- population. With the ground height fixed, Y is always
			-- GroundY + bob, inside +/- 0.15 of the ground plane.
			local groundY = entry.GroundY or 0.15
			local flatPos = Vector3.new(pos.X, groundY, pos.Z)
			local target = Vector3.new(entry.TargetPos.X, groundY, entry.TargetPos.Z)
			local delta = target - flatPos
			local distance = delta.Magnitude
			if distance < 3 then
				entry.TargetPos = randomFieldPosition()
			else
				local step = math.min(distance, entry.Speed * dt)
				local newPos = flatPos + delta.Unit * step
				local bob = math.sin(os.clock() * 4 + newPos.X) * 0.15
				local facing = CFrame.lookAt(newPos, newPos + delta)
				entry.Model:PivotTo(facing + Vector3.new(0, bob, 0))
			end
		end
	end
end

local function updateCarriedFollows()
	local now = os.clock()
	for player, data in pairs(GameState.GetAllPlayerData()) do
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		if head then
			for i, entry in ipairs(data.Carrying) do
				if entry.Model and entry.Model.Parent then
					local bob = math.sin(now * 3 + i * 1.7) * 0.18
					local targetPos = head.Position + Vector3.new(0, 1.7 + (i - 1) * 1.5 + bob, 0)
					local facing = CFrame.lookAt(targetPos, targetPos + head.CFrame.LookVector)
					entry.Model:PivotTo(facing)
				end
			end
		end
	end
end

local function checkDeposits()
	for player, data in pairs(GameState.GetAllPlayerData()) do
		if #data.Carrying > 0 then
			local base = GameState.GetBaseForPlayer(player)
			local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if base and rootPart and WorldBuilder.IsInsideBase(base, rootPart.Position) then
				depositCarriedAtBase(player)
			end
		end
	end
end

local function runWaveCycle()
	local waveModel = world.WaveModel
	local field = Config.Field
	while true do
		task.wait(Config.WavePeriod - Config.WaveWarningTime)
		local warningRemote = findRemote("WaveWarning")
		if warningRemote then
			warningRemote:FireAllClients("Warning", Config.WaveWarningTime)
		end
		task.wait(Config.WaveWarningTime)
		if warningRemote then
			warningRemote:FireAllClients("Start", 0)
		end
		local startX = field.MinX - 30
		local endX = field.MaxX + 30
		local elapsed = 0
		-- One hit per player per crossing: the band check below runs
		-- every Heartbeat for nine seconds, and a player must be
		-- knocked once, not re-thrown every frame while the wall
		-- passes through them.
		local hitThisWave = {}
		while elapsed < Config.WaveCrossTime do
			local dt = RunService.Heartbeat:Wait()
			elapsed = elapsed + dt
			local alpha = math.min(1, elapsed / Config.WaveCrossTime)
			local x = startX + (endX - startX) * alpha
			waveModel:PivotTo(CFrame.new(x, 15, -70))
			for player, data in pairs(GameState.GetAllPlayerData()) do
				if not hitThisWave[player] then
					local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if rootPart and math.abs(rootPart.Position.X - x) < 9 then
						if not isSafeFromWave(rootPart.Position) then
							hitThisWave[player] = true
							-- EVERY unsafe player is hit, carrier or
							-- not: the old check skipped anyone with
							-- empty hands entirely, so standing in
							-- the open felt like nothing at all.
							knockPlayerByWave(player)
							if #data.Carrying > 0 then
								dropAllCarriedToWave(player)
							end
						end
					end
				end
			end
		end
		waveModel:PivotTo(CFrame.new(-260, -60, -70))
		if warningRemote then
			warningRemote:FireAllClients("End", 0)
		end
	end
end

function CatchService.Start(worldRefs)
	world = worldRefs
	-- Every wild model lives in this folder under Workspace: visible,
	-- explorable, and its population countable at a glance.
	local folder = Instance.new("Folder")
	folder.Name = "WildBrainrots"
	folder.Parent = Workspace
	wildFolder = folder
	maintainWildPopulation()
	warn("Berburu Museng: CatchService live, wild population = " .. #wildBrainrots)
	-- Periodic restock: whatever the field loses between catches and
	-- leavers (a model destroyed while listed, a drop path that did
	-- not re-register), the population is topped back up to WildCount
	-- within a few seconds instead of staying depleted.
	task.spawn(function()
		while true do
			task.wait(5)
			maintainWildPopulation()
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		updateWildWander(dt)
		updateCarriedFollows()
	end)
	task.spawn(function()
		while true do
			task.wait(0.3)
			checkDeposits()
		end
	end)
	task.spawn(runWaveCycle)
	Players.PlayerRemoving:Connect(function(player)
		touchDebounce[player] = nil
		-- Any wild-caught brainrots the leaver was carrying are
		-- destroyed with their player data, so restock the field;
		-- without this the wild population only ever refills after
		-- the next successful catch and can sit depleted for good.
		task.delay(1, maintainWildPopulation)
	end)
end

return CatchService
