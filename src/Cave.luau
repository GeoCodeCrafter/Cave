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
	tunnelRadius = 9,
	-- galleries: a slow noise field that opens stretches of passage right out, so it reads as caves
	-- and not tunnels. it only adds width round the same network, so everything still connects
	galleryWiden = 20, -- extra studs of radius where the field is strongest
	galleryScale = 0.012, -- smaller = longer galleries
	-- rooms partway along passages, irregular, so a passage opens out before the next junction
	roomChance = 0.45, -- per passage
	roomRadius = 15,
	wiggle = 12, -- how far tunnels bend away from a straight line
	bend = 0.013, -- how tight the bends are. much above 0.02 and tunnels tear into separate pockets
	minRadius = 5.5, -- too thin and the terrain grid breaks tunnels apart
	chamberChance = 0.65, -- per node
	chamberRadius = 26,
	cavernChance = 0.2, -- per junction with 3+ tunnels, a huge flattened dome with rock pillars instead of a chamber
	cavernRadius = 46,
	cavernFlatten = 0.55, -- height compared to width
	-- chasms: long deep ravines through several layers, with rope bridges where tunnels meet them
	chasmCell = 320, -- studs, at most one chasm per cell this size
	chasmChance = 0.45,
	chasmLength = 220,
	chasmDepth = 170,
	chasmWidth = 30, -- across the top, narrows towards the bottom
	-- underground rivers: winding channels from one junction down to another, with real water
	riverCell = 384, -- studs, at most one river per cell this size
	riverChance = 0.6,
	riverWidth = 10, -- 14 filled the whole passage, it looked like a flood not a river
	riverClearance = 9, -- headroom above the riverbed
	riverDepth = 2.5, -- how deep the water is
	-- sinkholes: round shafts from the surface down through several layers, with a spiral ledge
	shaftCell = 288, -- studs, at most one shaft per cell this size
	shaftChance = 0.35,
	shaftRadius = 13,
	shaftDepth = 170,
	ledgeWidth = 6, -- the spiral shelf running round the inside wall
	ledgePitch = 28, -- studs it drops per full turn. 28 on a 13 stud shaft is about a 20 degree slope
	ledgeThickness = 4.5,
	-- lava tubes: long smooth round tunnels deep down, with a glowing cracked-lava floor
	tubeCell = 352, -- studs, at most one tube per cell this size
	tubeChance = 0.5,
	tubeRadius = 8,
	-- geodes: hollow crystal-lined balls sealed in solid rock, you have to dig to find them
	geodeCell = 160, -- studs, at most one geode per cube this size
	geodeChance = 0.35,
	geodeRadius = 8,
	-- the surface: rolling hills over the top of the mine, with cave mouths coming out of them
	surface = {
		height = 16, -- average ground height above top
		hills = 20, -- how far it rises and falls
		entranceCell = 256, -- studs, at most one cave mouth per cell this size
		entranceChance = 0.7,
		entranceRadius = 7,
		entranceRun = 110, -- studs sideways from the junction to the mouth. about a 25 degree walk
		-- skylights: narrow cracks from the roof of a big space near the top up to the grass, so
		-- daylight falls into the caves
		skylightCell = 160, -- studs, at most one per square this size
		skylightChance = 0.45,
		skylightRadius = 2.5,
	},
	-- layout: each region of chunks gets a random tree of tunnels, then a few extra links on top
	regionSize = 4, -- chunks per side
	loopChance = 0.12, -- a link the tree didn't use gets dug anyway, which makes a loop
	diagChance = 0.04, -- the odd diagonal shortcut
	crossChance = 0.15, -- regions always join their east and south neighbour once, sometimes more
	rampsPerRegion = 1, -- sloped tunnels down to the level below
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
		-- the crystal cave floor. it was a pale lilac (176, 166, 196) and any light, your lamp or the
		-- crystals' own, bleached it white. deep violet lets the glowing crystals stand out instead
		[Enum.Material.Salt] = Color3.fromRGB(72, 58, 104),
		[Enum.Material.Glacier] = Color3.fromRGB(116, 104, 176),
		-- mushroom biome
		[Enum.Material.Mud] = Color3.fromRGB(58, 50, 46),
		[Enum.Material.LeafyGrass] = Color3.fromRGB(38, 72, 64),
		-- tide pool biome
		[Enum.Material.Cobblestone] = Color3.fromRGB(92, 90, 86),
		[Enum.Material.Sand] = Color3.fromRGB(150, 140, 118),
		-- the surface
		[Enum.Material.Grass] = Color3.fromRGB(70, 96, 52),
		-- flowstone: the pale mineral crust left by dripping water
		[Enum.Material.Snow] = Color3.fromRGB(190, 176, 150),
	},
	-- water that collects in the dips in the floor, and the mineral it leaves behind
	pools = {
		maxCells = 40, -- bigger than this and it's not a dip, it's a flat floor with a gap in it
		flowstone = Enum.Material.Snow,
		streaks = 0.42, -- higher = fewer mineral streaks down the walls
	},
	-- plain rock areas only, chances per ceiling/floor voxel
	decor = {
		stalactiteChance = 0.05,
		stalagmiteChance = 0.015,
		rubbleChance = 0.03,
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
		-- tide pool caves come out of the plain rock. higher = fewer
		poolsAbove = 0.15,
		poolChance = 0.03, -- per flat floor voxel
		poolColors = { Color3.fromRGB(255, 110, 170), Color3.fromRGB(255, 150, 70), Color3.fromRGB(70, 230, 210) },
		algaeChance = 0.015, -- per wall voxel
		algaeColors = { Color3.fromRGB(80, 255, 170), Color3.fromRGB(60, 220, 255) },
	},
	radius = 2, -- chunks around each player
	surfaceRadius = 10, -- the ground layer loads much further out, you can see a long way up there
	unloadMargin = 2, -- chunks past radius before a chunk gets cleared away
	lightDistance = 110, -- lights further than this from every player switch off
	-- studs to push ore out of the wall. was 2 back when walls were smooth tubes, but on the rough
	-- walls that shoved about 1 clump in 10 off a bump into thin air. measured over 703 clumps:
	-- 2 = 68 floating, 1 = 14, 0.5 = 2, and none buried at any of them
	oreOffset = 0.5,
	lantern = { color = Color3.fromRGB(255, 206, 158), brightness = 1.6, range = 36 },
	glowwormChance = 0.3, -- per big-space ceiling voxel. tiny blue lights and hanging threads
	glowwormColor = Color3.fromRGB(120, 205, 255),
	-- big open spaces light themselves (lanterns only hang at junctions, and a gallery swallows your lamp)
	bigSpace = 11, -- studs of open air 10 studs out from a surface before it counts as a big space
	fungusChance = 0.02, -- per big-space wall voxel, a cluster of glowing shelf fungus with its own light
	fungusColors = { Color3.fromRGB(255, 170, 70), Color3.fromRGB(120, 255, 190), Color3.fromRGB(190, 140, 255) },
	roughness = 2.2, -- studs of bumps on the cave walls. 0 = smooth tubes
	outcropChance = 0.03, -- per rock voxel on a surface, a slab of textured rock set into it
	floorSquash = 1.7, -- how much flatter the floor is than the ceiling. 1 = round tubes
	boulderChance = 0.012, -- per floor voxel, half-buried boulders
	-- custom rock textures: base material name = MaterialVariant name (the variants live in
	-- MaterialService). anything not listed keeps roblox's own look
	textures = {
		Rock = "CaveRock",
		Slate = "CaveRock_Slate",
		-- the top layers are sandstone and limestone, so without these you'd barely see it near spawn
		Sandstone = "CaveRock_Sandstone",
		Limestone = "CaveRock_Limestone",
	} :: { [string]: string },
	dark = true, -- pitch black away from lights, your helmet lamp does the rest
	lamp = { range = 45, angle = 60, brightness = 2.4, color = Color3.fromRGB(255, 236, 205) },
	flare = { cooldown = 1.5, burn = 20, maxEach = 5, speed = 55, color = Color3.fromRGB(255, 90, 60) },
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
Cave.pools = 0
Cave.bridges = 0

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
	every chunk has one node somewhere inside it. the chunks are grouped into regions (4x4 on each
	level) and each region gets a random spanning tree over its nodes: every node is reachable, but
	the branches end in real dead ends. then a few links the tree skipped get dug anyway to make
	loops, each region joins its east and south neighbour at least once, and a couple of ramps go
	down to the level below. so it's all still one connected network, just not a grid any more.
	nodes where 4+ tunnels meet are hubs and always get a chamber, the big caverns only go on busy
	junctions, and dead ends sometimes finish in a small pocket.
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

-- how high the ground is here. two layers of hills plus a little lumpiness, never less than 6 studs
-- above the top of the mine so there's always a roof over the first level
local function surfaceHeight(x: number, z: number): number
	local s = Cave.settings
	local o = s.seed * 5.31
	local hills = math.noise(x * 0.009 + 0.5, o, z * 0.009 + 0.5) * 0.7 + math.noise(x * 0.025 + o, 0.5, z * 0.025) * 0.3
	local h = s.surface.height + hills * s.surface.hills * 1.6 + math.noise(x * 0.04, o + 3.7, z * 0.04) * 2
	return s.top + math.max(6, h)
end
Cave.surfaceHeight = surfaceHeight

-- links go from a node to one of these: east, south, diagonal, ramp down east, ramp down south
local STEP = {
	Vector3.new(1, 0, 0),
	Vector3.new(0, 0, 1),
	Vector3.new(1, 0, 1),
	Vector3.new(1, -1, 0),
	Vector3.new(0, -1, 1),
}
local layoutCache: { [string]: { [string]: boolean } } = {}

-- every link whose first node is in this region, as "x,z,dir" = true
local function regionLinks(rx: number, y: number, rz: number): { [string]: boolean }
	local s = Cave.settings
	local key = s.seed .. ":" .. rx .. "," .. y .. "," .. rz
	local got = layoutCache[key]
	if got then
		return got
	end
	local n = s.regionSize
	local x0, z0 = rx * n, rz * n
	local links: { [string]: boolean } = {}
	local function add(x: number, z: number, d: number)
		links[x .. "," .. z .. "," .. d] = true
	end

	-- random spanning tree: every inside link gets a random weight, take them lightest first and
	-- keep each one that joins two bits that weren't joined yet (kruskal). the rest might be loops
	local parent = {}
	for i = 1, n * n do
		parent[i] = i
	end
	local function root(i: number): number
		while parent[i] ~= i do
			parent[i] = parent[parent[i]]
			i = parent[i]
		end
		return i
	end
	local function id(x: number, z: number): number
		return (x - x0) + (z - z0) * n + 1
	end
	local edges = {}
	for x = x0, x0 + n - 1 do
		for z = z0, z0 + n - 1 do
			if x < x0 + n - 1 then
				table.insert(edges, { x = x, z = z, d = 1, w = hash(x, y, z, 200) })
			end
			if z < z0 + n - 1 then
				table.insert(edges, { x = x, z = z, d = 2, w = hash(x, y, z, 201) })
			end
		end
	end
	table.sort(edges, function(a, b)
		return a.w < b.w
	end)
	for _, e in edges do
		local a = root(id(e.x, e.z))
		local b = root(if e.d == 1 then id(e.x + 1, e.z) else id(e.x, e.z + 1))
		if a ~= b then
			parent[a] = b
			add(e.x, e.z, e.d)
		elseif hash(e.x, y, e.z, 202 + e.d) < s.loopChance then
			add(e.x, e.z, e.d)
		end
	end

	for x = x0, x0 + n - 2 do
		for z = z0, z0 + n - 2 do
			if hash(x, y, z, 205) < s.diagChance then
				add(x, z, 3)
			end
		end
	end

	-- join the neighbours: one crossing always, the others sometimes
	local pickE = math.floor(hash(rx, y, rz, 206) * n)
	local pickS = math.floor(hash(rx, y, rz, 207) * n)
	for i = 0, n - 1 do
		if i == pickE or hash(x0 + n - 1, y, z0 + i, 208) < s.crossChance then
			add(x0 + n - 1, z0 + i, 1)
		end
		if i == pickS or hash(x0 + i, y, z0 + n - 1, 209) < s.crossChance then
			add(x0 + i, z0 + n - 1, 2)
		end
	end

	-- ramps down, at least one so every level joins the one below
	for i = 1, math.max(1, s.rampsPerRegion) do
		local x = x0 + math.floor(hash(rx, y, rz, 210 + i) * n)
		local z = z0 + math.floor(hash(rx, y, rz, 220 + i) * n)
		add(x, z, if hash(rx, y, rz, 230 + i) < 0.5 then 4 else 5)
	end

	layoutCache[key] = links
	return links
end

local function hasLink(x: number, y: number, z: number, d: number): boolean
	if not hasNode(y) then
		return false
	end
	local n = Cave.settings.regionSize
	return regionLinks(math.floor(x / n), y, math.floor(z / n))[x .. "," .. z .. "," .. d] == true
end

-- the grid coordinates of every node this one has a tunnel to, both ways
local function linkedTo(x: number, y: number, z: number): { Vector3 }
	local out = {}
	local here = Vector3.new(x, y, z)
	for d, step in STEP do
		if hasLink(x, y, z, d) then
			table.insert(out, here + step)
		end
		local from = here - step
		if hasLink(from.X, from.Y, from.Z, d) then
			table.insert(out, from)
		end
	end
	return out
end

-- what goes at a node, from how many tunnels meet there
local function nodeKind(x: number, y: number, z: number): string
	local s = Cave.settings
	local links = #linkedTo(x, y, z)
	if links >= 3 and hash(x, y, z, 10) < s.cavernChance then
		return "cavern"
	elseif links >= 4 then
		return "hub"
	elseif links == 1 then
		return if hash(x, y, z, 6) < 0.5 then "pocket" else "end"
	elseif hash(x, y, z, 6) < s.chamberChance * (if links == 3 then 1 else 0.4) then
		return "chamber"
	end
	return "tunnel"
end

-- the lava tube that starts in this big grid cell, if there is one. it runs between two junctions
-- several chunks apart down in the deep layers. the actual curve is worked out later in tubePath
local function tubeForCell(gx: number, gz: number)
	local s = Cave.settings
	if hash(gx, 7373, gz, 90) >= s.tubeChance then
		return nil
	end
	local cell = s.tubeCell
	local cx = math.floor((gx + 0.3 + hash(gx, 7373, gz, 91) * 0.4) * cell / SIZE)
	local cz = math.floor((gz + 0.3 + hash(gx, 7373, gz, 92) * 0.4) * cell / SIZE)
	local cy = math.floor(s.top / SIZE) - 5 - math.floor(hash(gx, 7373, gz, 93) * 2)
	if not hasNode(cy) then
		return nil
	end
	local dx = (if hash(gx, 7373, gz, 94) < 0.5 then -1 else 1) * (6 + math.floor(hash(gx, 7373, gz, 95) * 4))
	local dz = (if hash(gx, 7373, gz, 96) < 0.5 then -1 else 1) * math.floor(hash(gx, 7373, gz, 97) * 3)
	return {
		a = nodeAt(cx, cy, cz),
		b = nodeAt(cx + dx, cy, cz + dz),
		r = s.tubeRadius * (0.85 + hash(gx, 7373, gz, 98) * 0.3),
		amp = 14 + hash(gx, 7373, gz, 99) * 16,
		phase = hash(gx, 7373, gz, 100) * math.pi * 2,
	}
