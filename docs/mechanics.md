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

- Buildings can set `pathable` in their JSON data.
- Pathable buildings still occupy cells for placement and selection, but they do not block pathfinding.
- Non-pathable buildings occupy cells and block pathfinding.
- Enemies apply an additional building-occupancy rule on top of grid pathability: only buildings with an `exit_enemy` command are considered valid occupied destination cells.
- Buildings can set `walkable_by` in their JSON data to control physics collision by actor type.
- Supported first-pass actor types are `unit` and `enemy`.
- The Exit Point is pathable and uses `"walkable_by": ["enemy"]`, so enemies can physically enter it while worker units still collide with it.
