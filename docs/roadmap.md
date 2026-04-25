# Roadmap

## Map Authoring

- Build an in-game map-building workflow for simple authored geometry.
- Let authored map geometry carry gameplay tags and metadata instead of representing map-critical behavior as player-built prototype buildings.
- First-pass gameplay tags should include `spawner` and `end_point`, replacing the current Scout-built `Spawner` and `Exit Point` flow over time.
- Keep the system flexible enough for later tagged geometry such as blockers, lanes, resource zones, scripted encounter points, or build-restricted areas.

## Combat And Enemy Prototyping

- Continue developing combat through data-driven attack stats, projectile definitions, and reusable targeting/damage systems.
- Add a first flying enemy definition to pressure-test flying movement against ground-based tower defense layouts.
- Add ranged attack presentation polish such as launch sounds, impact sounds, projectile trails, and tower attack animation timing.
- Continue improving debug tooling, including test enemies, damage readouts, and range/coverage feedback.

## Movement Presentation

- Keep flying movement readable through presentation helpers such as circular ground shadows, future bobbing, and altitude-aware selection/range indicators.

## Race Structure

- Support multiple selectable races over time.
- Each race should eventually define its own master builder unit. The current `Scout` is the prototype stand-in for that role.
- Each race's master builder should expose its own specific building roster through unit data, not through hardcoded build-menu logic.
- Keep project structure flexible enough for race-specific units, buildings, audio, UI presentation, and tech progression.
