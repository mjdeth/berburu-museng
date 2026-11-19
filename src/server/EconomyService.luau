-- EconomyService: the money. A 1-second income tick from placed
-- brainrots, egg purchases with hatch rolls, selling placed brainrots,
-- rebirths and speed/carry upgrades. Every purchase is validated here
-- on the server; clients and prompts only ask.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BrainrotData = require(Shared:WaitForChild("BrainrotData"))

local GameState = require(ServerScriptService:WaitForChild("GameState"))

local EconomyService = {}

local remotes = nil
local world = nil

-- Every Error string this service returns is shown to the player
-- verbatim (HUD message line, hatch popup), so they are all written
-- as player-facing text -- never internal reasons. A purchase that
-- lands before the player's state exists gets the loading line.
local LOADING_ERROR = "Still loading - one moment!"
local SHOP_HICCUP = "The shop hiccuped - try again"

local function getRemotes()
	if remotes then
		return remotes
	end
	remotes = ReplicatedStorage:WaitForChild("BerburuMusengRemotes")
	return remotes
end

-- Request-path remote lookup: FindFirstChild only, never WaitForChild.
-- A WaitForChild with no timeout inside a purchase handler (or in the
-- state push a handler triggers) yields the invoke forever if the
-- child is ever missing, and the player's click dies with no answer
-- and no error anywhere. FindFirstChild fails fast and visibly.
local function findRemote(name)
	local folder = ReplicatedStorage:FindFirstChild("BerburuMusengRemotes")
	if not folder then
		return nil
	end
	return folder:FindFirstChild(name)
end

local function fireCashUpdated(player)
	local data = GameState.GetPlayerData(player)
	if not data then
		return
	end
	local remote = findRemote("CashUpdated")
	if remote then
		remote:FireClient(player, data.Cash, GameState.GetIncomePerSecond(player))
	end
end

local function buildBasePayload(player)
	local data = GameState.GetPlayerData(player)
	if not data then
		return nil
	end
	local pads = {}
	for padIndex, entry in pairs(data.Pads) do
		local character = BrainrotData.GetCharacter(entry.Id)
		if character then
			table.insert(pads, {
				Pad = padIndex,
				Id = entry.Id,
				Name = character.Name,
				Rarity = character.Rarity,
				Mutation = entry.Mutation,
				Rate = BrainrotData.GetEffectiveRate(entry.Id, entry.Mutation) * GameState.GetIncomeMultiplier(player),
				SellPrice = math.floor(character.Price * Config.SellFraction),
			})
		end
	end
	table.sort(pads, function(a, b)
		return a.Pad < b.Pad
	end)
	return {
		Pads = pads,
		LockSeconds = math.ceil(GameState.GetLockSecondsLeft(player)),
		Rebirths = data.Rebirths,
		RebirthCost = GameState.GetRebirthCost(player),
		IncomeMultiplier = GameState.GetIncomeMultiplier(player),
		SpeedLevel = data.SpeedLevel,
		CarryLevel = data.CarryLevel,
		CarryCapacity = GameState.GetCarryCapacity(player),
		CarryingCount = #data.Carrying,
	}
end

-- Push the full HUD state (cash + base) to one player.
function EconomyService.SendState(player)
	fireCashUpdated(player)
	local payload = buildBasePayload(player)
	if payload then
		local remote = findRemote("BaseUpdated")
		if remote then
			remote:FireClient(player, payload)
		end
	end
end

-- Full state for the HUD's GetState pull: the base payload plus the
-- cash fields the CashUpdated event carries. The HUD invokes this on
-- start (with retries) so its first render never depends on winning
-- the race against the join-time event pushes below.
function EconomyService.GetState(player)
	local data = GameState.GetPlayerData(player)
	if not data then
		return { Error = LOADING_ERROR }
	end
	local payload = buildBasePayload(player)
	if not payload then
		return { Error = LOADING_ERROR }
	end
	payload.Cash = data.Cash
	payload.IncomePerSecond = GameState.GetIncomePerSecond(player)
	payload.BaseIndex = data.BaseIndex
	return payload
