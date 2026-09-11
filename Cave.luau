--!strict
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

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
	},
	radius = 2, -- chunks around each player
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
	local tunnels, chambers = {}, {}
	local reach = s.chamberRadius * 1.3 + s.wiggle + VOXEL + s.tunnelRadius * 1.4
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
					if hash(x, y, z, 6) < s.chamberChance and touches(a, a) then
						table.insert(chambers, { c = a, r = s.chamberRadius * (0.7 + hash(x, y, z, 7) * 0.6) })
					end
				end
			end
		end
	end

	cached = { tunnels = tunnels, chambers = chambers }
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
	return best
end

-- ============================================================ materials

local function materialAt(p: Vector3, isFloor: boolean): Enum.Material
	local s = Cave.settings
	local o = s.seed * 31.7

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

	model.Parent = getOreFolder()
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

	model.Parent = getFolder("Lanterns")
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

	terrain:WriteVoxels(Region3.new(min, min + Vector3.one * SIZE), VOXEL, materials, occupancy)

	if hasNode(cy) then
		placeLantern(nodeAt(cx, cy, cz))
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
						end
					end
				end
			end
		end
	end
end

function Cave.around(pos: Vector3)
	local r = Cave.settings.radius
	local cx, cy, cz = math.floor(pos.X / SIZE), math.floor(pos.Y / SIZE), math.floor(pos.Z / SIZE)
	for dy = -1, 1 do
		for dx = -r, r do
			for dz = -r, r do
				Cave.generateChunk(cx + dx, cy + dy, cz + dz)
				task.wait()
			end
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

-- a dug-out room with a plank floor, support beams, a lantern and a real SpawnLocation.
-- it sits on a node so the tunnels always connect to it. returns where players spawn
function Cave.buildSpawnRoom(center: Vector3?): CFrame
	local spot = Cave.preview(center, 2)
	local floorY = spot.Y - 3
	local size = Vector3.new(40, 16, 40)
	local middle = Vector3.new(spot.X, floorY + size.Y / 2, spot.Z)

	-- dig from a bit under the floor, otherwise the terrain smoothing creeps up over the planks.
	-- then a flattened dome on top so it's not a shoebox
	terrain:FillBlock(CFrame.new(middle - Vector3.new(0, 1, 0)), size + Vector3.new(0, 2, 0), Enum.Material.Air)
	terrain:FillBall(Vector3.new(spot.X, floorY + size.Y - 4, spot.Z), size.X * 0.6, Enum.Material.Air)

	-- anything generated inside the room would be floating now
	local half = size / 2 + Vector3.new(size.X * 0.2, size.Y, size.Z * 0.2)
	for _, folder in { getOreFolder(), getFolder("Lanterns") } do
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
	table.clear(done)
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

	model:SetAttribute("Broken", true)
	model:SetAttribute("HP", nil)
	shatter(model)
	setVisible(model, false)

	local stats = player:FindFirstChild("leaderstats")
	local count = stats and stats:FindFirstChild(def.name) :: IntValue?
	if count then
		count.Value += 1
	end

	task.delay(def.respawn, function()
		if model.Parent then
			setVisible(model, true)
			model:SetAttribute("Broken", nil)
		end
	end)
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
	end)
end

function Cave.start()
	Cave.applyColors()
	Cave.applyLighting()
	Cave.enableMining()
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
