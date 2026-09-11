--!strict
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local terrain = Workspace.Terrain

local Cave = {}

local VOXEL = 4
local CHUNK = 16 -- voxels per side, so 64 studs

Cave.settings = {
	seed = 1,
	chamberScale = 0.02,
	chamberSize = 0.28, -- higher = smaller chambers
	tunnelScale = 0.035,
	tunnelWidth = 0.08,
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
		{ name = "Coal", color = Color3.fromRGB(40, 40, 45), below = 0, chance = 0.02 },
		{ name = "Iron", color = Color3.fromRGB(200, 140, 95), below = -60, chance = 0.012 },
		{ name = "Gold", color = Color3.fromRGB(240, 195, 50), below = -150, chance = 0.006 },
		{ name = "Diamond", color = Color3.fromRGB(95, 230, 240), below = -260, chance = 0.003 },
	},
}

local done: { [string]: boolean } = {}

local function getOreFolder(): Folder
	local folder = Workspace:FindFirstChild("Ores")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Ores"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

-- > 0 means air
local function airness(p: Vector3): number
	local s = Cave.settings
	local o = s.seed * 97.31

	local chamber = math.noise(p.X * s.chamberScale + o, p.Y * s.chamberScale * 1.6, p.Z * s.chamberScale)

	-- two noise fields both near zero = a long winding tunnel
	local a = math.noise(p.X * s.tunnelScale, p.Y * s.tunnelScale + o, p.Z * s.tunnelScale)
	local b = math.noise(p.X * s.tunnelScale + o, p.Y * s.tunnelScale, p.Z * s.tunnelScale - o)
	local tunnel = s.tunnelWidth * s.tunnelWidth - (a * a + b * b)

	return math.max(chamber - s.chamberSize, tunnel * 20)
end

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

local function pickOre(depth: number, rng: Random)
	for i = #Cave.settings.ores, 1, -1 do
		local ore = Cave.settings.ores[i]
		if depth < ore.below and rng:NextNumber() < ore.chance then
			return ore
		end
	end
	return nil
end

local function placeOre(ore, pos: Vector3, rng: Random)
	local part = Instance.new("Part")
	part.Name = ore.name
	part.Anchored = true
	part.Size = Vector3.one * rng:NextNumber(2, 3.5)
	part.CFrame = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
	part.Color = ore.color
	part.Material = Enum.Material.Rock
	part:SetAttribute("Ore", ore.name)
	part.Parent = getOreFolder()
end

function Cave.generateChunk(cx: number, cy: number, cz: number)
	local key = cx .. "," .. cy .. "," .. cz
	if done[key] then
		return
	end
	done[key] = true

	local s = Cave.settings
	local min = Vector3.new(cx, cy, cz) * CHUNK * VOXEL
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
				local occ = math.clamp(0.5 - airness(p) * 6, 0, 1)
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

	local region = Region3.new(min, min + Vector3.one * CHUNK * VOXEL)
	terrain:WriteVoxels(region, VOXEL, materials, occupancy)

	-- ore on walls: solid voxels with air right next to them
	local rng = Random.new(s.seed * 1e6 + cx * 7919 + cy * 104729 + cz * 1299709)
	for x = 2, CHUNK - 1 do
		for y = 2, CHUNK - 1 do
			for z = 2, CHUNK - 1 do
				if not air[x][y][z] then
					local open = air[x + 1][y][z] or air[x - 1][y][z] or air[x][y + 1][z]
						or air[x][y - 1][z] or air[x][y][z + 1] or air[x][y][z - 1]
					if open then
						local p = min + Vector3.new(x - 0.5, y - 0.5, z - 0.5) * VOXEL
						local ore = pickOre(p.Y, rng)
						if ore then
							placeOre(ore, p, rng)
						end
					end
				end
			end
		end
	end
end

function Cave.around(pos: Vector3)
	local size = CHUNK * VOXEL
	local r = Cave.settings.radius
	local cx, cy, cz = math.floor(pos.X / size), math.floor(pos.Y / size), math.floor(pos.Z / size)
	for dy = -1, 1 do
		for dx = -r, r do
			for dz = -r, r do
				Cave.generateChunk(cx + dx, cy + dy, cz + dz)
				task.wait()
			end
		end
	end
end

-- for looking at it in edit mode, run from the command bar
function Cave.preview(center: Vector3?, radius: number?)
	local size = CHUNK * VOXEL
	local c = center or Vector3.new(0, -40, 0)
	local r = radius or 3
	Cave.applyColors()
	local cx, cy, cz = math.floor(c.X / size), math.floor(c.Y / size), math.floor(c.Z / size)
	for dy = -2, 0 do
		for dx = -r, r do
			for dz = -r, r do
				Cave.generateChunk(cx + dx, cy + dy, cz + dz)
			end
		end
	end
end

function Cave.clear()
	terrain:Clear()
	getOreFolder():ClearAllChildren()
	table.clear(done)
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