end

function EconomyService.OnPlayerJoined(player)
	-- Push immediately, and again at +3s: a RemoteEvent fired before
	-- the HUD has connected its listeners is gone for good, and a HUD
	-- that missed the join push used to sit on its $0 default until
	-- the first purchase happened to push again.
	EconomyService.SendState(player)
	task.delay(3, function()
		EconomyService.SendState(player)
	end)
end

local function rollHatch(eggIndex)
	local egg = BrainrotData.Eggs[eggIndex]
	local rarity = BrainrotData.RollRarityFromOdds(egg.Odds)
	local character = BrainrotData.RandomCharacterOfRarity(rarity)
	local mutation = BrainrotData.RollMutation(Config.HatchMutationOdds)
	return character, mutation
end

-- Buy and hatch an egg. Returns a result table for the client's reveal
-- animation, or { Error = ... } when the purchase is refused.
function EconomyService.BuyEgg(player, eggIndex)
	-- The checks are separate and ordered so the player hears the real
	-- reason: this used to be one combined guard that answered
	-- "Unknown egg" for a perfectly valid egg whenever the player's
	-- data was missing, masking the actual failure.
	local data = GameState.GetPlayerData(player)
	if not data then
		return { Error = LOADING_ERROR }
	end
	local egg = BrainrotData.Eggs[eggIndex]
	if not egg then
		return { Error = "That egg is not on the menu" }
	end
	if data.Cash < egg.Price then
		return { Error = "Not enough cash" }
	end
	-- Roll and BUILD first, charge last. This used to spend the cash
	-- up front and hatch afterwards: when the factory build threw on
	-- the live place, the player had paid $100 for an egg that never
	-- hatched and got nothing (the very next click then read "Not
	-- enough cash"). Now the hatchling must actually exist -- or the
	-- base-full sell price be fixed -- before a single dollar moves,
	-- and a failed build refuses the purchase with the cash intact.
	local character, mutation = rollHatch(eggIndex)
	if not character then
		return { Error = SHOP_HICCUP }
	end
	local freePad = GameState.GetFreePad(player)
	local sold = false
	local sellPrice = 0
	if freePad then
		if not GameState.PlaceOnPad(player, freePad, character.Id, mutation) then
			return { Error = SHOP_HICCUP }
		end
	else
		-- Base full: the hatchling is sold on the spot for half price.
		sellPrice = math.floor(character.Price * Config.SellFraction)
		sold = true
	end
	if not GameState.TrySpendCash(player, egg.Price) then
		-- Unreachable in practice (the balance was checked above and
		-- nothing in between yields), but if the spend ever did fail
		-- after a placement, undo the placement rather than hand out
		-- a free egg.
		if freePad then
			local _, placedModel = GameState.TakeFromPad(player, freePad)
			if placedModel then
				placedModel:Destroy()
			end
		end
		return { Error = "Not enough cash" }
	end
	if sold then
		GameState.AddCash(player, sellPrice)
	end
	EconomyService.SendState(player)
	return {
		Id = character.Id,
		Name = character.Name,
		Rarity = character.Rarity,
		Mutation = mutation,
		Sold = sold,
		SellPrice = sellPrice,
	}
end

function EconomyService.SellPad(player, padIndex)
	local data = GameState.GetPlayerData(player)
	if not data or not data.Pads[padIndex] then
		return { Error = "That pad is empty" }
	end
	-- The price is computed BEFORE anything leaves the pad: the
	-- credit must never depend on a lookup performed after the
	-- brainrot has already been removed.
	local character = BrainrotData.GetCharacter(data.Pads[padIndex].Id)
	local sellPrice = character and math.floor(character.Price * Config.SellFraction) or 0
	local entry, model = GameState.TakeFromPad(player, padIndex)
	if not entry then
		return { Error = "That pad is empty" }
	end
	if model then
		model:Destroy()
	end
	GameState.AddCash(player, sellPrice)
	EconomyService.SendState(player)
	return { Sold = true, SellPrice = sellPrice }
end

function EconomyService.DoRebirth(player)
	local data = GameState.GetPlayerData(player)
	if not data then
		return { Error = LOADING_ERROR }
	end
	local cost = GameState.GetRebirthCost(player)
	if data.Cash < cost then
		return { Error = "Rebirth needs $" .. cost }
	end
	-- Ordering audit (same pass as BuyEgg): the base is cleared
	-- BEFORE the cash reset and the rebirth increment below, so if
	-- clearing ever threw, the wrapInvoke pcall answers SHOP_HICCUP
	-- with the player's cash and rebirth count untouched -- the
	-- reset IS the charge, and it only lands after the effect.
	GameState.ClearBase(player)
	data.Cash = Config.StartingCash
	data.Rebirths = data.Rebirths + 1
	EconomyService.SendState(player)
	local effectRemote = findRemote("EffectEvent")
	if effectRemote then
		effectRemote:FireClient(player, "Rebirth", nil)
	end
	return { Rebirth = true, Rebirths = data.Rebirths, Multiplier = GameState.GetIncomeMultiplier(player) }
end

-- THE single place WalkSpeed is computed: BaseWalkSpeed + level *
-- SpeedPerLevel, written to the CURRENT character's Humanoid. Every
-- path that can change the effective speed goes through here -- the
-- Speed purchase (immediately, in the same call, so the upgrade is
-- felt the moment it is bought), CharacterAdded/respawn, and the
-- post-load re-apply in Main.
local function applySpeed(player)
	local data = GameState.GetPlayerData(player)
	if not data or not player.Character then
		return
	end
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Config.BaseWalkSpeed + data.SpeedLevel * Config.SpeedPerLevel
	end
end

function EconomyService.ApplySpeed(player)
	applySpeed(player)
end

function EconomyService.BuyUpgrade(player, kind)
	-- Ordering audit (same pass as BuyEgg): TrySpendCash is the
	-- atomic gate -- it deducts only when the balance covers the
	-- cost, and everything after it in each branch is an infallible
	-- table write plus a WalkSpeed re-apply, so money can never be
	-- taken without the level landing.
	local data = GameState.GetPlayerData(player)
	if not data then
		return { Error = LOADING_ERROR }
	end
	if kind == "Speed" then
		local level = data.SpeedLevel
		local cost = Config.SpeedUpgradeCosts[level + 1]
		if not cost then
			return { Error = "Speed is maxed out" }
		end
		if not GameState.TrySpendCash(player, cost) then
			return { Error = "Not enough cash" }
		end
		data.SpeedLevel = level + 1
		-- Applied immediately through the one shared ApplySpeed, so
		-- the new speed is live on the character the player is
		-- currently controlling -- not just after a respawn.
		EconomyService.ApplySpeed(player)
	elseif kind == "Carry" then
		local level = data.CarryLevel
		local cost = Config.CarryUpgradeCosts[level + 1]
		if not cost then
			return { Error = "Carry is maxed out" }
		end
		if not GameState.TrySpendCash(player, cost) then
			return { Error = "Not enough cash" }
		end
		data.CarryLevel = level + 1
	else
		return { Error = "That upgrade is not available" }
	end
	EconomyService.SendState(player)
	return { Upgraded = kind }
end

local function startIncomeTick()
	task.spawn(function()
		while true do
			task.wait(1)
			for player, data in pairs(GameState.GetAllPlayerData()) do
				local income = GameState.GetIncomePerSecond(player)
				if income > 0 then
					GameState.AddCash(player, income)
				end
				-- Push every second, income or not: this is the HUD's
				-- heartbeat. When the push was income-gated, a player
				-- with an empty base never received a single
				-- CashUpdated and the HUD showed its $0 default for
				-- the whole session.
				fireCashUpdated(player)
			end
		end
	end)
end

-- Every invoke handler runs its body behind pcall and ALWAYS returns
-- a result table. An uncaught error inside OnServerInvoke surfaces on
-- the client as a raised InvokeServer (which the HUD's click thread
-- used to swallow whole: the click simply did nothing), and a handler
-- that yields never answers at all. Wrapped, a failure becomes a
-- friendly Error table plus a warn trace naming the invoke.
local function describeResult(result)
	if type(result) ~= "table" then
		return "no result"
	end
	if result.Error then
		return "refused: " .. result.Error
	end
	if result.Name then
		return "hatched " .. result.Name
	end
	if result.Sold then
		return "sold"
	end
	if result.Rebirth then
		return "rebirthed"
	end
	if result.Upgraded then
		return "upgraded " .. result.Upgraded
	end
	return "ok"
end

-- (SHOP_HICCUP is declared with LOADING_ERROR at the top of this
-- file: BuyEgg needs it too, and a local declared down here would
-- not be in scope up there.)
local function wrapInvoke(name, body)
	return function(player, ...)
		local ok, result = pcall(body, player, ...)
		if not ok then
			warn("Berburu Museng: " .. name .. " errored for " .. player.Name .. ": " .. tostring(result))
			return { Error = SHOP_HICCUP }
		end
		if type(result) ~= "table" then
			warn("Berburu Museng: " .. name .. " returned no table for " .. player.Name)
			return { Error = SHOP_HICCUP }
		end
		warn("Berburu Museng: " .. name .. " for " .. player.Name .. " -> " .. describeResult(result))
		return result
	end
end

local function connectRemotes()
	local folder = getRemotes()
	folder:WaitForChild("BuyEggFunction").OnServerInvoke = wrapInvoke("BuyEgg", function(player, eggIndex)
		if type(eggIndex) ~= "number" then
			return { Error = "That egg is not on the menu" }
		end
		return EconomyService.BuyEgg(player, math.floor(eggIndex))
	end)
	folder:WaitForChild("SellPadFunction").OnServerInvoke = wrapInvoke("SellPad", function(player, padIndex)
		if type(padIndex) ~= "number" then
			return { Error = "That pad is empty" }
		end
		return EconomyService.SellPad(player, math.floor(padIndex))
	end)
	folder:WaitForChild("RebirthFunction").OnServerInvoke = wrapInvoke("Rebirth", function(player)
		return EconomyService.DoRebirth(player)
	end)
	folder:WaitForChild("BuyUpgradeFunction").OnServerInvoke = wrapInvoke("BuyUpgrade", function(player, kind)
		if kind ~= "Speed" and kind ~= "Carry" then
			return { Error = "That upgrade is not available" }
		end
		return EconomyService.BuyUpgrade(player, kind)
	end)
	folder:WaitForChild("GetStateFunction").OnServerInvoke = wrapInvoke("GetState", function(player)
		return EconomyService.GetState(player)
	end)
end

local function connectWorldPrompts()
	for _, stall in ipairs(world.EggStalls) do
		local eggIndex = stall.Index
		stall.Prompt.Triggered:Connect(function(player)
			local ok, err = pcall(EconomyService.BuyEgg, player, eggIndex)
			if not ok then
				warn("Berburu Museng: egg stall prompt errored for " .. player.Name .. ": " .. tostring(err))
			end
		end)
	end
	world.RebirthPrompt.Triggered:Connect(function(player)
		local ok, err = pcall(EconomyService.DoRebirth, player)
		if not ok then
			warn("Berburu Museng: rebirth prompt errored for " .. player.Name .. ": " .. tostring(err))
		end
	end)
	world.SpeedPrompt.Triggered:Connect(function(player)
		local ok, err = pcall(EconomyService.BuyUpgrade, player, "Speed")
		if not ok then
			warn("Berburu Museng: speed prompt errored for " .. player.Name .. ": " .. tostring(err))
		end
	end)
	world.CarryPrompt.Triggered:Connect(function(player)
		local ok, err = pcall(EconomyService.BuyUpgrade, player, "Carry")
		if not ok then
			warn("Berburu Museng: carry prompt errored for " .. player.Name .. ": " .. tostring(err))
		end
	end)
end

function EconomyService.Start(worldRefs)
	world = worldRefs
	connectRemotes()
	connectWorldPrompts()
	startIncomeTick()
	warn("Berburu Museng: EconomyService live (remotes connected, prompts wired, income tick running)")
end

return EconomyService
