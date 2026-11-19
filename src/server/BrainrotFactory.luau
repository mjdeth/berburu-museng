-- BrainrotFactory: builds a character Model for any cast member out of
-- plain Parts (no external assets). Every character is built from a
-- per-species plan: a body with a readable silhouette (round, box,
-- tall, squat, segmented, serpent, torpedo, quadruped or long), a
-- head, two eyes (white + pupil, on stalks for the frog, a neon visor
-- for the robot), and its signature accessory parts, finished with a
-- BillboardGui label showing name, rarity, mutation and $/s.
--
-- Round-5 polish: the first builds were a plain box + ball head +
-- single dark eye dots, which read as coloured blobs in screenshots.
-- Now the base build carries the species (belly plates, feet, face
-- plates, hoods, legs, serpent segments), the accessories anchor to
-- the head/body the plan actually built (glasses are ring frames
-- around the eyes, the sombrero has a dome, antennae come in pairs),
-- and Epic-and-up rarities get a neon ground ring so rarity reads at
-- a glance. Mutations keep their tint/sparkle treatment.
--
-- Parts are built in model-local space (origin at the ground under
-- the body, face toward -Z), then shifted by the caller's origin
-- CFrame, so the model can be placed and moved with Model:PivotTo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BrainrotData = require(Shared:WaitForChild("BrainrotData"))

local BrainrotFactory = {}

