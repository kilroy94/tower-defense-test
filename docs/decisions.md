# Decisions

## Data-driven unit and building definitions

Generic behavior for categories of objects should live in code. For example, scripts can hardcode how units move, how buildings occupy grid cells, how command buttons render, how action queues work, and how shared selection behavior functions.

Specific data for specific object types should live in human-readable JSON files under `data/`. This includes values like gold cost, health, damage, armor, movement speed, footprint, model dimensions, colors, portrait camera positioning, command availability, and voice line paths.

Prefer more small, focused JSON files over fewer large, wide-reaching files. Each individual unit, building, enemy, projectile, or other data-driven object should generally have its own JSON file.

Runtime scripts should load, normalize, and apply data. They should not duplicate specific object definitions as fallback content, because stale fallback data can hide broken or outdated JSON.

Unit-specific build menus are data-driven. A unit lists its buildable building IDs in its own JSON file using `available_buildings`; the building manager loads all building definitions, then filters and orders the build menu from the selected unit's list.

The current build menu is a simple 3x3 grid with the final slot reserved for Back, so it intentionally displays at most eight buildable buildings. Longer lists should trigger a warning for now. Future build menus should support paging or nested categories rather than widening the grid ad hoc.

Enemies should be unit-like but not player-controllable. Their generic behavior belongs in enemy scripts, while individual enemy stats, movement, collision, bounty, visuals, and AI profiles belong in per-enemy JSON files.

Movement type is data-driven under each unit or enemy `movement` block. First-pass `ground` movement uses grid pathing and blocker collision, while `flying` movement uses direct movement at a configured height and ignores ground path blockers.

Move turn rate is also data-driven under each unit or enemy `movement` block. Use `turn_speed` for degrees per second, `turn_alignment_degrees` for the forward cone required before movement starts, and `turn_acceleration_time` for the ramp to full turn speed. The default tuning targets Dota-like movement: `1080.0` degrees per second, an `11.5` degree alignment threshold, and a short `0.03s` ramp. `turn_speed <= 0` is the explicit instant-turn escape hatch.

Combat should be data-driven at the object-definition level and generic in runtime behavior. Units, enemies, and buildings should all describe their combat tuning through their own JSON data while shared attack processing lives in reusable combat systems.

Attack delivery should distinguish between `melee` and `ranged` rather than hardcoding separate behavior trees per actor type. Melee attacks resolve directly when their checks pass, while ranged attacks spawn projectile actors that track targets and apply damage on impact.

First-pass building combat lives in a focused `BuildingCombatSystem` that scans placed buildings with ranged attack stats, acquires valid enemy targets, and launches data-defined projectiles.

`attack_cooldown` is the gameplay-facing combat cadence stat. It determines when another attack can be used after the current attack completes. `attack_speed` is a separate presentation-oriented stat reserved for attack animation timing when animation support is added.

`max_health = -1` is the shared data-driven marker for invincibility. Invincible actors should remain selectable and visible to the player, but attack targeting and damage resolution should ignore them.

Death and destruction sounds should be data-driven per actor definition through an `audio.death` field, while generic world-audio playback stays in shared runtime helpers.

Projectile definitions should live in small JSON files under `data/projectiles/`, following the same pattern used for units, enemies, and buildings. Generic projectile movement, target tracking, visual creation, and impact handling should live in shared code.

Building commands should be data-driven in each building JSON file, while shared runtime behavior for those commands belongs in generic systems such as `BuildingActionSystem`.

Grid occupancy separates placement occupancy from path blocking. A pathable building still prevents another building from being placed on its footprint, but it does not block pathfinding.

Enemy pathfinding uses a stricter filtered walkability check than the generic grid. Occupied cells are blocked for enemies unless the occupying map geometry has the `end_point` tag.

Enemy exit detection should use the exit building's grid footprint rather than visual mesh size so the removal area matches pathfinding goals.

Enemy building attacks are a pathfinding fallback, not a sticky combat state. If an enemy can path to the exit, it should clear any cached building attack target and move on.

Enemy pathfinding must use the grid-owned map geometry index for terrain and ramp lookups. `MapGeometry` registers its footprint with `MapGrid`, including stacked pieces that do not occupy the base placement cell. Do not scan all `rts_map_geometry` nodes inside enemy walkability, height, or neighbor-expansion code; that pattern causes severe repath hitches as map geometry and enemy counts grow.

Endpoint-tagged map geometry is treated as an enemy goal/removal volume at its base height. Do not make ground enemies climb to the top of an endpoint cube unless that piece is intentionally also acting as elevated terrain through a future explicit rule.

Enemy exit routing belongs in `PathingSystem`. It builds reverse flow fields from endpoint target cells, caches the last completed answer by request, and rebuilds dirty fields when `MapGrid` pathing revision changes. Rebuild work should be proactive and cell-budgeted per frame so building placement does not make one enemy pay a full no-path search. `RtsEnemy` should delegate cell paths, terrain height, and traversal checks to `PathingSystem`; avoid per-enemy full-grid no-path searches on AI polls.

Building physics collision is also data-driven. `walkable_by` controls which actor types can physically pass through a building, independently from grid pathability.

Flying actors do not use the unit/enemy blocker collision masks in the first pass. If future flying blockers are needed, they should use a separate movement layer rather than overloading ground occupancy.

Command hotkeys are data-driven. The command grid owns `1` through `9` as universal slot hotkeys, while command-specific letter hotkeys come from `hotkey` and resolve conflicts with `fallback_hotkey`.

The map grid now favors finer placement granularity without changing the world's physical scale. The current baseline is `60 x 60` cells at `2.0` world units per cell, and legacy building footprints should be doubled on each axis to preserve their existing world-space size.

Current entry points:
- `data/units/scout.json`
- `data/units/unit_template.json`
- `data/buildings/north_tower.json`
- `data/buildings/east_hall.json`
- `data/buildings/southwest_depot.json`
- `data/buildings/building_template.json`
- `data/enemies/grunt.json`
- `data/enemies/enemy_template.json`
- `data/projectiles/basic_arrow.json`
- `data/projectiles/projectile_template.json`
- `scripts/projectiles/rts_projectile.gd`
- `scripts/systems/building_combat_system.gd`
- `scripts/systems/game_data.gd`
- `scripts/systems/building_action_system.gd`
- `scripts/systems/world_grid.gd`
- `scripts/systems/map_geometry.gd`
- `scripts/systems/pathing_system.gd`

Template JSON files use `"template": true` and are ignored by runtime loading. They exist as a reference when creating new object definitions.
