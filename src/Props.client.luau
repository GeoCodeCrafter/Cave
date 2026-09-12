-- goes in StarterPlayerScripts. the server places plain stand-in blocks for stalactites, crystals,
-- ore and rubble, tagged with which shape they are. this builds the real meshes on your computer
-- (the server's never reach you) and puts one inside each stand-in, hiding the block for you only.
-- the stand-in still does the collisions, the mining clicks and the digging
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CaveMeshes = require(ReplicatedStorage:WaitForChild("CaveMeshes"))
local lib = CaveMeshes.build()
if not lib then
	return
end

local function dress(part: Instance)
	if not part:IsA("BasePart") or part:FindFirstChild("LocalMesh") then
		return
	end
	local kind, index = part:GetAttribute("MeshKind"), part:GetAttribute("MeshIndex")
	local list = kind and lib[kind]
	local template = list and list[index]
	if not template then
		return
	end
	local mesh = template:Clone()
	mesh.Name = "LocalMesh"
	mesh.Size = part.Size
	mesh.CFrame = part.CFrame
	mesh.Color = part.Color
	mesh.Material = part.Material
	mesh.Transparency = part.Transparency
	mesh.CastShadow = part.CastShadow
	mesh.Anchored = true
	mesh.CanCollide = false
	-- clicks go through it to the stand-in, which is what the server knows about
	mesh.CanQuery = false
	mesh.CanTouch = false
	mesh.Parent = part
	part.LocalTransparencyModifier = 1
	-- ore shakes and hides when it breaks, so follow whatever the server does to the stand-in
	part:GetPropertyChangedSignal("CFrame"):Connect(function()
		mesh.CFrame = part.CFrame
	end)
	part:GetPropertyChangedSignal("Transparency"):Connect(function()
		mesh.Transparency = part.Transparency
	end)
end

for _, d in Workspace:GetDescendants() do
	dress(d)
end
Workspace.DescendantAdded:Connect(dress)
