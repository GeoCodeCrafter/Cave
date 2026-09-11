# progress

**01 · first go.** camera's inside the rock here, so the tunnels show up as blobs. all the little cubes are ore, buried in the walls where you can't mine them

![first version](progress/01-first-go.png)

**02 · rock layers.** top of the mine from above, sandstone on top with the tunnels breaking through

![rock layers](progress/02-rock-layers.png)

**03 · ore clumps.** ores are clumps now instead of single cubes, but i kept spawning inside solid rock so everything looked inside out. turns out the spawn point was just a fixed spot and it's rock most of the time

![ore clumps, inside the rock](progress/03-ore-clumps.png)

**04 · tried raycasting the ores onto the walls.** 0 placed, 2080 skipped. raycasts don't see terrain you just wrote in edit mode. did at least prove the terrain matches the code 300/300, so the cave maths was fine all along

![raycast attempt, no ores](progress/04-raycast-fail.png)

**05 · tunnel network.** threw out the noise blobs, they could never guarantee every cave connects. now every chunk has a node and tunnels link the nodes, so it's one connected web. way too thin and way too grid-like though

![tunnel network, first version](progress/05-tunnel-network.png)

**06 · ores actually in the tunnels.** wider tunnels, and the ores get pushed 2 studs out of the wall because roblox draws the wall further in than the maths says. first time you can walk up to one. still way too dark though

![ores on the tunnel walls](progress/06-ores-on-walls.png)

**07 · lighting.** lantern on a chain at every junction, gold and diamond glow, warm haze, bloom. switched lighting to Future for the shadows. finally looks like a mine

![lanterns and iron on the wall](progress/07-lanterns.png)

![gold glowing by a side tunnel](progress/08-gold.png)
