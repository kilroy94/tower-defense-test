# Session Log - 2026-04-23

## Reference Context

- Primary context file: `PROJECT_CONTEXT.md`
- Supporting docs:
  - `docs/roadmap.md`
  - `docs/mechanics.md`
  - `docs/tasks.md`
  - `docs/balance.md`
  - `docs/decisions.md`

## Active Focus

- Keep current work aligned with the RTS prototype direction:
  - camera controls
  - grid-aware building placement
  - worker commands
  - unit selection
  - command cards
  - action queueing
  - Warcraft III-inspired HUD interactions
- Preserve the data-driven architecture for units, buildings, enemies, and commands.
- Record both major milestones and smaller cleanup work as tasks are completed.

## Major Tasks Completed

- Session started. Context docs reviewed and working log created.
- Cleaned duplicate main scene confusion by removing stray untracked `scenes/main.tscn` and confirming the real entry scene remains `res://scenes/core/main.tscn`.
- Started the shared data-driven stat system by wiring in a first-pass health foundation for units, enemies, and buildings.

## Minor Tasks Completed

- Confirmed current working reference set in `docs/` plus `PROJECT_CONTEXT.md`.
- Verified `project.godot` was already pointing to `res://scenes/core/main.tscn`.
- Confirmed remaining root-level `main.tscn` references were editor metadata under `.godot/`, not runtime project configuration.
- Added shared stat normalization in `GameData` so all actor categories receive a consistent `stats` dictionary.
- Units and enemies now initialize `current_health` from `max_health` and expose runtime health through metadata plus simple accessors.
- Placed buildings now receive `max_health` and `current_health` metadata instead of only carrying a raw stats blob.
- Added a unit health readout to the selection panel below the selected unit's name using the `Current/Maximum` format.
- Extended the same health readout to selected enemies and buildings for consistent selection feedback.
- Documented the first-pass combat plan for melee attacks, ranged attacks, shared attack stats, and projectile data.
- Added the first-pass shared combat data shape to runtime normalization and current actor definitions.
- Added shared combat target-validation and attack-range helpers for units, enemies, and future building combat logic.
- Added first-pass shared damage application and melee attack resolution helpers, with unit and enemy wrappers wired to runtime health state.
- Added first-pass grunt melee behavior against buildings in range, plus live selection-panel health refresh and automatic cleanup for destroyed buildings.
- Added shared invincibility handling: `max_health = -1` now blocks damage and attack targeting, and the selection panel displays `Invincible` instead of numeric health.
- Updated enemy pathing fallback so grunts try to move toward and attack blocking buildings when the exit path is fully obstructed.
- Added shared data-driven death/destruction sound plumbing and hooked current building destruction into `audio.death`, using the requested building death asset.
- Refined grunt targeting to cache an attack target on the AI poll instead of rescanning every building every frame, with preference for the current obstruction goal when it is in range.
- Fixed a regression where grunts stopped acquiring nearby tower targets while already moving, and throttled building-manager maintenance work to reduce avoidable frame-time spikes.
- Removed temporary grunt combat debug logging after confirming the obstruction-attack flow.
- Confirmed the working grunt obstruction-break behavior with `attack_range` tuned to `2.0`.
- Increased grid resolution while preserving map scale by changing the baseline grid from `30 x 30` at `4.0` cell size to `60 x 60` at `2.0`, and scaled current building footprints to match.
- Verified the project still loads with `godot.exe --headless --path . --quit`.
- Recorded the local Godot executable paths in `PROJECT_CONTEXT.md` for future nightly work.

## Decisions And Notes

- Use this file as the running session log for completed work tonight.
- Keep durable architecture and design decisions in `docs/decisions.md` when we formalize them.
- Keep actionable future work in `docs/tasks.md` when new follow-up items emerge.
- Keep tuning observations in `docs/balance.md` when gameplay values start changing.
- First stat-system step stays intentionally narrow: normalize and initialize health before adding damage application, death handling, or UI display.
- Combat is planned as a shared data-driven system for units, enemies, and buildings, with `melee` and `ranged` as the first delivery types.
- `attack_cooldown` is the gameplay cadence stat for first-pass combat. `attack_speed` is reserved for future attack animation timing.
- Current sample combat assignments:
  - `Scout`: `melee`
  - `Grunt`: `melee`
  - `North Tower`: `ranged` with placeholder `projectile_id` set to `basic_arrow`
- Current combat tuning note:
  - `Grunt` melee attack range is currently `2.0` to reliably hit blocking buildings at the present scale.

## Open Follow-Ups

- Tomorrow's planned goals:
  - add attack functionality to towers
  - start the ranged attack and projectile system
  - move spawn and end points out of the Scout build menu and into dedicated map-level setup
  - add separate `ground` and `flying` movement types
