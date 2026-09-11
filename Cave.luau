--!strict
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local terrain = Workspace.Terrain

local Cave = {}

local VOXEL = 4
local CHUNK = 16 -- voxels per side, so 64 studs
local SIZE = CHUNK * VOXEL

Cave.settings = {
	seed = 1,
	tunnelRadius = 8,
	wiggle = 12, -- how far tunnels bend away from a straight line
	bend = 0.013, -- how tight the bends are. much above 0.02 and tunnels tear into separate pockets
	minRadius = 5.5, -- too thin and the terrain grid breaks tunnels apart
	chamberChance = 0.5, -- per node
	chamberRadius = 22,
	cavernChance = 0.07, -- per node, a huge flattened dome with rock pillars instead of a chamber
	cavernRadius = 46,
	cavernFlatten = 0.55, -- height compared to width
	southChance = 0.6, -- east links are always there, south ones only sometimes, so it's less of a grid
	diagChance = 0.25,
	rampChance = 0.45, -- per node, a sloped tunnel down to the level below
	top = 0, -- nothing generates above this y
	-- top down, each layer starts at this y (edges get warped by noise)
	-- band = the thin stripes running through each layer, like real sedimentary rock
	layers = {
		{ at = 0, material = Enum.Material.Sandstone, band = Enum.Material.Limestone },
		{ at = -50, material = Enum.Material.Limestone, band = Enum.Material.Slate },
		{ at = -120, material = Enum.Material.Slate, band = Enum.Material.Rock },
		{ at = -210, material = Enum.Material.Basalt, band = Enum.Material.Slate },
	},
	bandThickness = 5, -- studs
	patch = Enum.Material.Rock,
	floor = Enum.Material.Ground,
	lavaBelow = -280,
	colors = {
		[Enum.Material.Sandstone] = Color3.fromRGB(162, 136, 108),
		[Enum.Material.Limestone] = Color3.fromRGB(148, 141, 128),
		[Enum.Material.Slate] = Color3.fromRGB(88, 86, 92),
		[Enum.Material.Basalt] = Color3.fromRGB(50, 47, 52),
		[Enum.Material.Rock] = Color3.fromRGB(118, 110, 100),
		[Enum.Material.Ground] = Color3.fromRGB(80, 66, 52),
		-- crystal biome
		[Enum.Material.Salt] = Color3.fromRGB(176, 166, 196),
		[Enum.Material.Glacier] = Color3.fromRGB(116, 104, 176),
		-- mushroom biome
		[Enum.Material.Mud] = Color3.fromRGB(58, 50, 46),
		[Enum.Material.LeafyGrass] = Color3.fromRGB(38, 72, 64),
		-- flooded biome
		[Enum.Material.Cobblestone] = Color3.fromRGB(70, 86, 84),
		[Enum.Material.Sand] = Color3.fromRGB(96, 104, 92),
	},
	-- plain rock areas only, chances per ceiling/floor voxel
	decor = {
		stalactiteChance = 0.05,
		stalagmiteChance = 0.015,
		rubbleChance = 0.03,
		puddleChance = 0.006,
	},
	-- big regions of the mine. above crystalAbove = crystal caves, below mushroomBelow = mushroom caves
	biomes = {
		scale = 0.0035, -- smaller = bigger regions
		crystalAbove = 0.2,
		mushroomBelow = -0.2,
		crystalChance = 0.035, -- per wall voxel
		mushroomChance = 0.05, -- per floor voxel
		crystalColors = { Color3.fromRGB(170, 90, 255), Color3.fromRGB(80, 225, 255), Color3.fromRGB(255, 105, 215) },
		mushroomColors = { Color3.fromRGB(60, 255, 200), Color3.fromRGB(90, 170, 255), Color3.fromRGB(160, 255, 90) },
		-- flooded caves come out of the plain rock. higher = fewer
		floodedAbove = 0.15,
		waterLevel = 0.42, -- how far up each 64 stud layer the water comes
		algaeChance = 0.03, -- per wall voxel
		algaeColors = { Color3.fromRGB(80, 255, 170), Color3.fromRGB(60, 220, 255) },
	},
	radius = 2, -- chunks around each player
	unloadMargin = 2, -- chunks past radius before a chunk gets cleared away
	lightDistance = 110, -- lights further than this from every player switch off
	oreOffset = 2, -- studs to push ore out of the wall. roblox draws the wall further into the tunnel than the maths says, Cave.measure() tells you the real number
	lantern = { color = Color3.fromRGB(255, 206, 158), brightness = 1.6, range = 36 },
	oreGlow = {
		Gold = Color3.fromRGB(255, 196, 80),
		Diamond = Color3.fromRGB(120, 235, 255),
	},
	-- hits = clicks to break it, respawn = seconds until it grows back
	ores = {
		{ name = "Coal", color = Color3.fromRGB(34, 34, 38), material = Enum.Material.Slate, below = 0, chance = 0.012, hits = 3, respawn = 20 },
		{ name = "Iron", color = Color3.fromRGB(196, 132, 90), material = Enum.Material.Rock, below = -60, chance = 0.008, hits = 5, respawn = 30 },
		{ name = "Gold", color = Color3.fromRGB(240, 190, 45), material = Enum.Material.Foil, below = -150, chance = 0.004, hits = 8, respawn = 45 },
		{ name = "Diamond", color = Color3.fromRGB(110, 235, 245), material = Enum.Material.Glass, below = -260, chance = 0.002, hits = 12, respawn = 60 },
	},
	mineReach = 14, -- studs
	mineCooldown = 0.2, -- seconds between hits, stops autoclickers
	digRadius = 3.5, -- studs, size of each bite when you hold click on rock
	digReach = 16,
	digCooldown = 0.12,
	-- a sound id like "rbxassetid://1234567890" played on every pickaxe hit. empty = no sound
	hitSound = "",
}

local done: { [string]: boolean } = {}
local featureCache: { [string]: any } = {}

Cave.placed = 0

local function getFolder(name: string): Folder
	local folder = Workspace:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function getOreFolder(): Folder
	return getFolder("Ores")
end

