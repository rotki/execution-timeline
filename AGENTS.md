# Project Agents Notes

## Project overview
This is a **work‑in‑progress** log timeline visualizer for Rotki logs, written in **Odin** and rendered with **raylib**.

## What it uses
- **Language:** Odin (tested on `dev-2026-01`)
- **Rendering:** `vendor:raylib`
- **Font:** `SpaceMono-Regular.ttf` in the repo root
- **Input:** Rotki backend log files (`*.log`)

## Current parsing behavior
- Background tasks come from `Enter/Exit` pairs.
- Requests come from `start/end rotki api` pairs.
- Async requests are matched via `task_id` in a response, then closed when `/api/1/tasks/<id>` finishes.
- `Spawning task manager task ...` lines are treated as **fixed 5‑second tasks**.

## Pending work
- Add proper end markers for background tasks that currently only emit start lines (requires log format support for explicit end messages).
