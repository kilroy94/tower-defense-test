# Decisions

## Data-driven unit and building definitions

Generic behavior for categories of objects should live in code. For example, scripts can hardcode how units move, how buildings occupy grid cells, how command buttons render, how action queues work, and how shared selection behavior functions.

Specific data for specific object types should live in human-readable JSON files under `data/`. This includes values like gold cost, health, damage, armor, movement speed, footprint, model dimensions, colors, portrait camera positioning, command availability, and voice line paths.

Prefer more small, focused JSON files over fewer large, wide-reaching files. Each individual unit, building, enemy, projectile, or other data-driven object should generally have its own JSON file.

Runtime scripts should load, normalize, and apply data. They should not duplicate specific object definitions as fallback content, because stale fallback data can hide broken or outdated JSON.

Unit-specific build menus are data-driven. A unit lists its buildable building IDs in its own JSON file using `available_buildings`; the building manager loads all building definitions, then filters and orders the build menu from the selected unit's list.

The current build menu is a simple 3x3 grid with the final slot reserved for Back, so it intentionally displays at most eight buildable buildings. Longer lists should trigger a warning for now. Future build menus should support paging or nested categories rather than widening the grid ad hoc.

Enemies should be unit-like but not player-controllable. Their generic behavior belongs in enemy scripts, while individual enemy stats, movement, collision, bounty, visuals, and AI profiles belong in per-enemy JSON files.

Building commands should be data-driven in each building JSON file, while shared runtime behavior for those commands belongs in generic systems such as `BuildingActionSystem`.

Grid occupancy separates placement occupancy from path blocking. A pathable building still prevents another building from being placed on its footprint, but it does not block pathfinding.

Enemy pathfinding uses a stricter filtered walkability check than the generic grid. Building-occupied cells are blocked for enemies unless the building has an `exit_enemy` command.

Building physics collision is also data-driven. `walkable_by` controls which actor types can physically pass through a building, independently from grid pathability.

Command hotkeys are data-driven. The command grid owns `1` through `9` as universal slot hotkeys, while command-specific letter hotkeys come from `hotkey` and resolve conflicts with `fallback_hotkey`.

Current entry points:
- `data/units/scout.json`
- `data/units/unit_template.json`
- `data/buildings/north_tower.json`
- `data/buildings/east_hall.json`
- `data/buildings/southwest_depot.json`
- `data/buildings/building_template.json`
- `data/enemies/grunt.json`
- `data/enemies/enemy_template.json`
- `scripts/systems/game_data.gd`
- `scripts/systems/building_action_system.gd`

Template JSON files use `"template": true` and are ignored by runtime loading. They exist as a reference when creating new object definitions.
