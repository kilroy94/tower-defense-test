# Mechanics

## Prototype Special Buildings

- `Spawner`: provisional building that passively creates a Grunt at its south face every five seconds through its data-driven `Spawn` command.
- `Exit Point`: provisional pathable, transparent building that acts as the enemy pathfinding goal and passively removes enemies inside it through its data-driven `Exit` command.

## Enemies

- Enemies are non-player-controlled unit-like actors.
- Enemy stats, movement, collision, bounty, visuals, and AI profile should be defined in focused JSON files under `data/enemies/`.
- `Grunt` is the first prototype enemy. Its eventual loop is to spawn from a `Spawner` and path toward an `Exit Point`.
- Enemies with the `path_to_exit` AI role periodically look for a placed building whose id matches their AI `target`, currently `exit_point`. If no matching building exists, they idle and keep checking.
- If the target building is pathable, enemies path directly into its footprint. If the target building blocks pathing, enemies path to the nearest reachable neighboring cell.
- Enemy pathfinding treats building-occupied cells as blocked unless the occupying building has an `exit_enemy` command.
- If the path to the enemy goal is fully blocked by attackable buildings, melee enemies can fall back to moving into attack range of a blocking building and destroying it before continuing.

## Combat

- Combat will support two attack delivery types: `melee` and `ranged`.
- An attacker first acquires or is assigned a valid target, checks whether that target is still legal, and checks whether the target is inside attack range before making an attack.
- All combatants should eventually use the same first-pass attack concepts whether they are units, enemies, or buildings.

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

## Combat Stats

- Shared attack-related stats should be data-driven under each actor's `stats` block over time.
- `max_health` values of `-1` mean the actor is invincible.
- Invincible actors should be ignored by attack targeting and should not take damage.
- Actors can also define a data-driven `audio.death` sound for death or destruction events.
- The first combat stat set should include:
  - `damage`
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

- Projectile definitions should eventually live in focused JSON files under `data/projectiles/`.
- The first projectile stat set should include:
  - `travel_speed`
  - `turn_rate`
  - `impact_radius`
  - `lifetime`
- First-pass projectiles should track a single target and deal direct damage on impact.
- More advanced projectile behaviors such as splash, piercing, bouncing, homing falloff, or on-hit effects should layer on top of this base system later.

## Building Actions

- Buildings can define commands in their individual JSON files, matching the same command-grid data shape used by units.
- Passive building commands are executed by `BuildingActionSystem`.
- The first prototype passive actions are `spawn_enemy`, used by the Spawner's `Spawn` command, and `exit_enemy`, used by the Exit Point's `Exit` command.

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
- Enemies apply an additional building-occupancy rule on top of grid pathability: only buildings with an `exit_enemy` command are considered valid occupied destination cells.
- Buildings can set `walkable_by` in their JSON data to control physics collision by actor type.
- Supported first-pass actor types are `unit` and `enemy`.
- The Exit Point is pathable and uses `"walkable_by": ["enemy"]`, so enemies can physically enter it while worker units still collide with it.
