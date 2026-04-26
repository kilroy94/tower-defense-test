# Mechanics

## Map Geometry Tags

- Map-critical enemy flow is authored by placing map geometry and assigning gameplay tags in Mapping mode.
- The `spawner` tag passively creates a Grunt at the south face of the tagged geometry every five seconds by default.
- The `end_point` tag makes ground-level geometry pathable at its base height for enemies and removes enemies inside its grid footprint.
- Exit removal is based on the geometry footprint, so it matches the same cells enemies can path into.
- Tagged geometry recolors in-game so spawners and end points are visually readable while editing.

## Map Geometry Pathing

- `Cell Cube` is a 1x1 blocking map geometry piece by default.
- `Cell Ramp` is a 1x1 ramp map geometry piece.
- Ramp and cube cells are enemy-walkable terrain surfaces, but enemies can only enter elevated cube surfaces through valid ramp edges.
- Ground enemies use map geometry terrain height for their path waypoints and snap to the current walkable surface height while moving, so they travel on top of ramp-accessible cubes rather than through their volume.
- Ground enemies can change terrain height only through ramp transitions. They cannot step directly from ground onto the side of a cube.
- Ramp orientation is enforced for height transitions. At rotation `0`, a ramp rises toward positive grid Y; rotating the geometry changes which side is high.
- This is a first-pass 2D grid traversal model: enemies still snap between terrain heights rather than moving smoothly along the ramp slope.
- Enemy pathfinding reads terrain/ramp data from the `MapGrid` map-geometry cell index. Avoid scene-tree geometry scans during path expansion, because those searches are on the enemy repath hot path.
- Endpoint cells are goal/removal cells, not elevated terrain goals. Enemies enter them at the geometry base height, while ordinary cubes still resolve to their top surface and require valid ramp access.
- Enemy exit pathing goes through `PathingSystem`, which owns shared reverse flow fields for endpoint cells. If no valid exit route exists, that no-path result is reused by all enemies until occupancy or map geometry changes.
- Dirty endpoint flow fields rebuild proactively over a per-frame cell budget after pathing changes. Enemies can keep using the last completed field while a replacement is being built.

## Enemies

- Enemies are non-player-controlled unit-like actors.
- Enemy stats, movement, collision, bounty, visuals, and AI profile should be defined in focused JSON files under `data/enemies/`.
- `Grunt` is the first prototype enemy. Its current loop is to spawn from `spawner`-tagged map geometry and path toward `end_point`-tagged map geometry.
- `Test Dummy` is a debug enemy that can be spawned at the mouse position with `F2` for attack and damage-readout testing.
- Debug enemy damage readouts can tune `damage_display_font_size`, `damage_display_height_offset`, and `damage_display_outline_size` in the enemy JSON `debug` block.
- Enemies can define `movement.type` as `ground` or `flying`.
- Ground enemies use grid pathfinding and respect path blockers.
- Flying enemies move directly toward their objective and ignore grid path blockers.
- Enemies with the `path_to_exit` AI role periodically look for map geometry tagged `end_point`. If no matching geometry exists, they idle and keep checking.
- If the target geometry is pathable, enemies path directly into its footprint. If the target geometry blocks pathing, enemies path to the nearest reachable neighboring cell.
- Enemy pathfinding treats occupied cells as blocked unless the occupying map geometry has the `end_point` tag.
- If the path to the enemy goal is fully blocked by attackable buildings, melee enemies can fall back to moving into attack range of a blocking building and destroying it before continuing.
- Enemies should prefer a valid route to the exit over attacking buildings. On each AI poll, they check whether an exit path is available and resume movement if it is.
- Exit-route checks use one search that can stop at any valid exit goal cell, rather than running one path search per footprint cell.
- Exit-route checks query `PathingSystem`, so repeated enemy polls do not repeat the same full no-route search.
- Enemies already moving to the exit keep their current path only while its remaining waypoints are still walkable. If a new building blocks that path, they re-run the exit-route search and take another open route if one exists.
- Cached building attack targets do not permanently override pathing. Before a melee building attack proceeds, the enemy can make a throttled exit-route check and resume moving if a valid route exists.
- If no exit route exists, enemies fall back to attackable blockers. If a blocker path cannot be built but an attackable building is already in range, they keep that target instead of dropping into a silent idle.
- Enemy paths currently follow grid waypoints without smoothing so movement cannot cut between occupied building cells. Future smoothing needs a proper grid-clearance corridor before it is re-enabled.

## Movement Types

- Units and enemies can define movement under their JSON `movement` block.
- Supported first-pass movement types are `ground` and `flying`.
- `ground` actors use grid pathing and collision masks that respect their blocker layer.
- `flying` actors move directly to their target point at `movement.flight_height` and ignore unit/enemy/building blocker collision.
- Turn behavior is Dota-like and data-driven per unit/enemy. Movers rotate toward the next waypoint first, may begin moving once the target direction is within `turn_alignment_degrees`, and keep rotating while moving.
- `turn_speed` is measured in degrees per second. The default `1080.0` is tuned so a 180 degree turn takes about `0.17s`, close to the common Dota 2 hero range.
- `turn_alignment_degrees` is the allowed forward cone before movement starts. The default `11.5` matches Dota's action/movement facing threshold.
- `turn_acceleration_time` controls how long the turn rate takes to ramp to full speed. The default `0.03` keeps turns crisp while avoiding a totally instant max-rate snap. Raise it for heavier-feeling units; lower it or set it to `0` for immediate max turn rate.
- `turn_speed` of `0` or less preserves instant facing and bypasses turn delay.
- The current `Scout` uses flying movement so the prototype builder can move and build without being trapped by ground blockers.
- Flying builders can issue move and build orders to any in-bounds cell, while ground builders still require walkable cells and reachable build-adjacent cells.
- Flying actors render a simple circular ground shadow beneath them in addition to normal scene shadows so their height and map position stay readable.

