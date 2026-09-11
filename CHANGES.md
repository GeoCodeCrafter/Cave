# changes

- first version: chambers + spaghetti tunnels with terrain, generates around players, ore on walls
- can generate in edit mode now with Cave.preview() so you can actually look at it, Cave.clear() wipes it
- rock layers by depth (sandstone > limestone > slate > basalt) with wavy edges, rock patches, dirt floors, lava at the bottom, custom colours
- ores were buried inside the walls, now they're clumps of chunks stuck on the wall surface poking into the tunnel. gold is foil, diamond is glass
- kept spawning inside solid rock so you never actually saw a tunnel. findSpawn() looks for air with a floor, preview() puts the camera there and play mode spawns you there
- tried raycasting ores onto the walls, raycasts miss fresh terrain in edit mode so 0 ores. added Cave.check() which showed the terrain matches the code 300/300, so ores go straight on the voxel face again
