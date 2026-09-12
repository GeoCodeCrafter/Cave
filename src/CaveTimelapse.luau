--[[
	builds the mine chunk by chunk, nearest first, with the camera swinging round it, so you can record
	it building itself. edit mode, from the command bar or the editor plugin:

		local Cave = require(game.ServerScriptService.Cave)
		require(game.ServerScriptService.CaveTimelapse).run(Cave)

	options (all optional):
		center      where to build round, defaults to the spawn
		radius      chunks each way, default 3
		delay       seconds between chunks, default 0.05
		cutaway     true by default: the half facing the camera never gets built, so you watch the
		            tunnels appear in cross-section instead of a cube of rock growing
		distance, height   where the camera sits
		onProgress(done, total)
		stop()      return true to stop early
]]
local Workspace = game:GetService("Workspace")

local CaveTimelapse = {}

local FOLDERS = { "Ores", "Lanterns", "Decor", "Bridges", "Rivers" }

-- anything that got placed past the cut goes, or it floats in front of the camera
local function trim(plane: number)
	for _, name in FOLDERS do
		local f = Workspace:FindFirstChild(name)
		if f then
			for _, m in f:GetChildren() do
				local ok, pos = pcall(function()
					return (m :: any):GetPivot().Position
				end)
				if ok and pos.Z > plane then
					m:Destroy()
				end
			end
		end
	end
end

function CaveTimelapse.run(Cave, opts: { [string]: any }?): number
	local o = opts or {}
	local SIZE = Cave.SIZE
	local center: Vector3 = o.center or Cave.findSpawn()
	local radius = o.radius or 3
	local delay = o.delay or 0.05
	local cut = o.cutaway ~= false
	local distance = o.distance or radius * SIZE * 2.3
	local height = o.height or distance * 0.4
	local camera = Workspace.CurrentCamera

	Cave.clear()
	Cave.prepare()
	-- with the cut on, chunks wholly on the camera's side (+z) are skipped
	local plane = center.Z
	local todo = {}
	for _, c in Cave.chunksAround(center, radius, false) do
		if not cut or c.Z * SIZE < plane then
			table.insert(todo, c)
		end
	end

	-- the camera: a slow swing in front of the cut, or a full orbit without one
	local running = true
	local start = os.clock()
	task.spawn(function()
		while running do
			local t = os.clock() - start
			local angle = if cut then math.sin(t * 0.25) * math.rad(35) else t * 0.15
			local eye = center + Vector3.new(math.sin(angle) * distance, height, math.cos(angle) * distance)
			camera.CFrame = CFrame.lookAt(eye, center)
			task.wait()
		end
	end)

	local built = 0
	for i, c in todo do
		if o.stop and o.stop() then
			break
		end
		Cave.generateChunk(c.X, c.Y, c.Z)
		built += 1
		-- a chunk the cut goes through: take off the bit past the line
		local far = (c.Z + 1) * SIZE
		if cut and far > plane then
			Workspace.Terrain:FillBlock(
				CFrame.new(Vector3.new((c.X + 0.5) * SIZE, (c.Y + 0.5) * SIZE, (plane + far) / 2)),
				Vector3.new(SIZE, SIZE, far - plane),
				Enum.Material.Air
			)
			trim(plane)
		end
		if o.onProgress then
			o.onProgress(i, #todo)
		end
		task.wait(delay)
	end
	task.wait(1.5)
	running = false
	return built
end

return CaveTimelapse
