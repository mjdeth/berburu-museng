-- Effects: client-only juice. Floating text for catches, deposits,
-- wave knock-looses and rebirths (driven by the server's EffectEvent),
-- "+$" floaters as your income accumulates, sparkle bursts, and foam
-- washing over the field while the tsunami crosses. Nothing here
-- touches game state; it only renders what the server reports.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local remotes = ReplicatedStorage:WaitForChild("BerburuMusengRemotes")
local effectEvent = remotes:WaitForChild("EffectEvent")
local cashUpdated = remotes:WaitForChild("CashUpdated")
local waveWarning = remotes:WaitForChild("WaveWarning")

local activeFloaters = {} -- { Part, Gui, Label, Life, MaxLife }
local activeSparks = {} -- { Part, Velocity, Life, MaxLife }
local activeFoam = {} -- { Part, Speed }
local waveActive = false
local foamSpawnTimer = 0

local function spawnFloater(text, worldPosition, color, textSize)
	local part = Instance.new("Part")
	part.Name = "FloaterAnchor"
	part.Size = Vector3.new(0.4, 0.4, 0.4)
	part.CFrame = CFrame.new(worldPosition)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Name = "FloaterGui"
	gui.Adornee = part
	gui.Size = UDim2.fromOffset(260, 44)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "FloaterText"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextSize = textSize or 22
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0.3
	label.Parent = gui

	table.insert(activeFloaters, { Part = part, Label = label, Life = 0, MaxLife = 1.3 })
end

local function spawnSparkleBurst(worldPosition, color, count)
	for i = 1, count do
		local part = Instance.new("Part")
		part.Name = "Sparkle"
		part.Size = Vector3.new(0.35, 0.35, 0.35)
		part.CFrame = CFrame.new(worldPosition)
		part.Color = color
		part.Material = Enum.Material.Neon
		part.Anchored = true
		part.CanCollide = false
		part.Parent = workspace
		local velocity = Vector3.new(
			(math.random() - 0.5) * 9,
			math.random(4, 9),
			(math.random() - 0.5) * 9
		)
		table.insert(activeSparks, { Part = part, Velocity = velocity, Life = 0, MaxLife = 0.7 })
	end
end

local function spawnFoam()
	local field = Config.Field
	local part = Instance.new("Part")
	part.Name = "WaveFoam"
	part.Size = Vector3.new(math.random(2, 5), 0.5, math.random(2, 5))
	part.CFrame = CFrame.new(
		math.random(field.MinX, field.MinX + 40),
		0.45,
		math.random(field.MinZ, field.MaxZ)
	)
	part.Color = Color3.fromRGB(235, 250, 255)
	part.Material = Enum.Material.Neon
	part.Transparency = 0.35
	part.Anchored = true
	part.CanCollide = false
	part.Parent = workspace
	table.insert(activeFoam, { Part = part, Speed = (field.MaxX - field.MinX + 60) / Config.WaveCrossTime })
end

local function ownHeadPosition()
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if head then
		return head.Position + Vector3.new(0, 2.2, 0)
	end
	return nil
end

effectEvent.OnClientEvent:Connect(function(kind, position)
	local at = position or ownHeadPosition()
	if kind == "Catch" and at then
		spawnFloater("CAUGHT!", at, Color3.fromRGB(255, 220, 110), 24)
		spawnSparkleBurst(at, Color3.fromRGB(255, 220, 110), 8)
	elseif kind == "Deposit" and at then
		spawnFloater("DEPOSITED!", at, Color3.fromRGB(140, 255, 150), 24)
		spawnSparkleBurst(at, Color3.fromRGB(140, 255, 150), 8)
	elseif kind == "WaveDrop" and at then
		spawnFloater("KNOCKED LOOSE BY THE WAVE!", at, Color3.fromRGB(255, 110, 100), 22)
		spawnSparkleBurst(at, Color3.fromRGB(90, 160, 255), 12)
	elseif kind == "WaveHit" and at then
		spawnFloater("SPLASHED BY THE TSUNAMI!", at, Color3.fromRGB(120, 200, 255), 24)
		spawnSparkleBurst(at, Color3.fromRGB(120, 200, 255), 14)
	elseif kind == "Rebirth" then
		local headPos = ownHeadPosition()
		if headPos then
			spawnFloater("REBIRTH!", headPos, Color3.fromRGB(255, 140, 230), 26)
			spawnSparkleBurst(headPos, Color3.fromRGB(255, 140, 230), 14)
		end
	end
end)

-- Income milestones: every $50 earned pools into one "+$" floater.
local pooledIncome = 0
local lastCash = nil
cashUpdated.OnClientEvent:Connect(function(cash, incomePerSecond)
	if lastCash ~= nil and cash > lastCash then
		pooledIncome = pooledIncome + (cash - lastCash)
	end
	lastCash = cash
	if pooledIncome >= 50 then
		local headPos = ownHeadPosition()
		if headPos then
			spawnFloater("+$" .. math.floor(pooledIncome), headPos, Color3.fromRGB(150, 255, 150), 20)
		end
		pooledIncome = 0
	end
end)

waveWarning.OnClientEvent:Connect(function(state, seconds)
	if state == "Start" then
		waveActive = true
	elseif state == "End" then
		waveActive = false
		for _, foam in ipairs(activeFoam) do
			foam.Part:Destroy()
		end
		activeFoam = {}
	end
end)

RunService.RenderStepped:Connect(function(dt)
	for i = #activeFloaters, 1, -1 do
		local floater = activeFloaters[i]
		floater.Life = floater.Life + dt
		local alpha = floater.Life / floater.MaxLife
		if alpha >= 1 then
			floater.Part:Destroy()
			table.remove(activeFloaters, i)
		else
			floater.Part.CFrame = floater.Part.CFrame + Vector3.new(0, dt * 2.6, 0)
			floater.Label.TextTransparency = alpha * alpha
		end
	end
	for i = #activeSparks, 1, -1 do
		local spark = activeSparks[i]
		spark.Life = spark.Life + dt
		if spark.Life >= spark.MaxLife then
			spark.Part:Destroy()
			table.remove(activeSparks, i)
		else
			spark.Velocity = spark.Velocity - Vector3.new(0, 22 * dt, 0)
			spark.Part.CFrame = spark.Part.CFrame + spark.Velocity * dt
			spark.Part.Transparency = spark.Life / spark.MaxLife
		end
	end
	if waveActive then
		foamSpawnTimer = foamSpawnTimer - dt
		if foamSpawnTimer <= 0 then
			foamSpawnTimer = 0.12
			spawnFoam()
			spawnFoam()
		end
		for i = #activeFoam, 1, -1 do
			local foam = activeFoam[i]
			foam.Part.CFrame = foam.Part.CFrame + Vector3.new(foam.Speed * dt, 0, 0)
			if foam.Part.Position.X > Config.Field.MaxX + 30 then
				foam.Part:Destroy()
				table.remove(activeFoam, i)
			end
		end
	end
end)
