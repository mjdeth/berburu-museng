-- WorldBuilder: builds the whole island procedurally at runtime --
-- ground, plaza, shop stalls, the street of 8 bases with pads, the wild
-- field with its high-ground mesa, decorations, signs and the wave wall.
-- Returns references every other service works against.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BrainrotData = require(Shared:WaitForChild("BrainrotData"))

local WorldBuilder = {}

local function makePart(parent, name, size, cframe, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function makeCylinder(parent, name, height, diameter, cframe, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, diameter, diameter)
	part.CFrame = cframe * CFrame.Angles(0, 0, math.rad(90))
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function makeBillboardLabel(parent, adornee, size, offset, lines)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(size.X, size.Y)
	gui.StudsOffset = offset
	gui.AlwaysOnTop = true
	gui.MaxDistance = 220
	gui.LightInfluence = 0
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = gui
	for i, line in ipairs(lines) do
		local label = Instance.new("TextLabel")
		label.Name = "Line" .. i
		label.LayoutOrder = i
		label.Size = UDim2.new(1, 0, 0, line.Height or 24)
		label.BackgroundTransparency = 1
		label.Text = line.Text
		label.TextColor3 = line.Color
		label.TextSize = line.Size or 20
		label.Font = line.Font or Enum.Font.GothamBold
		label.TextStrokeTransparency = 0.35
		label.Parent = gui
	end
	gui.Parent = parent
	return gui
end

local function buildGround(worldFolder)
	-- Island base and lawn.
	makePart(worldFolder, "IslandBase", Vector3.new(576, 10, 496), CFrame.new(0, -5.05, 10),
		Color3.fromRGB(194, 172, 125), Enum.Material.Sand)
	makePart(worldFolder, "Lawn", Vector3.new(560, 2, 480), CFrame.new(0, -1, 10),
		Color3.fromRGB(105, 190, 90), Enum.Material.Grass)
	-- Ocean plane around the island.
	local ocean = makePart(worldFolder, "Ocean", Vector3.new(1400, 2, 1400), CFrame.new(0, -3.2, 10),
		Color3.fromRGB(40, 110, 200), Enum.Material.Glass)
	ocean.Transparency = 0.25
	-- Wild field overlay (brighter, worn grass).
	local field = Config.Field
	makePart(worldFolder, "FieldFloor", Vector3.new(field.MaxX - field.MinX, 0.2, field.MaxZ - field.MinZ),
		CFrame.new((field.MinX + field.MaxX) / 2, 0.05, (field.MinZ + field.MaxZ) / 2),
		Color3.fromRGB(130, 205, 105), Enum.Material.Grass)
	-- Plaza disc.
	makeCylinder(worldFolder, "Plaza", 0.6, 92, CFrame.new(0, 0.3, 80),
		Color3.fromRGB(215, 200, 170), Enum.Material.Sandstone)
end

local function buildMesa(worldFolder)
	-- High ground inside the field: the wave-safe mesa, with steps up.
	local mesa = makePart(worldFolder, "Mesa", Vector3.new(60, 14, 50), CFrame.new(110, 7, -120),
		Color3.fromRGB(178, 140, 95), Enum.Material.Rock)
	makePart(worldFolder, "MesaTop", Vector3.new(62, 1, 52), CFrame.new(110, 14.2, -120),
		Color3.fromRGB(120, 200, 100), Enum.Material.Grass)
	local stepTops = { 3.5, 7, 10.5 }
	local stepZ = { -80, -86, -92 }
	for i = 1, 3 do
		local top = stepTops[i]
		makePart(worldFolder, "MesaStep" .. i, Vector3.new(30, top, 6), CFrame.new(110, top / 2, stepZ[i]),
			Color3.fromRGB(178, 140, 95), Enum.Material.Rock)
	end
	local signPost = makePart(worldFolder, "MesaSignPost", Vector3.new(0.6, 7, 0.6), CFrame.new(110, 17.5, -120),
		Color3.fromRGB(120, 85, 50), Enum.Material.Wood)
	makeBillboardLabel(worldFolder, signPost, Vector2.new(260, 60), Vector3.new(0, 3, 0), {
		{ Text = "HIGH GROUND", Color = Color3.fromRGB(255, 255, 255), Size = 24 },
		{ Text = "safe from the tsunami", Color = Color3.fromRGB(200, 235, 255), Size = 16, Height = 20 },
	})
	return mesa
end

local function buildDecorations(worldFolder)
	math.randomseed(20261118)
	local field = Config.Field
	-- Trees scattered over the field, kept off the mesa.
	for i = 1, 26 do
		local x = math.random(field.MinX + 12, field.MaxX - 12)
		local z = math.random(field.MinZ + 12, field.MaxZ - 12)
		if math.abs(x - 110) < 42 and math.abs(z + 120) < 38 then
			x = x - 90
		end
		local tree = Instance.new("Model")
		tree.Name = "Tree"
		tree.Parent = worldFolder
		makeCylinder(tree, "Trunk", 5, 1.3, CFrame.new(x, 2.5, z), Color3.fromRGB(120, 85, 50), Enum.Material.Wood)
		local leaves = Instance.new("Part")
		leaves.Name = "Leaves"
		leaves.Shape = Enum.PartType.Ball
		leaves.Size = Vector3.new(6, 5, 6)
		leaves.CFrame = CFrame.new(x, 7, z)
		leaves.Color = Color3.fromRGB(70, 160, 70)
		leaves.Material = Enum.Material.Grass
		leaves.Anchored = true
		leaves.Parent = tree
		local leavesTop = leaves:Clone()
		leavesTop.Size = Vector3.new(4, 3.4, 4)
		leavesTop.CFrame = CFrame.new(x + 1, 9.4, z)
		leavesTop.Parent = tree
	end
	-- Rocks.
	for i = 1, 10 do
		local x = math.random(field.MinX + 10, field.MaxX - 10)
		local z = math.random(field.MinZ + 10, field.MaxZ - 10)
		local rock = Instance.new("Part")
		rock.Name = "Rock"
		rock.Shape = Enum.PartType.Ball
		rock.Size = Vector3.new(math.random(2, 4), math.random(1, 2), math.random(2, 4))
		rock.CFrame = CFrame.new(x, 0.5, z)
		rock.Color = Color3.fromRGB(140, 140, 145)
		rock.Material = Enum.Material.Rock
		rock.Anchored = true
		rock.Parent = worldFolder
	end
	-- Field warning signs along the south edge of the field.
	for _, x in ipairs({ -90, 90 }) do
		local post = makePart(worldFolder, "WarningPost", Vector3.new(0.6, 6, 0.6), CFrame.new(x, 3, 26),
			Color3.fromRGB(120, 85, 50), Enum.Material.Wood)
		makeBillboardLabel(worldFolder, post, Vector2.new(320, 66), Vector3.new(0, 2.6, 0), {
			{ Text = "TSUNAMI FIELD", Color = Color3.fromRGB(255, 90, 70), Size = 26 },
			{ Text = "catch, then dash home before the wave!", Color = Color3.fromRGB(255, 255, 255), Size = 15, Height = 20 },
		})
	end
end

local function buildPlazaAndShops(worldFolder)
	-- Spawn pad in the plaza.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "IslandSpawn"
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(0, 0.8, 108)
	spawn.Color = Color3.fromRGB(120, 200, 255)
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.4
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Parent = worldFolder

	-- Rebirth statue: a golden museng on a pedestal at the plaza centre.
	local pedestal = makePart(worldFolder, "RebirthPedestal", Vector3.new(7, 2.4, 7), CFrame.new(0, 1.8, 80),
		Color3.fromRGB(150, 130, 90), Enum.Material.Marble)
	local statueBody = makePart(worldFolder, "StatueBody", Vector3.new(3, 2.8, 2.8), CFrame.new(0, 4.4, 80),
		Color3.fromRGB(255, 205, 60), Enum.Material.Metal)
	local statueHead = Instance.new("Part")
	statueHead.Name = "StatueHead"
	statueHead.Shape = Enum.PartType.Ball
	statueHead.Size = Vector3.new(2, 2, 2)
	statueHead.CFrame = CFrame.new(0, 6.8, 80)
	statueHead.Color = Color3.fromRGB(255, 205, 60)
	statueHead.Material = Enum.Material.Metal
	statueHead.Anchored = true
	statueHead.Parent = worldFolder
	for _, dx in ipairs({ -0.8, 0.8 }) do
		makePart(worldFolder, "StatueEar", Vector3.new(0.5, 1.1, 0.3), CFrame.new(dx, 8, 80),
			Color3.fromRGB(255, 205, 60), Enum.Material.Metal)
	end
	local rebirthPrompt = Instance.new("ProximityPrompt")
	rebirthPrompt.Name = "RebirthPrompt"
	rebirthPrompt.ActionText = "Rebirth"
	rebirthPrompt.ObjectText = "x2 income forever - resets cash and base"
	rebirthPrompt.HoldDuration = 1
	rebirthPrompt.MaxActivationDistance = 14
	rebirthPrompt.Parent = pedestal
	makeBillboardLabel(worldFolder, statueHead, Vector2.new(300, 66), Vector3.new(0, 3.4, 0), {
		{ Text = "REBIRTH STATUE", Color = Color3.fromRGB(255, 225, 130), Size = 24 },
		{ Text = "reset for a permanent x2 income", Color = Color3.fromRGB(255, 255, 255), Size = 15, Height = 20 },
	})

	-- Egg shop: three stalls west of the plaza.
	local eggStalls = {}
	for i, egg in ipairs(BrainrotData.Eggs) do
		local x = -128 + (i - 1) * 30
		local z = 80
		local stall = Instance.new("Model")
		stall.Name = "EggStall" .. i
		stall.Parent = worldFolder
		makePart(stall, "Table", Vector3.new(12, 3, 7), CFrame.new(x, 1.5, z),
			Color3.fromRGB(140, 100, 65), Enum.Material.Wood)
		for _, dx in ipairs({ -5.5, 5.5 }) do
			makePart(stall, "Post", Vector3.new(0.7, 9, 0.7), CFrame.new(x + dx, 4.5, z - 3),
				Color3.fromRGB(120, 85, 50), Enum.Material.Wood)
		end
		local roof = makePart(stall, "Roof", Vector3.new(14, 0.6, 9), CFrame.new(x, 9.2, z),
			egg.Color, Enum.Material.SmoothPlastic)
		local eggPart = Instance.new("Part")
		eggPart.Name = "Egg"
		eggPart.Shape = Enum.PartType.Ball
		eggPart.Size = Vector3.new(3.4, 4.4, 3.4)
		eggPart.CFrame = CFrame.new(x, 5.4, z)
		eggPart.Color = egg.Color
		eggPart.Material = Enum.Material.SmoothPlastic
		eggPart.Anchored = true
		eggPart.Parent = stall
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BuyEggPrompt"
		prompt.ActionText = "Hatch"
		prompt.ObjectText = egg.Name .. " - $" .. egg.Price
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 12
		prompt.Parent = eggPart
		-- Each stall's label sits at its own height and a smaller size:
		-- BillboardGui labels render at a constant screen size, so at
		-- one shared height the three 280px labels merged into a single
		-- overlapping strip when seen from the plaza.
		makeBillboardLabel(stall, roof, Vector2.new(215, 56), Vector3.new(0, 2.2 + (i - 1) * 2.3, 0), {
			{ Text = egg.Name, Color = Color3.fromRGB(255, 255, 255), Size = 19 },
			{ Text = "$" .. egg.Price, Color = Color3.fromRGB(150, 255, 150), Size = 16, Height = 20 },
		})
		eggStalls[i] = { EggPart = eggPart, Prompt = prompt, Index = i }
	end

	-- Upgrade stall south-west of the plaza: speed and carry pedestals.
	local upgradeFolder = Instance.new("Folder")
	upgradeFolder.Name = "UpgradeStall"
	upgradeFolder.Parent = worldFolder
	local speedPedestal = makePart(upgradeFolder, "SpeedPedestal", Vector3.new(4, 3.4, 4), CFrame.new(-52, 1.7, 132),
		Color3.fromRGB(80, 170, 255), Enum.Material.Neon)
	local speedPrompt = Instance.new("ProximityPrompt")
	speedPrompt.Name = "BuySpeedPrompt"
	speedPrompt.ActionText = "Buy Speed"
	speedPrompt.ObjectText = "+4 walk speed"
	speedPrompt.HoldDuration = 0.4
	speedPrompt.MaxActivationDistance = 12
	speedPrompt.Parent = speedPedestal
	local carryPedestal = makePart(upgradeFolder, "CarryPedestal", Vector3.new(4, 3.4, 4), CFrame.new(-38, 1.7, 132),
		Color3.fromRGB(255, 150, 80), Enum.Material.Neon)
	local carryPrompt = Instance.new("ProximityPrompt")
	carryPrompt.Name = "BuyCarryPrompt"
	carryPrompt.ActionText = "Buy Carry"
	carryPrompt.ObjectText = "carry one more brainrot"
	carryPrompt.HoldDuration = 0.4
	carryPrompt.MaxActivationDistance = 12
	carryPrompt.Parent = carryPedestal
	makeBillboardLabel(upgradeFolder, speedPedestal, Vector2.new(300, 60), Vector3.new(0, 3.6, 0), {
		{ Text = "UPGRADES", Color = Color3.fromRGB(255, 255, 255), Size = 24 },
		{ Text = "speed boots and bigger arms", Color = Color3.fromRGB(210, 235, 255), Size = 15, Height = 20 },
	})

	return spawn, rebirthPrompt, eggStalls, speedPrompt, carryPrompt
end

local function buildBase(worldFolder, index, centerX, centerZ)
	local baseFolder = Instance.new("Folder")
	baseFolder.Name = "Base" .. index
	baseFolder.Parent = worldFolder

	local plotColor = Color3.fromHSV((index - 1) / Config.BaseCount, 0.35, 0.95)
	local plot = makePart(baseFolder, "Plot", Vector3.new(48, 1, 38), CFrame.new(centerX, 0, centerZ),
		plotColor, Enum.Material.SmoothPlastic)
	plot.TopSurface = Enum.SurfaceType.Smooth

	-- Display pads: two rows of five.
	local pads = {}
	local padPositions = {}
	for row = 0, 1 do
		for col = 0, 4 do
			local padIndex = row * 5 + col + 1
			local px = centerX - 16 + col * 8
			local pz = centerZ - 9 + row * 18
			local pad = makeCylinder(baseFolder, "Pad" .. padIndex, 0.5, 4.6, CFrame.new(px, 0.75, pz),
				Color3.fromRGB(70, 70, 85), Enum.Material.Neon)
			pads[padIndex] = pad
			padPositions[padIndex] = Vector3.new(px, 1.0, pz)
		end
	end

	-- Fences: back and side walls, front split by an entrance gap.
	local wallColor = Color3.fromRGB(150, 115, 75)
	makePart(baseFolder, "FenceBack", Vector3.new(48, 3, 1), CFrame.new(centerX, 2, centerZ - 18.5),
		wallColor, Enum.Material.Wood)
	makePart(baseFolder, "FenceLeft", Vector3.new(1, 3, 38), CFrame.new(centerX - 23.5, 2, centerZ),
		wallColor, Enum.Material.Wood)
	makePart(baseFolder, "FenceRight", Vector3.new(1, 3, 38), CFrame.new(centerX + 23.5, 2, centerZ),
		wallColor, Enum.Material.Wood)
	makePart(baseFolder, "FenceFrontLeft", Vector3.new(19, 3, 1), CFrame.new(centerX - 14.5, 2, centerZ + 18.5),
		wallColor, Enum.Material.Wood)
	makePart(baseFolder, "FenceFrontRight", Vector3.new(19, 3, 1), CFrame.new(centerX + 14.5, 2, centerZ + 18.5),
		wallColor, Enum.Material.Wood)

	-- Lock force-field: four walls, invisible until the base is locked.
	local forceFieldParts = {}
	local ffColor = Color3.fromRGB(90, 220, 255)
	local function forceFieldWall(name, size, cframe)
		local wall = makePart(baseFolder, name, size, cframe, ffColor, Enum.Material.ForceField)
		wall.Transparency = 1
		wall.CanCollide = false
		table.insert(forceFieldParts, wall)
		return wall
	end
	forceFieldWall("FieldBack", Vector3.new(48, 9, 0.6), CFrame.new(centerX, 5, centerZ - 18.5))
	forceFieldWall("FieldFront", Vector3.new(48, 9, 0.6), CFrame.new(centerX, 5, centerZ + 18.5))
	forceFieldWall("FieldLeft", Vector3.new(0.6, 9, 38), CFrame.new(centerX - 23.5, 5, centerZ))
	forceFieldWall("FieldRight", Vector3.new(0.6, 9, 38), CFrame.new(centerX + 23.5, 5, centerZ))

	-- Lock pedestal in the entrance gap.
	local lockPedestal = makePart(baseFolder, "LockPedestal", Vector3.new(2.6, 3.6, 2.6),
		CFrame.new(centerX + 7, 2.3, centerZ + 17), Color3.fromRGB(90, 220, 255), Enum.Material.Neon)
	local lockPrompt = Instance.new("ProximityPrompt")
	lockPrompt.Name = "LockPrompt"
	lockPrompt.ActionText = "Lock Base"
	lockPrompt.ObjectText = "60 seconds of force-field"
	lockPrompt.HoldDuration = 0.5
	lockPrompt.MaxActivationDistance = 12
	lockPrompt.Parent = lockPedestal

	-- Owner sign at the front-left corner. The label height alternates
	-- by base index: BillboardGui labels render at a constant screen
	-- size and always on top, so eight identical signs at one height
	-- merged into a single overlapping strip when the owner looked
	-- down the row of bases. A 1.6-stud stagger separates neighbours.
	local signPost = makePart(baseFolder, "SignPost", Vector3.new(0.6, 7, 0.6),
		CFrame.new(centerX - 21, 3.5, centerZ + 18), Color3.fromRGB(120, 85, 50), Enum.Material.Wood)
	local signGui = makeBillboardLabel(baseFolder, signPost, Vector2.new(300, 66),
		Vector3.new(0, 3.2 + (index % 2) * 1.6, 0), {
		{ Text = "EMPTY BASE", Color = Color3.fromRGB(255, 255, 255), Size = 24 },
		{ Text = "deposit brainrots here", Color = Color3.fromRGB(220, 240, 255), Size = 15, Height = 20 },
	})
	local signLabel = signGui:FindFirstChild("Line1")

	return {
		Index = index,
		Plot = plot,
		Center = Vector3.new(centerX, 0.5, centerZ),
		Pads = pads,
		PadPositions = padPositions,
		LockPrompt = lockPrompt,
		ForceFieldParts = forceFieldParts,
		SignLabel = signLabel,
		Owner = nil,
	}
end

local function buildBases(worldFolder)
	local bases = {}
	local xs = { -168, -56, 56, 168 }
	local index = 0
	for _, z in ipairs({ 170, 218 }) do
		for _, x in ipairs(xs) do
			index = index + 1
			bases[index] = buildBase(worldFolder, index, x, z)
		end
	end
	return bases
end

local function buildWave(worldFolder)
	local waveModel = Instance.new("Model")
	waveModel.Name = "TsunamiWave"
	waveModel.Parent = worldFolder
	local wall = makePart(waveModel, "WaveWall", Vector3.new(6, 30, 230), CFrame.new(-260, -60, -70),
		Color3.fromRGB(50, 130, 255), Enum.Material.Glass)
	wall.Transparency = 0.35
	wall.CanCollide = false
	local foam = makePart(waveModel, "WaveFoam", Vector3.new(7, 3, 230), CFrame.new(-260, -44, -70),
		Color3.fromRGB(235, 250, 255), Enum.Material.Neon)
	foam.Transparency = 0.25
	foam.CanCollide = false
	waveModel.PrimaryPart = wall
	return waveModel
end

function WorldBuilder.Build()
	local worldFolder = Instance.new("Folder")
	worldFolder.Name = "BerburuMusengWorld"
	worldFolder.Parent = Workspace

	buildGround(worldFolder)
	buildMesa(worldFolder)
	buildDecorations(worldFolder)
	local spawn, rebirthPrompt, eggStalls, speedPrompt, carryPrompt = buildPlazaAndShops(worldFolder)
	local bases = buildBases(worldFolder)
	local waveModel = buildWave(worldFolder)

	return {
		Folder = worldFolder,
		Bases = bases,
		EggStalls = eggStalls,
		RebirthPrompt = rebirthPrompt,
		SpeedPrompt = speedPrompt,
		CarryPrompt = carryPrompt,
		SpawnLocation = spawn,
		WaveModel = waveModel,
		PlazaCenter = Vector3.new(0, 0.6, 80),
		MesaBounds = { MinX = 80, MaxX = 140, MinZ = -145, MaxZ = -95, TopY = 14.7 },
	}
end

function WorldBuilder.SetBaseOwner(base, playerName)
	base.SignLabel.Text = string.upper(playerName) .. "'S BASE"
end

function WorldBuilder.ClearBaseOwner(base)
	base.SignLabel.Text = "EMPTY BASE"
end

function WorldBuilder.SetBaseLocked(base, locked)
	for _, wall in ipairs(base.ForceFieldParts) do
		wall.Transparency = locked and 0.35 or 1
		wall.CanCollide = locked
	end
end

-- Is a position inside a base plot's footprint (the deposit / safety test)?
function WorldBuilder.IsInsideBase(base, position)
	local center = base.Center
	return math.abs(position.X - center.X) <= 24 and math.abs(position.Z - center.Z) <= 19
end

return WorldBuilder