end

-- the shaft in this big grid cell, if there is one. it's centred on a junction on the top layer, so
-- it's always joined to the tunnels, and it breaks through the surface as a sinkhole
local function shaftForCell(gx: number, gz: number)
	local s = Cave.settings
	if hash(gx, 9999, gz, 80) >= s.shaftChance then
		return nil
	end
	local cell = s.shaftCell
	local cx = math.floor((gx + 0.3 + hash(gx, 9999, gz, 81) * 0.4) * cell / SIZE)
	local cz = math.floor((gz + 0.3 + hash(gx, 9999, gz, 82) * 0.4) * cell / SIZE)
	local cy = math.floor(s.top / SIZE) - 1
	if not hasNode(cy) then
		return nil
	end
	local node = nodeAt(cx, cy, cz)
	return {
		c = Vector2.new(node.X, node.Z),
		r = s.shaftRadius * (0.8 + hash(gx, 9999, gz, 83) * 0.4),
		top = surfaceHeight(node.X, node.Z) + 2,
		bottom = node.Y - s.shaftDepth * (0.75 + hash(gx, 9999, gz, 84) * 0.5),
		spin = hash(gx, 9999, gz, 85) * math.pi * 2,
		dir = if hash(gx, 9999, gz, 86) < 0.5 then 1 else -1,
	}
end

-- the river that starts in this big grid cell, if there is one. it runs from one junction to
-- another a few chunks away, winding between them, always downhill from the higher end
local function riverForCell(gx: number, gz: number)
	local s = Cave.settings
	if hash(gx, 8888, gz, 60) >= s.riverChance then
		return nil
	end
	local cell = s.riverCell
	local cx = math.floor((gx + 0.3 + hash(gx, 8888, gz, 61) * 0.4) * cell / SIZE)
	local cz = math.floor((gz + 0.3 + hash(gx, 8888, gz, 62) * 0.4) * cell / SIZE)
	local cy = math.floor(s.top / SIZE) - 1 - math.floor(hash(gx, 8888, gz, 63) * 3)
	if not hasNode(cy) then
		return nil
	end
	local dx = (if hash(gx, 8888, gz, 64) < 0.5 then -1 else 1) * (3 + math.floor(hash(gx, 8888, gz, 65) * 3))
	local dz = (if hash(gx, 8888, gz, 66) < 0.5 then -1 else 1) * (1 + math.floor(hash(gx, 8888, gz, 67) * 3))
	local a, b = nodeAt(cx, cy, cz), nodeAt(cx + dx, cy, cz + dz)
	if a.Y < b.Y then
		a, b = b, a
	end
	local side = Vector3.new(-(b.Z - a.Z), 0, b.X - a.X).Unit
	local amp = 18 + hash(gx, 8888, gz, 69) * 22
	local phase = hash(gx, 8888, gz, 70) * math.pi * 2
	local pts = {}
	local n = 7
	for i = 0, n do
		local t = i / n
		local base = a:Lerp(b, t)
		-- the ends sit on the junctions, the middle swings side to side
		local meander = math.sin(t * math.pi * 2 + phase) * amp * math.sin(t * math.pi)
		-- the bed runs about 6 studs under the junctions, so the channel opens into their tunnels
		local bed = (a.Y - 6) + (b.Y - a.Y) * t
		table.insert(pts, Vector3.new(base.X, bed, base.Z) + side * meander)
	end
	return {
		pts = pts,
		halfW = s.riverWidth * (0.8 + hash(gx, 8888, gz, 68) * 0.4) / 2,
		clearance = s.riverClearance,
		depth = s.riverDepth,
	}
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
	local reach = math.max(s.chamberRadius * 1.3, s.cavernRadius * 1.2) + s.wiggle + VOXEL + s.tunnelRadius * 1.4 + s.galleryWiden
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
					for d, step in STEP do
						if hasLink(x, y, z, d) then
							local b = nodeAt(x + step.X, y + step.Y, z + step.Z)
							if touches(a, b) then
								table.insert(tunnels, { a = a, ab = b - a, len2 = (b - a):Dot(b - a) })
							end
							-- a room partway along some passages, so they open out instead of staying one width
							if hash(x, y, z, 300 + d) < s.roomChance then
								local at = a:Lerp(b, 0.3 + hash(x, y, z, 310 + d) * 0.4)
								if touches(at, at) then
									table.insert(chambers, { c = at, r = s.roomRadius * (0.7 + hash(x, y, z, 320 + d) * 0.6) })
								end
							end
						end
					end
					local kind = nodeKind(x, y, z)
					if kind == "cavern" then
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
					elseif touches(a, a) then
						local size = if kind == "hub" then 1 + hash(x, y, z, 7) * 0.35
							elseif kind == "chamber" then 0.7 + hash(x, y, z, 7) * 0.6
							elseif kind == "pocket" then 0.45 + hash(x, y, z, 7) * 0.2
							else 0
						if size > 0 then
							table.insert(chambers, { c = a, r = s.chamberRadius * size })
						end
					end
				end
			end
		end
	end

	-- chasms live on a much bigger grid than the chunks
	local chasms = {}
	local cell = s.chasmCell
	for gx = math.floor(lo.X / cell) - 1, math.floor(hi.X / cell) + 1 do
		for gz = math.floor(lo.Z / cell) - 1, math.floor(hi.Z / cell) + 1 do
			if hash(gx, 7777, gz, 50) < s.chasmChance then
				local center = Vector2.new((gx + 0.2 + hash(gx, 7777, gz, 51) * 0.6) * cell, (gz + 0.2 + hash(gx, 7777, gz, 52) * 0.6) * cell)
				local angle = hash(gx, 7777, gz, 53) * math.pi
				local len = s.chasmLength * (0.7 + hash(gx, 7777, gz, 54) * 0.5)
				local dir = Vector2.new(math.cos(angle), math.sin(angle))
				local a = center - dir * len / 2
				local top = s.top - 14 - hash(gx, 7777, gz, 55) * 20
				local bottom = top - s.chasmDepth * (0.75 + hash(gx, 7777, gz, 56) * 0.5)
				local halfTop = s.chasmWidth * (0.8 + hash(gx, 7777, gz, 57) * 0.4) / 2
				local pad = halfTop + s.wiggle * 1.5
				local b = a + dir * len
				local inX = math.max(a.X, b.X) + pad >= lo.X and math.min(a.X, b.X) - pad <= hi.X
				local inZ = math.max(a.Y, b.Y) + pad >= lo.Z and math.min(a.Y, b.Y) - pad <= hi.Z
				local inY = top + pad >= lo.Y and bottom - pad <= hi.Y
				if inX and inZ and inY then
					table.insert(chasms, {
						a = a,
						ab = dir * len,
						len2 = len * len,
						top = top,
						bottom = bottom,
						halfTop = halfTop,
						halfBottom = halfTop * 0.35,
					})
				end
			end
		end
	end

	-- rivers can run a few cells from where they start, so look a couple of cells out
	local rivers = {}
	local rcell = s.riverCell
	for gx = math.floor(lo.X / rcell) - 2, math.floor(hi.X / rcell) + 2 do
		for gz = math.floor(lo.Z / rcell) - 2, math.floor(hi.Z / rcell) + 2 do
			local rv = riverForCell(gx, gz)
			if rv then
				local mn, mx = rv.pts[1], rv.pts[1]
				for _, p in rv.pts do
					mn, mx = mn:Min(p), mx:Max(p)
				end
				local pad = rv.halfW + s.wiggle * 1.5 + rv.clearance
				if mx.X + pad >= lo.X and mn.X - pad <= hi.X and mx.Z + pad >= lo.Z and mn.Z - pad <= hi.Z
					and mx.Y + pad >= lo.Y and mn.Y - pad <= hi.Y
				then
					table.insert(rivers, rv)
				end
			end
		end
	end

	local shafts = {}
	local scell = s.shaftCell
	for gx = math.floor(lo.X / scell) - 1, math.floor(hi.X / scell) + 1 do
		for gz = math.floor(lo.Z / scell) - 1, math.floor(hi.Z / scell) + 1 do
			local sh = shaftForCell(gx, gz)
			if sh then
				local pad = sh.r + s.wiggle * 1.5 + 4
				if sh.c.X + pad >= lo.X and sh.c.X - pad <= hi.X and sh.c.Y + pad >= lo.Z and sh.c.Y - pad <= hi.Z
					and sh.top + 4 >= lo.Y and sh.bottom <= hi.Y
				then
					table.insert(shafts, sh)
				end
			end
		end
	end

	local tubes = {}
	local tcell = s.tubeCell
	for gx = math.floor(lo.X / tcell) - 2, math.floor(hi.X / tcell) + 2 do
		for gz = math.floor(lo.Z / tcell) - 2, math.floor(hi.Z / tcell) + 2 do
			local tb = tubeForCell(gx, gz)
			if tb then
				local mn, mx = tb.a:Min(tb.b), tb.a:Max(tb.b)
				local pad = tb.amp + tb.r + s.wiggle * 1.5 + 8
				if mx.X + pad >= lo.X and mn.X - pad <= hi.X and mx.Z + pad >= lo.Z and mn.Z - pad <= hi.Z
					and mx.Y + pad >= lo.Y and mn.Y - pad <= hi.Y
				then
					table.insert(tubes, tb)
				end
			end
		end
	end

	cached = {
		tunnels = tunnels,
		chambers = chambers,
		caverns = caverns,
		pillars = pillars,
		chasms = chasms,
		rivers = rivers,
		shafts = shafts,
		tubes = tubes,
	}
	featureCache[key] = cached
	return cached
end

-- bend space a bit so tunnels wander instead of running dead straight
local function warp(p: Vector3): Vector3
	local s = Cave.settings
	local o = s.seed * 17.13
	local b = s.bend
	return p + Vector3.new(
		math.noise(p.X * b, p.Y * b, p.Z * b + o),
		math.noise(p.X * b + o, p.Y * b, p.Z * b),
		math.noise(p.X * b, p.Y * b + o, p.Z * b)
	) * s.wiggle * 2
end

-- the inverse of warp, roughly: where a point on a straight tunnel line actually ended up
local function unwarp(target: Vector3): Vector3
	local p = target
	for _ = 1, 4 do
		p = target - (warp(p) - p)
	end
	return p
end

-- where a shaft actually is. shafts go straight down in real space, not in the bent tunnel space,
-- or they wander sideways and the ledge blocks the view down. centred on where the junction it sits
-- on really ended up, so it still opens into that junction's tunnels
local function shaftCentre(sh): Vector3
	if not sh.pc then
		sh.pc = unwarp(Vector3.new(sh.c.X, sh.top - 40, sh.c.Y))
	end
	return sh.pc
end

-- a lava tube's curve, in real space: from one junction's real position to the other's, swaying side
-- to side and rising and dipping a little. worked out once and kept
local function tubePath(tb): { Vector3 }
	if tb.path then
		return tb.path
	end
	local a, b = unwarp(tb.a), unwarp(tb.b)
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local side = if flat.Magnitude > 0.1 then Vector3.new(-flat.Z, 0, flat.X).Unit else Vector3.xAxis
	local pts = {}
	for i = 0, 10 do
		local t = i / 10
		local ends = math.sin(t * math.pi) -- 0 at both ends, so they sit exactly on the junctions
		local sway = math.sin(t * math.pi * 2 + tb.phase) * tb.amp * ends
		local lift = math.sin(t * math.pi * 3 + tb.phase) * 4 * ends
		table.insert(pts, a:Lerp(b, t) + side * sway + Vector3.new(0, lift, 0))
	end
	tb.path = pts
	return pts
end

-- how far inside the nearest lava tube a point is. > 0 is inside, < 0 is out in the rock
local function tubeClearance(p: Vector3): number
	local f = featuresFor(math.floor(p.X / SIZE), math.floor(p.Y / SIZE), math.floor(p.Z / SIZE))
	local best = -math.huge
	for _, tb in f.tubes do
		local pts = tubePath(tb)
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local ab = b - a
			local k = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
			local v = tb.r - (p - (a + ab * k)).Magnitude
			if v > best then
				best = v
			end
		end
	end
	return best
end

-- studs of clearance: > 0 is air, < 0 is rock, 0 is the wall
-- cave mouths: a straight sloping tunnel from a junction on the top level up to the lowest bit of
-- ground nearby, so it comes out of a hillside instead of the top of a hill. real space, not bent,
-- like the shafts, so it lines up with the surface
local entranceCache: { [string]: any } = {}

local function entranceForCell(gx: number, gz: number)
	local s = Cave.settings
	local e = s.surface
	local key = s.seed .. ":" .. gx .. "," .. gz
	local cached = entranceCache[key]
	if cached ~= nil then
		return if cached then cached else nil
	end
	local found = nil
	local cy = math.floor(s.top / SIZE) - 1
	if hash(gx, 5555, gz, 120) < e.entranceChance and hasNode(cy) then
		local cell = e.entranceCell
		local cx = math.floor((gx + 0.3 + hash(gx, 5555, gz, 121) * 0.4) * cell / SIZE)
		local cz = math.floor((gz + 0.3 + hash(gx, 5555, gz, 122) * 0.4) * cell / SIZE)
		local a = unwarp(nodeAt(cx, cy, cz))
		local out, low = Vector3.xAxis, math.huge
		for i = 0, 7 do
			local angle = (i + hash(gx, 5555, gz, 123)) * math.pi / 4
			local d = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local b = a + d * e.entranceRun
			local h = surfaceHeight(b.X, b.Z)
			if h < low then
				out, low = d, h
			end
		end
		local mouth = Vector3.new(a.X, 0, a.Z) + out * e.entranceRun + Vector3.new(0, low + 1, 0)
		-- carry on a bit past the mouth so it opens right up instead of ending in a round cap
		local b = mouth + out * 12
		found = { a = a, b = b, mouth = mouth, out = out, ab = b - a, len2 = (b - a):Dot(b - a), r = e.entranceRadius }
	end
	entranceCache[key] = found or false
	return found
end

local entranceChunks: { [string]: { any } } = {}

