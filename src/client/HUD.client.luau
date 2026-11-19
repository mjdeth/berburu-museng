-- HUD: the whole screen interface for Berburu Museng.
-- Cash and income top-right (clear of Roblox's top-left menu corner),
-- a wave warning banner top-centre, the shop panel (eggs, upgrades,
-- rebirth) on the right, the base panel with pad sell buttons and the
-- lock countdown bottom-left, and the hatch reveal popup in the centre.
-- The HUD only asks the server; every purchase is validated there.
--
-- Structure note: the remote connections and the GetState sync are
-- wired FIRST, before a single GuiObject is built, and they write
-- into a plain state cache. Rendering reads the cache. This ordering
-- is load-bearing: this script once died partway through UI
-- construction (one makeButton call passed its arguments shifted by
-- one, landing a string in the color slot), and because the state
-- wiring sat BELOW the construction, the HUD froze on its $0 default
-- for the whole session while the server held the player's real
-- cash. Wiring first + cache means a cosmetic failure can now cost
-- at most a widget, never the state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BrainrotData = require(Shared:WaitForChild("BrainrotData"))

local remotes = ReplicatedStorage:WaitForChild("BerburuMusengRemotes")
local buyEggFunction = remotes:WaitForChild("BuyEggFunction")
local sellPadFunction = remotes:WaitForChild("SellPadFunction")
local rebirthFunction = remotes:WaitForChild("RebirthFunction")
local buyUpgradeFunction = remotes:WaitForChild("BuyUpgradeFunction")
local getStateFunction = remotes:WaitForChild("GetStateFunction")
local cashUpdated = remotes:WaitForChild("CashUpdated")
local baseUpdated = remotes:WaitForChild("BaseUpdated")
local waveWarning = remotes:WaitForChild("WaveWarning")

local function formatMoney(amount)
	amount = math.floor(amount)
	if amount >= 1000000 then
		return string.format("$%.2fM", amount / 1000000)
	elseif amount >= 10000 then
		return string.format("$%.1fK", amount / 1000)
	else
		return "$" .. amount
	end
end

-- ------------------------------------------------------------------
-- State wiring FIRST: latest-state cache + remote connections +
-- GetState pull. Rendering (further down) is applied through
-- applyState, which stays nil until the UI exists.
-- ------------------------------------------------------------------

local latestCash = nil -- { Cash = ..., IncomePerSecond = ... }
local latestBase = nil -- base payload table
local latestWave = nil -- { State = ..., Seconds = ... }
local waveCountdownEnd = nil
local applyState = nil

local function requestApply()
	if applyState then
		applyState()
	end
end

cashUpdated.OnClientEvent:Connect(function(cash, incomePerSecond)
	latestCash = { Cash = cash, IncomePerSecond = incomePerSecond }
	requestApply()
end)

baseUpdated.OnClientEvent:Connect(function(payload)
	latestBase = payload
	requestApply()
end)

waveWarning.OnClientEvent:Connect(function(state, seconds)
	latestWave = { State = state, Seconds = seconds }
	if state == "Warning" then
		waveCountdownEnd = os.clock() + seconds
	else
		waveCountdownEnd = nil
	end
	requestApply()
end)

-- First state by pull, not by push: the join-time pushes can fire
-- before this script connects its listeners, and a missed RemoteEvent
-- is never replayed -- that race is exactly how the HUD used to sit
-- on its $0 / empty-base defaults for a whole session. Pull GetState
-- with retries until the server has state for us, then cache it.
task.spawn(function()
	for _ = 1, 5 do
		local ok, state = pcall(function()
			return getStateFunction:InvokeServer()
		end)
		if ok and type(state) == "table" and state.Cash ~= nil then
			latestCash = { Cash = state.Cash, IncomePerSecond = state.IncomePerSecond }
			latestBase = state
			requestApply()
			return
		end
		task.wait(1)
	end
end)

-- ------------------------------------------------------------------
-- UI construction. Every builder call below is cosmetic: if one
-- throws, the state wiring above is already live and keeps the HUD's
-- numbers honest. makeButton is pcall-guarded per call (see below).
-- ------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "BerburuMusengHUD"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function makeLabel(parent, name, size, position, anchor, text, textSize, color, font)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.AnchorPoint = anchor or Vector2.new(0, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextSize = textSize
	label.TextColor3 = color
	label.Font = font or Enum.Font.GothamBold
	label.TextStrokeTransparency = 0.5
	label.Parent = parent
	return label
end

local function makePanel(parent, name, size, position, anchor, color)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = anchor or Vector2.new(0, 0)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

local function buildButton(parent, name, size, position, text, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Text = text
	button.TextSize = 15
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	button.Parent = parent
	return button
end

-- Every button is built behind pcall. A bad argument (the shop
-- toggle once passed an extra anchor argument, shifting its text
-- into the color slot: "Color3 expected, got string") must cost one
-- button, never the script -- the unguarded version died on that
-- call and took every panel and render function below it with it.
local function makeButton(...)
	local ok, button = pcall(buildButton, ...)
	if not ok then
		warn("Berburu Museng HUD: a button failed to build: " .. tostring(button))
		return nil
	end
	return button
end

-- Cash readout, top-right.
local cashLabel = makeLabel(gui, "CashLabel", UDim2.new(0, 260, 0, 38), UDim2.new(1, -16, 0, 14),
	Vector2.new(1, 0), "$0", 30, Color3.fromRGB(150, 255, 150))
cashLabel.TextXAlignment = Enum.TextXAlignment.Right
local incomeLabel = makeLabel(gui, "IncomeLabel", UDim2.new(0, 260, 0, 24), UDim2.new(1, -16, 0, 52),
	Vector2.new(1, 0), "+$0/s", 17, Color3.fromRGB(220, 240, 255))
incomeLabel.TextXAlignment = Enum.TextXAlignment.Right

-- Wave warning banner, top-centre.
local waveBanner = makePanel(gui, "WaveBanner", UDim2.new(0, 460, 0, 54), UDim2.new(0.5, 0, 0, 16),
	Vector2.new(0.5, 0), Color3.fromRGB(200, 60, 50))
waveBanner.Visible = false
local waveLabel = makeLabel(waveBanner, "WaveLabel", UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0),
	Vector2.new(0, 0), "", 22, Color3.fromRGB(255, 255, 255))
waveLabel.TextXAlignment = Enum.TextXAlignment.Center

-- Transient message line under the banner.
local messageLabel = makeLabel(gui, "MessageLabel", UDim2.new(0, 520, 0, 26), UDim2.new(0.5, 0, 0, 78),
	Vector2.new(0.5, 0), "", 17, Color3.fromRGB(255, 235, 160))
messageLabel.TextXAlignment = Enum.TextXAlignment.Center
local messageToken = 0
local function showMessage(text, seconds)
	messageToken = messageToken + 1
	local token = messageToken
	messageLabel.Text = text
	task.spawn(function()
		task.wait(seconds or 3)
		if messageToken == token then
			messageLabel.Text = ""
		end
	end)
end

-- Shop panel, right side under the cash readout.
local shopPanel = makePanel(gui, "ShopPanel", UDim2.new(0, 252, 0, 348), UDim2.new(1, -16, 0, 92),
	Vector2.new(1, 0), Color3.fromRGB(30, 34, 48))
makeLabel(shopPanel, "ShopTitle", UDim2.new(1, -16, 0, 24), UDim2.new(0, 8, 0, 6),
	Vector2.new(0, 0), "EGG SHOP", 18, Color3.fromRGB(255, 255, 255))

local hatchBusy = false
local hatchPopup = makePanel(gui, "HatchPopup", UDim2.new(0, 360, 0, 170), UDim2.new(0.5, 0, 0.5, 0),
	Vector2.new(0.5, 0.5), Color3.fromRGB(24, 26, 40))
hatchPopup.Visible = false
local hatchTitle = makeLabel(hatchPopup, "HatchTitle", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 12),
	Vector2.new(0, 0), "HATCHING...", 20, Color3.fromRGB(255, 255, 255))
hatchTitle.TextXAlignment = Enum.TextXAlignment.Center
local hatchName = makeLabel(hatchPopup, "HatchName", UDim2.new(1, -20, 0, 44), UDim2.new(0, 10, 0, 52),
	Vector2.new(0, 0), "???", 28, Color3.fromRGB(255, 255, 255))
hatchName.TextXAlignment = Enum.TextXAlignment.Center
local hatchInfo = makeLabel(hatchPopup, "HatchInfo", UDim2.new(1, -20, 0, 26), UDim2.new(0, 10, 0, 104),
	Vector2.new(0, 0), "", 17, Color3.fromRGB(220, 240, 255))
hatchInfo.TextXAlignment = Enum.TextXAlignment.Center

local function runHatchReveal(result)
	hatchBusy = true
	hatchPopup.Visible = true
	hatchTitle.Text = "HATCHING..."
	hatchInfo.Text = ""
	local names = {}
	for _, character in ipairs(BrainrotData.Characters) do
		table.insert(names, character.Name)
	end
	local started = os.clock()
	while os.clock() - started < 1.2 do
		hatchName.Text = names[math.random(1, #names)]
		hatchName.TextColor3 = Color3.fromRGB(200, 200, 200)
		task.wait(0.08)
	end
	if result.Error then
		hatchTitle.Text = "NO LUCK"
		hatchName.Text = result.Error
		hatchName.TextColor3 = Color3.fromRGB(255, 120, 110)
		hatchInfo.Text = ""
	else
		local rarityData = BrainrotData.Rarities[result.Rarity]
		hatchTitle.Text = "YOU HATCHED"
		hatchName.Text = result.Name
		hatchName.TextColor3 = rarityData and rarityData.Color or Color3.fromRGB(255, 255, 255)
		local info = result.Rarity
		if result.Mutation and result.Mutation ~= "None" then
			info = result.Mutation .. " " .. info
		end
		if result.Sold then
			info = info .. " - base full, sold for " .. formatMoney(result.SellPrice)
		end
		hatchInfo.Text = info
	end
	task.wait(2.4)
	hatchPopup.Visible = false
	hatchBusy = false
end

local SHOP_SILENT = "The shop did not answer - try again"

local function buyEgg(eggIndex)
	if hatchBusy then
		return
	end
	hatchBusy = true -- set before the invoke so double-taps cannot queue
	-- Feedback FIRST, before any invoke: the popup used to appear
	-- only after the server answered, so a slow or lost invoke made
	-- the click look completely dead. A click now always shows the
	-- hatching state within the same frame.
	hatchPopup.Visible = true
	hatchTitle.Text = "HATCHING..."
	hatchName.Text = "..."
	hatchName.TextColor3 = Color3.fromRGB(200, 200, 200)
	hatchInfo.Text = ""
	local answered = false
	local timedOut = false
	task.spawn(function()
		local ok, result = pcall(function()
			return buyEggFunction:InvokeServer(eggIndex)
		end)
		answered = true
		if timedOut then
			-- The watchdog already closed the popup and freed the
			-- button; a late answer changes nothing on screen.
			return
		end
		if not ok or type(result) ~= "table" then
			hatchPopup.Visible = false
			hatchBusy = false
			showMessage(SHOP_SILENT)
			return
		end
		hatchBusy = false -- runHatchReveal owns the flag from here
		runHatchReveal(result)
	end)
	task.spawn(function()
		task.wait(6)
		if not answered then
			timedOut = true
			hatchPopup.Visible = false
			hatchBusy = false
			showMessage(SHOP_SILENT)
		end
	end)
end

for i, egg in ipairs(BrainrotData.Eggs) do
	local button = makeButton(shopPanel, "EggButton" .. i, UDim2.new(1, -16, 0, 34),
		UDim2.new(0, 8, 0, 36 + (i - 1) * 40), egg.Name .. "  " .. formatMoney(egg.Price),
		Color3.fromRGB(90, 70, 140))
	local eggIndex = i
	if button then
		button.MouseButton1Click:Connect(function()
			task.spawn(function()
				buyEgg(eggIndex)
			end)
		end)
	end
end

makeLabel(shopPanel, "UpgradeTitle", UDim2.new(1, -16, 0, 24), UDim2.new(0, 8, 0, 162),
	Vector2.new(0, 0), "UPGRADES", 18, Color3.fromRGB(255, 255, 255))

local upgradeBusy = false
local function buyUpgrade(kind)
	if upgradeBusy then
		return
	end
	upgradeBusy = true
	local ok, result = pcall(function()
		return buyUpgradeFunction:InvokeServer(kind)
	end)
	upgradeBusy = false
	if not ok or type(result) ~= "table" then
		showMessage(SHOP_SILENT)
		return
	end
	if result.Error then
		showMessage(result.Error)
	else
		showMessage(kind .. " upgraded!")
	end
end

local speedButton = makeButton(shopPanel, "SpeedButton", UDim2.new(1, -16, 0, 34),
	UDim2.new(0, 8, 0, 190), "Speed +8", Color3.fromRGB(50, 110, 180))
if speedButton then
	speedButton.MouseButton1Click:Connect(function()
		task.spawn(function()
			buyUpgrade("Speed")
		end)
	end)
end
local carryButton = makeButton(shopPanel, "CarryButton", UDim2.new(1, -16, 0, 34),
	UDim2.new(0, 8, 0, 230), "Carry +1", Color3.fromRGB(190, 110, 50))
if carryButton then
	carryButton.MouseButton1Click:Connect(function()
		task.spawn(function()
			buyUpgrade("Carry")
		end)
	end)
end

local rebirthButton = makeButton(shopPanel, "RebirthButton", UDim2.new(1, -16, 0, 40),
	UDim2.new(0, 8, 0, 282), "REBIRTH", Color3.fromRGB(170, 60, 140))
if rebirthButton then
	rebirthButton.MouseButton1Click:Connect(function()
		task.spawn(function()
			if upgradeBusy then
				return
			end
			upgradeBusy = true
			local ok, result = pcall(function()
				return rebirthFunction:InvokeServer()
			end)
			upgradeBusy = false
			if not ok or type(result) ~= "table" then
				showMessage(SHOP_SILENT)
			elseif result.Error then
				showMessage(result.Error)
			else
				showMessage("Rebirthed! Income is now x" .. result.Multiplier)
			end
		end)
	end)
end

-- NOTE: makeButton takes (parent, name, size, position, text,
-- color) -- no anchor argument. This call once passed a stray
-- Vector2 anchor as the fifth argument (copied from a makeLabel
-- call), shifting "Hide shop" into the color slot; the assignment
-- button.BackgroundColor3 = "Hide shop" threw, and because the
-- script died here, everything below (base panel, renders, state
-- wiring) never ran. The anchor is set explicitly on the next line,
-- where it always belonged.
local shopToggle = makeButton(gui, "ShopToggle", UDim2.new(0, 84, 0, 28), UDim2.new(1, -268, 0, 92),
	"Hide shop", Color3.fromRGB(60, 64, 80))
if shopToggle then
	shopToggle.AnchorPoint = Vector2.new(1, 0)
	shopToggle.Position = UDim2.new(1, -284, 0, 92)
	shopToggle.MouseButton1Click:Connect(function()
		shopPanel.Visible = not shopPanel.Visible
		shopToggle.Text = shopPanel.Visible and "Hide shop" or "Show shop"
	end)
end

-- Base panel, bottom-left: lock state, carrying, pad list with sell buttons.
local basePanel = makePanel(gui, "BasePanel", UDim2.new(0, 300, 0, 240), UDim2.new(0, 16, 1, -16),
	Vector2.new(0, 1), Color3.fromRGB(30, 34, 48))
makeLabel(basePanel, "BaseTitle", UDim2.new(1, -16, 0, 24), UDim2.new(0, 8, 0, 6),
	Vector2.new(0, 0), "YOUR BASE", 18, Color3.fromRGB(255, 255, 255))
local lockLabel = makeLabel(basePanel, "LockLabel", UDim2.new(1, -16, 0, 22), UDim2.new(0, 8, 0, 32),
	Vector2.new(0, 0), "Base unlocked - steal risk!", 14, Color3.fromRGB(255, 180, 120))
local carryingLabel = makeLabel(basePanel, "CarryingLabel", UDim2.new(1, -16, 0, 22), UDim2.new(0, 8, 0, 54),
	Vector2.new(0, 0), "Carrying 0/1", 14, Color3.fromRGB(220, 240, 255))
local padList = Instance.new("Frame")
padList.Name = "PadList"
padList.Size = UDim2.new(1, -16, 0, 150)
padList.Position = UDim2.new(0, 8, 0, 80)
padList.BackgroundTransparency = 1
padList.Parent = basePanel
local padLayout = Instance.new("UIListLayout")
padLayout.FillDirection = Enum.FillDirection.Vertical
padLayout.SortOrder = Enum.SortOrder.LayoutOrder
padLayout.Padding = UDim.new(0, 3)
padLayout.Parent = padList

local sellBusy = false
local function rebuildPadList(pads)
	for _, child in ipairs(padList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, pad in ipairs(pads) do
		local row = Instance.new("Frame")
		row.Name = "PadRow" .. pad.Pad
		row.LayoutOrder = pad.Pad
		row.Size = UDim2.new(1, 0, 0, 24)
		row.BackgroundTransparency = 1
		row.Parent = padList
		local text = pad.Name .. "  " .. formatMoney(pad.Rate) .. "/s"
		if pad.Mutation ~= "None" then
			text = pad.Mutation .. " " .. text
		end
		local label = makeLabel(row, "PadLabel", UDim2.new(1, -64, 1, 0), UDim2.new(0, 0, 0, 0),
			Vector2.new(0, 0), text, 13, Color3.fromRGB(235, 240, 255))
		label.TextXAlignment = Enum.TextXAlignment.Left
		local sellButton = makeButton(row, "SellButton", UDim2.new(0, 58, 0, 22), UDim2.new(1, 0, 0, 1),
			"Sell", Color3.fromRGB(150, 60, 60))
		if sellButton then
			sellButton.AnchorPoint = Vector2.new(1, 0)
			sellButton.TextSize = 12
			local padIndex = pad.Pad
			sellButton.MouseButton1Click:Connect(function()
				if sellBusy then
					return
				end
				sellBusy = true
				local ok, result = pcall(function()
					return sellPadFunction:InvokeServer(padIndex)
				end)
				sellBusy = false
				if not ok or type(result) ~= "table" then
					showMessage(SHOP_SILENT)
				elseif result.Error then
					showMessage(result.Error)
				else
					showMessage("Sold for " .. formatMoney(result.SellPrice))
				end
			end)
		end
	end
	if #pads == 0 then
		makeLabel(padList, "EmptyLabel", UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 0, 0),
			Vector2.new(0, 0), "No brainrots placed yet", 13, Color3.fromRGB(170, 180, 200))
	end
end

-- ------------------------------------------------------------------
-- Rendering: reads ONLY the state cache filled at the top of this
-- file. applyState is installed now that every widget it touches
-- exists, then run once to paint whatever arrived during
-- construction.
-- ------------------------------------------------------------------

local function renderCash(cash, incomePerSecond)
	cashLabel.Text = formatMoney(cash)
	incomeLabel.Text = "+" .. formatMoney(incomePerSecond) .. "/s"
end

local function renderBase(payload)
	rebuildPadList(payload.Pads)
	if payload.LockSeconds > 0 then
		lockLabel.Text = "LOCKED: " .. payload.LockSeconds .. "s of force-field"
		lockLabel.TextColor3 = Color3.fromRGB(140, 230, 255)
	else
		lockLabel.Text = "Base unlocked - steal risk!"
		lockLabel.TextColor3 = Color3.fromRGB(255, 180, 120)
	end
	carryingLabel.Text = "Carrying " .. payload.CarryingCount .. "/" .. payload.CarryCapacity
		.. " - base holds " .. #payload.Pads .. "/" .. Config.PadsPerBase
	if speedButton then
		local speedCost = Config.SpeedUpgradeCosts[payload.SpeedLevel + 1]
		speedButton.Text = speedCost and ("Speed +8  " .. formatMoney(speedCost)) or "Speed MAXED"
	end
	if carryButton then
		local carryCost = Config.CarryUpgradeCosts[payload.CarryLevel + 1]
		carryButton.Text = carryCost and ("Carry +1  " .. formatMoney(carryCost)) or "Carry MAXED"
	end
	if rebirthButton then
		rebirthButton.Text = "REBIRTH x" .. (payload.IncomeMultiplier * 2) .. "  " .. formatMoney(payload.RebirthCost)
	end
end

local function renderWave(wave)
	if wave.State == "Warning" then
		waveBanner.Visible = true
		waveBanner.BackgroundColor3 = Color3.fromRGB(200, 60, 50)
	elseif wave.State == "Start" then
		waveBanner.Visible = true
		waveBanner.BackgroundColor3 = Color3.fromRGB(40, 110, 220)
		waveLabel.Text = "TSUNAMI! Get to a base or high ground!"
	elseif wave.State == "End" then
		waveBanner.Visible = false
	end
end

applyState = function()
	if latestCash then
		renderCash(latestCash.Cash, latestCash.IncomePerSecond)
	end
	if latestBase then
		renderBase(latestBase)
	end
	if latestWave then
		renderWave(latestWave)
	end
end
applyState()

-- Wave countdown ticker.
task.spawn(function()
	while true do
		task.wait(0.25)
		if waveCountdownEnd then
			local left = math.ceil(waveCountdownEnd - os.clock())
			if left > 0 then
				waveLabel.Text = "TSUNAMI IN " .. left .. "s - dash home with your catch!"
			end
		end
	end
end)
