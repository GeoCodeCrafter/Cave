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
	rock = Enum.Material.Slate,
	deepRock = Enum.Material.Basalt,
	deepAt = -200,
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
				local v = airness(p)
				local occ = math.clamp(0.5 - v * 6, 0, 1)
				air[x][y][z] = occ < 0.5
				occupancy[x][y][z] = occ
				materials[x][y][z] = if occ == 0
					then Enum.Material.Air
					elseif p.Y < s.deepAt then s.deepRock
					else s.rock
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
