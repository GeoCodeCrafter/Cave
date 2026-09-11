--!strict
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

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
		{ name = "Coal", color = Color3.fromRGB(34, 34, 38), material = Enum.Material.Slate, below = 0, chance = 0.012 },
		{ name = "Iron", color = Color3.fromRGB(196, 132, 90), material = Enum.Material.Rock, below = -60, chance = 0.008 },
		{ name = "Gold", color = Color3.fromRGB(240, 190, 45), material = Enum.Material.Foil, below = -150, chance = 0.004 },
		{ name = "Diamond", color = Color3.fromRGB(110, 235, 245), material = Enum.Material.Glass, below = -260, chance = 0.002 },
	},
}

local done: { [string]: boolean } = {}

Cave.placed = 0
Cave.skipped = 0 -- raycast found no wall, so no ore

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

-- a clump of chunks stuck to the wall, poking out along the wall's normal
local function placeOre(ore, wall: Vector3, normal: Vector3, rng: Random)
	local model = Instance.new("Model")
	model.Name = ore.name
	model:SetAttribute("Ore", ore.name)

	-- any two directions across the wall
	local side = normal:Cross(if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis).Unit
	local up = normal:Cross(side)

	for i = 1, rng:NextInteger(3, 6) do
		local part = Instance.new(if rng:NextNumber() < 0.4 then "WedgePart" else "Part")
		part.Name = ore.name
		part.Anchored = true
		part.CanCollide = true
		part.Size = Vector3.new(rng:NextNumber(0.8, 2.2), rng:NextNumber(0.8, 2.6), rng:NextNumber(0.8, 2.2))
		local offset = side * rng:NextNumber(-1.5, 1.5) + up * rng:NextNumber(-1.5, 1.5)
		local out = normal * rng:NextNumber(-0.2, 0.8)
		local pos = wall + offset + out
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

local DIRS = { Vector3.xAxis, -Vector3.xAxis, Vector3.yAxis, -Vector3.yAxis, Vector3.zAxis, -Vector3.zAxis }

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

	-- ore on walls. pick rock voxels next to air, then stand in the air and raycast back at
	-- the wall, so the ore sits on the surface roblox actually drew instead of where the
	-- voxel maths thinks it is (smooth terrain doesn't put the surface on the voxel edge)
	local rng = Random.new(s.seed * 1e6 + cx * 7919 + cy * 104729 + cz * 1299709)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { terrain }

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
							local from = p + open * VOXEL
							local hit = Workspace:Raycast(from, -open * VOXEL * 2, params)
							if hit then
								placeOre(ore, hit.Position, hit.Normal, rng)
								Cave.placed += 1
							else
								Cave.skipped += 1
							end
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

-- somewhere in a tunnel: air here and above, solid floor underneath
function Cave.findSpawn(near: Vector3?): Vector3
	local c = near or Vector3.new(0, -40, 0)
	local up, down = Vector3.new(0, 4, 0), Vector3.new(0, -6, 0)
	for r = 0, 240, 8 do
		for i = 0, 15 do
			local angle = i / 16 * math.pi * 2
			local x, z = c.X + math.cos(angle) * r, c.Z + math.sin(angle) * r
			for y = math.min(c.Y, -12), c.Y - 160, -4 do
				local p = Vector3.new(x, y, z)
				if airness(p) > 0.05 and airness(p + up) > 0.05 and airness(p + down) < -0.05 then
					return p
				end
			end
		end
	end
	warn("Cave.findSpawn found no tunnel, using", c)
	return c
end

-- for looking at it in edit mode, run from the command bar. puts the camera in a tunnel
function Cave.preview(center: Vector3?, radius: number?): Vector3
	local size = CHUNK * VOXEL
	local spot = Cave.findSpawn(center)
	local r = radius or 3
	Cave.applyColors()
	local cx, cy, cz = math.floor(spot.X / size), math.floor(spot.Y / size), math.floor(spot.Z / size)
	for dy = -2, 1 do
		for dx = -r, r do
			for dz = -r, r do
				Cave.generateChunk(cx + dx, cy + dy, cz + dz)
			end
		end
	end
	if not RunService:IsRunning() then
		local eye = spot + Vector3.new(0, 2, 0)
		Workspace.CurrentCamera.CFrame = CFrame.lookAt(eye, eye + Vector3.new(0, 0, 10))
	end
	print(("cave: %d ores placed, %d skipped (no wall found)"):format(Cave.placed, Cave.skipped))
	return spot
end

function Cave.clear()
	terrain:Clear()
	getOreFolder():ClearAllChildren()
	table.clear(done)
	Cave.placed, Cave.skipped = 0, 0
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
