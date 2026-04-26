# Session Log - 2026-04-25

## Active Focus

- Recover from the map-geometry/ramp pathfinding regression and preserve the lesson in project context so future sessions do not repeat it.

## Completed

- Added a `MapGrid` map-geometry index keyed by grid cell.
- `MapGeometry` now registers and unregisters its footprint with `MapGrid`, including stacked geometry that does not register placement occupancy.
- Enemy terrain-height, ramp, and walkability lookups now query `map_grid.get_top_map_geometry_at_cell(cell)` instead of scanning every node in the `rts_map_geometry` group during path searches.
- Fixed endpoint pathing: endpoint-tagged geometry is entered at its base height, so a ground-level endpoint cube no longer requires a ramp.
- Skipped the expensive blocker-fallback search when no attackable buildings exist, preventing repeated no-route hitches in maps where the route failure is terrain/tag related rather than building related.
- Replaced per-enemy exit route searches with a shared reverse flow-field cache keyed by grid pathing revision and endpoint cells, so no-path results are reused until the map changes.
- Promoted exit flow-field ownership into `PathingSystem`, with proactive dirty-field rebuilds spread across a configurable per-frame cell budget.
- Removed the enemy-local flow-field fallback so `RtsEnemy` delegates cell paths, terrain height, and traversal checks to `PathingSystem`.
- Added top-right FPS debug display to the HUD.
- Added optional enemy path debug lines so each moving enemy can draw its current remaining path.
- Reduced tower/combat performance cost by moving target acquisition out of per-frame full scans, staggering building scans, caching attack-capable buildings, and skipping acquisition when no enemies exist.
- Raised the combat tick default to `1.0 / 60.0` after throttling made higher update rates affordable.
- Added Dota-like data-driven turning for units and enemies. Movement now uses `turn_speed`, `turn_alignment_degrees`, and `turn_acceleration_time`; defaults are `1080.0`, `11.5`, and `0.03` to approximate Dota 2's quick turn-in-place behavior while keeping `turn_speed <= 0` as the instant-turn escape hatch.
- Updated `PROJECT_CONTEXT.md`, `docs/decisions.md`, `docs/mechanics.md`, and `docs/tasks.md` with the pathfinding performance guardrail.

## Validation

- `godot.exe --headless --path . --quit` completed successfully from the project root.
- The console executable path currently listed in `PROJECT_CONTEXT.md` failed because the expected paired main executable was not present at that location.

## Critical Guardrail

- Do not put `get_tree().get_nodes_in_group("rts_map_geometry")` inside enemy path expansion, walkability checks, terrain-height checks, or any code reached repeatedly while an enemy is repathing. Use the grid-owned map-geometry index instead.
- Do not treat endpoint cells as elevated cube tops for normal enemy goal pathing. Endpoint cells are goal/removal volumes and should be entered at their base height.
- Do not run a full no-path search separately for every enemy. Enemy exit routing should query `PathingSystem`; flow fields are shared, invalidated by grid pathing revision, and rebuilt over a frame budget.
