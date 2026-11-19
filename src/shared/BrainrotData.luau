-- BrainrotData: the cast of Berburu Museng. Data only: rarities, mutations,
-- every character's name, price, money-per-second, colors and accessory list,
-- plus the egg tables and the hatch / wild-spawn roll helpers the server uses.

local BrainrotData = {}

BrainrotData.RarityOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Brainrot God" }

BrainrotData.Rarities = {
	["Common"] = { Color = Color3.fromRGB(235, 235, 235) },
	["Rare"] = { Color = Color3.fromRGB(80, 170, 255) },
	["Epic"] = { Color = Color3.fromRGB(190, 90, 255) },
	["Legendary"] = { Color = Color3.fromRGB(255, 165, 40) },
	["Mythic"] = { Color = Color3.fromRGB(255, 70, 120) },
	["Brainrot God"] = { Color = Color3.fromRGB(255, 240, 120) },
}

-- Mutation name -> income multiplier and label tint.
BrainrotData.Mutations = {
	["None"] = { Mult = 1, Color = Color3.fromRGB(220, 220, 220) },
	["Gold"] = { Mult = 2, Color = Color3.fromRGB(255, 205, 60) },
	["Diamond"] = { Mult = 3, Color = Color3.fromRGB(150, 240, 255) },
	["Galaxy"] = { Mult = 5, Color = Color3.fromRGB(200, 130, 255) },
}

-- The cast. Accessories name the procedural parts BrainrotFactory bolts on:
-- Ears, Horns, Hat, Crown, Wings, Tail, Antenna, Mohawk, Halo, Fin,
-- Tentacles, Crest, Helmet, Beak, Glasses, LeafCrown, Spikes, Cape, Pipes, PotHat.
BrainrotData.Characters = {
	-- Common
	{ Id = "kucing_kardus", Name = "Kucing Kardus", Rarity = "Common", Price = 25, Rate = 1,
		Body = Color3.fromRGB(214, 164, 102), Accent = Color3.fromRGB(150, 105, 60), Accessories = { "Ears", "Tail" } },
	{ Id = "bebek_botak", Name = "Bebek Botak", Rarity = "Common", Price = 40, Rate = 2,
		Body = Color3.fromRGB(245, 225, 90), Accent = Color3.fromRGB(255, 140, 40), Accessories = { "Beak" } },
	{ Id = "kodok_kacamata", Name = "Kodok Kacamata", Rarity = "Common", Price = 60, Rate = 3,
		Body = Color3.fromRGB(110, 200, 110), Accent = Color3.fromRGB(40, 40, 40), Accessories = { "Glasses" } },
	{ Id = "semut_sombrero", Name = "Semut Sombrero", Rarity = "Common", Price = 85, Rate = 4,
		Body = Color3.fromRGB(120, 70, 45), Accent = Color3.fromRGB(240, 200, 90), Accessories = { "Hat", "Antenna" } },
	{ Id = "ular_sendal", Name = "Ular Sendal Jepit", Rarity = "Common", Price = 120, Rate = 5,
		Body = Color3.fromRGB(90, 180, 160), Accent = Color3.fromRGB(255, 120, 160), Accessories = { "Tail" } },
	-- Rare
	{ Id = "ayam_astronot", Name = "Ayam Astronot", Rarity = "Rare", Price = 300, Rate = 9,
		Body = Color3.fromRGB(240, 240, 240), Accent = Color3.fromRGB(255, 90, 60), Accessories = { "Helmet", "Beak" } },
	{ Id = "pinguin_panci", Name = "Pinguin Panci", Rarity = "Rare", Price = 450, Rate = 13,
		Body = Color3.fromRGB(50, 55, 75), Accent = Color3.fromRGB(170, 175, 185), Accessories = { "PotHat", "Beak" } },
	{ Id = "kambing_knalpot", Name = "Kambing Knalpot", Rarity = "Rare", Price = 700, Rate = 19,
		Body = Color3.fromRGB(205, 195, 185), Accent = Color3.fromRGB(90, 90, 100), Accessories = { "Horns", "Pipes", "Ears" } },
	{ Id = "monyet_daun", Name = "Monyet Mahkota Daun", Rarity = "Rare", Price = 1000, Rate = 27,
		Body = Color3.fromRGB(150, 105, 70), Accent = Color3.fromRGB(80, 190, 90), Accessories = { "LeafCrown", "Tail", "Ears" } },
	-- Epic
	{ Id = "naga_nasipadang", Name = "Naga Nasi Padang", Rarity = "Epic", Price = 2500, Rate = 55,
		Body = Color3.fromRGB(200, 60, 60), Accent = Color3.fromRGB(255, 190, 70), Accessories = { "Horns", "Wings", "Tail", "Crest" } },
	{ Id = "hiu_hoodie", Name = "Hiu Hoodie", Rarity = "Epic", Price = 4000, Rate = 85,
		Body = Color3.fromRGB(110, 150, 190), Accent = Color3.fromRGB(255, 110, 180), Accessories = { "Fin", "Tail" } },
	{ Id = "robot_rujak", Name = "Robot Rujak", Rarity = "Epic", Price = 6500, Rate = 135,
		Body = Color3.fromRGB(160, 165, 175), Accent = Color3.fromRGB(255, 200, 60), Accessories = { "Antenna", "Glasses" } },
	{ Id = "kuda_kpop", Name = "Kuda K-Pop", Rarity = "Epic", Price = 10000, Rate = 210,
		Body = Color3.fromRGB(235, 200, 220), Accent = Color3.fromRGB(140, 220, 255), Accessories = { "Mohawk", "Ears", "Tail" } },
	-- Legendary
	{ Id = "garuda_geprek", Name = "Garuda Geprek", Rarity = "Legendary", Price = 25000, Rate = 480,
		Body = Color3.fromRGB(190, 130, 50), Accent = Color3.fromRGB(255, 90, 50), Accessories = { "Wings", "Crest", "Beak", "Tail" } },
	{ Id = "kraken_kerang", Name = "Kraken Kerang", Rarity = "Legendary", Price = 45000, Rate = 850,
		Body = Color3.fromRGB(150, 80, 190), Accent = Color3.fromRGB(255, 170, 210), Accessories = { "Tentacles", "Crown" } },
	{ Id = "phoenix_peyek", Name = "Phoenix Peyek", Rarity = "Legendary", Price = 80000, Rate = 1500,
		Body = Color3.fromRGB(255, 130, 50), Accent = Color3.fromRGB(255, 220, 90), Accessories = { "Wings", "Crest", "Tail", "Beak" } },
	-- Mythic
	{ Id = "museng_petir", Name = "Museng Raja Petir", Rarity = "Mythic", Price = 200000, Rate = 3600,
		Body = Color3.fromRGB(120, 90, 200), Accent = Color3.fromRGB(255, 240, 120), Accessories = { "Crown", "Cape", "Ears", "Tail" } },
	{ Id = "dewa_durian", Name = "Dewa Durian Kosmik", Rarity = "Mythic", Price = 500000, Rate = 8500,
		Body = Color3.fromRGB(90, 160, 80), Accent = Color3.fromRGB(255, 225, 130), Accessories = { "Spikes", "Halo", "Crown" } },
	-- Brainrot God
	{ Id = "museng_omega", Name = "Museng Omega Terlarang", Rarity = "Brainrot God", Price = 1500000, Rate = 22000,
		Body = Color3.fromRGB(255, 215, 90), Accent = Color3.fromRGB(255, 255, 255), Accessories = { "Crown", "Wings", "Halo", "Cape", "Tail" } },
}