## Combat

- Combat will support two attack delivery types: `melee` and `ranged`.
- An attacker first acquires or is assigned a valid target, checks whether that target is still legal, and checks whether the target is inside attack range before making an attack.
- All combatants should eventually use the same first-pass attack concepts whether they are units, enemies, or buildings.
- Holding `Alt` while a combat-capable unit, enemy, or building is selected shows its current attack range as a ground perimeter.

## Melee Attacks

- A melee attack resolves directly on the target when all attack checks pass.
- The first-pass melee flow is:
  - target is valid
  - target is within attack range
  - attacker is ready to attack
  - damage is applied immediately
- First-pass melee hits always land once the above checks pass.
- Future combat layers such as evasion, miss chances, shields, resistances, or status effects should hook into the hit-resolution step rather than changing the basic attack loop shape.

## Ranged Attacks

- A ranged attack creates a projectile instead of applying damage immediately.
- The projectile tracks its target in flight and applies damage when it reaches the target.
- If a ranged attacker passes its attack checks, the attack is considered launched once the projectile is spawned, even though the damage lands later.
- Projectile behavior should stay generic in code while projectile-specific tuning lives in per-projectile data.
- Placed buildings with `attack_type` set to `ranged` can acquire enemy targets in range and launch their configured `projectile_id`.
- Placed buildings with `attack_type` set to `melee` can acquire enemy targets in range and apply direct damage without a projectile.
- First-pass building target priority is nearest valid enemy in attack range.

## Combat Stats

- Shared attack-related stats should be data-driven under each actor's `stats` block over time.
- `max_health` values of `-1` mean the actor is invincible.
- Invincible actors should be ignored by attack targeting and should not take damage.
- `health_regen_per_second` restores health over time for actors that implement regeneration.
- Actors can also define a data-driven `audio.death` sound for death or destruction events.
- The first combat stat set should include:
  - `damage`
  - `health_regen_per_second`
  - `attack_range`
  - `attack_speed`
  - `attack_cooldown`
  - `attack_type`
  - `projectile_id` for ranged attackers
- `attack_cooldown` is the gameplay timing stat that controls how soon another attack can be used after an attack completes.
- `attack_speed` is reserved for attack animation timing and presentation. It does not need to drive gameplay behavior yet while attack animations are still placeholder or absent.
- `attack_type` should identify whether the attacker uses `melee` or `ranged`.
- `projectile_id` should be empty or omitted for melee attackers.

## Projectile Stats

- Projectile definitions live in focused JSON files under `data/projectiles/`.
- `basic_arrow` is the first projectile definition and is referenced by `North Tower`.
- The first projectile stat set should include:
  - `travel_speed`
  - `turn_rate`
  - `impact_radius`
  - `lifetime`
- Projectile definitions can also tune `launch_height`, `target_height`, and simple `visual` data.
- First-pass projectiles should track a single target and deal direct damage on impact.
- If a projectile's target becomes invalid, invincible, dead, or removed before impact, the projectile cleans itself up without applying damage.
- More advanced projectile behaviors such as splash, piercing, bouncing, homing falloff, or on-hit effects should layer on top of this base system later.

## Map Geometry Actions

- Passive map geometry behavior is driven by gameplay tags.
- The `spawner` tag creates enemies through `BuildingActionSystem` for now.
- The `end_point` tag removes enemies whose current grid cell is inside the tagged geometry footprint.

## Command Hotkeys

- The command grid always supports slot hotkeys `1` through `9`, matching the visible 3x3 grid.
- Commands can define `hotkey` and `fallback_hotkey` in JSON.
- If two commands in the current command menu share the same primary `hotkey`, the command grid uses each command's `fallback_hotkey` when it is available and does not conflict.
- Building options in the build menu use the same command hotkey system by reading `hotkey` and `fallback_hotkey` from each building JSON file.

## Grid Occupancy

- The playable map currently preserves its same world-space size while using a denser grid: cells are `2.0` world units wide instead of `4.0`, and the map uses `60 x 60` cells instead of `30 x 30`.
- Existing building footprints should be scaled to match the denser grid so their physical world-space dimensions stay the same. For example, a legacy `1 x 1` building footprint becomes `2 x 2`.
- Buildings can set `pathable` in their JSON data.
- Pathable buildings still occupy cells for placement and selection, but they do not block pathfinding.
- Non-pathable buildings occupy cells and block pathfinding.
- Enemies apply an additional occupancy rule on top of grid pathability: only map geometry tagged `end_point` is considered a valid occupied destination.
- Buildings can set `walkable_by` in their JSON data to control physics collision by actor type.
- Supported first-pass actor types are `unit` and `enemy`.
- Applying the `end_point` tag makes ground-level map geometry pathable so enemies can enter it.