local function entrancesNear(cx: number, cz: number): { any }
	local key = Cave.settings.seed .. ":" .. cx .. "," .. cz
	local got = entranceChunks[key]
	if got then
		return got
	end
	local e = Cave.settings.surface
	local cell = e.entranceCell
	local pad = e.entranceRun + e.entranceRadius + 40
	local list = {}
	for gx = math.floor((cx * SIZE - pad) / cell), math.floor(((cx + 1) * SIZE + pad) / cell) do
		for gz = math.floor((cz * SIZE - pad) / cell), math.floor(((cz + 1) * SIZE + pad) / cell) do
			local en = entranceForCell(gx, gz)
			if en then
				local lo, hi = en.a:Min(en.b), en.a:Max(en.b)
				local r = en.r + 8
				if hi.X + r >= cx * SIZE and lo.X - r <= (cx + 1) * SIZE and hi.Z + r >= cz * SIZE and lo.Z - r <= (cz + 1) * SIZE then
					table.insert(list, en)
				end
			end
		end
	end
	entranceChunks[key] = list
	return list
end

-- skylights are worked out from the cave shape itself (is there a big space under here?), so while
-- that's being checked they're left out, or finding one would need itself
local skySkip = false
local skylightsNear: (cx: number, cz: number) -> { any }

local function airness(p: Vector3): number
	local s = Cave.settings
	local f = featuresFor(math.floor(p.X / SIZE), math.floor(p.Y / SIZE), math.floor(p.Z / SIZE))
	local o = s.seed * 17.13
	local q = warp(p)
	-- galleries: where the slow field is up, the passage opens right out
	local gallery = math.max(0, math.noise(p.X * s.galleryScale + o, p.Y * s.galleryScale, p.Z * s.galleryScale - o) * 1.6)
	local r = math.max(s.minRadius, s.tunnelRadius * (1 + math.noise(p.X * 0.05, p.Y * 0.05, p.Z * 0.05 - o) * 0.4))
		+ gallery * s.galleryWiden

	local best = -math.huge
	local shaftBest = -math.huge -- kept apart so the roof below doesn't cap the sinkholes
	for _, t in f.tunnels do
		local ap = q - t.a
		local k = math.clamp(ap:Dot(t.ab) / t.len2, 0, 1)
		-- squashed below the middle and stretched above: flatter floor, arched ceiling
		local d = ap - t.ab * k
		local v = r - Vector3.new(d.X, d.Y * (if d.Y < 0 then s.floorSquash else 0.85), d.Z).Magnitude
		if v > best then
			best = v
		end
	end
	for _, c in f.chambers do
		local d = q - c.c
		-- lumpy rather than a clean ball, so rooms don't look like bubbles
		local cr = c.r * (1 + math.noise(q.X * 0.05, q.Y * 0.05 + o, q.Z * 0.05) * 0.35)
		local v = cr - Vector3.new(d.X, d.Y * (if d.Y < 0 then s.floorSquash else 0.85), d.Z).Magnitude
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
	for _, c in f.chasms do
		if q.Y < c.top and q.Y > c.bottom then
			local t = (c.top - q.Y) / (c.top - c.bottom) -- 0 at the top, 1 at the bottom
			local half = c.halfTop * (1 - t) + c.halfBottom * t
			local ap = Vector2.new(q.X - c.a.X, q.Z - c.a.Y)
			local k = math.clamp(ap:Dot(c.ab) / c.len2, 0, 1)
			local v = half - (ap - c.ab * k).Magnitude
			-- round off the top and bottom so it doesn't end in a flat slab
			v = math.min(v, (c.top - q.Y) * 0.5, (q.Y - c.bottom) * 0.5)
			if v > best then
				best = v
			end
		end
	end
	-- shafts: a round hole straight down. the spiral ledge is the part of the shaft that stays rock:
	-- a shelf ledgeWidth deep round the wall, dropping ledgePitch studs per turn
	for _, sh in f.shafts do
		if p.Y < sh.top + 4 and p.Y > sh.bottom then
			local c = shaftCentre(sh)
			local d = Vector2.new(p.X - c.X, p.Z - c.Z)
			local dist = d.Magnitude
			local v = math.min(sh.r - dist, (p.Y - sh.bottom) * 0.5)
			if v > 0 and dist > sh.r - s.ledgeWidth then
				local angle = math.atan2(d.Y, d.X)
				local turns = (sh.top - p.Y) / s.ledgePitch - sh.dir * (angle + sh.spin) / (2 * math.pi)
				if (turns - math.floor(turns)) * s.ledgePitch < s.ledgeThickness then
					v = -1
				end
			end
			if v > shaftBest then
				shaftBest = v
			end
		end
	end
	-- river channels: flat floor just under the bed, headroom above it, as wide as the river
	for _, rv in f.rivers do
		local pts = rv.pts
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local ab = Vector2.new(b.X - a.X, b.Z - a.Z)
			local ap = Vector2.new(q.X - a.X, q.Z - a.Z)
			local k = math.clamp(ap:Dot(ab) / ab:Dot(ab), 0, 1)
			local dxz = (ap - ab * k).Magnitude
			if dxz < rv.halfW + 4 then
				local bed = a.Y + (b.Y - a.Y) * k
				local v = math.min(rv.halfW - dxz, (q.Y - (bed - 1)) * 0.8, (bed + rv.clearance - q.Y) * 0.8)
				if v > best then
					best = v
				end
			end
		end
	end
	-- a roof: caverns and chambers on the top level reach up past the low bits of ground and broke
	-- through as huge open pits. nothing cave-shaped goes above 6 under the top of the mine, except
	-- the sinkholes and cave mouths, which are meant to open up. that also keeps the ground layer
	-- solid, which matters because far out only the ground layer gets built, nothing under it
	if p.Y > s.top - 40 then
		best = math.min(best, (s.top - 6) - p.Y)
	end
	best = math.max(best, shaftBest)
	-- skylights go up through the roof too, like the sinkholes. a narrow crack that wanders a little
	if not skySkip and p.Y > s.top - 80 then
		for _, sk in skylightsNear(math.floor(p.X / SIZE), math.floor(p.Z / SIZE)) do
			if p.Y > sk.bottom - 3 and p.Y < sk.top then
				local wander = math.sin(p.Y * 0.07 + sk.phase) * 1.2
				local d = Vector2.new(p.X - sk.x - wander, p.Z - sk.z).Magnitude
				local v = math.min(sk.r - d, (p.Y - (sk.bottom - 3)) * 0.5)
				if v > best then
					best = v
				end
			end
		end
	end
	-- cave mouths, only near the top where they can be
	if p.Y > s.top - SIZE - 12 then
		for _, en in entrancesNear(math.floor(p.X / SIZE), math.floor(p.Z / SIZE)) do
			local ap = p - en.a
			local k = math.clamp(ap:Dot(en.ab) / en.len2, 0, 1)
			local d = ap - en.ab * k
			local v = en.r - Vector3.new(d.X, d.Y * (if d.Y < 0 then s.floorSquash else 0.85), d.Z).Magnitude
			if v > best then
				best = v
			end
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
	-- rough rock: big slow lumps plus a finer layer, nothing much under 9 studs across. the terrain
	-- grid is 4 studs, and the old 3 stud bumps and thin shelves came out as jagged random facets
	-- that made it look like an old game. the fine detail comes from the rock outcrops instead
	local rough = math.noise(p.X * 0.045, p.Y * 0.045 + o, p.Z * 0.045) * s.roughness * 1.6
		+ math.noise(p.X * 0.11 + o, p.Y * 0.11, p.Z * 0.11) * s.roughness * 0.6
	-- lava tubes are round and almost smooth, the lava polished the walls on its way through, so
	-- where a tube is the nearest wall the bumps are mostly left off
	local tube = tubeClearance(p)
	if tube > best then
		return tube + rough * 0.15
	end
	-- open sky above the ground. a bit of the roughness so the hills aren't perfectly smooth
	if p.Y > s.top - 8 then
		local sky = p.Y - surfaceHeight(p.X, p.Z)
		return math.max(best + rough, sky + rough * 0.3)
	end
	return best + rough
end

Cave.airness = airness

local skylightCache: { [string]: any } = {}
local skylightChunks: { [string]: { any } } = {}

-- the skylight in this square, if there is one: only where there's a big space with its roof
-- within about 60 studs of the surface. the crack runs from that roof up to the grass
local function skylightForCell(gx: number, gz: number)
	local s = Cave.settings
	local e = s.surface
	local key = s.seed .. ":" .. gx .. "," .. gz
	local cached = skylightCache[key]
	if cached ~= nil then
		return if cached then cached else nil
	end
	local found = nil
	if hash(gx, 4444, gz, 130) < e.skylightChance then
		local cell = e.skylightCell
		local x = (gx + 0.2 + hash(gx, 4444, gz, 131) * 0.6) * cell
		local z = (gz + 0.2 + hash(gx, 4444, gz, 132) * 0.6) * cell
		skySkip = true
		local bottom = nil
		for y = s.top - 8, s.top - 70, -2 do
			local p = Vector3.new(x, y, z)
			if airness(p) > 1 then
				-- only worth it over a big space, not a crawl
				if airness(p - Vector3.new(0, 8, 0)) > 5 then
					bottom = y
				end
				break
			end
		end
		skySkip = false
		if bottom then
			found = {
				x = x,
				z = z,
				bottom = bottom,
				top = surfaceHeight(x, z) + 3,
				r = e.skylightRadius * (0.8 + hash(gx, 4444, gz, 133) * 0.5),
				phase = hash(gx, 4444, gz, 134) * math.pi * 2,
			}
		end
	end
	skylightCache[key] = found or false
	return found
end

skylightsNear = function(cx: number, cz: number): { any }
	local key = Cave.settings.seed .. ":" .. cx .. "," .. cz
	local got = skylightChunks[key]
	if got then
		return got
	end
	local cell = Cave.settings.surface.skylightCell
	local list = {}
	for gx = math.floor((cx * SIZE - 8) / cell), math.floor(((cx + 1) * SIZE + 8) / cell) do
		for gz = math.floor((cz * SIZE - 8) / cell), math.floor(((cz + 1) * SIZE + 8) / cell) do
			local sk = skylightForCell(gx, gz)
			if sk and sk.x + sk.r + 3 >= cx * SIZE and sk.x - sk.r - 3 <= (cx + 1) * SIZE
				and sk.z + sk.r + 3 >= cz * SIZE and sk.z - sk.r - 3 <= (cz + 1) * SIZE
			then
				table.insert(list, sk)
			end
		end
	end
	skylightChunks[key] = list
	return list
end

-- ============================================================ geodes
--[[
	hollow balls lined with crystals, sealed inside solid rock so you have to dig to find them. the
	one thing in the mine that deliberately doesn't connect. only placed where the whole ball and a
	shell round it is rock, and a few sparkles on the nearest tunnel wall give it away
]]

local geodeCache: { [string]: any } = {}

