--!strict
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local terrain = Workspace.Terrain

local Cave = {}

local VOXEL = 4
local CHUNK = 16 -- voxels per side, so 64 studs
local SIZE = CHUNK * VOXEL

Cave.settings = {
	seed = 1,
	tunnelRadius = 5,
	wiggle = 9, -- how far tunnels bend away from a straight line
	bend = 0.015, -- how tight the bends are. much above 0.02 and tunnels tear into separate pockets
	minRadius = 4, -- thinner than a voxel and the terrain grid breaks tunnels apart
	chamberChance = 0.3, -- per node
	chamberRadius = 15,
	rampChance = 0.35, -- per node, a sloped tunnel down to the level below
	top = 0, -- nothing generates above this y
	-- top down, each layer starts at this y (edges get warped by noise)
	layers = {
		{ at = 0, material = Enum.Material.Sandstone },
		{ at = -50, material = Enum.Material.Limestone },
		{ at = -120, material = Enum.Material.Slate },
		{ at = -210, material = Enum.Material.Basalt },
	},
	patch = Enum.Material.Rock,
	floor = Enum.Material.Ground,
	lavaBelow = -280,
	colors = {
		[Enum.Material.Sandstone] = Color3.fromRGB(176, 142, 104),
		[Enum.Material.Limestone] = Color3.fromRGB(158, 148, 132),
		[Enum.Material.Slate] = Color3.fromRGB(86, 84, 90),
		[Enum.Material.Basalt] = Color3.fromRGB(44, 41, 46),
		[Enum.Material.Rock] = Color3.fromRGB(116, 104, 94),
		[Enum.Material.Ground] = Color3.fromRGB(88, 70, 52),
	},
	radius = 2, -- chunks around each player
	ores = {
		{ name = "Coal", color = Color3.fromRGB(34, 34, 38), material = Enum.Material.Slate, below = 0, chance = 0.012 },
		{ name = "Iron", color = Color3.fromRGB(196, 132, 90), material = Enum.Material.Rock, below = -60, chance = 0.008 },
		{ name = "Gold", color = Color3.fromRGB(240, 190, 45), material = Enum.Material.Foil, below = -150, chance = 0.004 },
		{ name = "Diamond", color = Color3.fromRGB(110, 235, 245), material = Enum.Material.Glass, below = -260, chance = 0.002 },
	},
}

local done: { [string]: boolean } = {}
local featureCache: { [string]: any } = {}

Cave.placed = 0

local function getOreFolder(): Folder
	local folder = Workspace:FindFirstChild("Ores")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Ores"
		folder.Parent = Workspace
	end
	return folder :: Folder
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
		cx + 0.25 + hash(cx, cy, cz, 1) * 0.5,
		cy + 0.35 + hash(cx, cy, cz, 2) * 0.3,
		cz + 0.25 + hash(cx, cy, cz, 3) * 0.5
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
	local reach = s.chamberRadius * 1.3 + s.wiggle + VOXEL
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
					local links = { nodeAt(x + 1, y, z), nodeAt(x, y, z + 1) }
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
	local material = s.layers[1].material
	for _, layer in s.layers do
		if y < layer.at then
			material = layer.material
		end
	end
	return material
end

function Cave.applyColors()
	for material, color in Cave.settings.colors do
		terrain:SetMaterialColor(material, color)
	end
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
							placeOre(ore, wall, normal, rng)
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

function Cave.clear()
	terrain:Clear()
	getOreFolder():ClearAllChildren()
	table.clear(done)
	table.clear(featureCache)
	Cave.placed = 0
end

function Cave.start()
	Cave.applyColors()
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