local function addPart(model, name, size, offset, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = offset
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function addBall(model, name, size, offset, color, material)
	local part = addPart(model, name, size, offset, color, material)
	part.Shape = Enum.PartType.Ball
	return part
end

-- Vertical-axis cylinder (pole, hat brim, ring): the part's height
-- runs along Y after the built-in quarter turn.
local function addCylinder(model, name, height, diameter, offset, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, diameter, diameter)
	part.CFrame = offset * CFrame.Angles(0, 0, math.rad(90))
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

-- Forward-facing disc (glasses rims and lenses): the cylinder's
-- height axis is turned to run along Z, so the flat face looks -Z.
local function addDisc(model, name, thickness, diameter, offset, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(thickness, diameter, diameter)
	part.CFrame = offset * CFrame.Angles(0, math.rad(90), 0)
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function addWedge(model, name, size, offset, color, material)
	local part = Instance.new("WedgePart")
	part.Name = name
	part.Size = size
	part.CFrame = offset
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

-- ------------------------------------------------------------------
-- Species plans. Form picks the base builder; the rest are flags and
-- dimensions the shared builders anchor to. Upright dimensions are
-- (BodySize, BodyY, HeadSize, HeadPos); other forms set their own
-- anchors in their builder.
-- ------------------------------------------------------------------

local STD_HEAD_SIZE = Vector3.new(1.5, 1.5, 1.5)
local STD_HEAD_POS = Vector3.new(0, 2.9, 0)

local PLANS = {
	kucing_kardus = { Form = "Upright", BodyShape = "Box",
		BodySize = Vector3.new(2.4, 2.2, 2.2), BodyY = 1.1, Feet = true },
	bebek_botak = { Form = "Upright",
		BodySize = Vector3.new(2.35, 2.1, 2.15), BodyY = 1.08, Belly = true, Feet = true, TailTuft = true },
	kodok_kacamata = { Form = "Upright",
		BodySize = Vector3.new(2.75, 1.85, 2.45), BodyY = 0.98,
		HeadSize = Vector3.new(1.85, 1.3, 1.65), HeadPos = Vector3.new(0, 2.5, 0), Eyes = "Top" },
	semut_sombrero = { Form = "Segments" },
	ular_sendal = { Form = "Serpent", SkipAccessories = { Tail = true } },
	ayam_astronot = { Form = "Upright",
		BodySize = Vector3.new(2.35, 2.1, 2.15), BodyY = 1.08, Belly = true, Feet = true, Comb = true },
	pinguin_panci = { Form = "Upright",
		BodySize = Vector3.new(2.05, 2.5, 2.05), BodyY = 1.27, HeadPos = Vector3.new(0, 3.02, 0),
		Belly = true, Flippers = true, Feet = true },
	kambing_knalpot = { Form = "Quadruped", Beard = true },
	monyet_daun = { Form = "Upright", FacePlate = true, RoundEars = true },
	naga_nasipadang = { Form = "Long", Belly = true },
	hiu_hoodie = { Form = "Torpedo", TailFin = true },
	robot_rujak = { Form = "Upright", BodyShape = "Box", HeadShape = "Box",
		BodySize = Vector3.new(2.3, 2.2, 2.1), BodyY = 1.1,
		HeadSize = Vector3.new(1.45, 1.35, 1.45), HeadPos = Vector3.new(0, 2.85, 0),
		Eyes = "Visor", Panel = true, Feet = true },
	kuda_kpop = { Form = "Quadruped" },
	garuda_geprek = { Form = "Upright",
		BodySize = Vector3.new(2.05, 2.5, 2.05), BodyY = 1.27, HeadPos = Vector3.new(0, 3.02, 0),
		Belly = true, Feet = true },
	kraken_kerang = { Form = "Upright",
		BodySize = Vector3.new(2.6, 1.9, 2.5), BodyY = 1.0,
		HeadSize = Vector3.new(1.6, 1.6, 1.6), HeadPos = Vector3.new(0, 2.62, 0) },
	phoenix_peyek = { Form = "Upright", FanTail = true, SkipAccessories = { Tail = true } },
	museng_petir = { Form = "Upright", Bolt = true },
	dewa_durian = { Form = "Upright",
		BodySize = Vector3.new(2.5, 2.35, 2.35), BodyY = 1.18 },
	museng_omega = { Form = "Upright",
		BodySize = Vector3.new(2.5, 2.35, 2.35), BodyY = 1.18 },
}

local function finalizeCtx(ctx)
	ctx.HeadTopY = ctx.HeadPos.Y + ctx.HeadSize.Y / 2
	ctx.FaceZ = ctx.HeadPos.Z - ctx.HeadSize.Z / 2
	ctx.BodyTopY = ctx.BodyY + ctx.BodySize.Y / 2
	ctx.BodyFrontZ = ctx.BodyZ - ctx.BodySize.Z / 2
	ctx.BodyBackZ = ctx.BodyZ + ctx.BodySize.Z / 2
	return ctx
end

-- ------------------------------------------------------------------
-- Base builders. Each returns the body part (the label's adornee)
-- and leaves the shared anchors on ctx.
-- ------------------------------------------------------------------

local function buildUpright(model, character, plan, ctx)
	ctx.BodySize = plan.BodySize or Vector3.new(2.35, 2.2, 2.2)
	ctx.BodyY = plan.BodyY or 1.1
	ctx.BodyZ = 0
	ctx.HeadSize = plan.HeadSize or STD_HEAD_SIZE
	ctx.HeadPos = plan.HeadPos or STD_HEAD_POS
	local body
	if plan.BodyShape == "Box" then
		body = addPart(model, "Body", ctx.BodySize, CFrame.new(0, ctx.BodyY, 0), character.Body)
	else
		body = addBall(model, "Body", ctx.BodySize, CFrame.new(0, ctx.BodyY, 0), character.Body)
	end
	local head
	if plan.HeadShape == "Box" then
		head = addPart(model, "Head", ctx.HeadSize, CFrame.new(ctx.HeadPos), character.Accent)
	else
		head = addBall(model, "Head", ctx.HeadSize, CFrame.new(ctx.HeadPos), character.Accent)
	end
	return body, head
end

local function buildSegments(model, character, ctx)
	-- The ant: three balls in a row, six little legs underneath.
	local abdomen = addBall(model, "Body", Vector3.new(1.75, 1.6, 1.75),
		CFrame.new(0, 0.95, 1.05), character.Body)
	addBall(model, "Segment", Vector3.new(1.2, 1.1, 1.2), CFrame.new(0, 0.8, -0.05), character.Body)
	local head = addBall(model, "Head", Vector3.new(1.3, 1.3, 1.3),
		CFrame.new(0, 1.2, -1.15), character.Accent)
	for _, sx in ipairs({ -1, 1 }) do
		for _, z in ipairs({ 0.8, 0.05, -0.55 }) do
			addPart(model, "Leg", Vector3.new(0.14, 0.8, 0.14),
				CFrame.new(sx * 0.55, 0.36, z) * CFrame.Angles(0, 0, sx * 0.5), character.Body)
		end
	end
	ctx.BodySize = Vector3.new(1.75, 1.6, 1.75)
	ctx.BodyY = 0.95
	ctx.BodyZ = 1.05
	ctx.HeadSize = Vector3.new(1.3, 1.3, 1.3)
	ctx.HeadPos = Vector3.new(0, 1.2, -1.15)
	return abdomen, head
end

local function buildSerpent(model, character, ctx)
	-- The snake: a chain of balls rising to a raised head, with its
	-- signature flip-flop (sendal jepit) riding on its back.
	addBall(model, "Segment", Vector3.new(1.05, 0.95, 1.05), CFrame.new(0, 0.5, 1.55), character.Body)
	local mid = addBall(model, "Body", Vector3.new(1.55, 1.4, 1.55),
		CFrame.new(0, 0.72, 0.45), character.Body)
	addBall(model, "Segment", Vector3.new(1.35, 1.25, 1.35), CFrame.new(0, 0.95, -0.75), character.Body)
	local head = addBall(model, "Head", Vector3.new(1.3, 1.3, 1.3),
		CFrame.new(0, 1.5, -1.7), character.Accent)
	local sendal = addPart(model, "Sendal", Vector3.new(0.95, 0.16, 1.7),
		CFrame.new(0, 1.52, 0.45), character.Accent)
	sendal.Material = Enum.Material.SmoothPlastic
	for _, sx in ipairs({ -1, 1 }) do
		addPart(model, "SendalStrap", Vector3.new(0.13, 0.1, 0.85),
			CFrame.new(sx * 0.22, 1.66, 0.3) * CFrame.Angles(0, sx * 0.5, 0), character.Accent)
	end
	ctx.BodySize = Vector3.new(1.55, 1.4, 1.55)
	ctx.BodyY = 0.72
	ctx.BodyZ = 0.45
	ctx.HeadSize = Vector3.new(1.3, 1.3, 1.3)
	ctx.HeadPos = Vector3.new(0, 1.5, -1.7)
	return mid, head
end

local function buildTorpedo(model, character, ctx)
	-- The shark: one stretched ball, face at the front, a hood ball
	-- behind it. No separate head part; the eyes sit on the body.
	local body = addBall(model, "Body", Vector3.new(2.0, 1.9, 3.4),
		CFrame.new(0, 1.05, 0.2), character.Body)
	addBall(model, "Belly", Vector3.new(1.3, 0.85, 1.9),
		CFrame.new(0, 0.6, -0.75), Color3.fromRGB(250, 246, 230))
	addBall(model, "Hood", Vector3.new(2.25, 2.1, 2.1), CFrame.new(0, 1.2, 0.95), character.Accent)
	for _, sx in ipairs({ -1, 1 }) do
		addWedge(model, "SideFin", Vector3.new(0.18, 0.9, 1.3),
			CFrame.new(sx * 1.02, 0.72, -0.1) * CFrame.Angles(0, 0, sx * -0.6), character.Accent)
	end
	ctx.BodySize = Vector3.new(2.0, 1.9, 3.4)
	ctx.BodyY = 1.05
	ctx.BodyZ = 0.2
	ctx.HeadSize = Vector3.new(1.5, 1.4, 1.4)
	ctx.HeadPos = Vector3.new(0, 1.3, -1.45)
	-- Eyes directly on the body's front.
	for _, dx in ipairs({ -0.6, 0.6 }) do
		addBall(model, "Eye", Vector3.new(0.34, 0.34, 0.34),
			CFrame.new(dx, 1.32, -1.42), Color3.fromRGB(255, 255, 255))
		addBall(model, "Pupil", Vector3.new(0.18, 0.18, 0.18),
			CFrame.new(dx, 1.32, -1.56), Color3.fromRGB(25, 25, 30))
	end
	return body, nil
end

local function buildQuadruped(model, character, ctx)
	-- Goat and horse: four legs, a long body, a neck and a raised
	-- head with a muzzle.
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			addCylinder(model, "Leg", 0.95, 0.34, CFrame.new(sx * 0.72, 0.48, sz * 0.85), character.Body)
		end
	end
	local body = addBall(model, "Body", Vector3.new(2.1, 1.8, 3.1),
		CFrame.new(0, 1.78, 0), character.Body)
	addCylinder(model, "Neck", 1.1, 0.62,
		CFrame.new(0, 2.35, -1.55) * CFrame.Angles(math.rad(-35), 0, 0), character.Body)
	local head = addBall(model, "Head", Vector3.new(1.3, 1.3, 1.3),
		CFrame.new(0, 2.85, -2.05), character.Accent)
	addBall(model, "Muzzle", Vector3.new(0.8, 0.65, 0.8), CFrame.new(0, 2.7, -2.6), character.Body)
	ctx.BodySize = Vector3.new(2.1, 1.8, 3.1)
	ctx.BodyY = 1.78
	ctx.BodyZ = 0
	ctx.HeadSize = Vector3.new(1.3, 1.3, 1.3)
	ctx.HeadPos = Vector3.new(0, 2.85, -2.05)
	return body, head
end

local function buildLong(model, character, ctx)
	-- The dragon: a long horizontal body, neck rising to a head at
	-- the front, belly plate underneath the chest.
	local body = addBall(model, "Body", Vector3.new(2.2, 2.0, 3.0),
		CFrame.new(0, 1.05, 0.35), character.Body)
	addCylinder(model, "Neck", 0.9, 0.7,
		CFrame.new(0, 1.7, -1.05) * CFrame.Angles(math.rad(-30), 0, 0), character.Body)
	local head = addBall(model, "Head", Vector3.new(1.45, 1.45, 1.45),
		CFrame.new(0, 2.2, -1.5), character.Accent)
	addBall(model, "Belly", Vector3.new(1.35, 1.15, 1.6),
		CFrame.new(0, 0.72, -0.95), Color3.fromRGB(250, 246, 230))
	ctx.BodySize = Vector3.new(2.2, 2.0, 3.0)
	ctx.BodyY = 1.05
	ctx.BodyZ = 0.35
	ctx.HeadSize = Vector3.new(1.45, 1.45, 1.45)
	ctx.HeadPos = Vector3.new(0, 2.2, -1.5)
	return body, head
end

-- ------------------------------------------------------------------
-- Shared face / body dressing
-- ------------------------------------------------------------------

local function buildEyes(model, ctx)
	local plan = ctx.Plan
	if plan.Eyes == "Visor" then
		addPart(model, "Visor", Vector3.new(ctx.HeadSize.X * 0.92, 0.4, 0.16),
			CFrame.new(ctx.HeadPos.X, ctx.HeadPos.Y + 0.05, ctx.FaceZ - 0.03),
			ctx.Accent, Enum.Material.Neon)
		return
	end
	ctx.EyePositions = {}
	if plan.Eyes == "Top" then
		-- Frog eyes: white balls on short stalks above the head,
		-- pupils looking forward off their fronts.
		for _, sx in ipairs({ -1, 1 }) do
			local ex = ctx.HeadPos.X + sx * ctx.HeadSize.X * 0.26
			local ey = ctx.HeadTopY + 0.34
			local ez = ctx.HeadPos.Z - ctx.HeadSize.Z * 0.08
			addCylinder(model, "EyeStalk", 0.34, 0.16, CFrame.new(ex, ctx.HeadTopY + 0.12, ez), ctx.BodyColor)
			addBall(model, "Eye", Vector3.new(0.44, 0.44, 0.44), CFrame.new(ex, ey, ez),
				Color3.fromRGB(255, 255, 255))
			addBall(model, "Pupil", Vector3.new(0.2, 0.2, 0.2), CFrame.new(ex, ey, ez - 0.17),
				Color3.fromRGB(25, 25, 30))
			table.insert(ctx.EyePositions, Vector3.new(ex, ey, ez))
		end
		return
	end
	-- Standard: white ball + dark pupil on the head's -Z face.
	local whiteD = ctx.HeadSize.X * 0.24
	for _, sx in ipairs({ -1, 1 }) do
		local ex = ctx.HeadPos.X + sx * ctx.HeadSize.X * 0.24
		local ey = ctx.HeadPos.Y + ctx.HeadSize.Y * 0.08
		local ez = ctx.FaceZ - whiteD * 0.18
		addBall(model, "Eye", Vector3.new(whiteD, whiteD, whiteD), CFrame.new(ex, ey, ez),
			Color3.fromRGB(255, 255, 255))
		addBall(model, "Pupil", Vector3.new(whiteD * 0.52, whiteD * 0.52, whiteD * 0.52),
			CFrame.new(ex, ey, ez - whiteD * 0.4), Color3.fromRGB(25, 25, 30))
		table.insert(ctx.EyePositions, Vector3.new(ex, ey, ez))
	end
end

local function buildBelly(model, ctx)
	addBall(model, "Belly", Vector3.new(ctx.BodySize.X * 0.6, ctx.BodySize.Y * 0.58, 0.55),
		CFrame.new(0, ctx.BodyY - ctx.BodySize.Y * 0.12, ctx.BodyFrontZ + 0.1),
		Color3.fromRGB(250, 246, 230))
end

local function buildFeet(model, ctx)
	for _, sx in ipairs({ -1, 1 }) do
		addBall(model, "Foot", Vector3.new(0.55, 0.3, 0.85),
			CFrame.new(sx * ctx.BodySize.X * 0.24, 0.15, ctx.BodyFrontZ + 0.25), ctx.Accent)
	end
end

local function buildExtras(model, ctx)
	local plan = ctx.Plan
	if plan.Comb then
		-- The astronaut chicken's comb, riding on top of its helmet
		-- (the helmet ball reaches ~0.1 studs past the head's top).
		for _, dz in ipairs({ -0.32, 0, 0.32 }) do
			addBall(model, "Comb", Vector3.new(0.34, 0.34, 0.34),
				CFrame.new(0, ctx.HeadTopY + 0.26, ctx.HeadPos.Z + dz),
				Color3.fromRGB(255, 80, 70))
		end
	end
	if plan.TailTuft then
		-- The duck's little tail tuft, kicked up at the back.
		addWedge(model, "TailTuft", Vector3.new(0.7, 0.5, 0.9),
			CFrame.new(0, ctx.BodyTopY - 0.18, ctx.BodyBackZ + 0.12)
				* CFrame.Angles(math.rad(-35), 0, 0), ctx.Accent)
	end
	if plan.Flippers then
		for _, sx in ipairs({ -1, 1 }) do
			addWedge(model, "Flipper", Vector3.new(0.28, 1.5, 0.85),
				CFrame.new(sx * (ctx.BodySize.X / 2 + 0.12), ctx.BodyY + 0.1, ctx.BodyZ - 0.2)
					* CFrame.Angles(0, 0, sx * 0.65), ctx.BodyColor)
		end
	end
	if plan.Beard then
		addWedge(model, "Beard", Vector3.new(0.5, 0.7, 0.4),
			CFrame.new(ctx.HeadPos.X, ctx.HeadPos.Y - ctx.HeadSize.Y * 0.48, ctx.FaceZ - 0.12),
			Color3.fromRGB(232, 226, 216))
	end
	if plan.Bolt then
		-- A lightning bolt on the chest, two neon slashes.
		addPart(model, "BoltTop", Vector3.new(0.36, 1.05, 0.14),
			CFrame.new(0.1, ctx.BodyY + 0.32, ctx.BodyFrontZ - 0.06)
				* CFrame.Angles(0, 0, 0.5), Color3.fromRGB(255, 240, 120), Enum.Material.Neon)
		addPart(model, "BoltBottom", Vector3.new(0.36, 1.05, 0.14),
			CFrame.new(-0.1, ctx.BodyY - 0.32, ctx.BodyFrontZ - 0.06)
				* CFrame.Angles(0, 0, 0.5), Color3.fromRGB(255, 240, 120), Enum.Material.Neon)
	end
	if plan.Panel then
		-- The robot's chest panel and buttons.
		addPart(model, "ChestPanel", Vector3.new(1.5, 1.1, 0.12),
			CFrame.new(0, ctx.BodyY + 0.1, ctx.BodyFrontZ - 0.04), Color3.fromRGB(60, 60, 70))
		local buttonColors = {
			Color3.fromRGB(255, 90, 90), Color3.fromRGB(120, 255, 140), Color3.fromRGB(110, 180, 255),
		}
		for i, bx in ipairs({ -0.4, 0, 0.4 }) do
			addBall(model, "Button", Vector3.new(0.22, 0.22, 0.22),
				CFrame.new(bx, ctx.BodyY + 0.28, ctx.BodyFrontZ - 0.14), buttonColors[i], Enum.Material.Neon)
		end
	end
end

local function buildFacePlate(model, ctx)
	-- The monkey's cream face plate; the eyes are laid over it.
	addBall(model, "FacePlate", Vector3.new(1.02, 0.92, 0.5),
		CFrame.new(ctx.HeadPos.X, ctx.HeadPos.Y - 0.05, ctx.FaceZ + 0.18),
		Color3.fromRGB(245, 220, 180))
end

-- ------------------------------------------------------------------
-- Accessories. Signature: (model, accent, bodyColor, ctx); every
-- offset anchors to the head/body the plan built.
-- ------------------------------------------------------------------

local AccessoryBuilders = {}

function AccessoryBuilders.Ears(model, accent, bodyColor, ctx)
	if ctx.Plan.RoundEars then
		for _, sx in ipairs({ -1, 1 }) do
			addBall(model, "Ear", Vector3.new(0.52, 0.52, 0.52),
				CFrame.new(ctx.HeadPos.X + sx * (ctx.HeadSize.X / 2 + 0.08),
					ctx.HeadPos.Y + ctx.HeadSize.Y * 0.12, ctx.HeadPos.Z), accent)
		end
		return
	end
	for _, sx in ipairs({ -1, 1 }) do
		addWedge(model, "Ear", Vector3.new(0.42, 0.95, 0.3),
			CFrame.new(ctx.HeadPos.X + sx * ctx.HeadSize.X * 0.36, ctx.HeadTopY + 0.26, ctx.HeadPos.Z)
				* CFrame.Angles(math.rad(-10), 0, sx * -0.22), accent)
	end
end

function AccessoryBuilders.Horns(model, accent, bodyColor, ctx)
	for _, sx in ipairs({ -1, 1 }) do
		addWedge(model, "Horn", Vector3.new(0.5, 1.0, 0.5),
			CFrame.new(ctx.HeadPos.X + sx * ctx.HeadSize.X * 0.34, ctx.HeadTopY + 0.28, ctx.HeadPos.Z + 0.05)
				* CFrame.Angles(math.rad(-32), 0, sx * -0.28), accent)
	end
end

function AccessoryBuilders.Hat(model, accent, bodyColor, ctx)
	-- The sombrero: a wide flat brim, a dome, and a band.
	addCylinder(model, "HatBrim", 0.16, 2.75,
		CFrame.new(ctx.HeadPos.X, ctx.HeadTopY + 0.04, ctx.HeadPos.Z), accent)
	addBall(model, "HatDome", Vector3.new(1.3, 0.85, 1.3),
		CFrame.new(ctx.HeadPos.X, ctx.HeadTopY + 0.38, ctx.HeadPos.Z), accent)
	addCylinder(model, "HatBand", 0.18, 1.38,
		CFrame.new(ctx.HeadPos.X, ctx.HeadTopY + 0.18, ctx.HeadPos.Z), bodyColor)
end

function AccessoryBuilders.Crown(model, accent, bodyColor, ctx)
	local gold = Color3.fromRGB(255, 200, 40)
	addCylinder(model, "CrownBand", 0.5, ctx.HeadSize.X * 1.12,
		CFrame.new(ctx.HeadPos.X, ctx.HeadTopY + 0.18, ctx.HeadPos.Z), gold, Enum.Material.Metal)
	for _, offset in ipairs({
		Vector3.new(0.42, 0, 0), Vector3.new(-0.42, 0, 0),
		Vector3.new(0, 0, 0.42), Vector3.new(0, 0, -0.42),
	}) do
		local scaled = Vector3.new(offset.X * ctx.HeadSize.X / 1.5, 0, offset.Z * ctx.HeadSize.X / 1.5)
		addPart(model, "CrownSpike", Vector3.new(0.3, 0.6, 0.3),
			CFrame.new(ctx.HeadPos + scaled + Vector3.new(0, ctx.HeadSize.Y / 2 + 0.66, 0)),
			gold, Enum.Material.Metal)
	end
end

function AccessoryBuilders.Wings(model, accent, bodyColor, ctx)
	for _, sx in ipairs({ -1, 1 }) do
		addPart(model, "Wing", Vector3.new(1.9, 1.05, 0.2),
			CFrame.new(sx * (ctx.BodySize.X / 2 + 0.7), ctx.BodyY + ctx.BodySize.Y * 0.28, ctx.BodyBackZ - 0.55)
				* CFrame.Angles(0, sx * 0.35, sx * -0.5), accent)
		addPart(model, "WingFeather", Vector3.new(1.35, 0.8, 0.18),
			CFrame.new(sx * (ctx.BodySize.X / 2 + 0.55), ctx.BodyY + ctx.BodySize.Y * 0.02, ctx.BodyBackZ - 0.35)
				* CFrame.Angles(0, sx * 0.3, sx * -0.35), accent)
	end
end

function AccessoryBuilders.Tail(model, accent, bodyColor, ctx)
	if ctx.Plan.TailFin then
		-- The shark's vertical tail fin.
		addWedge(model, "TailFin", Vector3.new(0.16, 1.7, 1.15),
			CFrame.new(0, ctx.BodyY + ctx.BodySize.Y * 0.3, ctx.BodyBackZ + 0.35), accent)
		return
	end
	if ctx.Plan.FanTail then
		-- The phoenix's fanned tail feathers.
		for _, spec in ipairs({ { 0, 0 }, { -0.45, -0.55 }, { 0.45, 0.55 } }) do
			addWedge(model, "TailFeather", Vector3.new(0.5, 2.3, 0.16),
				CFrame.new(spec[1], ctx.BodyY + 0.5, ctx.BodyBackZ + 0.55)
					* CFrame.Angles(math.rad(-38), 0, spec[2]), accent)
		end
		return
	end
	addPart(model, "Tail", Vector3.new(0.42, 0.42, 2.0),
		CFrame.new(0, ctx.BodyY - ctx.BodySize.Y * 0.18, ctx.BodyBackZ + 0.75)
			* CFrame.Angles(math.rad(30), 0, 0), accent)
	addBall(model, "TailTip", Vector3.new(0.5, 0.5, 0.5),
		CFrame.new(0, ctx.BodyY + 0.38, ctx.BodyBackZ + 1.55), accent)
end

function AccessoryBuilders.Antenna(model, accent, bodyColor, ctx)
	-- A pair of stalks, tipped with neon.
	for _, sx in ipairs({ -1, 1 }) do
		addCylinder(model, "AntennaStalk", 0.95, 0.14,
			CFrame.new(ctx.HeadPos.X + sx * ctx.HeadSize.X * 0.22, ctx.HeadTopY + 0.38, ctx.HeadPos.Z)
				* CFrame.Angles(0, 0, sx * -0.3), bodyColor)
		addBall(model, "AntennaTip", Vector3.new(0.5, 0.5, 0.5),
			CFrame.new(ctx.HeadPos.X + sx * (ctx.HeadSize.X * 0.22 + 0.27), ctx.HeadTopY + 0.82, ctx.HeadPos.Z),
			accent, Enum.Material.Neon)
	end
end

function AccessoryBuilders.Mohawk(model, accent, bodyColor, ctx)
	if ctx.Plan.Form == "Quadruped" then
		-- The horse's mane: slabs descending the neck.
		for _, spec in ipairs({
			{ 0.62, 0.55 }, { 0.3, 1.0 }, { -0.02, 1.45 },
		}) do
			addPart(model, "Mane", Vector3.new(0.3, 0.75, 0.5),
				CFrame.new(0, ctx.HeadPos.Y + spec[1], ctx.HeadPos.Z + spec[2])
					* CFrame.Angles(math.rad(-30), 0, 0), accent, Enum.Material.Neon)
		end
		return
	end
	addPart(model, "Mohawk", Vector3.new(0.34, 0.9, 1.65),
		CFrame.new(ctx.HeadPos.X, ctx.HeadTopY + 0.3, ctx.HeadPos.Z), accent, Enum.Material.Neon)
end

function AccessoryBuilders.Halo(model, accent, bodyColor, ctx)
	local halo = addCylinder(model, "Halo", 0.16, ctx.HeadSize.X * 1.3,
		CFrame.new(ctx.HeadPos.X, ctx.HeadTopY + 0.62, ctx.HeadPos.Z),
		Color3.fromRGB(255, 240, 150), Enum.Material.Neon)
	halo.Transparency = 0.15
end

function AccessoryBuilders.Fin(model, accent, bodyColor, ctx)
	addWedge(model, "Fin", Vector3.new(0.28, 1.25, 1.45),
		CFrame.new(0, ctx.BodyTopY + 0.3, ctx.BodyZ + 0.3) * CFrame.Angles(math.rad(-22), 0, 0), accent)
end

function AccessoryBuilders.Tentacles(model, accent, bodyColor, ctx)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local ox = sx * (ctx.BodySize.X / 2 - 0.18)
			local oz = ctx.BodyZ + sz * (ctx.BodySize.Z / 2 - 0.18)
			addPart(model, "Tentacle", Vector3.new(0.42, 1.35, 0.42),
				CFrame.new(ox, 0.55, oz) * CFrame.Angles(sz * 0.22, 0, sx * -0.25), accent)
			addBall(model, "TentacleTip", Vector3.new(0.46, 0.46, 0.46),
				CFrame.new(ox + sx * 0.18, 0.14, oz + sz * 0.15), accent)
		end
	end
end

function AccessoryBuilders.Crest(model, accent, bodyColor, ctx)
	for _, dz in ipairs({ -0.42, 0.03, 0.48 }) do
		addWedge(model, "CrestSpike", Vector3.new(0.38, 0.8, 0.5),
			CFrame.new(ctx.HeadPos.X, ctx.HeadTopY + 0.24, ctx.HeadPos.Z + dz)
				* CFrame.Angles(math.rad(-14), 0, 0), accent, Enum.Material.Neon)
	end
end

function AccessoryBuilders.Helmet(model, accent, bodyColor, ctx)
	local helmet = addBall(model, "Helmet",
		Vector3.new(ctx.HeadSize.X * 1.18, ctx.HeadSize.Y * 1.18, ctx.HeadSize.Z * 1.18),
		CFrame.new(ctx.HeadPos), Color3.fromRGB(210, 235, 255), Enum.Material.Glass)
	helmet.Transparency = 0.5
end

function AccessoryBuilders.Beak(model, accent, bodyColor, ctx)
	addWedge(model, "Beak", Vector3.new(0.68, 0.42, 0.9),
		CFrame.new(ctx.HeadPos.X, ctx.HeadPos.Y - ctx.HeadSize.Y * 0.05, ctx.FaceZ - 0.32)
			* CFrame.Angles(math.rad(180), 0, 0), Color3.fromRGB(255, 140, 40))
end

function AccessoryBuilders.Glasses(model, accent, bodyColor, ctx)
	-- Ring frames around the actual eyes, a bridge, and temple arms
	-- running back to the head.
	local dark = Color3.fromRGB(30, 30, 40)
	local rimD = ctx.HeadSize.X * 0.52
	for i, eyePos in ipairs(ctx.EyePositions or {}) do
		local rim = addDisc(model, "GlassesRim", 0.1, rimD, CFrame.new(eyePos), dark)
		rim.Name = "GlassesRim" .. i
		local lens = addDisc(model, "Lens", 0.14, rimD * 0.8,
			CFrame.new(eyePos - Vector3.new(0, 0, 0.05)), dark, Enum.Material.Glass)
		lens.Transparency = 0.3
		local arm = addPart(model, "GlassesArm", Vector3.new(0.09, 0.09, ctx.HeadSize.Z * 0.55),
			CFrame.new(eyePos.X + (eyePos.X >= ctx.HeadPos.X and 1 or -1) * rimD * 0.48,
				eyePos.Y, ctx.HeadPos.Z - ctx.HeadSize.Z * 0.1), dark)
		arm.Name = "GlassesArm" .. i
	end
	if ctx.EyePositions and #ctx.EyePositions == 2 then
		local midY = (ctx.EyePositions[1].Y + ctx.EyePositions[2].Y) / 2
		local midZ = (ctx.EyePositions[1].Z + ctx.EyePositions[2].Z) / 2
		addPart(model, "GlassesBridge", Vector3.new(ctx.HeadSize.X * 0.24, 0.09, 0.09),
			CFrame.new(ctx.HeadPos.X, midY + 0.05, midZ), dark)
	end
end

function AccessoryBuilders.LeafCrown(model, accent, bodyColor, ctx)
	local green = Color3.fromRGB(80, 190, 90)
	addCylinder(model, "LeafBand", 0.3, ctx.HeadSize.X * 1.2,
		CFrame.new(ctx.HeadPos.X, ctx.HeadTopY + 0.08, ctx.HeadPos.Z), green)
	for _, angle in ipairs({ 0, 2.1, 4.2 }) do
		addBall(model, "Leaf", Vector3.new(0.55, 0.35, 0.55),
			CFrame.new(ctx.HeadPos.X + math.sin(angle) * ctx.HeadSize.X * 0.5,
				ctx.HeadTopY + 0.32, ctx.HeadPos.Z + math.cos(angle) * ctx.HeadSize.X * 0.5), green)
	end
end

function AccessoryBuilders.Spikes(model, accent, bodyColor, ctx)
	-- The durian's armour: wedges ringing the whole body.
	local offsets = {
		Vector3.new(0, ctx.BodyTopY + 0.28, ctx.BodyZ),
		Vector3.new(0.98, ctx.BodyY + 0.55, ctx.BodyZ + 0.3),
		Vector3.new(-0.98, ctx.BodyY + 0.55, ctx.BodyZ - 0.3),
		Vector3.new(0.82, ctx.BodyY + 0.1, ctx.BodyZ - 0.78),
		Vector3.new(-0.82, ctx.BodyY + 0.1, ctx.BodyZ + 0.78),
		Vector3.new(0, ctx.BodyY + 0.62, ctx.BodyZ + 0.88),
		Vector3.new(0, ctx.BodyY + 0.62, ctx.BodyZ - 0.88),
	}
	for _, offset in ipairs(offsets) do
		addWedge(model, "Spike", Vector3.new(0.5, 0.85, 0.5), CFrame.new(offset), accent)
	end
end

function AccessoryBuilders.Cape(model, accent, bodyColor, ctx)
	addPart(model, "Cape", Vector3.new(1.95, 2.4, 0.14),
		CFrame.new(0, ctx.BodyY + 0.25, ctx.BodyBackZ + 0.16) * CFrame.Angles(math.rad(9), 0, 0),
		Color3.fromRGB(200, 40, 60))
end

function AccessoryBuilders.Pipes(model, accent, bodyColor, ctx)
	for _, sx in ipairs({ -1, 1 }) do
		addCylinder(model, "ExhaustPipe", 1.35, 0.42,
			CFrame.new(sx * (ctx.BodySize.X / 2 - 0.32), ctx.BodyTopY + 0.45, ctx.BodyBackZ - 0.5),
			Color3.fromRGB(90, 90, 100), Enum.Material.Metal)
	end
end

function AccessoryBuilders.PotHat(model, accent, bodyColor, ctx)
	addCylinder(model, "Pot", 0.85, ctx.HeadSize.X * 1.02,
		CFrame.new(ctx.HeadPos.X, ctx.HeadTopY + 0.35, ctx.HeadPos.Z),
		Color3.fromRGB(170, 175, 185), Enum.Material.Metal)
	addBall(model, "PotKnob", Vector3.new(0.4, 0.4, 0.4),
		CFrame.new(ctx.HeadPos.X, ctx.HeadTopY + 0.95, ctx.HeadPos.Z),
		Color3.fromRGB(60, 60, 70), Enum.Material.Metal)
end

-- ------------------------------------------------------------------
-- Mutation + rarity treatment
-- ------------------------------------------------------------------

local function applyMutationTreatment(model, mutation)
	if mutation == "Gold" or mutation == "Diamond" or mutation == "Galaxy" then
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart")
				and (child.Name == "Body" or child.Name == "Head" or child.Name == "Segment") then
				if mutation == "Gold" then
					child.Color = child.Name == "Head"
						and Color3.fromRGB(255, 215, 90) or Color3.fromRGB(255, 200, 60)
					child.Material = Enum.Material.Metal
				elseif mutation == "Diamond" then
					child.Color = child.Name == "Head"
						and Color3.fromRGB(200, 250, 255) or Color3.fromRGB(170, 240, 255)
					child.Material = Enum.Material.Glass
					child.Transparency = 0.15
				else
					child.Color = child.Name == "Head"
						and Color3.fromRGB(90, 50, 160) or Color3.fromRGB(60, 30, 110)
					child.Material = Enum.Material.Neon
				end
			end
		end
	end
	if mutation == "Galaxy" then
		local starOffsets = {
			Vector3.new(0.7, 1.6, -1.05), Vector3.new(-0.6, 0.7, -1.05), Vector3.new(0.1, 1.2, 1.12),
		}
		for _, offset in ipairs(starOffsets) do
			addBall(model, "GalaxyStar", Vector3.new(0.22, 0.22, 0.22), CFrame.new(offset),
				Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
		end
	end
end

local RING_TRANSPARENCY = {
	["Rare"] = 0.45, ["Epic"] = 0.3, ["Legendary"] = 0.18,
	["Mythic"] = 0.12, ["Brainrot God"] = 0.05,
}

local function buildRarityRing(model, character, mutation)
	local transparency = RING_TRANSPARENCY[character.Rarity]
	local color = BrainrotData.Rarities[character.Rarity].Color
	if mutation ~= "None" then
		color = BrainrotData.Mutations[mutation].Color
		transparency = math.min(transparency or 0.3, 0.25)
	end
	if not transparency then
		return
	end
	local ring = addCylinder(model, "RarityRing", 0.1, 3.05, CFrame.new(0, 0.05, 0),
		color, Enum.Material.Neon)
	ring.Transparency = transparency
end

-- ------------------------------------------------------------------
-- Label
-- ------------------------------------------------------------------

local function buildLabel(model, root, character, mutation, effectiveRate)
	local gui = Instance.new("BillboardGui")
	gui.Name = "BrainrotLabel"
	gui.Adornee = root
	gui.Size = UDim2.fromOffset(240, 96)
	gui.StudsOffset = Vector3.new(0, 3.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 160
	gui.LightInfluence = 0

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = gui

	local rarityData = BrainrotData.Rarities[character.Rarity]
	local mutationData = BrainrotData.Mutations[mutation] or BrainrotData.Mutations.None

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.LayoutOrder = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 30)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = character.Name
	nameLabel.TextColor3 = rarityData.Color
	nameLabel.TextSize = 22
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Parent = gui

	local infoText = character.Rarity
	if mutation ~= "None" then
		infoText = mutation .. " " .. character.Rarity
	end
	local infoLabel = Instance.new("TextLabel")
	infoLabel.Name = "InfoLabel"
	infoLabel.LayoutOrder = 2
	infoLabel.Size = UDim2.new(1, 0, 0, 22)
	infoLabel.BackgroundTransparency = 1
	infoLabel.Text = infoText
	infoLabel.TextColor3 = mutation ~= "None" and mutationData.Color or Color3.fromRGB(235, 235, 235)
	infoLabel.TextSize = 16
	infoLabel.Font = Enum.Font.GothamBold
	infoLabel.TextStrokeTransparency = 0.3
	infoLabel.Parent = gui

	local rateLabel = Instance.new("TextLabel")
	rateLabel.Name = "RateLabel"
	rateLabel.LayoutOrder = 3
	rateLabel.Size = UDim2.new(1, 0, 0, 22)
	rateLabel.BackgroundTransparency = 1
	rateLabel.Text = "$" .. effectiveRate .. "/s"
	rateLabel.TextColor3 = Color3.fromRGB(140, 255, 150)
	rateLabel.TextSize = 16
	rateLabel.Font = Enum.Font.GothamBold
	rateLabel.TextStrokeTransparency = 0.3
	rateLabel.Parent = gui

	gui.Parent = model
	return gui
end

-- ------------------------------------------------------------------
-- Build
-- ------------------------------------------------------------------

-- Build the character named by id, with the given mutation ("None",
-- "Gold", "Diamond" or "Galaxy"), with the model's ground-level origin
-- at originCFrame.
function BrainrotFactory.BuildCharacter(id, mutation, originCFrame)
	local character = BrainrotData.GetCharacter(id)
	if not character then
		return nil
	end
	mutation = mutation or "None"
	local origin = originCFrame or CFrame.new()
	local plan = PLANS[id] or { Form = "Upright" }

	local model = Instance.new("Model")
	model.Name = character.Name

	local ctx = {
		Plan = plan,
		Accent = character.Accent,
		BodyColor = character.Body,
		BodyZ = 0,
	}

	local bodyPart
	if plan.Form == "Segments" then
		bodyPart = buildSegments(model, character, ctx)
	elseif plan.Form == "Serpent" then
		bodyPart = buildSerpent(model, character, ctx)
	elseif plan.Form == "Torpedo" then
		bodyPart = buildTorpedo(model, character, ctx)
	elseif plan.Form == "Quadruped" then
		bodyPart = buildQuadruped(model, character, ctx)
	elseif plan.Form == "Long" then
		bodyPart = buildLong(model, character, ctx)
	else
		bodyPart = buildUpright(model, character, plan, ctx)
	end
	finalizeCtx(ctx)

	if plan.FacePlate then
		buildFacePlate(model, ctx)
	end
	if plan.Form ~= "Torpedo" then
		buildEyes(model, ctx)
	end
	if plan.Belly and plan.Form ~= "Torpedo" and plan.Form ~= "Long" then
		buildBelly(model, ctx)
	end
	if plan.Feet then
		buildFeet(model, ctx)
	end

	for _, accessoryName in ipairs(character.Accessories) do
		if not (plan.SkipAccessories and plan.SkipAccessories[accessoryName]) then
			local builder = AccessoryBuilders[accessoryName]
			if builder then
				builder(model, character.Accent, character.Body, ctx)
			end
		end
	end
	buildExtras(model, ctx)

	applyMutationTreatment(model, mutation)
	buildRarityRing(model, character, mutation)

	local effectiveRate = BrainrotData.GetEffectiveRate(id, mutation)
	buildLabel(model, bodyPart, character, mutation, effectiveRate)

	-- Shift the whole local build to the caller's origin.
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") then
			child.CFrame = origin * child.CFrame
		end
	end

	-- The model's pivot must sit at ground level under the body, not
	-- at its centre, so callers can PivotTo a ground CFrame directly
	-- and GetPivot() reads in ground space. That used to be done by
	-- writing model.PivotOffset -- but PivotOffset is not a scriptable
	-- member of Model, and the write throws in Roblox ("PivotOffset
	-- is not a valid member of Model"). It killed every factory build
	-- on the live place (CatchService start, every egg hatch) while
	-- the headless shim tolerated it. Never write it again: instead
	-- the model gets an invisible Root part exactly at the origin,
	-- and the Root is the PrimaryPart -- with no pivot offset
	-- anywhere, a Model's pivot IS its PrimaryPart's CFrame.
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.CFrame = origin
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model
	model.PrimaryPart = root
	model:SetAttribute("BrainrotId", id)
	model:SetAttribute("Mutation", mutation)
	model:SetAttribute("Rate", effectiveRate)
	return model
end

return BrainrotFactory