local function geodeForCell(gx: number, gy: number, gz: number)
	local s = Cave.settings
	local key = s.seed .. ":" .. gx .. "," .. gy .. "," .. gz
	local cached = geodeCache[key]
	if cached ~= nil then
		return if cached then cached else nil
	end
	local found = nil
	local cell = s.geodeCell
	if hash(gx, gy, gz, 110) < s.geodeChance then
		local c = Vector3.new(
			(gx + 0.25 + hash(gx, gy, gz, 111) * 0.5) * cell,
			(gy + 0.25 + hash(gx, gy, gz, 112) * 0.5) * cell,
			(gz + 0.25 + hash(gx, gy, gz, 113) * 0.5) * cell
		)
		local r = s.geodeRadius * (0.85 + hash(gx, gy, gz, 114) * 0.35)
		if c.Y < s.top - r - 20 then
			-- sealed: the middle and 26 points round a shell 4 studs out all have to be solid rock
			local sealed = airness(c) < -1
			for dx = -1, 1 do
				for dy = -1, 1 do
					for dz = -1, 1 do
						if sealed and (dx ~= 0 or dy ~= 0 or dz ~= 0) then
							if airness(c + Vector3.new(dx, dy, dz).Unit * (r + 4)) > -1 then
								sealed = false
							end
						end
					end
				end
			end
			if sealed then
				local palette = {
					Color3.fromRGB(170, 90, 255), -- amethyst
					Color3.fromRGB(255, 200, 70), -- citrine
					Color3.fromRGB(80, 225, 255), -- aqua
					Color3.fromRGB(255, 105, 180), -- rose
				}
				found = { c = c, r = r, color = palette[1 + math.floor(hash(gx, gy, gz, 115) * #palette)] }
			end
		end
	end
	geodeCache[key] = found or false
	return found
end

-- every geode whose ball and shell reach into this chunk
local function geodesNear(min: Vector3): { any }
	local cell = Cave.settings.geodeCell
	local reach = 16
	local list = {}
	for gx = math.floor((min.X - reach) / cell), math.floor((min.X + SIZE + reach) / cell) do
		for gy = math.floor((min.Y - reach) / cell), math.floor((min.Y + SIZE + reach) / cell) do
			for gz = math.floor((min.Z - reach) / cell), math.floor((min.Z + SIZE + reach) / cell) do
				local g = geodeForCell(gx, gy, gz)
				if g then
					local near = g.r + 3
					if g.c.X + near >= min.X and g.c.X - near <= min.X + SIZE
						and g.c.Y + near >= min.Y and g.c.Y - near <= min.Y + SIZE
						and g.c.Z + near >= min.Z and g.c.Z - near <= min.Z + SIZE
					then
						table.insert(list, g)
					end
				end
			end
		end
	end
	return list
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
	-- a second, separate map for the tide pool bits, so they're not stuck between the other two
	local f = math.noise(p.X * b.scale - 31.4, p.Y * b.scale * 0.5 + Cave.settings.seed * 3.3, p.Z * b.scale + 12.9)
	if f > b.poolsAbove then
		return "pools"
	end
	return "rock"
end
Cave.biomeAt = biomeAt

local function materialAt(p: Vector3, isFloor: boolean): Enum.Material
	local s = Cave.settings
	local o = s.seed * 31.7

	-- the surface: grass on top, a few studs of earth under it, bare rock where it's steep
	if p.Y > s.top - 8 then
		local ground = surfaceHeight(p.X, p.Z)
		if p.Y > ground - 7 then
			local steep = math.abs(surfaceHeight(p.X + 4, p.Z) - ground) + math.abs(surfaceHeight(p.X, p.Z + 4) - ground)
			if steep > 5 or math.noise(p.X * 0.03, o, p.Z * 0.03) > 0.45 then
				return s.patch
			end
			return if isFloor and p.Y > ground - 4 then Enum.Material.Grass else Enum.Material.Ground
		end
	end

	-- right round a lava tube: glowing cracked lava on the floor, dark basalt everywhere else
	if tubeClearance(p) > -3 then
		return if isFloor then Enum.Material.CrackedLava else Enum.Material.Basalt
	end

	local biome = biomeAt(p)
	if biome == "crystal" then
		if isFloor then
			return Enum.Material.Salt
		end
		return if math.noise(p.X * 0.06, p.Y * 0.06, p.Z * 0.06 + o) > 0.2 then Enum.Material.Glacier else Enum.Material.Basalt
	elseif biome == "mushroom" then
		return if isFloor then Enum.Material.LeafyGrass else Enum.Material.Mud
	elseif biome == "pools" then
		return if isFloor then Enum.Material.Sand else Enum.Material.Cobblestone
	end

	if p.Y < s.lavaBelow and math.noise(p.X * 0.04, p.Y * 0.04 + o, p.Z * 0.04) > 0.3 then
		return Enum.Material.CrackedLava
	end
	if isFloor and p.Y > s.layers[#s.layers].at then
		return s.floor
	end
	-- mineral streaks: noise stretched tall and thin, so it runs down the walls like drip stains
	if not isFloor and math.noise(p.X * 0.2 + o, p.Y * 0.015, p.Z * 0.2 - o) > s.pools.streaks then
		return s.pools.flowstone
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

-- swaps roblox's stock materials for the MaterialVariants named in settings.textures, terrain
-- included. a missing variant gets a warning and the stock look, it never stops the mine building
function Cave.applyTextures()
	local MaterialService = game:GetService("MaterialService")
	for baseName, variantName in Cave.settings.textures do
		local ok, base = pcall(function()
			return (Enum.Material :: any)[baseName]
		end)
		local variant = MaterialService:FindFirstChild(variantName, true)
		if not ok or not base then
			warn("cave: textures has an unknown material", baseName)
		elseif not variant or not variant:IsA("MaterialVariant") then
			warn("cave: no MaterialVariant called", variantName, "in MaterialService, keeping stock", baseName)
		else
			local set, err = pcall(function()
				MaterialService:SetBaseMaterialOverride(base, variantName)
			end)
			if not set then
				warn("cave: couldn't swap", baseName, "for", variantName, err)
			end
		end
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
	-- afternoon sun on the surface. the rock shadows the sun and outdoor ambient only reaches places
	-- that can see the sky, so the caves stay dark apart from light coming down sinkholes and mouths
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(32, 30, 29)
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 122, 130)
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.GlobalShadows = true

	-- properly dark underground, so the lanterns, crystals and your lamp actually matter
	if Cave.settings.dark then
		Lighting.Ambient = Color3.fromRGB(6, 6, 7)
	end

	-- still, clear water so you can see what's at the bottom of the pools
	-- lighter and clearer, and barely reflecting. in a dark cave a reflective surface just mirrors the
	-- dark and reads as a navy slab. small waves so it catches light and looks like it's moving
	terrain.WaterColor = Color3.fromRGB(70, 170, 190)
	terrain.WaterTransparency = 0.95
	terrain.WaterReflectance = 0.1
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 8

	local atmosphere = getEffect("Atmosphere", "CaveAtmosphere") :: Atmosphere
	-- starts as the daylight haze. underground each player's Atmosphere script swaps in the cave fog
	atmosphere.Density = 0.3
	atmosphere.Offset = 0
	atmosphere.Color = Color3.fromRGB(190, 205, 225)
	atmosphere.Decay = Color3.fromRGB(110, 125, 150)
	atmosphere.Glare = 0
	atmosphere.Haze = 1

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

-- ============================================================ meshes
--[[
	the prop shapes live in ReplicatedStorage.CaveMeshes so players' computers can build them too.
	meshes built on the server never reach players (they get checker boxes), so while the game runs
	the server only places plain stand-in blocks tagged with which shape they are, and each player's
	Props script swaps in the real mesh. in edit mode there's no player, so Studio builds them here
]]
local CaveMeshes = require(ReplicatedStorage:WaitForChild("CaveMeshes"))

local function buildMeshLib()
	if RunService:IsRunning() then
		return nil
	end
	return CaveMeshes.build()
end
Cave.buildMeshLib = buildMeshLib

-- a stand-in block tagged with a shape (while the game runs), or the real mesh (in edit mode).
-- nil only if meshes aren't available in edit mode
local function newMesh(kind: string, rng: Random): BasePart?
	local count = CaveMeshes.counts[kind]
	if not count then
		return nil
	end
	local index = rng:NextInteger(1, count)
	if RunService:IsRunning() then
		local stand = Instance.new("Part")
		stand:SetAttribute("MeshKind", kind)
		stand:SetAttribute("MeshIndex", index)
		return stand
	end
	local lib = CaveMeshes.build()
	local list = lib and lib[kind]
	if not list then
		return nil
	end
	return list[index]:Clone()
end

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
		local part = newMesh("lump", rng) or Instance.new(if rng:NextNumber() < 0.4 then "WedgePart" else "Part")
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

		local shard = newMesh("crystal", rng)
		local part: BasePart = shard or Instance.new("Part")
		part.Name = "Shard"
		part.Anchored = true
		part.CanCollide = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = color
		part.Transparency = 0.15
		if shard then
			-- the mesh points up its y axis, turn that to point along dir
			part.Size = Vector3.new(width, len, width)
			part.CFrame = safeLookAt(base + dir * len / 2, dir) * CFrame.Angles(-math.pi / 2, 0, 0)
		else
			part.Size = Vector3.new(width, width, len)
			part.CFrame = safeLookAt(base + dir * len / 2, dir)
		end
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

-- a little pool sunk into the floor: clear water, a ring of wet stones, glowing bits on the bottom
local function placeTidePool(floor: Vector3, rng: Random)
	local b = Cave.settings.biomes
	local r = rng:NextNumber(4, 7)
	-- the water replaces the rock under the floor, so it sits in a basin and can't float
	terrain:FillCylinder(CFrame.new(floor - Vector3.new(0, 2, 0)), 4, r * 0.8, Enum.Material.Water)

	local model = Instance.new("Model")
	model.Name = "TidePool"

	local stones = rng:NextInteger(6, 10)
	for i = 1, stones do
		local angle = (i / stones) * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local dist = r * rng:NextNumber(0.78, 0.95)
		local size = Vector3.new(rng:NextNumber(0.8, 2), rng:NextNumber(0.5, 1.2), rng:NextNumber(0.8, 2))
		local stone = Instance.new("Part")
		stone.Name = "Stone"
		stone.Anchored = true
		stone.Material = Enum.Material.Slate
		stone.Color = Color3.fromRGB(54, 56, 58):Lerp(Color3.fromRGB(92, 90, 86), rng:NextNumber())
		stone.Size = size
		stone.CFrame = CFrame.new(floor + Vector3.new(math.cos(angle) * dist, size.Y * 0.2, math.sin(angle) * dist))
			* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3))
		stone.Parent = model
	end

	for _ = 1, rng:NextInteger(3, 6) do
		local angle, dist = rng:NextNumber(0, 6.28), r * rng:NextNumber(0, 0.55)
		local size = rng:NextNumber(0.4, 0.9)
		local blob = Instance.new("Part")
		blob.Name = "Anemone"
		blob.Shape = Enum.PartType.Ball
		blob.Anchored = true
		blob.CanCollide = false
		blob.CastShadow = false
		blob.Material = Enum.Material.Neon
		blob.Color = b.poolColors[rng:NextInteger(1, #b.poolColors)]
		blob.Size = Vector3.one * size
		blob.CFrame = CFrame.new(floor + Vector3.new(math.cos(angle) * dist, -3.4 + size / 2, math.sin(angle) * dist))
		blob.Parent = model
	end

	-- a soft glow from under the water
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(90, 220, 230)
	light.Range = r * 2.5
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = model:FindFirstChild("Anemone")

	keep(model, "Decor")
end

local function inCavern(p: Vector3): boolean
	local f = featuresFor(math.floor(p.X / SIZE), math.floor(p.Y / SIZE), math.floor(p.Z / SIZE))
	local q = warp(p)
	for _, c in f.caverns do
		local d = q - c.c
		if Vector3.new(d.X, d.Y / c.flat, d.Z).Magnitude < c.r + 6 then
			return true
		end
	end
	return false
end

-- a patch of glowworms on a ceiling: tiny blue dots, and a couple of the sticky threads they hang
local function placeGlowworms(ceiling: Vector3, rng: Random)
	local color = Cave.settings.glowwormColor
	local model = Instance.new("Model")
	model.Name = "Glowworms"

	local function glow(size: number, at: Vector3)
		local dot = Instance.new("Part")
		dot.Name = "Glow"
		dot.Shape = Enum.PartType.Ball
		dot.Anchored = true
		dot.CanCollide = false
		dot.CanQuery = false
		dot.CastShadow = false
		dot.Material = Enum.Material.Neon
		dot.Color = color
		dot.Size = Vector3.one * size
		dot.CFrame = CFrame.new(at)
		dot.Parent = model
	end

	for _ = 1, rng:NextInteger(4, 8) do
		glow(rng:NextNumber(0.12, 0.28), ceiling + Vector3.new(rng:NextNumber(-2, 2), -0.2, rng:NextNumber(-2, 2)))
	end
	for _ = 1, rng:NextInteger(0, 2) do
		local len = rng:NextNumber(1, 3.5)
		local at = ceiling + Vector3.new(rng:NextNumber(-1.8, 1.8), 0, rng:NextNumber(-1.8, 1.8))
		local thread = Instance.new("Part")
		thread.Name = "Thread"
		thread.Anchored = true
		thread.CanCollide = false
		thread.CanQuery = false
		thread.CastShadow = false
		thread.Material = Enum.Material.SmoothPlastic
		thread.Color = color:Lerp(Color3.new(1, 1, 1), 0.5)
		thread.Transparency = 0.55
		thread.Size = Vector3.new(0.04, len, 0.04)
		thread.CFrame = CFrame.new(at - Vector3.new(0, len / 2, 0))
		thread.Parent = model
		glow(0.18, at - Vector3.new(0, len, 0))
	end

	if rng:NextNumber() < 0.15 then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 26
		light.Brightness = 0.9
		light.Shadows = false
		light.Parent = model:FindFirstChild("Glow")
	end
	keep(model, "Decor")
end

-- a cluster of glowing shelf fungus on a wall: flat round caps sticking out, one colour per
-- cluster, and a light so a big space isn't just black past your lamp
local function placeFungus(wall: Vector3, normal: Vector3, rng: Random)
	local colors = Cave.settings.fungusColors
	local color = colors[rng:NextInteger(1, #colors)]
	local side = normal:Cross(Vector3.yAxis)
	side = if side.Magnitude > 0.1 then side.Unit else Vector3.xAxis
	local model = Instance.new("Model")
	model.Name = "Fungus"
	for i = 1, rng:NextInteger(3, 6) do
		local d = rng:NextNumber(0.8, 2)
		local cap = Instance.new("Part")
		cap.Name = "Cap"
		cap.Shape = Enum.PartType.Cylinder
		cap.Anchored = true
		cap.CanCollide = false
		cap.CanQuery = false
		cap.CastShadow = false
		cap.Material = Enum.Material.Neon
		cap.Color = color:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.2))
		-- a cylinder's axis is its x, so turn it upright to make a flat cap
		cap.Size = Vector3.new(0.22, d, d)
		local at = wall + normal * (d * 0.3) + side * rng:NextNumber(-1.6, 1.6) + Vector3.new(0, (i - 2) * 0.7 + rng:NextNumber(-0.3, 0.3), 0)
		cap.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, 0)
		cap.Parent = model
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 22
	light.Brightness = 1.1
	light.Shadows = false
	light.Parent = model:FindFirstChild("Cap")
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

	-- one real cone if meshes work. its root is at the top and it points down, so stalagmites flip it
	local cone = newMesh("spike", rng)
	if cone then
		cone.Anchored = true
		cone.CanCollide = solid
		cone.Material = Enum.Material.Slate
		cone.Color = color
		cone.Size = Vector3.new(width, len, width)
		local turn = if sign > 0 then CFrame.Angles(math.pi, spin, 0) else CFrame.Angles(0, spin, 0)
		-- sunk 0.6 studs into the rock so there's no gap where it meets the ceiling/floor
		cone.CFrame = axis * CFrame.new(0, sign * (len / 2 - 0.6), 0) * turn
		cone.Parent = model
		keep(model, "Decor")
		return
	end

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
		local part = newMesh("lump", rng) or Instance.new("Part")
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

-- a slab of rock set into a wall, floor or ceiling, in the same rock and colour as round it, and
-- textured like the terrain. breaks up the smooth stretches between the big shapes
local function placeOutcrop(wall: Vector3, normal: Vector3, p: Vector3, rng: Random)
	local rock = newMesh("outcrop", rng)
	if not rock then
		return
	end
	local size = rng:NextNumber(3, 7.5)
	rock.Name = "Outcrop"
	rock.Anchored = true
	rock.CanCollide = false
	rock.Material = materialAt(p, false)
	rock.Color = rockColor(p):Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.15))
	rock.Size = Vector3.new(size, size * rng:NextNumber(0.35, 0.6), size * rng:NextNumber(0.7, 1.1))
	-- its flat side faces out of the surface, with about a third of it sticking out
	rock.CFrame = safeLookAt(wall - normal * rock.Size.Y * 0.15, normal)
		* CFrame.Angles(-math.pi / 2, 0, 0)
		* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local model = Instance.new("Model")
	model.Name = "Outcrop"
	rock.Parent = model
	keep(model, "Decor")
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