BrainrotData.ById = {}
for _, character in ipairs(BrainrotData.Characters) do
	BrainrotData.ById[character.Id] = character
end

-- Egg tiers: price and the rarity odds (percent) a hatch rolls against.
BrainrotData.Eggs = {
	{ Name = "Telur Kardus", Price = 100, Color = Color3.fromRGB(200, 170, 120),
		Odds = { Common = 70, Rare = 25, Epic = 5 } },
	{ Name = "Telur Emas Palsu", Price = 1500, Color = Color3.fromRGB(255, 205, 60),
		Odds = { Rare = 55, Epic = 32, Legendary = 11, Mythic = 2 } },
	{ Name = "Telur Naga Kosmik", Price = 25000, Color = Color3.fromRGB(170, 90, 255),
		Odds = { Epic = 45, Legendary = 35, Mythic = 16, ["Brainrot God"] = 4 } },
}

function BrainrotData.GetCharacter(id)
	return BrainrotData.ById[id]
end

function BrainrotData.GetEffectiveRate(id, mutation)
	local character = BrainrotData.ById[id]
	if not character then
		return 0
	end
	local mutationData = BrainrotData.Mutations[mutation] or BrainrotData.Mutations.None
	return character.Rate * mutationData.Mult
end

function BrainrotData.RollRarityFromOdds(odds)
	local total = 0
	for _, rarity in ipairs(BrainrotData.RarityOrder) do
		if odds[rarity] then
			total = total + odds[rarity]
		end
	end
	if total <= 0 then
		return "Common"
	end
	local roll = math.random() * total
	local running = 0
	for _, rarity in ipairs(BrainrotData.RarityOrder) do
		if odds[rarity] then
			running = running + odds[rarity]
			if roll <= running then
				return rarity
			end
		end
	end
	return "Common"
end

function BrainrotData.RandomCharacterOfRarity(rarity)
	local pool = {}
	for _, character in ipairs(BrainrotData.Characters) do
		if character.Rarity == rarity then
			table.insert(pool, character)
		end
	end
	if #pool == 0 then
		return BrainrotData.Characters[1]
	end
	return pool[math.random(1, #pool)]
end

-- Mutation roll. odds is { Gold = pct, Diamond = pct, Galaxy = pct }.
function BrainrotData.RollMutation(odds)
	local roll = math.random() * 100
	if roll <= (odds.Galaxy or 0) then
		return "Galaxy"
	end
	if roll <= (odds.Galaxy or 0) + (odds.Diamond or 0) then
		return "Diamond"
	end
	if roll <= (odds.Galaxy or 0) + (odds.Diamond or 0) + (odds.Gold or 0) then
		return "Gold"
	end
	return "None"
end

return BrainrotData
