# Rotki Log Timeline (WIP)

This is a **work-in-progress** visualizer for Rotki backend logs. It parses log lines and renders a timeline using raylib so you can see what is running over time.

## What it does

- **Upper panel:** background tasks (e.g., `Enter/Exit` pairs)
- **Lower panel:** API requests (`start/end rotki api`)
- Shows **start/end** bars, lanes to avoid overlap, and **hover tooltips** with:
  - name
  - start/end timestamps
  - duration
- Special handling for async requests:
  - If a request response includes a `task_id`, the duration is extended until the matching `/api/1/tasks/<id>` request finishes.
- `Spawning task manager task ...` lines are shown as **fixed 5‑second tasks** (temporary placeholder until real end markers exist).

## Usage

### Run with the default log
```
odin run .
```

### Run with a specific log file
```
odin run . -- /path/to/your.log
```

## Controls

- **Left‑drag** to pan
- **Mouse wheel** to zoom

## Requirements

- Odin (tested with `dev-2026-01`)
- raylib (via Odin vendor package)
- `SpaceMono-Regular.ttf` in the project root

## Notes / WIP

- Parsing is tailored to current Rotki log formats and may need updates.
- Async task matching is best‑effort; if it doesn’t match a `task_id`, the request uses its direct end time.
- More log patterns and richer metadata will be added later.