-- a sagging plank bridge across a chasm. walks out from the middle both ways until it finds
-- floor, so the ends land on the real tunnel floor rather than a guess
local function placeBridge(center: Vector3, dir: Vector3)
	local function edge(sign: number): Vector3?
		for step = 2, 80 do
			local p = center + dir * (sign * step)
			for drop = 0, 14, 2 do
				local below = p - Vector3.new(0, drop, 0)
				if airness(below) < 0 then
					return below
				end
			end
		end
		return nil
	end
	local e1, e2 = edge(-1), edge(1)
	if not e1 or not e2 then
		return
	end
	local a = e1 - dir * 2 + Vector3.new(0, 0.3, 0)
	local b = e2 + dir * 2 + Vector3.new(0, 0.3, 0)
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local length = flat.Magnitude
	if length < 8 or length > 120 then
		return
	end

	local model = Instance.new("Model")
	model.Name = "Bridge"
	local right = dir:Cross(Vector3.yAxis).Unit
	local sagDepth = math.min(3, length * 0.04)
	local function along(t: number): Vector3
		return a:Lerp(b, t) - Vector3.new(0, math.sin(t * math.pi) * sagDepth, 0)
	end

	local function part(name: string, size: Vector3, cframe: CFrame, material: Enum.Material, color: Color3)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = cframe
		p.Material = material
		p.Color = color
		p.Parent = model
		return p
	end

	local planks = math.max(2, math.floor(length / 1.3))
	for i = 0, planks do
		local pos = along(i / planks)
		local shade = Color3.fromRGB(104, 74, 48):Lerp(Color3.fromRGB(80, 56, 36), (i * 37 % 10) / 10)
		part("Plank", Vector3.new(5, 0.3, 1.1), CFrame.lookAt(pos, pos + dir), Enum.Material.WoodPlanks, shade)
	end

	-- rope rails, as short straight pieces so they follow the sag
	local rope = Color3.fromRGB(150, 128, 92)
	for _, side in { -1, 1 } do
		local prev: Vector3? = nil
		for i = 0, planks, 2 do
			local p = along(i / planks) + right * side * 2.4 + Vector3.new(0, 2.6, 0)
			if prev then
				local mid = (prev + p) / 2
				part("Rope", Vector3.new(0.15, 0.15, (p - prev).Magnitude), CFrame.lookAt(mid, p), Enum.Material.Fabric, rope)
			end
			prev = p
		end
		for _, t in { 0, 1 } do
			local base = along(t) + right * side * 2.4
			part("Post", Vector3.new(0.4, 3.2, 0.4), CFrame.new(base + Vector3.new(0, 1.3, 0)), Enum.Material.Wood, Color3.fromRGB(90, 64, 42))
		end
	end

	local lamp = part("Lamp", Vector3.new(0.7, 0.9, 0.7), CFrame.new(along(0) + right * 2.4 + Vector3.new(0, 3.3, 0)), Enum.Material.Neon, Cave.settings.lantern.color)
	local light = Instance.new("PointLight")
	light.Color = Cave.settings.lantern.color
	light.Range = 22
	light.Brightness = 1.4
	light.Parent = lamp

	keep(model, "Bridges")
	Cave.bridges += 1
end

-- the inside of a geode: glowing crystals all over the inner wall pointing in, a light in the middle,
-- and a few sparkles on the nearest tunnel wall as the only clue. built by the chunk its centre is in
local function placeGeode(g, min: Vector3)
	local c = g.c
	local mine = c.X >= min.X and c.X < min.X + SIZE and c.Y >= min.Y and c.Y < min.Y + SIZE and c.Z >= min.Z and c.Z < min.Z + SIZE
	if not mine then
		return
	end
	local rng = Random.new(math.floor(c.X * 7 + c.Y * 13 + c.Z * 17))
	local model = Instance.new("Model")
	model.Name = "Geode"
	local n = 70
	for i = 0, n - 1 do
		-- points spread evenly over the inside of the ball
		local yv = 1 - (i + 0.5) / n * 2
		local ring = math.sqrt(1 - yv * yv)
		local phi = i * 2.399963
		local out = Vector3.new(math.cos(phi) * ring, yv, math.sin(phi) * ring)
		local inward = (-out + Vector3.new(rng:NextNumber(-0.25, 0.25), rng:NextNumber(-0.25, 0.25), rng:NextNumber(-0.25, 0.25))).Unit
		local len = rng:NextNumber(1.5, 3.5)
		local width = rng:NextNumber(0.5, 1)
		local base = c + out * (g.r - 0.8)
		local shard = newMesh("crystal", rng)
		local part: BasePart = shard or Instance.new("Part")
		part.Name = "Shard"
		part.Anchored = true
		part.CanCollide = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = g.color:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.25))
		part.Transparency = 0.1
		if shard then
			part.Size = Vector3.new(width, len, width)
			part.CFrame = safeLookAt(base + inward * len / 2, inward) * CFrame.Angles(-math.pi / 2, 0, 0)
		else
			part.Size = Vector3.new(width, width, len)
			part.CFrame = safeLookAt(base + inward * len / 2, inward)
		end
		part.Parent = model
	end
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.Transparency = 1
	core.Size = Vector3.one
	core.CFrame = CFrame.new(c)
	local light = Instance.new("PointLight")
	light.Color = g.color
	light.Range = g.r * 2.5
	light.Brightness = 1.5
	light.Shadows = false
	light.Parent = core
	core.Parent = model
	keep(model, "Decor")

	-- the clue: find the nearest tunnel wall in any of the six directions and make it sparkle a bit
	local clue, closest = nil, math.huge
	for _, d in { Vector3.xAxis, -Vector3.xAxis, Vector3.yAxis, -Vector3.yAxis, Vector3.zAxis, -Vector3.zAxis } do
		for step = g.r + 3, g.r + 20 do
			if airness(c + d * step) > 0 then
				if step < closest then
					closest = step
					clue = c + d * (step - 0.5)
				end
				break
			end
		end
	end
	if clue then
		local hint = Instance.new("Model")
		hint.Name = "GeodeSparkle"
		local spot = Instance.new("Part")
		spot.Name = "Sparkle"
		spot.Anchored = true
		spot.CanCollide = false
		spot.CanQuery = false
		spot.Transparency = 1
		spot.Size = Vector3.new(3, 3, 3)
		spot.CFrame = CFrame.new(clue)
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Color = ColorSequence.new(g.color)
		sparkle.Size = NumberSequence.new(0.15, 0)
		sparkle.Transparency = NumberSequence.new(0, 1)
		sparkle.Lifetime = NumberRange.new(1, 2)
		sparkle.Speed = NumberRange.new(0.2, 0.6)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Rate = 3
		sparkle.LightEmission = 1
		sparkle.Shape = Enum.ParticleEmitterShape.Box
		sparkle.Parent = spot
		spot.Parent = hint
		keep(hint, "Decor")
	end
end

-- a timber frame just inside a cave mouth, where there's rock over the tunnel, and a lantern
-- behind it. built by whichever chunk the frame lands in
local function placeEntrance(en, min: Vector3)
	local inward = -en.ab.Unit
	local at = nil
	for i = 0, 40 do
		local c = en.mouth + inward * (i * 2)
		if c.Y + en.r * 1.4 < surfaceHeight(c.X, c.Z) then
			at = c
			break
		end
	end
	if not at or at.X < min.X or at.Y < min.Y or at.Z < min.Z
		or at.X >= min.X + SIZE or at.Y >= min.Y + SIZE or at.Z >= min.Z + SIZE
	then
		return
	end
	local wood = Color3.fromRGB(84, 58, 38)
	local model = Instance.new("Model")
	model.Name = "CaveMouth"
	local frame = CFrame.lookAt(at, at + en.out)
	local half = en.r * 0.7
	local function beam(size: Vector3, cf: CFrame)
		local b = Instance.new("Part")
		b.Name = "Timber"
		b.Anchored = true
		b.Size = size
		b.CFrame = cf
		b.Material = Enum.Material.Wood
		b.Color = wood
		b.Parent = model
	end
	for _, x in { -half, half } do
		beam(Vector3.new(1.3, 9, 1.3), frame * CFrame.new(x, 0.75, 0))
	end
	beam(Vector3.new(half * 2 + 2.6, 1.3, 1.5), frame * CFrame.new(0, 5, 0))
	keep(model, "Decor")
	placeLantern(at + inward * 6)
end

-- under a skylight: a faint shaft of light down the crack with dust drifting in it, and a warm light
-- where it lands. the real sun comes down the crack too, this makes sure it reads even when the sun
-- is at an angle. built by the chunk the bottom of the crack is in
local function placeSkylight(sk, min: Vector3)
	if sk.x < min.X or sk.x >= min.X + SIZE or sk.z < min.Z or sk.z >= min.Z + SIZE
		or sk.bottom < min.Y or sk.bottom >= min.Y + SIZE
	then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Skylight"
	local len = sk.top - sk.bottom + 10
	local ray = Instance.new("Part")
	ray.Name = "Ray"
	ray.Shape = Enum.PartType.Cylinder
	ray.Anchored = true
	ray.CanCollide = false
	ray.CanQuery = false
	ray.CastShadow = false
	ray.Material = Enum.Material.Neon
	ray.Color = Color3.fromRGB(255, 240, 205)
	ray.Transparency = 0.94
	-- a cylinder's axis is its x, turn it upright. it reaches 10 studs below the roof so the light
	-- visibly falls into the space
	ray.Size = Vector3.new(len, sk.r * 1.6, sk.r * 1.6)
	ray.CFrame = CFrame.new(sk.x, sk.bottom - 10 + len / 2, sk.z) * CFrame.Angles(0, 0, math.pi / 2)
	local dust = Instance.new("ParticleEmitter")
	dust.Shape = Enum.ParticleEmitterShape.Box
	dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	dust.Color = ColorSequence.new(Color3.fromRGB(255, 244, 220))
	dust.Size = NumberSequence.new(0.08)
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.4), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(4, 7)
	dust.Rate = 6
	dust.Speed = NumberRange.new(0.1, 0.3)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.LightEmission = 0.6
	dust.Parent = ray
	ray.Parent = model
	local spot = Instance.new("Part")
	spot.Name = "Glow"
	spot.Anchored = true
	spot.CanCollide = false
	spot.CanQuery = false
	spot.Transparency = 1
	spot.Size = Vector3.one
	spot.CFrame = CFrame.new(sk.x, sk.bottom - 12, sk.z)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 238, 205)
	light.Range = 24
	light.Brightness = 1.3
	light.Shadows = false
	light.Parent = spot
	spot.Parent = model
	keep(model, "Decor")
end

-- an orange light on the floor of a lava tube every 18 studs or so, so the tube glows
local function placeTubeGlow(tb, min: Vector3)
	local pts = tubePath(tb)
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local steps = math.max(1, math.floor((b - a).Magnitude / 18))
		for step = 0, steps - 1 do
			local floor = a:Lerp(b, step / steps) - Vector3.new(0, tb.r - 1.5, 0)
			local mine = floor.X >= min.X and floor.X < min.X + SIZE
				and floor.Y >= min.Y and floor.Y < min.Y + SIZE
				and floor.Z >= min.Z and floor.Z < min.Z + SIZE
			if mine then
				local model = Instance.new("Model")
				model.Name = "LavaGlow"
				local p = Instance.new("Part")
				p.Name = "Light"
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.Transparency = 1
				p.Size = Vector3.one
				p.CFrame = CFrame.new(floor)
				local light = Instance.new("PointLight")
				light.Color = Color3.fromRGB(255, 110, 40)
				light.Range = 22
				light.Brightness = 1.4
				light.Shadows = false
				light.Parent = p
				p.Parent = model
				keep(model, "Decor")
			end
		end
	end
end

-- a torch on the shaft wall just above the ledge, every quarter turn, so you can see the spiral
local function placeShaftTorches(sh, min: Vector3)
	local s = Cave.settings
	local turnsTotal = (sh.top - sh.bottom) / s.ledgePitch
	local t = 0.25
	while t < turnsTotal do
		-- the ledge's top surface is at this height for this angle
		local y = sh.top - s.ledgePitch * t
		local theta = sh.dir * 2 * math.pi * t - sh.spin
		local c = shaftCentre(sh)
		local at = Vector3.new(c.X + math.cos(theta) * (sh.r - 0.6), y + 3.5, c.Z + math.sin(theta) * (sh.r - 0.6))
		local mine = at.X >= min.X and at.X < min.X + SIZE and at.Y >= min.Y and at.Y < min.Y + SIZE and at.Z >= min.Z and at.Z < min.Z + SIZE
		if mine and y > sh.bottom + 6 then
			local inward = Vector3.new(c.X, at.Y, c.Z) - at
			inward = if inward.Magnitude > 0.1 then inward.Unit else Vector3.xAxis
			local model = Instance.new("Model")
			model.Name = "WallTorch"
			local stick = Instance.new("Part")
			stick.Name = "Stick"
			stick.Anchored = true
			stick.CanCollide = false
			stick.Size = Vector3.new(0.35, 1.4, 0.35)
			stick.CFrame = CFrame.lookAt(at, at + inward) * CFrame.Angles(math.rad(-25), 0, 0)
			stick.Material = Enum.Material.Wood
			stick.Color = Color3.fromRGB(84, 58, 38)
			stick.Parent = model
			local flame = Instance.new("Part")
			flame.Name = "Flame"
			flame.Shape = Enum.PartType.Ball
			flame.Anchored = true
			flame.CanCollide = false
			flame.CastShadow = false
			flame.Size = Vector3.one * 0.6
			flame.CFrame = CFrame.new(at + inward * 0.4 + Vector3.new(0, 0.8, 0))
			flame.Material = Enum.Material.Neon
			flame.Color = Color3.fromRGB(255, 160, 70)
			flame.Parent = model
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 180, 110)
			light.Range = 18
			light.Brightness = 1.6
			light.Parent = flame
			keep(model, "Decor")
		end
		t += 0.25
	end
end

-- is this point in the water part of a river channel
local function riverWaterAt(p: Vector3, rivers): boolean
	local q = warp(p)
	for _, rv in rivers do
		local pts = rv.pts
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local ab = Vector2.new(b.X - a.X, b.Z - a.Z)
			local ap = Vector2.new(q.X - a.X, q.Z - a.Z)
			local k = math.clamp(ap:Dot(ab) / ab:Dot(ab), 0, 1)
			if (ap - ab * k).Magnitude < rv.halfW - 0.5 then
				local bed = a.Y + (b.Y - a.Y) * k
				if q.Y > bed - 1.5 and q.Y < bed + rv.depth then
					return true
				end
			end
		end
	end
	return false
end

-- foam flecks drifting downstream, so the water reads as moving
local function placeCurrent(at: Vector3, flow: Vector3)
	local model = Instance.new("Model")
	model.Name = "Current"
	local p = Instance.new("Part")
	p.Name = "Emitter"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(6, 0.2, 2)
	p.CFrame = CFrame.lookAt(at, at + flow)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(Color3.fromRGB(225, 245, 255))
	e.Size = NumberSequence.new(0.4, 0.08)
	e.Transparency = NumberSequence.new(0.15, 1)
	e.Lifetime = NumberRange.new(1.5, 2.5)
	e.Speed = NumberRange.new(4, 6)
	e.Rate = 12
	e.SpreadAngle = Vector2.new(10, 2)
	e.EmissionDirection = Enum.NormalId.Front
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.LightEmission = 0.8
	e.Parent = p
	p.Parent = model
	keep(model, "Rivers")
end

-- a soft light just under the surface, so the river glows in the dark instead of vanishing
local function placeRiverGlow(at: Vector3)
	local model = Instance.new("Model")
	model.Name = "RiverGlow"
	local p = Instance.new("Part")
	p.Name = "Light"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.CFrame = CFrame.new(at - Vector3.new(0, 1.2, 0))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(90, 200, 230)
	light.Range = 16
	light.Brightness = 0.9
	light.Shadows = false
	light.Parent = p
	p.Parent = model
	keep(model, "Rivers")
end

