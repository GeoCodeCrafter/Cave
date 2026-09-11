# progress

**first version.** camera's inside the rock here, so the tunnels show up as blobs. all the little cubes are ore, buried in the walls where you can't mine them

![first version](progress%20images/Screenshot%202026-09-11%20143727.png)

**rock layers.** top of the mine from above, sandstone on top with the tunnels breaking through

![rock layers](progress%20images/Screenshot%202026-09-11%20143752.png)

**ore clumps.** ores are clumps now instead of single cubes, but i kept spawning inside solid rock so everything looked inside out. turns out the spawn point was just a fixed spot and it's rock most of the time

![ore clumps, inside the rock](progress%20images/Screenshot%202026-09-11%20144226.png)

**tried raycasting the ores onto the walls.** 0 placed, 2080 skipped. raycasts don't see terrain you just wrote in edit mode. did at least prove the terrain matches the code 300/300, so the cave maths was fine all along

![raycast attempt, no ores](progress%20images/Screenshot%202026-09-11%20145430.png)

**tunnel network.** threw out the noise blobs, they could never guarantee every cave connects. now every chunk has a node and tunnels link the nodes, so it's one connected web. way too thin and way too grid-like though

![tunnel network, first version](progress%20images/Screenshot%202026-09-11%20150537.png)

**ores actually in the tunnels.** wider tunnels, and the ores get pushed 2 studs out of the wall because roblox draws the wall further in than the maths says. first time you can walk up to one. still way too dark though

![ores on the tunnel walls](progress%20images/Screenshot%202026-09-11%20151150.png)