-- everything a chunk made, so it can be removed again when nobody's near
local chunkObjects: { [string]: { Instance } } = {}
local chunkCoords: { [string]: Vector3 } = {}
local pinned: { [string]: boolean } = {}
local digs: { { at: Vector3, r: number } } = {}
local lights: { [PointLight]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local collecting: { Instance }? = nil

local function chunkKey(cx: number, cy: number, cz: number): string
	return cx .. "," .. cy .. "," .. cz
end

local function keep(model: Instance, folderName: string)
	-- a chunk reloading shouldn't put ore or decor back inside a hole somebody dug
	if collecting and #digs > 0 and model:IsA("Model") then
		local pos = model:GetBoundingBox().Position
		for _, d in digs do
			if (pos - d.at).Magnitude < d.r + 3 then
				model:Destroy()
				return
			end
		end
	end
	model.Parent = getFolder(folderName)
	if collecting then
		table.insert(collecting, model)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("PointLight") then
			lights[d] = true
		end
	end
end

-- ============================================================ the tunnel network
--[[
	every chunk has one node somewhere inside it. each node gets a tunnel to the
	node east (+x) and south (+z) of it, so every level is one connected grid.
	some nodes also get a ramp down to the level below, and some get a chamber.
	all the air is part of that network, so nothing can end up sealed off.
]]

local function hash(x: number, y: number, z: number, k: number): number
	local h = (x * 374761393 + y * 668265263 + z * 1440662683 + k * 3266489917 + Cave.settings.seed * 2654435761) % 4294967296
	h = bit32.bxor(h, bit32.rshift(h, 15))
	h = (h * 2246822519) % 4294967296
	h = bit32.bxor(h, bit32.rshift(h, 13))
	return h / 4294967296
end

local function hasNode(cy: number): boolean
	return (cy + 1) * SIZE <= Cave.settings.top
end

local function nodeAt(cx: number, cy: number, cz: number): Vector3
	return Vector3.new(
		cx + 0.1 + hash(cx, cy, cz, 1) * 0.8,
		cy + 0.3 + hash(cx, cy, cz, 2) * 0.4,
		cz + 0.1 + hash(cx, cy, cz, 3) * 0.8
	) * SIZE
end

-- every tunnel and chamber that could reach into this chunk
local function featuresFor(cx: number, cy: number, cz: number)
	local key = cx .. "," .. cy .. "," .. cz
	local cached = featureCache[key]
	if cached then
		return cached
	end

	local s = Cave.settings
	local tunnels, chambers, caverns, pillars = {}, {}, {}, {}
	local reach = math.max(s.chamberRadius * 1.3, s.cavernRadius * 1.2) + s.wiggle + VOXEL + s.tunnelRadius * 1.4
	local lo = Vector3.new(cx, cy, cz) * SIZE - Vector3.one * reach
	local hi = Vector3.new(cx + 1, cy + 1, cz + 1) * SIZE + Vector3.one * reach

	local function touches(a: Vector3, b: Vector3): boolean
		local mn, mx = a:Min(b), a:Max(b)
		return mx.X >= lo.X and mn.X <= hi.X and mx.Y >= lo.Y and mn.Y <= hi.Y and mx.Z >= lo.Z and mn.Z <= hi.Z
	end

	for x = cx - 2, cx + 1 do
		for y = cy - 1, cy + 2 do
			for z = cz - 2, cz + 1 do
				if hasNode(y) then
					local a = nodeAt(x, y, z)
					local links = { nodeAt(x + 1, y, z) }
					if hash(x, y, z, 8) < s.southChance then
						table.insert(links, nodeAt(x, y, z + 1))
					end
					if hash(x, y, z, 9) < s.diagChance then
						table.insert(links, nodeAt(x + 1, y, z + 1))
					end
					if hash(x, y, z, 4) < s.rampChance and hasNode(y - 1) then
						if hash(x, y, z, 5) < 0.5 then
							table.insert(links, nodeAt(x + 1, y - 1, z))
						else
							table.insert(links, nodeAt(x, y - 1, z + 1))
						end
					end
					for _, b in links do
						if touches(a, b) then
							table.insert(tunnels, { a = a, ab = b - a, len2 = (b - a):Dot(b - a) })
						end
					end
					if hash(x, y, z, 10) < s.cavernChance then
						if touches(a, a) then
							local r = s.cavernRadius * (0.8 + hash(x, y, z, 11) * 0.4)
							table.insert(caverns, { c = a, r = r, flat = s.cavernFlatten })
							-- pillars off to the sides, never in the middle where the tunnels come in
							for i = 1, 2 + math.floor(hash(x, y, z, 12) * 3) do
								local angle = hash(x, y, z, 20 + i) * math.pi * 2
								local dist = r * (0.3 + hash(x, y, z, 30 + i) * 0.3)
								table.insert(pillars, {
									x = a.X + math.cos(angle) * dist,
									z = a.Z + math.sin(angle) * dist,
									y = a.Y,
									h = r * s.cavernFlatten + 6,
									r = 2.5 + hash(x, y, z, 40 + i) * 3.5,
								})
							end
						end
					elseif hash(x, y, z, 6) < s.chamberChance and touches(a, a) then
						table.insert(chambers, { c = a, r = s.chamberRadius * (0.7 + hash(x, y, z, 7) * 0.6) })
					end
				end
			end
		end
	end

	cached = { tunnels = tunnels, chambers = chambers, caverns = caverns, pillars = pillars }
	featureCache[key] = cached
	return cached
end

-- studs of clearance: > 0 is air, < 0 is rock, 0 is the wall
local function airness(p: Vector3): number
	local s = Cave.settings
	local f = featuresFor(math.floor(p.X / SIZE), math.floor(p.Y / SIZE), math.floor(p.Z / SIZE))
	local o = s.seed * 17.13

	-- bend space a bit so tunnels wander instead of running dead straight
	local b = s.bend
	local q = p + Vector3.new(
		math.noise(p.X * b, p.Y * b, p.Z * b + o),
		math.noise(p.X * b + o, p.Y * b, p.Z * b),
		math.noise(p.X * b, p.Y * b + o, p.Z * b)
	) * s.wiggle * 2
	local r = math.max(s.minRadius, s.tunnelRadius * (1 + math.noise(p.X * 0.05, p.Y * 0.05, p.Z * 0.05 - o) * 0.4))

	local best = -math.huge
	for _, t in f.tunnels do
		local ap = q - t.a
		local k = math.clamp(ap:Dot(t.ab) / t.len2, 0, 1)
		local v = r - (ap - t.ab * k).Magnitude
		if v > best then
			best = v
		end
	end
	for _, c in f.chambers do
		local v = c.r - (q - c.c).Magnitude
		if v > best then
			best = v
		end
	end
	for _, c in f.caverns do
		local d = q - c.c
		local v = c.r - Vector3.new(d.X, d.Y / c.flat, d.Z).Magnitude
		if v > best then
			best = v
		end
	end
	-- pillars put rock back, but only inside their cavern's height
	for _, pl in f.pillars do
		if math.abs(q.Y - pl.y) < pl.h then
			local v = Vector2.new(q.X - pl.x, q.Z - pl.z).Magnitude - pl.r
			if v < best then
				best = v
			end
		end
	end
	return best
end

-- ============================================================ materials

local function biomeAt(p: Vector3): string
	local b = Cave.settings.biomes
	local n = math.noise(p.X * b.scale + Cave.settings.seed * 7.7, p.Y * b.scale * 0.5, p.Z * b.scale)
	if n > b.crystalAbove then
		return "crystal"
	elseif n < b.mushroomBelow then
		return "mushroom"
	end
	-- a second, separate map for the flooded bits, so they're not stuck between the other two
	local f = math.noise(p.X * b.scale - 31.4, p.Y * b.scale * 0.5 + Cave.settings.seed * 3.3, p.Z * b.scale + 12.9)
	if f > b.floodedAbove then
		return "flooded"
	end
	return "rock"
end
Cave.biomeAt = biomeAt

local function materialAt(p: Vector3, isFloor: boolean): Enum.Material
	local s = Cave.settings
	local o = s.seed * 31.7

	local biome = biomeAt(p)
	if biome == "crystal" then
		if isFloor then
			return Enum.Material.Salt
		end
		return if math.noise(p.X * 0.06, p.Y * 0.06, p.Z * 0.06 + o) > 0.2 then Enum.Material.Glacier else Enum.Material.Basalt
	elseif biome == "mushroom" then
		return if isFloor then Enum.Material.LeafyGrass else Enum.Material.Mud
	elseif biome == "flooded" then
		return if isFloor then Enum.Material.Sand else Enum.Material.Cobblestone
	end

	if p.Y < s.lavaBelow and math.noise(p.X * 0.04, p.Y * 0.04 + o, p.Z * 0.04) > 0.3 then
		return Enum.Material.CrackedLava
	end
	if isFloor and p.Y > s.layers[#s.layers].at then
		return s.floor
	end
	if math.noise(p.X * 0.05 + o, p.Y * 0.08, p.Z * 0.05) > 0.32 then
		return s.patch
	end

	local y = p.Y + math.noise(p.X * 0.012, o, p.Z * 0.012) * 24
	local layer = s.layers[1]
	for _, l in s.layers do
		if y < l.at then
			layer = l
		end
	end
	-- every third band is the stripe material. the warp above keeps the stripes wavy
	if math.floor(y / s.bandThickness) % 3 == 0 then
		return layer.band
	end
	return layer.material
end

function Cave.applyColors()
	for material, color in Cave.settings.colors do
		terrain:SetMaterialColor(material, color)
	end
end

local function getEffect(class: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing then
		return existing
	end
	local effect = Instance.new(class)
	effect.Name = name
	effect.Parent = Lighting
	return effect
end

-- dark and warm underground, a bit of haze so tunnels fade out, bloom so lanterns glow
function Cave.applyLighting()
	Lighting.ClockTime = 0
	Lighting.Brightness = 0.4
	Lighting.Ambient = Color3.fromRGB(32, 30, 29)
	Lighting.OutdoorAmbient = Color3.fromRGB(22, 21, 21)
	Lighting.EnvironmentDiffuseScale = 0.15
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.GlobalShadows = true

	-- still, dark cave water for the puddles
	terrain.WaterColor = Color3.fromRGB(34, 64, 72)
	terrain.WaterTransparency = 0.55
	terrain.WaterReflectance = 0.35
	terrain.WaterWaveSize = 0
	terrain.WaterWaveSpeed = 0

	local atmosphere = getEffect("Atmosphere", "CaveAtmosphere") :: Atmosphere
	atmosphere.Density = 0.38
	atmosphere.Offset = 0
	atmosphere.Color = Color3.fromRGB(52, 48, 46)
	atmosphere.Decay = Color3.fromRGB(26, 24, 23)
	atmosphere.Glare = 0
	atmosphere.Haze = 1.5

	local bloom = getEffect("BloomEffect", "CaveBloom") :: BloomEffect
	bloom.Intensity = 0.7
	bloom.Size = 28
	bloom.Threshold = 0.9

	local grade = getEffect("ColorCorrectionEffect", "CaveColor") :: ColorCorrectionEffect
	grade.Contrast = 0.12
	grade.Saturation = -0.05
	grade.TintColor = Color3.fromRGB(255, 244, 232)
end

-- ============================================================ ores

local function pickOre(depth: number, rng: Random)
	for i = #Cave.settings.ores, 1, -1 do
		local ore = Cave.settings.ores[i]
		if depth < ore.below and rng:NextNumber() < ore.chance then
			return ore
		end
	end
	return nil
end

-- a clump of chunks stuck to the wall, poking out along the wall's normal
local function placeOre(ore, wall: Vector3, normal: Vector3, rng: Random)
	local model = Instance.new("Model")
	model.Name = ore.name
	model:SetAttribute("Ore", ore.name)

	-- any two directions across the wall
	local side = normal:Cross(if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis).Unit
	local up = normal:Cross(side)

	for _ = 1, rng:NextInteger(3, 6) do
		local part = Instance.new(if rng:NextNumber() < 0.4 then "WedgePart" else "Part")
		part.Name = ore.name
		part.Anchored = true
		part.Size = Vector3.new(rng:NextNumber(0.8, 2.2), rng:NextNumber(0.8, 2.6), rng:NextNumber(0.8, 2.2))
		local offset = side * rng:NextNumber(-1.5, 1.5) + up * rng:NextNumber(-1.5, 1.5)
		local pos = wall + offset + normal * rng:NextNumber(0, 0.8)
		-- lookAt breaks if you look straight along its up vector, so floors/ceilings need a different one
		part.CFrame = CFrame.lookAt(pos, pos + normal, if math.abs(normal.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis)
			* CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, 6.28))
		part.Color = ore.color
		part.Material = ore.material
		part:SetAttribute("Ore", ore.name)
		part.Parent = model
	end

	local detector = Instance.new("ClickDetector")
	detector.MaxActivationDistance = Cave.settings.mineReach
	detector.Parent = model

	local glow = Cave.settings.oreGlow[ore.name]
	local first = model:FindFirstChildWhichIsA("BasePart")
	if glow and first then
		local light = Instance.new("PointLight")
		light.Color = glow
		light.Range = 12
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = first
	end

	keep(model, "Ores")
end

-- where the wall actually is between a rock point and an air point, and which way it faces
local function wallBetween(rock: Vector3, open: Vector3): (Vector3, Vector3)
	local a, b = airness(rock), airness(rock + open * VOXEL)
	local t = math.clamp(a / (a - b), 0, 1)
	local wall = rock + open * VOXEL * t

	local e = 1
	local normal = Vector3.new(
		airness(wall + Vector3.xAxis * e) - airness(wall - Vector3.xAxis * e),
		airness(wall + Vector3.yAxis * e) - airness(wall - Vector3.yAxis * e),
		airness(wall + Vector3.zAxis * e) - airness(wall - Vector3.zAxis * e)
	)
	return wall, if normal.Magnitude > 0 then normal.Unit else open
end

local function safeLookAt(from: Vector3, dir: Vector3): CFrame
	return CFrame.lookAt(from, from + dir, if math.abs(dir.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis)
end

-- a spray of glowing crystals growing out of any surface
local function placeCrystal(wall: Vector3, normal: Vector3, rng: Random)
	local b = Cave.settings.biomes
	local color = b.crystalColors[rng:NextInteger(1, #b.crystalColors)]
	local side = normal:Cross(if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis).Unit
	local up = normal:Cross(side)

	local model = Instance.new("Model")
	model.Name = "Crystal"
	for _ = 1, rng:NextInteger(3, 6) do
		local len = rng:NextNumber(2.5, 7)
		local width = rng:NextNumber(0.5, 1.3)
		local dir = (normal + side * rng:NextNumber(-0.6, 0.6) + up * rng:NextNumber(-0.6, 0.6)).Unit
		local base = wall + side * rng:NextNumber(-1, 1) + up * rng:NextNumber(-1, 1) - normal * 0.5

		local part = Instance.new("Part")
		part.Name = "Shard"
		part.Anchored = true
		part.CanCollide = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = color
		part.Transparency = 0.15
		part.Size = Vector3.new(width, width, len)
		part.CFrame = safeLookAt(base + dir * len / 2, dir)
		part.Parent = model
	end

	if rng:NextNumber() < 0.4 then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 18
		light.Brightness = 1.4
		light.Shadows = false
		light.Parent = model:FindFirstChildWhichIsA("BasePart")
	end
	keep(model, "Decor")
end

-- a little clump of glowing mushrooms on a floor
local function placeMushroom(floor: Vector3, rng: Random)
	local b = Cave.settings.biomes
	local color = b.mushroomColors[rng:NextInteger(1, #b.mushroomColors)]
	local model = Instance.new("Model")
	model.Name = "Mushrooms"

	for _ = 1, rng:NextInteger(1, 4) do
		local height = rng:NextNumber(1.5, 5)
		local capRadius = rng:NextNumber(1.2, 3.2)
		local at = floor + Vector3.new(rng:NextNumber(-2, 2), -0.3, rng:NextNumber(-2, 2))
		-- cylinders lie along x, so turn them upright
		local upright = CFrame.Angles(0, 0, math.pi / 2)

		local stem = Instance.new("Part")
		stem.Name = "Stem"
		stem.Shape = Enum.PartType.Cylinder
		stem.Anchored = true
		stem.CanCollide = false
		stem.Material = Enum.Material.SmoothPlastic
		stem.Color = Color3.fromRGB(214, 208, 192)
		local thick = rng:NextNumber(0.5, 0.9)
		stem.Size = Vector3.new(height, thick, thick)
		stem.CFrame = CFrame.new(at + Vector3.new(0, height / 2, 0)) * upright
		stem.Parent = model

		local cap = Instance.new("Part")
		cap.Name = "Cap"
		cap.Shape = Enum.PartType.Cylinder
		cap.Anchored = true
		cap.CanCollide = false
		cap.CastShadow = false
		cap.Material = Enum.Material.Neon
		cap.Color = color
		cap.Size = Vector3.new(0.6, capRadius * 2, capRadius * 2)
		cap.CFrame = CFrame.new(at + Vector3.new(0, height, 0)) * upright
		cap.Parent = model
	end

	if rng:NextNumber() < 0.5 then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 16
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = model:FindFirstChild("Cap")
	end
	keep(model, "Decor")
end

-- flat glowing discs stuck to the wall
local function placeAlgae(wall: Vector3, normal: Vector3, rng: Random)
	local b = Cave.settings.biomes
	local color = b.algaeColors[rng:NextInteger(1, #b.algaeColors)]
	local side = normal:Cross(if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis).Unit
	local up = normal:Cross(side)

	local model = Instance.new("Model")
	model.Name = "Algae"
	for _ = 1, rng:NextInteger(2, 5) do
		local r = rng:NextNumber(0.6, 1.6)
		local pos = wall + side * rng:NextNumber(-1.5, 1.5) + up * rng:NextNumber(-1.5, 1.5) + normal * 0.1
		local part = Instance.new("Part")
		part.Name = "Patch"
		part.Shape = Enum.PartType.Cylinder
		part.Anchored = true
		part.CanCollide = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = color
		part.Transparency = 0.35
		part.Size = Vector3.new(0.12, r * 2, r * 2)
		-- cylinders point along x, turn that to face out of the wall
		part.CFrame = safeLookAt(pos, normal) * CFrame.Angles(0, math.pi / 2, 0)
		part.Parent = model
	end
	if rng:NextNumber() < 0.3 then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 12
		light.Brightness = 1
		light.Shadows = false
		light.Parent = model:FindFirstChildWhichIsA("BasePart")
	end
	keep(model, "Decor")
end

-- the colour of the rock at a point, so spikes and rubble match the wall they grow out of
local function rockColor(p: Vector3): Color3
	local ok, color = pcall(function()
		return terrain:GetMaterialColor(materialAt(p, false))
	end)
	return if ok then color else Color3.fromRGB(110, 104, 98)
end

-- stalactite (up = -y) or stalagmite (up = +y). tapering stack of blocks, each twisted a bit
local function placeSpike(base: Vector3, up: Vector3, color: Color3, rng: Random, solid: boolean)
	local len = rng:NextNumber(4, 10)
	local width = rng:NextNumber(1.2, 2.4)
	local segments = 4
	local spin = rng:NextNumber(0, math.pi)
	local sign = if up.Y < 0 then -1 else 1
	local axis = CFrame.new(base) * CFrame.Angles(rng:NextNumber(-0.12, 0.12), 0, rng:NextNumber(-0.12, 0.12))

	local model = Instance.new("Model")
	model.Name = if sign < 0 then "Stalactite" else "Stalagmite"
	for i = 0, segments - 1 do
		local h = len / segments
		local w = width * (1 - (i / segments) * 0.8)
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = solid
		part.Material = Enum.Material.Slate
		part.Color = color
		part.Size = Vector3.new(w, h + 0.2, w)
		-- starts 0.6 studs inside the rock so there's no gap where it meets the ceiling/floor
		part.CFrame = axis * CFrame.new(0, sign * (h * i + h / 2 - 0.6), 0) * CFrame.Angles(0, spin + i * 0.5, 0)
		part.Parent = model
	end
	keep(model, "Decor")
end

local function placeRubble(floor: Vector3, color: Color3, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Rubble"
	for _ = 1, rng:NextInteger(2, 5) do
		local size = Vector3.new(rng:NextNumber(0.5, 1.6), rng:NextNumber(0.4, 1.1), rng:NextNumber(0.5, 1.6))
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.Material = Enum.Material.Slate
		part.Color = color:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.25))
		part.Size = size
		part.CFrame = CFrame.new(floor + Vector3.new(rng:NextNumber(-2.5, 2.5), size.Y * 0.3, rng:NextNumber(-2.5, 2.5)))
			* CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28))
		part.Parent = model
	end
	keep(model, "Decor")
end

-- sinks a shallow disc of real terrain water into the floor
local function placePuddle(floor: Vector3, rng: Random)
	terrain:FillCylinder(CFrame.new(floor - Vector3.new(0, 0.8, 0)), 2, rng:NextNumber(3, 6), Enum.Material.Water)
end

-- a lantern hanging on a chain from the ceiling above a node. nodes are always open space
local function placeLantern(at: Vector3)
	local s = Cave.settings.lantern
	local top = at
	for _ = 1, 40 do
		if airness(top + Vector3.new(0, 1, 0)) < 0 then
			break
		end
		top += Vector3.new(0, 1, 0)
	end
	-- a bit higher than the node if there's room, otherwise it hangs in your face
	local pos = if (top - at).Y > 5 then top - Vector3.new(0, 4, 0) else at

	local model = Instance.new("Model")
	model.Name = "Lantern"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Anchored = true
	body.CanCollide = false
	body.Size = Vector3.new(0.9, 1.3, 0.9)
	body.CFrame = CFrame.new(pos)
	body.Material = Enum.Material.Neon
	body.Color = s.color
	body.Parent = model

	local chainLength = (top - pos).Y + 1
	if chainLength > 0.5 then
		local chain = Instance.new("Part")
		chain.Name = "Chain"
		chain.Anchored = true
		chain.CanCollide = false
		chain.Size = Vector3.new(0.15, chainLength, 0.15)
		chain.CFrame = CFrame.new(pos + Vector3.new(0, 0.65 + chainLength / 2 - 0.5, 0))
		chain.Material = Enum.Material.Metal
		chain.Color = Color3.fromRGB(40, 38, 36)
		chain.Parent = model
	end

	local light = Instance.new("PointLight")
	light.Color = s.color
	light.Brightness = s.brightness
	light.Range = s.range
	light.Shadows = true
	light.Parent = body

	keep(model, "Lanterns")
end

local DIRS = { Vector3.xAxis, -Vector3.xAxis, Vector3.yAxis, -Vector3.yAxis, Vector3.zAxis, -Vector3.zAxis }

-- ============================================================ chunks

function Cave.generateChunk(cx: number, cy: number, cz: number)
	local key = cx .. "," .. cy .. "," .. cz
	if done[key] then
		return
	end
	done[key] = true

	local s = Cave.settings
	local min = Vector3.new(cx, cy, cz) * SIZE
	if min.Y >= s.top then
		return
	end

	local objects = {}
	collecting = objects
	chunkObjects[key] = objects
	chunkCoords[key] = Vector3.new(cx, cy, cz)

	local materials = table.create(CHUNK)
	local occupancy = table.create(CHUNK)
	local air = table.create(CHUNK)

	for x = 1, CHUNK do
		materials[x], occupancy[x], air[x] = {}, {}, {}
		for y = 1, CHUNK do
			materials[x][y], occupancy[x][y], air[x][y] = {}, {}, {}
			for z = 1, CHUNK do
				local p = min + Vector3.new(x - 0.5, y - 0.5, z - 0.5) * VOXEL
				local occ = math.clamp(0.5 - airness(p) / VOXEL, 0, 1)
				air[x][y][z] = occ < 0.5
				occupancy[x][y][z] = occ
			end
		end
	end

	-- a single air voxel with rock on all six sides is a sealed pocket. pillars leave the odd one
	-- where they meet a cavern wall, so fill them back in. edges are skipped, the neighbour's unknown
	for x = 2, CHUNK - 1 do
		for y = 2, CHUNK - 1 do
			for z = 2, CHUNK - 1 do
				if air[x][y][z]
					and not (air[x + 1][y][z] or air[x - 1][y][z] or air[x][y + 1][z]
						or air[x][y - 1][z] or air[x][y][z + 1] or air[x][y][z - 1])
				then
					air[x][y][z] = false
					occupancy[x][y][z] = 1
				end
			end
		end
	end

	for x = 1, CHUNK do
		for y = 1, CHUNK do
			for z = 1, CHUNK do
				if occupancy[x][y][z] == 0 then
					materials[x][y][z] = Enum.Material.Air
				else
					local p = min + Vector3.new(x - 0.5, y - 0.5, z - 0.5) * VOXEL
					local isFloor = if y < CHUNK then air[x][y + 1][z] else false
					materials[x][y][z] = materialAt(p, isFloor)
				end
			end
		end
	end

	-- flooding: every layer has a flat water line. open space under it in a flooded area turns to
	-- water, but only if there's rock somewhere under that column. roblox water doesn't flow, so
	-- water over a drop into the chunk below would just hang in the air
	local level = (cy + s.biomes.waterLevel) * SIZE
	for x = 1, CHUNK do
		for z = 1, CHUNK do
			local under = min + Vector3.new((x - 0.5) * VOXEL, -VOXEL / 2, (z - 0.5) * VOXEL)
			local supported = not (air[x][1][z] and airness(under) > 0)
			for y = 1, CHUNK do
				local py = min.Y + (y - 0.5) * VOXEL
				if py >= level then
					break
				end
				if not air[x][y][z] then
					supported = true
				elseif supported then
					local p = Vector3.new(min.X + (x - 0.5) * VOXEL, py, min.Z + (z - 0.5) * VOXEL)
					if biomeAt(p) == "flooded" then
						materials[x][y][z] = Enum.Material.Water
						occupancy[x][y][z] = 1
					end
				end
			end
		end
	end

	terrain:WriteVoxels(Region3.new(min, min + Vector3.one * SIZE), VOXEL, materials, occupancy)

	-- put back any digging that happened here before the chunk was unloaded
	for _, d in digs do
		local c = d.at
		if c.X > min.X - d.r and c.X < min.X + SIZE + d.r
			and c.Y > min.Y - d.r and c.Y < min.Y + SIZE + d.r
			and c.Z > min.Z - d.r and c.Z < min.Z + SIZE + d.r
		then
			terrain:FillBall(c, d.r, Enum.Material.Air)
		end
	end

	-- crystal and mushroom caves light themselves, lanterns only in plain rock
	if hasNode(cy) then
		local node = nodeAt(cx, cy, cz)
		if biomeAt(node) == "rock" then
			placeLantern(node)
		end
	end

	-- ore on walls: rock voxels with air right next to them, placed on the real surface
	local rng = Random.new(s.seed * 1e6 + cx * 7919 + cy * 104729 + cz * 1299709)
	for x = 2, CHUNK - 1 do
		for y = 2, CHUNK - 1 do
			for z = 2, CHUNK - 1 do
				if not air[x][y][z] then
					local open: Vector3? = nil
					for _, d in DIRS do
						if air[x + d.X][y + d.Y][z + d.Z] then
							open = d
							break
						end
					end
					if open then
						local p = min + Vector3.new(x - 0.5, y - 0.5, z - 0.5) * VOXEL
						local ore = pickOre(p.Y, rng)
						if ore then
							local wall, normal = wallBetween(p, open)
							placeOre(ore, wall + normal * s.oreOffset, normal, rng)
							Cave.placed += 1
						else
							local biome = biomeAt(p)
							if biome == "crystal" and rng:NextNumber() < s.biomes.crystalChance then
								local wall, normal = wallBetween(p, open)
								placeCrystal(wall + normal * s.oreOffset * 0.5, normal, rng)
							elseif biome == "mushroom" and open == Vector3.yAxis and rng:NextNumber() < s.biomes.mushroomChance then
								local wall, normal = wallBetween(p, open)
								if normal.Y > 0.6 then
									placeMushroom(wall + normal * s.oreOffset, rng)
								end
							elseif biome == "flooded" and rng:NextNumber() < s.biomes.algaeChance then
								local wall, normal = wallBetween(p, open)
								placeAlgae(wall, normal, rng)
							elseif biome == "rock" and (open == Vector3.yAxis or open == -Vector3.yAxis) then
								local d = s.decor
								local roll = rng:NextNumber()
								if open == -Vector3.yAxis then
									if roll < d.stalactiteChance then
										local wall = wallBetween(p, open)
										placeSpike(wall, -Vector3.yAxis, rockColor(p), rng, false)
									end
								elseif roll < d.stalagmiteChance then
									local wall = wallBetween(p, open)
									placeSpike(wall, Vector3.yAxis, rockColor(p), rng, true)
								elseif roll < d.stalagmiteChance + d.rubbleChance then
									local wall = wallBetween(p, open)
									placeRubble(wall, rockColor(p), rng)
								elseif roll < d.stalagmiteChance + d.rubbleChance + d.puddleChance then
									local wall = wallBetween(p, open)
									placePuddle(wall, rng)
								end
							end
						end
					end
				end
			end
		end
	end	collecting = nil
end

-- nearest chunks first, so whatever you're walking into shows up before the ones behind you
function Cave.around(pos: Vector3)
	local r = Cave.settings.radius
	local cx, cy, cz = math.floor(pos.X / SIZE), math.floor(pos.Y / SIZE), math.floor(pos.Z / SIZE)
	local todo = {}
	for dy = -1, 1 do
		for dx = -r, r do
			for dz = -r, r do
				if not done[chunkKey(cx + dx, cy + dy, cz + dz)] then
					table.insert(todo, Vector3.new(dx, dy, dz))
				end
			end
		end
	end
	table.sort(todo, function(a, b)
		return a.Magnitude < b.Magnitude
	end)
	for _, d in todo do
		Cave.generateChunk(cx + d.X, cy + d.Y, cz + d.Z)
		task.wait()
	end
end

local function unloadChunk(key: string, c: Vector3)
	for _, model in chunkObjects[key] or {} do
		model:Destroy()
	end
	chunkObjects[key] = nil
	chunkCoords[key] = nil
	done[key] = nil
	terrain:FillBlock(CFrame.new(c * SIZE + Vector3.one * SIZE / 2), Vector3.one * SIZE, Enum.Material.Air)
end

-- clears chunks that are far from every player. the spawn room's chunks are never cleared
function Cave.unloadFar()
	local keepWithin = Cave.settings.radius + Cave.settings.unloadMargin
	local centers = {}
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local p = root.Position
			table.insert(centers, Vector3.new(math.floor(p.X / SIZE), math.floor(p.Y / SIZE), math.floor(p.Z / SIZE)))
		end
	end
	if #centers == 0 then
		return
	end
	for key, c in chunkCoords do
		if not pinned[key] then
			local near = false
			for _, p in centers do
				local d = c - p
				if math.max(math.abs(d.X), math.abs(d.Y), math.abs(d.Z)) <= keepWithin then
					near = true
					break
				end
			end
			if not near then
				unloadChunk(key, c)
			end
		end
	end
end

-- lights far from everyone switch off. broken ores keep theirs off
local function cullLights()
	local roots = {}
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			table.insert(roots, root.Position)
		end
	end
	local far = Cave.settings.lightDistance
	for light in lights do
		local part = light.Parent
		if part and part:IsA("BasePart") then
			local near = false
			for _, pos in roots do
				if (pos - part.Position).Magnitude < far then
					near = true
					break
				end
			end
			local owner = part.Parent
			light.Enabled = near and not (owner and owner:GetAttribute("Broken"))
		else
			lights[light] = nil
		end
	end
end

-- ============================================================ helpers

-- the node in the chunk you asked about is always inside a tunnel, so start there
function Cave.findSpawn(near: Vector3?): Vector3
	local c = near or Vector3.new(0, -40, 0)
	local cy = math.min(math.floor(c.Y / SIZE), math.floor(Cave.settings.top / SIZE) - 1)
	local node = nodeAt(math.floor(c.X / SIZE), cy, math.floor(c.Z / SIZE))
	-- drop to the floor
	local p = node
	for _ = 1, 20 do
		if airness(p - Vector3.new(0, 2, 0)) < 0 then
			break
		end
		p -= Vector3.new(0, 2, 0)
	end
	return p + Vector3.new(0, 3, 0)
end

-- for looking at it in edit mode, run from the command bar. puts the camera in a tunnel
function Cave.preview(center: Vector3?, radius: number?): Vector3
	local spot = Cave.findSpawn(center)
	local r = radius or 2
	Cave.applyColors()
	Cave.applyLighting()
	local cx, cy, cz = math.floor(spot.X / SIZE), math.floor(spot.Y / SIZE), math.floor(spot.Z / SIZE)
	for dy = -2, 1 do
		for dx = -r, r do
			for dz = -r, r do
				Cave.generateChunk(cx + dx, cy + dy, cz + dz)
			end
		end
	end
	if not RunService:IsRunning() then
		Workspace.CurrentCamera.CFrame = CFrame.lookAt(spot, spot + Vector3.new(1, 0, 0))
	end
	print(("cave: %d ores placed"):format(Cave.placed))
	return spot
end

-- caverns are rare, so this finds the nearest one, builds around it and (in edit mode) puts the camera inside
function Cave.findCavern(near: Vector3?): Vector3?
	local c = near or Vector3.zero
	local cx0, cz0 = math.floor(c.X / SIZE), math.floor(c.Z / SIZE)
	local topCy = math.floor(Cave.settings.top / SIZE) - 1
	for r = 0, 12 do
		for dx = -r, r do
			for dz = -r, r do
				if math.max(math.abs(dx), math.abs(dz)) == r then
					for cy = topCy, topCy - 3, -1 do
						local x, z = cx0 + dx, cz0 + dz
						if hash(x, cy, z, 10) < Cave.settings.cavernChance then
							local node = nodeAt(x, cy, z)
							Cave.preview(node, 2)
							if not RunService:IsRunning() then
								Workspace.CurrentCamera.CFrame = CFrame.lookAt(node, node + Vector3.new(1, -0.2, 0.5))
							end
							print("cave: cavern at", node)
							return node
						end
					end
				end
			end
		end
	end
	warn("cave: no cavern found nearby, try a different seed or raise cavernChance")
	return nil
end

-- jump to the nearest "crystal" / "mushroom" / "rock" area, builds around it and moves the camera there
function Cave.findBiome(name: string, near: Vector3?): Vector3?
	local c = near or Vector3.new(0, -60, 0)
	for r = 0, 1600, 32 do
		for i = 0, math.max(1, math.floor(r / 16)) - 1 do
			local angle = i / math.max(1, math.floor(r / 16)) * math.pi * 2
			local p = Vector3.new(c.X + math.cos(angle) * r, c.Y, c.Z + math.sin(angle) * r)
			if biomeAt(p) == name then
				local spot = Cave.preview(p, 2)
				print("cave:", name, "biome at", spot)
				return spot
			end
		end
	end
	warn("cave: no " .. name .. " biome found nearby, try another seed or change biomes.crystalAbove / mushroomBelow")
	return nil
end

-- a dug-out room with a plank floor, support beams, a lantern and a real SpawnLocation.
-- it sits on a node so the tunnels always connect to it. returns where players spawn
function Cave.buildSpawnRoom(center: Vector3?): CFrame
	local spot = Cave.preview(center, 2)
	local floorY = spot.Y - 3

	-- the spawn room's chunks never get unloaded
	local sx, sy, sz = math.floor(spot.X / SIZE), math.floor(spot.Y / SIZE), math.floor(spot.Z / SIZE)
	for dx = -1, 1 do
		for dy = -1, 1 do
			for dz = -1, 1 do
				pinned[chunkKey(sx + dx, sy + dy, sz + dz)] = true
			end
		end
	end
	local size = Vector3.new(40, 16, 40)
	local middle = Vector3.new(spot.X, floorY + size.Y / 2, spot.Z)

	-- dig from a bit under the floor, otherwise the terrain smoothing creeps up over the planks.
	-- then a flattened dome on top so it's not a shoebox
	terrain:FillBlock(CFrame.new(middle - Vector3.new(0, 1, 0)), size + Vector3.new(0, 2, 0), Enum.Material.Air)
	terrain:FillBall(Vector3.new(spot.X, floorY + size.Y - 4, spot.Z), size.X * 0.6, Enum.Material.Air)

	-- anything generated inside the room would be floating now
	local half = size / 2 + Vector3.new(size.X * 0.2, size.Y, size.Z * 0.2)
	for _, folder in { getOreFolder(), getFolder("Lanterns"), getFolder("Decor") } do
		for _, model in folder:GetChildren() do
			if model:IsA("Model") then
				local offset = model:GetPivot().Position - middle
				if math.abs(offset.X) < half.X and math.abs(offset.Y) < half.Y and math.abs(offset.Z) < half.Z then
					model:Destroy()
				end
			end
		end
	end

	local old = Workspace:FindFirstChild("SpawnRoom")
	if old then
		old:Destroy()
	end
	local room = Instance.new("Model")
	room.Name = "SpawnRoom"

	local wood = Color3.fromRGB(110, 78, 50)
	local function block(name: string, partSize: Vector3, cframe: CFrame, material: Enum.Material, color: Color3)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.Size = partSize
		part.CFrame = cframe
		part.Material = material
		part.Color = color
		part.Parent = room
		return part
	end

	block("Floor", Vector3.new(size.X, 2, size.Z), CFrame.new(spot.X, floorY - 1, spot.Z), Enum.Material.WoodPlanks, wood)

	-- four posts and beams across the ceiling, like a propped-up mine room
	local postHeight = 12
	for _, corner in { Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1) } do
		local at = Vector3.new(spot.X + corner.X * (size.X / 2 - 1.5), floorY + postHeight / 2, spot.Z + corner.Z * (size.Z / 2 - 1.5))
		block("Post", Vector3.new(1.2, postHeight, 1.2), CFrame.new(at), Enum.Material.Wood, wood)
	end
	for _, sign in { 1, -1 } do
		local z = spot.Z + sign * (size.Z / 2 - 1.5)
		block("Beam", Vector3.new(size.X - 1, 1.2, 1.2), CFrame.new(spot.X, floorY + postHeight, z), Enum.Material.Wood, wood)
	end

	local pad = Instance.new("SpawnLocation")
	pad.Name = "CaveSpawn"
	pad.Anchored = true
	pad.Neutral = true
	pad.Duration = 0
	pad.Size = Vector3.new(6, 0.4, 6)
	pad.CFrame = CFrame.new(spot.X, floorY + 0.2, spot.Z)
	pad.Material = Enum.Material.Slate
	pad.Color = Color3.fromRGB(70, 62, 56)
	pad.Parent = room

	local light = Instance.new("PointLight")
	light.Color = Cave.settings.lantern.color
	light.Brightness = 2
	light.Range = 30
	light.Shadows = true
	light.Parent = block("Lamp", Vector3.new(1.2, 1.2, 1.2), CFrame.new(spot.X, floorY + postHeight - 1.2, spot.Z), Enum.Material.Neon, Cave.settings.lantern.color)

	room.Parent = Workspace

	-- only spawn in the mine
	for _, other in Workspace:GetDescendants() do
		if other:IsA("SpawnLocation") and other ~= pad then
			other.Enabled = false
		end
	end

	return pad.CFrame + Vector3.new(0, 3, 0)
end

-- does the terrain roblox built match what the code thinks is rock/air?
function Cave.check()
	local spot = Cave.findSpawn()
	local rng = Random.new(1)
	local same, total = 0, 0
	for _ = 1, 300 do
		local p = spot + Vector3.new(rng:NextNumber(-100, 100), rng:NextNumber(-60, 30), rng:NextNumber(-100, 100))
		if p.Y < Cave.settings.top then
			local cell = Vector3.new(math.floor(p.X / VOXEL), math.floor(p.Y / VOXEL), math.floor(p.Z / VOXEL)) * VOXEL
			local _, occ = terrain:ReadVoxels(Region3.new(cell, cell + Vector3.one * VOXEL), VOXEL)
			total += 1
			if (airness(cell + Vector3.one * VOXEL / 2) > 0) == (occ[1][1][1] < 0.5) then
				same += 1
			end
		end
	end
	print(("cave check: terrain matches the code at %d of %d points"):format(same, total))
end

-- run in PLAY mode (raycasts don't see fresh terrain in edit mode). fires rays at the walls
-- from the spawn and compares where roblox's wall really is with where the code thinks it is
function Cave.measure()
	local spot = Cave.findSpawn()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { terrain }
	local rng = Random.new(2)
	local sum, n = 0, 0
	for _ = 1, 60 do
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.6, 0.6), rng:NextNumber(-1, 1))
		if dir.Magnitude > 0.1 then
			local hit = Workspace:Raycast(spot, dir.Unit * 80, params)
			if hit then
				-- airness at roblox's wall: 0 = same place, positive = roblox's wall is further into the tunnel
				sum += airness(hit.Position)
				n += 1
			end
		end
	end
	if n == 0 then
		print("cave measure: no rays hit anything, are you in play mode?")
	else
		print(("cave measure: %d rays hit. roblox's wall is %.2f studs %s the code's wall"):format(
			n, math.abs(sum / n), if sum > 0 then "in front of (into the tunnel from)" else "behind"))
		print(("cave measure: set oreOffset = %.1f"):format(math.max(0, sum / n)))
	end
end

function Cave.clear()
	terrain:Clear()
	getOreFolder():ClearAllChildren()
	getFolder("Lanterns"):ClearAllChildren()
	getFolder("Decor"):ClearAllChildren()
	table.clear(done)
	table.clear(chunkObjects)
	table.clear(chunkCoords)
	table.clear(pinned)
	table.clear(digs)
	table.clear(lights)
	table.clear(featureCache)
	Cave.placed = 0
end

-- ============================================================ mining

local lastHit: { [Player]: number } = {}
local homes: { [BasePart]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local hooked: { [ClickDetector]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function oreDef(name: string?)
	for _, ore in Cave.settings.ores do
		if ore.name == name then
			return ore
		end
	end
	return nil
end

local function oreParts(model: Model): { BasePart }
	local parts = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
	return parts
end

local function setVisible(model: Model, visible: boolean)
	for _, part in oreParts(model) do
		part.Transparency = if visible then 0 else 1
		part.CanCollide = visible
		part.CanQuery = visible
		local light = part:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = visible
		end
	end
	local detector = model:FindFirstChildOfClass("ClickDetector")
	if detector then
		detector.MaxActivationDistance = if visible then Cave.settings.mineReach else 0
	end
end

local function chips(model: Model, color: Color3)
	local first = oreParts(model)[1]
	if not first then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new(0.35, 0)
	emitter.Speed = NumberRange.new(8, 14)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Acceleration = Vector3.new(0, -50, 0)
	emitter.EmissionDirection = Enum.NormalId.Front -- ores face out of the wall, so chips fly into the tunnel
	emitter.Rate = 0
	emitter.Parent = first
	emitter:Emit(10)
	Debris:AddItem(emitter, 1)
end

local function shake(model: Model)
	for _, part in oreParts(model) do
		local home = homes[part] or part.CFrame
		homes[part] = home
		local nudge = CFrame.new(math.random() * 0.3 - 0.15, math.random() * 0.3 - 0.15, math.random() * 0.3 - 0.15)
		part.CFrame = home
		TweenService:Create(part, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { CFrame = home * nudge }):Play()
	end
end

-- bits of the ore fly out into the tunnel and disappear
local function shatter(model: Model)
	for _, part in oreParts(model) do
		for _ = 1, 2 do
			local bit = Instance.new("Part")
			bit.Size = part.Size * 0.45
			bit.CFrame = part.CFrame * CFrame.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
			bit.Color = part.Color
			bit.Material = part.Material
			bit.Anchored = false
			bit.CanCollide = true
			bit.AssemblyLinearVelocity = part.CFrame.LookVector * 12 + Vector3.new(math.random() * 8 - 4, 10, math.random() * 8 - 4)
			bit.Parent = Workspace
			Debris:AddItem(bit, 2)
		end
	end
end

-- is anyone standing where this ore would grow back?
local function someoneInTheWay(model: Model): boolean
	local characters = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(characters, player.Character)
		end
	end
	if #characters == 0 then
		return false
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = characters
	local cf, size = model:GetBoundingBox()
	return #Workspace:GetPartBoundsInBox(cf, size + Vector3.one * 2, params) > 0
end

-- respawn = grow back later. dug-out ores don't, the rock they grew on is gone
local function breakOre(player: Player, model: Model, respawn: boolean)
	local def = oreDef(model:GetAttribute("Ore"))
	if not def then
		return
	end
	model:SetAttribute("Broken", true)
	model:SetAttribute("HP", nil)
	shatter(model)

	local stats = player:FindFirstChild("leaderstats")
	local count = stats and stats:FindFirstChild(def.name) :: IntValue?
	if count then
		count.Value += 1
	end

	if not respawn then
		model:Destroy()
		return
	end
	setVisible(model, false)
	task.delay(def.respawn, function()
		-- don't grow back inside somebody, wait for them to move
		while model.Parent and someoneInTheWay(model) do
			task.wait(2)
		end
		if model.Parent then
			setVisible(model, true)
			model:SetAttribute("Broken", nil)
		end
	end)
end

local function onMine(player: Player, model: Model)
	local def = oreDef(model:GetAttribute("Ore"))
	if not def or model:GetAttribute("Broken") then
		return
	end
	local now = os.clock()
	if now - (lastHit[player] or 0) < Cave.settings.mineCooldown then
		return
	end
	lastHit[player] = now

	chips(model, def.color)
	local hp = (model:GetAttribute("HP") or def.hits) - 1
	if hp > 0 then
		model:SetAttribute("HP", hp)
		shake(model)
		return
	end

	breakOre(player, model, true)
end

local function hook(detector: Instance)
	if not detector:IsA("ClickDetector") or hooked[detector] then
		return
	end
	hooked[detector] = true
	detector.MouseClick:Connect(function(player)
		local model = detector.Parent
		if model and model:IsA("Model") then
			onMine(player, model)
		end
	end)
end

-- ============================================================ saving ore counts

local oreStore: DataStore? = nil
local storeWarned = false

local function getStore(): DataStore?
	if oreStore then
		return oreStore
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("CaveOres")
	end)
	if ok then
		oreStore = result
		return result
	end
	if not storeWarned then
		storeWarned = true
		warn("cave: can't save ore counts. publish the place and turn on Studio Access to API Services (Game Settings > Security)")
	end
	return nil
end

local function saveStats(player: Player)
	-- if loading failed, saving now would overwrite their real counts with zeros
	if not player:GetAttribute("OresLoaded") then
		return
	end
	local stats = player:FindFirstChild("leaderstats")
	local store = getStore()
	if not stats or not store then
		return
	end
	local data = {}
	for _, v in stats:GetChildren() do
		if v:IsA("IntValue") then
			data[v.Name] = v.Value
		end
	end
	local ok, err = pcall(function()
		store:SetAsync("player_" .. player.UserId, data)
	end)
	if not ok then
		warn("cave: couldn't save ores for", player.Name, err)
	end
end

local function loadStats(player: Player, stats: Folder)
	local store = getStore()
	if not store then
		return
	end
	local ok, data = pcall(function()
		return store:GetAsync("player_" .. player.UserId)
	end)
	if not ok then
		warn("cave: couldn't load ores for", player.Name, data)
		return
	end
	if type(data) == "table" then
		for name, n in data do
			local value = stats:FindFirstChild(name)
			-- added, not set: anything mined while this was loading still counts
			if value and value:IsA("IntValue") and type(n) == "number" then
				value.Value += n
			end
		end
	end
	player:SetAttribute("OresLoaded", true)
end

local function giveStats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	for _, ore in Cave.settings.ores do
		local value = Instance.new("IntValue")
		value.Name = ore.name
		value.Parent = stats
	end
	stats.Parent = player
	task.spawn(loadStats, player, stats)
end

function Cave.enableMining()
	local folder = getOreFolder()
	for _, d in folder:GetDescendants() do
		hook(d)
	end
	folder.DescendantAdded:Connect(hook)

	for _, player in Players:GetPlayers() do
		giveStats(player)
	end
	Players.PlayerAdded:Connect(giveStats)
	Players.PlayerRemoving:Connect(function(player)
		lastHit[player] = nil
		saveStats(player)
	end)

	-- autosave, and save everyone if the server shuts down
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				task.spawn(saveStats, player)
			end
		end
	end)
	game:BindToClose(function()
		local left = #Players:GetPlayers()
		for _, player in Players:GetPlayers() do
			task.spawn(function()
				saveStats(player)
				left -= 1
			end)
		end
		local waited = 0
		while left > 0 and waited < 20 do
			waited += task.wait(0.2)
		end
	end)
end

-- ============================================================ digging

local lastDig: { [Player]: number } = {}

local function dust(at: Vector3)
	local cell = Vector3.new(math.floor(at.X / VOXEL), math.floor(at.Y / VOXEL), math.floor(at.Z / VOXEL)) * VOXEL
	local mats = terrain:ReadVoxels(Region3.new(cell, cell + Vector3.one * VOXEL), VOXEL)
	local ok, color = pcall(function()
		return terrain:GetMaterialColor(mats[1][1][1])
	end)

	local puff = Instance.new("Part")
	puff.Anchored = true
	puff.CanCollide = false
	puff.CanQuery = false
	puff.Transparency = 1
	puff.Size = Vector3.one
	puff.CFrame = CFrame.new(at)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(if ok then color else Color3.fromRGB(120, 110, 100))
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.3, 0.7)
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.Rate = 0
	emitter.Parent = puff
	puff.Parent = Workspace
	emitter:Emit(14)
	Debris:AddItem(puff, 1)
end

-- anything the dig took the rock out from under: ores count as mined, everything else shatters
local function clearDugOut(player: Player, center: Vector3, radius: number)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { getOreFolder(), getFolder("Decor"), getFolder("Lanterns") }
	local seen: { [Instance]: boolean } = {}
	for _, part in Workspace:GetPartBoundsInRadius(center, radius, params) do
		local model = part.Parent
		if model and model:IsA("Model") and not seen[model] then
			seen[model] = true
			if model:GetAttribute("Ore") then
				if model:GetAttribute("Broken") then
					model:Destroy()
				else
					breakOre(player, model, false)
				end
			else
				shatter(model)
				model:Destroy()
			end
		end
	end
end

-- the client (Dig.client.luau) sends where you're pointing, the server decides if you're allowed
local function digAt(player: Player, at: Vector3)
	local s = Cave.settings
	local now = os.clock()
	if now - (lastDig[player] or 0) < s.digCooldown then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - at).Magnitude > s.digReach then
		return
	end
	if at.Y > s.top - 2 then
		return
	end
	lastDig[player] = now

	-- aim the bite a little into the wall, not centred on the surface
	local into = (at - root.Position).Unit
	dust(at - into)
	terrain:FillBall(at + into, s.digRadius, Enum.Material.Air)
	table.insert(digs, { at = at + into, r = s.digRadius })
	clearDugOut(player, at + into, s.digRadius + 1.5)
end

local function hitSound(at: Vector3)
	local id = Cave.settings.hitSound
	if id == "" then
		return
	end
	local spot = Instance.new("Attachment")
	spot.WorldPosition = at
	spot.Parent = terrain
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = 0.6
	sound.PlaybackSpeed = 0.9 + math.random() * 0.2
	sound.Parent = spot
	sound:Play()
	Debris:AddItem(spot, 2)
end

-- the pickaxe (Dig.client.luau) sends what it hit, the server decides if you're allowed
function Cave.enableDigging()
	local remote = ReplicatedStorage:FindFirstChild("CaveSwing") :: RemoteEvent?
	if not remote then
		local created = Instance.new("RemoteEvent")
		created.Name = "CaveSwing"
		created.Parent = ReplicatedStorage
		remote = created
	end

	(remote :: RemoteEvent).OnServerEvent:Connect(function(player, target, at)
		if typeof(at) ~= "Vector3" or typeof(target) ~= "Instance" then
			return
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (root.Position - at).Magnitude > Cave.settings.digReach then
			return
		end
		if target == terrain then
			digAt(player, at)
			hitSound(at)
		elseif target:IsA("BasePart") and target:IsDescendantOf(getOreFolder()) then
			local model = target.Parent
			if model and model:IsA("Model") then
				onMine(player, model)
				hitSound(at)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastDig[player] = nil
	end)
end

-- ============================================================ pickaxe

local function makePickaxe(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Pickaxe"
	tool.CanBeDropped = false
	-- grip frame's +z points behind you, so the hand holds the +z end and the head sits out at -z
	tool.Grip = CFrame.new(0, 0, 1.5)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 0.3, 4)
	handle.Material = Enum.Material.Wood
	handle.Color = Color3.fromRGB(110, 78, 50)
	handle.CanCollide = false
	handle.Massless = true
	handle.CFrame = CFrame.new()
	handle.Parent = tool

	-- the head sits across the far end of the handle
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(0.45, 3.2, 0.5)
	head.Material = Enum.Material.Metal
	head.Color = Color3.fromRGB(132, 132, 140)
	head.CanCollide = false
	head.Massless = true
	head.CFrame = CFrame.new(0, 0, -1.8)
	head.Parent = tool

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = head

	return tool
end

-- everyone gets a pickaxe, including after they respawn
function Cave.enablePickaxe()
	local StarterPack = game:GetService("StarterPack")
	if not StarterPack:FindFirstChild("Pickaxe") then
		makePickaxe().Parent = StarterPack
	end
	for _, player in Players:GetPlayers() do
		local backpack = player:FindFirstChildOfClass("Backpack")
		local holding = player.Character and player.Character:FindFirstChild("Pickaxe")
		if backpack and not backpack:FindFirstChild("Pickaxe") and not holding then
			makePickaxe().Parent = backpack
		end
	end
end

function Cave.start()
	Cave.applyColors()
	Cave.applyLighting()
	Cave.enableMining()
	Cave.enableDigging()
	Cave.enablePickaxe()

	task.spawn(function()
		while true do
			task.wait(3)
			Cave.unloadFar()
		end
	end)
	task.spawn(function()
		while true do
			cullLights()
			task.wait(0.5)
		end
	end)
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					Cave.around(root.Position)
				end
			end
			task.wait(0.5)
		end
	end)
end

return Cave