-- where a river runs out over a drop: a sheet of falling water, streaks down it, spray at the bottom
local function placeWaterfall(top: Vector3, flow: Vector3, halfW: number)
	local drop = 0
	while drop < 220 and airness(top - Vector3.new(0, drop + 2, 0)) > 0 do
		drop += 2
	end
	if drop < 6 then
		return
	end
	local width = halfW * 1.4
	local model = Instance.new("Model")
	model.Name = "Waterfall"

	local mid = top + flow - Vector3.new(0, drop / 2, 0)
	local sheet = Instance.new("Part")
	sheet.Name = "Sheet"
	sheet.Anchored = true
	sheet.CanCollide = false
	sheet.CanQuery = false
	sheet.CastShadow = false
	sheet.Material = Enum.Material.Glass
	sheet.Transparency = 0.45
	sheet.Color = Color3.fromRGB(170, 215, 240)
	sheet.Size = Vector3.new(width, drop, 0.4)
	sheet.CFrame = CFrame.lookAt(mid, mid + flow)
	sheet.Parent = model

	local streaks = Instance.new("ParticleEmitter")
	streaks.Color = ColorSequence.new(Color3.fromRGB(235, 248, 255))
	streaks.Size = NumberSequence.new(0.35, 0.1)
	streaks.Transparency = NumberSequence.new(0.2, 1)
	streaks.Lifetime = NumberRange.new(1, 2)
	streaks.Speed = NumberRange.new(5, 10)
	streaks.Acceleration = Vector3.new(0, -60, 0)
	streaks.Rate = 30
	streaks.EmissionDirection = Enum.NormalId.Bottom
	streaks.Shape = Enum.ParticleEmitterShape.Box
	streaks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	streaks.Parent = sheet

	local base = Instance.new("Part")
	base.Name = "Spray"
	base.Anchored = true
	base.CanCollide = false
	base.CanQuery = false
	base.Transparency = 1
	base.Size = Vector3.new(width, 1, width)
	base.CFrame = CFrame.new(top + flow - Vector3.new(0, drop, 0))
	base.Parent = model
	local mist = Instance.new("ParticleEmitter")
	mist.Color = ColorSequence.new(Color3.fromRGB(240, 250, 255))
	mist.Size = NumberSequence.new(3, 6)
	mist.Transparency = NumberSequence.new(0.7, 1)
	mist.Lifetime = NumberRange.new(2, 4)
	mist.Speed = NumberRange.new(1, 3)
	mist.SpreadAngle = Vector2.new(180, 180)
	mist.Rate = 12
	mist.EmissionDirection = Enum.NormalId.Top
	mist.Parent = base

	keep(model, "Rivers")
end

-- currents along the water, and a waterfall wherever the river runs out over a drop. each spot
-- belongs to exactly one chunk, the one its point on the river line falls in
local function placeRiverDetails(rv, min: Vector3)
	local pts = rv.pts
	local count = 0
	local function held(at: Vector3): boolean
		return airness(unwarp(Vector3.new(at.X, at.Y - 3, at.Z))) < 0
	end
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		if flat.Magnitude > 0.1 then
			local flow = flat.Unit
			local steps = math.max(1, math.floor(flat.Magnitude / 6))
			for step = 0, steps - 1 do
				local qp = a:Lerp(b, step / steps)
				local mine = qp.X >= min.X and qp.X < min.X + SIZE
					and qp.Y >= min.Y and qp.Y < min.Y + SIZE
					and qp.Z >= min.Z and qp.Z < min.Z + SIZE
				if mine then
					local surface = unwarp(qp + Vector3.new(0, rv.depth - 0.2, 0))
					if held(qp) then
						count += 1
						if count % 3 == 0 then
							placeCurrent(surface, flow)
						end
						if count % 4 == 1 then
							placeRiverGlow(surface)
						end
						-- crossing an open cave there's no wall to hold the water in and it just looks like
						-- a puddle, so raise a low bank of the local rock on that side. kept off the chunk
						-- edges, the next chunk to load would slice it
						local inner = qp.X > min.X + 3 and qp.X < min.X + SIZE - 3 and qp.Z > min.Z + 3 and qp.Z < min.Z + SIZE - 3
						if inner then
							local side = Vector3.new(-flow.Z, 0, flow.X)
							for _, sgn in { -1, 1 } do
								local at = unwarp(qp + side * sgn * (rv.halfW + 1.5) + Vector3.new(0, rv.depth * 0.6, 0))
								if airness(at) > 1.5 then
									terrain:FillBall(at, 3.2, materialAt(at, false))
								end
							end
						end
					elseif held(qp - flow * 6) then
						placeWaterfall(surface, flow, rv.halfW)
					end
				end
			end
		end
	end
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
	if min.Y >= s.top + s.surface.height + s.surface.hills * 1.6 + 8 then
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

	-- small sealed bubbles (the rough walls make a few) get filled back in. anything touching
	-- the chunk edge is left alone, it might open up into the next chunk
	local seen: { [number]: boolean } = {}
	local function cellId(x: number, y: number, z: number): number
		return x + (y - 1) * CHUNK + (z - 1) * CHUNK * CHUNK
	end
	for sx = 1, CHUNK do
		for sy = 1, CHUNK do
			for sz = 1, CHUNK do
				if air[sx][sy][sz] and not seen[cellId(sx, sy, sz)] then
					local stack, cells, edge = { Vector3.new(sx, sy, sz) }, {}, false
					seen[cellId(sx, sy, sz)] = true
					while #stack > 0 do
						local c = table.remove(stack) :: Vector3
						table.insert(cells, c)
						if c.X == 1 or c.Y == 1 or c.Z == 1 or c.X == CHUNK or c.Y == CHUNK or c.Z == CHUNK then
							edge = true
						end
						for _, d in DIRS do
							local n = c + d
							if n.X >= 1 and n.Y >= 1 and n.Z >= 1 and n.X <= CHUNK and n.Y <= CHUNK and n.Z <= CHUNK
								and air[n.X][n.Y][n.Z] and not seen[cellId(n.X, n.Y, n.Z)]
							then
								seen[cellId(n.X, n.Y, n.Z)] = true
								table.insert(stack, n)
							end
						end
					end
					if not edge and #cells < 12 then
						for _, c in cells do
							air[c.X][c.Y][c.Z] = false
							occupancy[c.X][c.Y][c.Z] = 1
						end
					end
				end
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

	-- geodes get hollowed out after the pocket cleanup, or it would fill them straight back in
	local geodes = geodesNear(min)
	for _, g in geodes do
		for x = 1, CHUNK do
			for y = 1, CHUNK do
				for z = 1, CHUNK do
					local p = min + Vector3.new(x - 0.5, y - 0.5, z - 0.5) * VOXEL
					local d = (p - g.c).Magnitude
					if d < g.r + 4 then
						local occ = math.clamp(0.5 - (g.r - d) / VOXEL, 0, 1)
						if occ < occupancy[x][y][z] then
							occupancy[x][y][z] = occ
							air[x][y][z] = occ < 0.5
						end
					end
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

	-- a geode's inner wall is violet crystal rock, a couple of studs thick
	for _, g in geodes do
		for x = 1, CHUNK do
			for y = 1, CHUNK do
				for z = 1, CHUNK do
					if occupancy[x][y][z] > 0 then
						local p = min + Vector3.new(x - 0.5, y - 0.5, z - 0.5) * VOXEL
						if (p - g.c).Magnitude < g.r + 2.5 then
							materials[x][y][z] = Enum.Material.Glacier
						end
					end
				end
			end
		end
	end

	-- river water: fills the bottom of any channel through here, but a cell only gets water if
	-- the one under it is rock or water. roblox water doesn't flow, it'd hang over a drop
	local rf = featuresFor(cx, cy, cz)
	if #rf.rivers > 0 then
		for x = 1, CHUNK do
			for z = 1, CHUNK do
				local under = min + Vector3.new((x - 0.5) * VOXEL, -VOXEL / 2, (z - 0.5) * VOXEL)
				local held = not (air[x][1][z] and airness(under) > 0)
				for y = 1, CHUNK do
					if not air[x][y][z] then
						held = true
					else
						local p = min + Vector3.new(x - 0.5, y - 0.5, z - 0.5) * VOXEL
						if held and riverWaterAt(p, rf.rivers) then
							materials[x][y][z] = Enum.Material.Water
							occupancy[x][y][z] = 1
							-- sand under the water so the bottom looks like a riverbed, not cave wall
							if y > 1 and not air[x][y - 1][z] then
								materials[x][y - 1][z] = Enum.Material.Sand
							end
						else
							held = false
						end
					end
				end
			end
		end
	end

	-- pools: water settles in the dips in the floor. start from any open cell with rock under it and
	-- spread sideways over the floor at that height. if it reaches a drop, the chunk edge or river
	-- water, or gets too big, it would run away, so it stays dry. only a dip walled in on every
	-- side fills up. the rock round it gets a flowstone rim, the crust real pools leave
	local pooled: { [number]: boolean } = {}
	local function pid(x: number, y: number, z: number): number
		return x + (y - 1) * CHUNK + (z - 1) * CHUNK * CHUNK
	end
	local SIDES = { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }
	for y = 2, CHUNK do
		for x = 1, CHUNK do
			for z = 1, CHUNK do
				if air[x][y][z] and not air[x][y - 1][z] and not pooled[pid(x, y, z)]
					and materials[x][y][z] ~= Enum.Material.Water
				then
					local start = min + Vector3.new(x - 0.5, y - 0.5, z - 0.5) * VOXEL
					local cells, walls, stack = {}, {}, { Vector3.new(x, y, z) }
					-- underground only, water sitting in little dips on the grass just looked like cyan stickers
					local leaks = start.Y < s.lavaBelow or tubeClearance(start) > -3
						or start.Y > surfaceHeight(start.X, start.Z) - 8
					pooled[pid(x, y, z)] = true
					while #stack > 0 do
						local c = table.remove(stack) :: Vector3
						table.insert(cells, c)
						for _, d in SIDES do
							local n = c + d
							if n.X < 1 or n.Z < 1 or n.X > CHUNK or n.Z > CHUNK then
								leaks = true
							elseif not air[n.X][y][n.Z] then
								table.insert(walls, n)
							elseif materials[n.X][y][n.Z] == Enum.Material.Water or air[n.X][y - 1][n.Z] then
								leaks = true
							elseif not pooled[pid(n.X, y, n.Z)] then
								pooled[pid(n.X, y, n.Z)] = true
								table.insert(stack, n)
							end
						end
						if #cells > s.pools.maxCells then
							leaks = true
						end
					end
					if not leaks then
						Cave.pools += 1
						for _, c in cells do
							materials[c.X][y][c.Z] = Enum.Material.Water
							occupancy[c.X][y][c.Z] = 1
						end
						if biomeAt(start) == "rock" and start.Y < surfaceHeight(start.X, start.Z) - 8 then
							for _, c in cells do
								materials[c.X][y - 1][c.Z] = s.pools.flowstone
							end
							for _, w in walls do
								materials[w.X][y][w.Z] = s.pools.flowstone
							end
						end
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

	-- rope bridges where a tunnel runs into a chasm. the chunk the crossing point falls in builds
	-- it, so each bridge only gets built once
	local f = featuresFor(cx, cy, cz)
	for _, c in f.chasms do
		for _, t in f.tunnels do
			-- ramps are too steep to bridge
			if math.abs(t.ab.Y) < 10 then
				local dx, dz = t.ab.X, t.ab.Z
				local ex, ez = c.ab.X, c.ab.Y
				local denom = dx * ez - dz * ex
				if math.abs(denom) > 1e-6 then
					local wx, wz = c.a.X - t.a.X, c.a.Y - t.a.Z
					local u = (wx * ez - wz * ex) / denom
					local w = (wx * dz - wz * dx) / denom
					if u > 0 and u < 1 and w > 0.05 and w < 0.95 then
						local hit = t.a + t.ab * u
						local mine = hit.X >= min.X and hit.X < min.X + SIZE
							and hit.Y >= min.Y and hit.Y < min.Y + SIZE
							and hit.Z >= min.Z and hit.Z < min.Z + SIZE
						if mine and hit.Y > c.bottom + 10 and hit.Y < c.top - 6 then
							-- the tunnel's been bent by the warp, step back to where it really runs
							local p = hit
							for _ = 1, 4 do
								p = hit - (warp(p) - p)
							end
							placeBridge(p, Vector3.new(dx, 0, dz).Unit)
						end
					end
				end
			end
		end
	end

	for _, rv in f.rivers do
		placeRiverDetails(rv, min)
	end
	for _, sh in f.shafts do
		placeShaftTorches(sh, min)
	end
	for _, tb in f.tubes do
		placeTubeGlow(tb, min)
	end
	for _, g in geodes do
		placeGeode(g, min)
	end
	if min.Y > s.top - SIZE - 12 then
		for _, en in entrancesNear(cx, cz) do
			placeEntrance(en, min)
		end
		for _, sk in skylightsNear(cx, cz) do
			placeSkylight(sk, min)
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
	-- nothing from the caves grows on the hills outside
	local nearTop = min.Y + SIZE > s.top - 8
	local function outdoors(x: number, y: number, z: number): boolean
		local p = min + Vector3.new(x - 0.5, y - 0.5, z - 0.5) * VOXEL
		return p.Y > surfaceHeight(p.X, p.Z) - 6
	end
	for x = 2, CHUNK - 1 do
		for y = 2, CHUNK - 1 do
			for z = 2, CHUNK - 1 do
				if not air[x][y][z] and not (nearTop and outdoors(x, y, z)) then
					-- half-buried boulders on floors, made of the same rock so they blend in. kept off
					-- the chunk edges or the next chunk to load would slice them in half
					if air[x][y + 1][z] and x >= 3 and x <= CHUNK - 2 and z >= 3 and z <= CHUNK - 2
						and rng:NextNumber() < s.boulderChance
					then
						local fp = min + Vector3.new(x - 0.5, y - 0.5, z - 0.5) * VOXEL
						local floor = (wallBetween(fp, Vector3.yAxis))
						local br = rng:NextNumber(1.8, 3.6)
						terrain:FillBall(floor + Vector3.new(0, br * 0.2, 0), br, materialAt(fp, false))
					end
					-- glowworms on the ceiling of any big space, caverns and wide galleries, so there's a
					-- roof of little lights over them instead of black
					if air[x][y - 1][z] and rng:NextNumber() < s.glowwormChance then
						local cp = min + Vector3.new(x - 0.5, y - 0.5, z - 0.5) * VOXEL
						if inCavern(cp) or airness(cp - Vector3.new(0, 10, 0)) > s.bigSpace then
							placeGlowworms((wallBetween(cp, -Vector3.yAxis)), rng)
						end
					end
					local open: Vector3? = nil
					for _, d in DIRS do
						if air[x + d.X][y + d.Y][z + d.Z] then
							open = d
							break
						end
					end
					if open then
						local p = min + Vector3.new(x - 0.5, y - 0.5, z - 0.5) * VOXEL
						-- rock slabs in the surfaces, everywhere but the lava tubes (those stay smooth)
						if rng:NextNumber() < s.outcropChance and tubeClearance(p) < -3 then
							local wall, normal = wallBetween(p, open)
							placeOutcrop(wall, normal, p, rng)
						end
						-- glowing fungus on the walls of big spaces. not in the crystal caves or lava tubes,
						-- they light themselves
						if open.Y == 0 and rng:NextNumber() < s.fungusChance then
							local wall, normal = wallBetween(p, open)
							if airness(wall + normal * 10) > s.bigSpace and tubeClearance(p) < -3 and biomeAt(p) ~= "crystal" then
								placeFungus(wall, normal, rng)
							end
						end
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
							elseif biome == "pools" then
								local roll = rng:NextNumber()
								-- pools stay away from chunk edges, the next chunk to load would cut them in half
								local inner = x >= 3 and x <= CHUNK - 2 and z >= 3 and z <= CHUNK - 2
								if open == Vector3.yAxis and inner and roll < s.biomes.poolChance then
									local wall, normal = wallBetween(p, open)
									if normal.Y > 0.8 then
										placeTidePool(wall, rng)
									end
								elseif open ~= Vector3.yAxis and roll < s.biomes.algaeChance then
									local wall, normal = wallBetween(p, open)
									placeAlgae(wall, normal, rng)
								end
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
								end
							end
						end
					end
				end
			end
		end
	end	collecting = nil
