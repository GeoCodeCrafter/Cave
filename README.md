# Cave

procedural mines for roblox. tunnels generate around you as you explore, every cave connects to every other one, and ore grows on the walls.

![gold glowing next to a side tunnel](progress/08-gold.png)

- terrain tunnels, chambers and the odd huge cavern with rock pillars, all one connected network so there's never a sealed-off pocket
- rock changes with depth: sandstone, limestone, slate, basalt, then lava at the bottom. thin stripes through each layer
- biomes: plain rock with lanterns, crystal caves full of glowing neon crystals, mushroom caves, and caves full of little tide pools
- stalactites, stalagmites, rubble and little puddles in the plain rock bits
- coal, iron, gold and diamond on the walls. hit them with the pickaxe to mine them, they grow back later
- hold click on rock to dig your own tunnels. whatever you dig out from under breaks instead of floating
- ore counts save between sessions
- spawn room at a junction so you never spawn inside rock
- chunks load nearest first around players and unload when nobody's near, digging is remembered
- `Cave.preview()`, `Cave.findCavern()` and `Cave.findBiome("crystal")` build it in edit mode so you can fly around

## setup

with [rojo](https://rojo.space): `rokit install`, then `rojo serve` and hit connect in the studio plugin. it puts everything below in the right place and sets lighting to Future for you. you still need step 5.

or by hand:

1. put `Cave.luau` in ServerScriptService as a ModuleScript called `Cave`
2. put `Test.server.luau` next to it as a Script. it builds the area around a tunnel and spawns you in it
3. put `Dig.client.luau` in StarterPlayerScripts as a LocalScript. it's the pickaxe: equip it and hold click to mine ore and dig rock
4. set `Lighting.Technology` to Future (scripts can't change it)
5. to keep ore counts between sessions, publish the place and turn on Studio Access to API Services (File → Experience Settings → Security)

everything you'd want to tweak is in `Cave.settings` at the top of the module.

every screenshot with what went wrong at each step is in [PROGRESS.md](PROGRESS.md). the change log is in [CHANGES.md](CHANGES.md).