end

-- the far ground: every ground-level chunk within surfaceRadius, plus the 4 under it wherever a
-- sinkhole or cave mouth opens up, so you don't look down one and see sky at the bottom
local function farGround(cx: number, cz: number): { Vector3 }
	local s = Cave.settings
	local groundCy = math.floor(s.top / SIZE)
	local sr = s.surfaceRadius
	local list = {}
	for dx = -sr, sr do
		for dz = -sr, sr do
			local x, z = cx + dx, cz + dz
			table.insert(list, Vector3.new(x, groundCy, z))
			if #featuresFor(x, groundCy - 1, z).shafts > 0 or #entrancesNear(x, z) > 0 then
				for dy = 1, 4 do
					table.insert(list, Vector3.new(x, groundCy - dy, z))
				end
			end
		end
	end
	return list
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
	-- near the top, the ground layer loads a lot further out so the hills don't stop at a cliff edge
	local groundCy = math.floor(Cave.settings.top / SIZE)
	if cy >= groundCy - 2 then
		for _, c in farGround(cx, cz) do
			if not done[chunkKey(c.X, c.Y, c.Z)] then
				table.insert(todo, c - Vector3.new(cx, cy, cz))
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
			local groundCy = math.floor(Cave.settings.top / SIZE)
			for _, p in centers do
				local d = c - p
				if math.max(math.abs(d.X), math.abs(d.Y), math.abs(d.Z)) <= keepWithin then
					near = true
					break
				end
				-- the far ground layer stays while you're anywhere near the top
				if c.Y >= groundCy - 4 and p.Y >= groundCy - 2
					and math.max(math.abs(d.X), math.abs(d.Z)) <= Cave.settings.surfaceRadius + Cave.settings.unloadMargin
				then
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
	-- nodes live in bent space, unwarp puts it where the tunnel really is
	local node = unwarp(nodeAt(math.floor(c.X / SIZE), cy, math.floor(c.Z / SIZE)))
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
-- colours, textures, lighting and the prop meshes: everything a build needs before the first chunk
function Cave.prepare()
	Cave.applyColors()
	Cave.applyTextures()
	Cave.applyLighting()
	-- build the prop meshes up front so chunk generation never stops to wait for them
	buildMeshLib()
end

-- every chunk a build round this spot needs, nearest first: the caves r chunks round it, and if it's
-- near the top the far ground layer too. the editor plugin and the timelapse build from this list
function Cave.chunksAround(spot: Vector3, radius: number?, withGround: boolean?): { Vector3 }
	local r = radius or 2
	local cx, cy, cz = math.floor(spot.X / SIZE), math.floor(spot.Y / SIZE), math.floor(spot.Z / SIZE)
	local list = {}
	for dy = -2, 1 do
		for dx = -r, r do
			for dz = -r, r do
				table.insert(list, Vector3.new(cx + dx, cy + dy, cz + dz))
			end
		end
	end
	local groundCy = math.floor(Cave.settings.top / SIZE)
	if withGround ~= false and cy >= groundCy - 2 then
		for _, c in farGround(cx, cz) do
			table.insert(list, c)
		end
	end
	local middle = Vector3.new(cx, cy, cz)
	table.sort(list, function(a, b)
		return (a - middle).Magnitude < (b - middle).Magnitude
	end)
	return list
end

function Cave.preview(center: Vector3?, radius: number?): Vector3
	local spot = Cave.findSpawn(center)
	Cave.prepare()
	for _, c in Cave.chunksAround(spot, radius) do
		Cave.generateChunk(c.X, c.Y, c.Z)
	end
	if not RunService:IsRunning() then
		Workspace.CurrentCamera.CFrame = CFrame.lookAt(spot, spot + Vector3.new(1, 0, 0))
	end
	print(("cave: %d ores placed, %d bridges"):format(Cave.placed, Cave.bridges))
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
						if nodeKind(x, cy, z) == "cavern" then
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

-- finds the nearest chasm, builds around it and (in edit mode) hangs the camera partway down it
function Cave.findChasm(near: Vector3?): Vector3?
	local s = Cave.settings
	local c = near or Vector3.zero
	local cell = s.chasmCell
	local gx0, gz0 = math.floor(c.X / cell), math.floor(c.Z / cell)
	for r = 0, 6 do
		for dx = -r, r do
			for dz = -r, r do
				local gx, gz = gx0 + dx, gz0 + dz
				if math.max(math.abs(dx), math.abs(dz)) == r and hash(gx, 7777, gz, 50) < s.chasmChance then
					-- same numbers featuresFor uses for this cell
					local center = Vector2.new((gx + 0.2 + hash(gx, 7777, gz, 51) * 0.6) * cell, (gz + 0.2 + hash(gx, 7777, gz, 52) * 0.6) * cell)
					local angle = hash(gx, 7777, gz, 53) * math.pi
					local top = s.top - 14 - hash(gx, 7777, gz, 55) * 20
					local eye = Vector3.new(center.X, top - 30, center.Y)
					Cave.preview(eye, 3)
					if not RunService:IsRunning() then
						local dir = Vector3.new(math.cos(angle), -0.25, math.sin(angle))
						Workspace.CurrentCamera.CFrame = CFrame.lookAt(eye, eye + dir)
					end
					print("cave: chasm at", eye)
					return eye
				end
			end
		end
	end
	warn("cave: no chasm found nearby, raise chasmChance or try another seed")
	return nil
end

-- finds the nearest skylight, builds round it and (in edit mode) looks up the crack from the floor
function Cave.findSkylight(near: Vector3?): Vector3?
	local c = near or Vector3.zero
	local cell = Cave.settings.surface.skylightCell
	local gx0, gz0 = math.floor(c.X / cell), math.floor(c.Z / cell)
	for r = 0, 6 do
		for dx = -r, r do
			for dz = -r, r do
				if math.max(math.abs(dx), math.abs(dz)) == r then
					local sk = skylightForCell(gx0 + dx, gz0 + dz)
					if sk then
						local under = Vector3.new(sk.x + 14, sk.bottom - 12, sk.z + 6)
						Cave.preview(under, 2)
						if not RunService:IsRunning() then
							Workspace.CurrentCamera.CFrame = CFrame.lookAt(under, Vector3.new(sk.x, sk.bottom + 6, sk.z))
						end
						print("cave: skylight at", sk.x, sk.bottom, sk.z)
						return Vector3.new(sk.x, sk.bottom, sk.z)
					end
				end
			end
		end
	end
	warn("cave: no skylight found nearby, raise surface.skylightChance")
	return nil
end

-- finds the nearest cave mouth, builds around it and (in edit mode) looks at it from outside
function Cave.findEntrance(near: Vector3?): (Vector3?, Vector3?)
	local c = near or Vector3.zero
	local cell = Cave.settings.surface.entranceCell
	local gx0, gz0 = math.floor(c.X / cell), math.floor(c.Z / cell)
	for r = 0, 5 do
		for dx = -r, r do
			for dz = -r, r do
				if math.max(math.abs(dx), math.abs(dz)) == r then
					local en = entranceForCell(gx0 + dx, gz0 + dz)
					if en then
						Cave.preview(en.mouth, 2)
						if not RunService:IsRunning() then
							local eye = en.mouth + en.out * 30 + Vector3.new(0, 10, 0)
							Workspace.CurrentCamera.CFrame = CFrame.lookAt(eye, en.mouth)
						end
						print("cave: cave mouth at", en.mouth)
						return en.mouth, en.a
					end
				end
			end
		end
	end
	warn("cave: no cave mouth found nearby, raise surface.entranceChance")
	return nil
end

-- finds the nearest geode, builds around it and (in edit mode) puts the camera inside it
function Cave.findGeode(near: Vector3?): Vector3?
	local c = near or Vector3.new(0, -100, 0)
	local cell = Cave.settings.geodeCell
	local gx0, gy0, gz0 = math.floor(c.X / cell), math.floor(c.Y / cell), math.floor(c.Z / cell)
	for r = 0, 4 do
		for dx = -r, r do
			for dy = -r, r do
				for dz = -r, r do
					if math.max(math.abs(dx), math.abs(dy), math.abs(dz)) == r then
						local g = geodeForCell(gx0 + dx, gy0 + dy, gz0 + dz)
						if g then
							Cave.preview(g.c, 1)
							if not RunService:IsRunning() then
								Workspace.CurrentCamera.CFrame = CFrame.lookAt(g.c, g.c + Vector3.new(1, -0.3, 0.2))
							end
							print("cave: geode at", g.c)
							return g.c
						end
					end
				end
			end
		end
	end
	warn("cave: no geode found nearby, raise geodeChance or try another seed")
	return nil
end

-- finds the nearest lava tube, builds around it and (in edit mode) looks along it from the middle
function Cave.findTube(near: Vector3?): Vector3?
	local c = near or Vector3.zero
	local cell = Cave.settings.tubeCell
	local gx0, gz0 = math.floor(c.X / cell), math.floor(c.Z / cell)
	for r = 0, 6 do
		for dx = -r, r do
			for dz = -r, r do
				if math.max(math.abs(dx), math.abs(dz)) == r then
					local tb = tubeForCell(gx0 + dx, gz0 + dz)
					if tb then
						local pts = tubePath(tb)
						local eye = pts[5]
						Cave.preview(eye, 2)
						if not RunService:IsRunning() then
							Workspace.CurrentCamera.CFrame = CFrame.lookAt(eye, pts[6])
						end
						print("cave: lava tube at", eye)
						return eye
					end
				end
			end
		end
	end
	warn("cave: no lava tube found nearby, raise tubeChance or try another seed")
	return nil
end

-- finds the nearest shaft, builds around it and (in edit mode) looks down the spiral from near the top
function Cave.findShaft(near: Vector3?): Vector3?
	local c = near or Vector3.zero
	local cell = Cave.settings.shaftCell
	local gx0, gz0 = math.floor(c.X / cell), math.floor(c.Z / cell)
	for r = 0, 6 do
		for dx = -r, r do
			for dz = -r, r do
				if math.max(math.abs(dx), math.abs(dz)) == r then
					local sh = shaftForCell(gx0 + dx, gz0 + dz)
					if sh then
						local centre = shaftCentre(sh)
						local eye = Vector3.new(centre.X, sh.top - 24, centre.Z)
						Cave.preview(eye, 3)
						if not RunService:IsRunning() then
							local down = Vector3.new(centre.X + sh.r * 0.8, sh.top - 70, centre.Z)
							Workspace.CurrentCamera.CFrame = CFrame.lookAt(eye, down)
						end
						print("cave: shaft at", eye)
						return eye
					end
				end
			end
		end
	end
	warn("cave: no shaft found nearby, raise shaftChance or try another seed")
	return nil
end

-- finds the nearest river, builds around it and (in edit mode) looks downstream along it
function Cave.findRiver(near: Vector3?): Vector3?
	local c = near or Vector3.zero
	local cell = Cave.settings.riverCell
	local gx0, gz0 = math.floor(c.X / cell), math.floor(c.Z / cell)
	for r = 0, 6 do
		for dx = -r, r do
			for dz = -r, r do
				if math.max(math.abs(dx), math.abs(dz)) == r then
					local rv = riverForCell(gx0 + dx, gz0 + dz)
					if rv then
						local eye = unwarp(rv.pts[3] + Vector3.new(0, rv.depth + 3, 0))
						Cave.preview(eye, 2)
						if not RunService:IsRunning() then
							local ahead = unwarp(rv.pts[4] + Vector3.new(0, rv.depth + 3, 0))
							Workspace.CurrentCamera.CFrame = CFrame.lookAt(eye, ahead)
						end
						print("cave: river at", eye)
						return eye
					end
				end
			end
		end
	end
	warn("cave: no river found nearby, raise riverChance or try another seed")
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

	-- which way the first tunnel goes: along one of the node's links, a level one if there is one
	local c = center or Vector3.new(0, -40, 0)
	local nx, nz = math.floor(c.X / SIZE), math.floor(c.Z / SIZE)
	local ny = math.min(math.floor(c.Y / SIZE), math.floor(Cave.settings.top / SIZE) - 1)
	local links = linkedTo(nx, ny, nz)
	local first = links[1]
	for _, l in links do
		if l.Y == ny then
			first = l
			break
		end
	end
	local node, east = nodeAt(nx, ny, nz), nodeAt(first.X, first.Y, first.Z)
	local flatDir = Vector3.new(east.X - node.X, 0, east.Z - node.Z).Unit
	local floorMid = Vector3.new(spot.X, floorY, spot.Z)
	-- room-local frame: -z points at the first tunnel, +x is to your right
	local base = CFrame.lookAt(floorMid, floorMid + flatDir)
	local metal = Color3.fromRGB(62, 62, 66)
	local darkWood = Color3.fromRGB(84, 58, 38)

	-- rails and sleepers running from the pad towards the tunnel
	for _, x in { -1.2, 1.2 } do
		block("Rail", Vector3.new(0.25, 0.25, 15), base * CFrame.new(x, 0.25, -11.5), Enum.Material.Metal, metal)
	end
	for i = 0, 10 do
		block("Sleeper", Vector3.new(3.4, 0.2, 0.5), base * CFrame.new(0, 0.1, -(4 + i * 1.5)), Enum.Material.Wood, darkWood)
	end

	-- a minecart on the rails with some coal in it
	local cart = base * CFrame.new(0, 1.1, -13)
	block("CartFloor", Vector3.new(3, 0.3, 4.4), cart, Enum.Material.WoodPlanks, darkWood)
	for _, x in { -1.5, 1.5 } do
		block("CartSide", Vector3.new(0.3, 1.8, 4.4), cart * CFrame.new(x, 0.9, 0), Enum.Material.WoodPlanks, darkWood)
	end
	for _, z in { -2.2, 2.2 } do
		block("CartEnd", Vector3.new(3, 1.8, 0.3), cart * CFrame.new(0, 0.9, z), Enum.Material.WoodPlanks, darkWood)
	end
	for _, x in { -1.6, 1.6 } do
		for _, z in { -1.4, 1.4 } do
			local wheel = block("Wheel", Vector3.new(0.4, 1.2, 1.2), cart * CFrame.new(x, -0.4, z), Enum.Material.Metal, metal)
			wheel.Shape = Enum.PartType.Cylinder
		end
	end
	local coal = Cave.settings.ores[1]
	for i = 1, 6 do
		local lump = block("Coal", Vector3.new(0.9, 0.7, 0.9), cart * CFrame.new(((i - 1) % 3 - 1) * 0.8, 1.2 + (i > 3 and 0.4 or 0), (i > 3 and 0.8 or -0.6)) * CFrame.Angles(i, i * 2, 0), coal.material, coal.color)
		lump.CanCollide = false
	end

	-- crates in one back corner, barrels in the other
	local crate = Color3.fromRGB(122, 90, 58)
	block("Crate", Vector3.new(3, 3, 3), base * CFrame.new(13, 1.5, 13), Enum.Material.WoodPlanks, crate)
	block("Crate", Vector3.new(3, 3, 3), base * CFrame.new(13, 4.5, 13) * CFrame.Angles(0, 0.4, 0), Enum.Material.WoodPlanks, crate)
	block("Crate", Vector3.new(2.4, 2.4, 2.4), base * CFrame.new(9.6, 1.2, 13.5) * CFrame.Angles(0, -0.3, 0), Enum.Material.WoodPlanks, crate)
	for _, at in { Vector3.new(-13, 1.5, 13), Vector3.new(-10.3, 1.5, 13.6) } do
		local barrel = block("Barrel", Vector3.new(3, 2.3, 2.3), base * CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Wood, darkWood)
		barrel.Shape = Enum.PartType.Cylinder
	end

	-- a sign on a post with the controls, facing the pad
	block("SignPost", Vector3.new(0.4, 3.4, 0.4), base * CFrame.new(-9, 1.7, -4), Enum.Material.Wood, darkWood)
	local sign = block("Sign", Vector3.new(6, 3.2, 0.3), base * CFrame.new(-9, 4.2, -4) * CFrame.Angles(0, -math.pi / 2, 0), Enum.Material.WoodPlanks, crate)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.SourceSansBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(250, 236, 205)
	label.Text = "hold click with the pickaxe\nto mine ore and dig rock\nF to throw a flare\n\nfollow the lanterns out"
	label.Parent = gui
	gui.Parent = sign

	-- a tool rack with a spare pickaxe leaning on it
	for _, z in { -3, -5 } do
		block("RackPost", Vector3.new(0.3, 3, 0.3), base * CFrame.new(10, 1.5, z), Enum.Material.Wood, darkWood)
	end
	block("RackBar", Vector3.new(0.3, 0.3, 2.6), base * CFrame.new(10, 2.8, -4), Enum.Material.Wood, darkWood)
	local lean = base * CFrame.new(9.4, 1.6, -4) * CFrame.Angles(0, 0, -0.35)
	block("SpareHandle", Vector3.new(0.25, 3.4, 0.25), lean, Enum.Material.Wood, Color3.fromRGB(110, 78, 50))
	block("SpareHead", Vector3.new(0.4, 0.45, 2.8), lean * CFrame.new(0, 1.6, 0), Enum.Material.Metal, Color3.fromRGB(132, 132, 140))

	room.Parent = Workspace

	-- the first tunnel: lanterns showing the way out, and a bit of easy ore so the first minute pays off
	local rng = Random.new(Cave.settings.seed * 31 + 7)
	-- starts past the dug-out room, otherwise the wall they need is already gone
	for _, t in { 0.5, 0.72, 0.95 } do
		placeLantern(unwarp(node:Lerp(east, t)))
	end
	local right = flatDir:Cross(Vector3.yAxis).Unit
	for i, pick in { { t = 0.55, side = 1, ore = 1 }, { t = 0.68, side = -1, ore = 1 }, { t = 0.82, side = 1, ore = 2 } } do
		local from = unwarp(node:Lerp(east, pick.t))
		local dir = (right * pick.side + Vector3.new(0, -0.3, 0)).Unit
		for s = 0.5, 24, 0.5 do
			if airness(from + dir * s) < 0 then
				local wall = from + dir * (s - 0.25)
				local n = Vector3.new(
					airness(wall + Vector3.xAxis) - airness(wall - Vector3.xAxis),
					airness(wall + Vector3.yAxis) - airness(wall - Vector3.yAxis),
					airness(wall + Vector3.zAxis) - airness(wall - Vector3.zAxis)
				)
				local normal = if n.Magnitude > 0 then n.Unit else -dir
				placeOre(Cave.settings.ores[pick.ore], wall + normal * Cave.settings.oreOffset, normal, rng)
				break
			end
		end
	end

	-- only spawn in the mine
	for _, other in Workspace:GetDescendants() do
		if other:IsA("SpawnLocation") and other ~= pad then
			other.Enabled = false
		end
	end

	return pad.CFrame + Vector3.new(0, 3, 0)
end

-- the bits of the network the debug views and the editor plugin need to see
Cave.SIZE = SIZE
Cave.VOXEL = VOXEL
Cave.network = {
	nodeAt = nodeAt,
	hasNode = hasNode,
	linkedTo = linkedTo,
	nodeKind = nodeKind,
	unwarp = unwarp,
}

-- numbers for this seed's network, in a block of regions around the spawn: how many junctions,
-- dead ends, hubs and loops, how much tunnel, and whether it's all one piece
function Cave.stats(regions: number?, levels: number?): { [string]: number }
	local s = Cave.settings
	local n = s.regionSize
	local half = (regions or 3) * n
	local topY = math.floor(s.top / SIZE) - 1
	local lowY = topY - (levels or 4) + 1
	local function inside(v: Vector3): boolean
		return v.X >= -half and v.X < half and v.Z >= -half and v.Z < half and v.Y <= topY and v.Y >= lowY
	end
	local out = { nodes = 0, links = 0, deadEnds = 0, hubs = 0, caverns = 0, chambers = 0, pieces = 0, loops = 0, tunnelStuds = 0 }
	local seen: { [string]: boolean } = {}
	for y = topY, lowY, -1 do
		for x = -half, half - 1 do
			for z = -half, half - 1 do
				out.nodes += 1
				local here = Vector3.new(x, y, z)
				local links = linkedTo(x, y, z)
				for _, l in links do
					-- count each link once, from its lower end, and only if both ends are in the block
					if inside(l) and (l.Y < y or (l.Y == y and (l.X > x or (l.X == x and l.Z > z)))) then
						out.links += 1
						out.tunnelStuds += (nodeAt(l.X, l.Y, l.Z) - nodeAt(x, y, z)).Magnitude
					end
				end
				local kind = nodeKind(x, y, z)
				if #links == 1 then out.deadEnds += 1 end
				if #links >= 4 then out.hubs += 1 end
				if kind == "cavern" then out.caverns += 1 end
				if kind == "chamber" or kind == "hub" or kind == "pocket" then out.chambers += 1 end
				-- flood fill from every node nobody's reached yet, each fill is one separate piece
				local key = x .. "," .. y .. "," .. z
				if not seen[key] then
					out.pieces += 1
					seen[key] = true
					local stack = { here }
					while #stack > 0 do
						local v = table.remove(stack) :: Vector3
						for _, l in linkedTo(v.X, v.Y, v.Z) do
							local k = l.X .. "," .. l.Y .. "," .. l.Z
							if inside(l) and not seen[k] then
								seen[k] = true
								table.insert(stack, l)
							end
						end
					end
				end
			end
		end
	end
	out.loops = out.links - out.nodes + out.pieces
	out.tunnelStuds = math.floor(out.tunnelStuds)
	print(("cave stats, seed %d, %d junctions: %d dead ends, %d hubs, %d loops, %d caverns, %d chambers, %.1f km of tunnel, %s"):format(
		s.seed, out.nodes, out.deadEnds, out.hubs, out.loops, out.caverns, out.chambers, out.tunnelStuds * 0.28 / 1000,
		if out.pieces == 1 then "all one connected cave" else out.pieces .. " SEPARATE PIECES"))
	return out
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
	getFolder("Bridges"):ClearAllChildren()
	getFolder("Rivers"):ClearAllChildren()
	table.clear(done)
	table.clear(chunkObjects)
	table.clear(chunkCoords)
	table.clear(pinned)
	table.clear(digs)
	table.clear(lights)
	table.clear(featureCache)
	table.clear(layoutCache)
	table.clear(entranceCache)
	table.clear(entranceChunks)
	table.clear(skylightCache)
	table.clear(skylightChunks)
	Cave.placed = 0
	Cave.pools = 0
	Cave.bridges = 0
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

-- the pickaxe (Pickaxe.client.luau) sends where you're pointing, the server decides if you're allowed
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
	if at.Y > surfaceHeight(at.X, at.Z) + 4 then
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

-- the pickaxe (Pickaxe.client.luau) sends what it hit, the server decides if you're allowed
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

-- ============================================================ helmet lamp and flares

local function giveLamp(character: Model)
	local head = character:WaitForChild("Head", 5) :: BasePart?
	if not head or head:FindFirstChild("HelmetLamp") then
		return
	end
	local l = Cave.settings.lamp
	local beam = Instance.new("SpotLight")
	beam.Name = "HelmetLamp"
	beam.Face = Enum.NormalId.Front
	beam.Range = l.range
	beam.Angle = l.angle
	beam.Brightness = l.brightness
	beam.Color = l.color
	beam.Shadows = true
	beam.Parent = head
	-- a little spill so your own feet aren't in the dark
	local spill = Instance.new("PointLight")
	spill.Name = "LampSpill"
	spill.Range = 9
	spill.Brightness = 0.5
	spill.Color = l.color
	spill.Shadows = false
	spill.Parent = head
end

function Cave.enableLamps()
	local function hook(player: Player)
		player.CharacterAdded:Connect(giveLamp)
		if player.Character then
			task.spawn(giveLamp, player.Character)
		end
	end
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerAdded:Connect(hook)
end

local lastFlare: { [Player]: number } = {}
local liveFlares: { [Player]: { BasePart } } = {}

local function throwFlare(player: Player, dir: Vector3)
	local f = Cave.settings.flare
	local now = os.clock()
	if now - (lastFlare[player] or 0) < f.cooldown then
		return
	end
	local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
	if not head or dir.Magnitude < 0.01 or dir.Magnitude > 2 then
		return
	end
	lastFlare[player] = now
	dir = dir.Unit

	-- only so many burning at once, the oldest goes out
	local mine = liveFlares[player] or {}
	liveFlares[player] = mine
	while #mine >= f.maxEach do
		local old = table.remove(mine, 1)
		if old then
			old:Destroy()
		end
	end

	local flare = Instance.new("Part")
	flare.Name = "Flare"
	flare.Size = Vector3.new(0.35, 0.35, 1.2)
	flare.Material = Enum.Material.Neon
	flare.Color = f.color
	flare.CFrame = CFrame.lookAt(head.Position + dir * 2, head.Position + dir * 3)
	flare.AssemblyLinearVelocity = dir * f.speed + Vector3.new(0, 12, 0)
	flare.AssemblyAngularVelocity = Vector3.new(math.random() * 10 - 5, math.random() * 10 - 5, math.random() * 10 - 5)

	local light = Instance.new("PointLight")
	light.Color = f.color
	light.Range = 32
	light.Brightness = 3
	light.Shadows = true
	light.Parent = flare

	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(f.color, Color3.fromRGB(255, 220, 120))
	sparks.Size = NumberSequence.new(0.25, 0)
	sparks.Speed = NumberRange.new(3, 8)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.Rate = 40
	sparks.LightEmission = 1
	sparks.Acceleration = Vector3.new(0, -20, 0)
	sparks.Parent = flare

	flare.Parent = Workspace
	-- the server moves it, so everyone sees the same bounce
	flare:SetNetworkOwner(nil)
	table.insert(mine, flare)

	task.delay(f.burn - 3, function()
		if flare.Parent then
			sparks.Enabled = false
			TweenService:Create(light, TweenInfo.new(3), { Brightness = 0 }):Play()
		end
	end)
	Debris:AddItem(flare, f.burn)
end

function Cave.enableFlares()
	local remote = ReplicatedStorage:FindFirstChild("CaveFlare") :: RemoteEvent?
	if not remote then
		local created = Instance.new("RemoteEvent")
		created.Name = "CaveFlare"
		created.Parent = ReplicatedStorage
		remote = created
	end
	(remote :: RemoteEvent).OnServerEvent:Connect(function(player, dir)
		if typeof(dir) == "Vector3" then
			throwFlare(player, dir)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastFlare[player] = nil
		for _, flare in liveFlares[player] or {} do
			flare:Destroy()
		end
		liveFlares[player] = nil
	end)
end

-- the seed in the bottom corner, so people can share a mine they liked
function Cave.showSeed()
	local StarterGui = game:GetService("StarterGui")
	local old = StarterGui:FindFirstChild("CaveSeed")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "CaveSeed"
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.new(0, 12, 1, -12)
	label.Size = UDim2.fromOffset(220, 26)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.SourceSansSemibold
	label.TextSize = 18
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(235, 225, 205)
	label.TextStrokeTransparency = 0.6
	label.Text = "seed " .. tostring(Cave.settings.seed)
	label.Parent = gui
	gui.Parent = StarterGui
end

function Cave.start()
	Cave.applyColors()
	Cave.applyTextures()
	Cave.applyLighting()
	-- build the prop meshes up front so chunk generation never stops to wait for them
	buildMeshLib()
	Cave.showSeed()

	-- tell each player's Atmosphere script which biome they're standing in, it does the fog and particles
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					local p = root.Position
					local biome = biomeAt(p)
					if biome == "rock" and p.Y < Cave.settings.lavaBelow then
						biome = "deep"
					elseif p.Y > surfaceHeight(p.X, p.Z) - 6 then
						biome = "surface"
					end
					if player:GetAttribute("CaveBiome") ~= biome then
						player:SetAttribute("CaveBiome", biome)
					end
				end
			end
			task.wait(0.5)
		end
	end)

	Cave.enableLamps()
	Cave.enableFlares()
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
