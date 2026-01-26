package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"

import rl "vendor:raylib"

main :: proc() {
	log_path := "20260125_140736_rotkehlchen.log"
	if len(os.args) > 1 {
		log_path = os.args[1]
	}

	tasks, requests, ok, min_ts, max_ts := parse_log_file(log_path)
	if !ok {
		fmt.println("Failed to read log:", log_path)
		return
	}

	task_lanes := assign_lanes(&tasks)
	request_lanes := assign_lanes(&requests)

	if max_ts <= min_ts {
		max_ts = min_ts + 1
	}

	padding := i64(math.max(1.0, f64(max_ts-min_ts)*0.05))
	view_start := min_ts - padding
	view_end := max_ts + padding

	rl.SetConfigFlags(rl.ConfigFlags{.WINDOW_RESIZABLE, .WINDOW_MAXIMIZED})
	rl.InitWindow(1280, 720, to_cstring("rotki timeline"))
	rl.SetTargetFPS(60)

	ui_font := rl.LoadFont(to_cstring("SpaceMono-Regular.ttf"))
	rl.SetTextureFilter(ui_font.texture, rl.TextureFilter.BILINEAR)

	defer rl.UnloadFont(ui_font)
	defer rl.CloseWindow()

	dragging := false
	last_mouse_x := i32(0)

	for !rl.WindowShouldClose() {
		screen_w := rl.GetScreenWidth()
		screen_h := rl.GetScreenHeight()

		if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
			dragging = true
			last_mouse_x = rl.GetMouseX()
		}
		if rl.IsMouseButtonReleased(rl.MouseButton.LEFT) {
			dragging = false
		}
		if dragging {
			dx := rl.GetMouseX() - last_mouse_x
			last_mouse_x = rl.GetMouseX()
			span := f64(view_end - view_start)
			pan := i64(span * f64(dx) / f64(screen_w))
			view_start -= pan
			view_end -= pan
		}

		wheel := rl.GetMouseWheelMove()
		if wheel != 0 {
			zoom_factor := math.pow(1.1, f64(wheel))
			mouse_x := rl.GetMouseX()
			anchor := view_start + i64((f64(mouse_x)/f64(screen_w)) * f64(view_end-view_start))
			new_span := i64(f64(view_end-view_start) / zoom_factor)
			if new_span < 1 {
				new_span = 1
			}
			view_start = anchor - i64(f64(new_span)*f64(mouse_x)/f64(screen_w))
			view_end = view_start + new_span
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{245, 244, 240, 255})

		margin := f32(24)
		gap := f32(18)
		region_h := (f32(screen_h) - margin*2 - gap) / 2
		task_rect := rl.Rectangle{margin, margin, f32(screen_w) - margin*2, region_h}
		req_rect := rl.Rectangle{margin, margin + region_h + gap, f32(screen_w) - margin*2, region_h}

		draw_region(ui_font, "Background tasks", task_rect)
		draw_region(ui_font, "Requests", req_rect)

		draw_timeline(ui_font, task_rect, tasks[:], task_lanes, view_start, view_end, rl.Color{76, 141, 247, 255})
		draw_timeline(ui_font, req_rect, requests[:], request_lanes, view_start, view_end, rl.Color{85, 171, 115, 255})

		draw_time_axis(ui_font, task_rect, view_start, view_end)

		draw_text(ui_font, "Left-drag to pan, mouse wheel to zoom", 24, screen_h-24, 12, rl.Color{110, 110, 110, 255})

		rl.EndDrawing()
	}
}

// --- Rendering helpers ---

draw_region :: proc(font: rl.Font, title: string, rect: rl.Rectangle) {
	rl.DrawRectangleRec(rect, rl.Color{255, 255, 255, 255})
	rl.DrawRectangleLinesEx(rect, 1, rl.Color{200, 200, 200, 255})
	text_y := i32(rect.y) + 6
	draw_text(font, title, i32(rect.x)+8, text_y, 16, rl.Color{50, 50, 50, 255})
}

draw_timeline :: proc(font: rl.Font, rect: rl.Rectangle, events: []Event, lanes: int, view_start, view_end: i64, color: rl.Color) {
	if len(events) == 0 {
		return
	}
	lane_count := max_int(1, lanes)
	lane_h := (rect.height - 28) / f32(lane_count)
	if lane_h < 10 {
		lane_h = 10
	}

	mouse := rl.GetMousePosition()

	hovered := false
	hover_ev := Event{}

	for ev in events {
		x1 := time_to_x(ev.start, view_start, view_end, rect)
		x2 := time_to_x(ev.end, view_start, view_end, rect)
		if x2 < rect.x || x1 > rect.x+rect.width {
			continue
		}
		min_w := f32(2)
		if x2 < x1+min_w {
			x2 = x1 + min_w
		}

		y := rect.y + 22 + f32(ev.lane)*lane_h
		h := max_f32(6, lane_h-4)
		rec := rl.Rectangle{x1, y, x2 - x1, h}
		rl.DrawRectangleRec(rec, color)
		rl.DrawRectangleLinesEx(rec, 1, rl.Color{30, 30, 30, 60})

		if rec.width > 40 {
			draw_label_in_rect(font, ev.name, rec, 12, rl.Color{20, 20, 20, 255})
		}

		if rl.CheckCollisionPointRec(mouse, rec) {
			hovered = true
			hover_ev = ev
		}
	}

	if hovered {
		draw_tooltip(font, hover_ev, mouse)
	}
}

draw_time_axis :: proc(font: rl.Font, rect: rl.Rectangle, view_start, view_end: i64) {
	span := view_end - view_start
	step := choose_tick_step(span)
	start_tick := (view_start / step) * step
	if start_tick < view_start {
		start_tick += step
	}

	for t := start_tick; t <= view_end; t += step {
		x := time_to_x(t, view_start, view_end, rect)
		rl.DrawLineEx(rl.Vector2{x, rect.y}, rl.Vector2{x, rect.y + rect.height}, 1, rl.Color{230, 230, 230, 255})
		label := format_hms(t)
		draw_text(font, label, i32(x) - 20, i32(rect.y) - 18, 12, rl.Color{90, 90, 90, 255})
	}
}

draw_label_in_rect :: proc(font: rl.Font, text: string, rect: rl.Rectangle, font_size: i32, color: rl.Color) {
	pad := f32(4)
	max_w := rect.width - pad*2
	label := text
	for measure_text_width(font, label, font_size) > max_w && len(label) > 4 {
		label = label[:len(label)-1]
	}
	if label != text && len(label) > 3 {
		label = fmt.tprintf("%s...", label[:len(label)-3])
	}
	if measure_text_width(font, label, font_size) <= max_w {
		draw_text(font, label, i32(rect.x+pad), i32(rect.y+2), font_size, color)
	}
}

draw_tooltip :: proc(font: rl.Font, ev: Event, pos: rl.Vector2) {
	label := fmt.tprintf("%s (%s)", ev.name, ev.actor)
	dur := fmt.tprintf("%s - %s", format_hms(ev.start), format_hms(ev.end))
	elapsed := format_duration(ev.end - ev.start)
	elapsed_line := fmt.tprintf("Duration: %s", elapsed)
	w := max_f32(
		measure_text_width(font, label, 12),
		max_f32(measure_text_width(font, dur, 12), measure_text_width(font, elapsed_line, 12)),
	) + 12
	h := f32(48)
	rec := rl.Rectangle{pos.x + 12, pos.y + 12, f32(w), f32(h)}
	rl.DrawRectangleRec(rec, rl.Color{255, 255, 255, 245})
	rl.DrawRectangleLinesEx(rec, 1, rl.Color{50, 50, 50, 180})
	draw_text(font, label, i32(rec.x)+6, i32(rec.y)+4, 12, rl.Color{30, 30, 30, 255})
	draw_text(font, dur, i32(rec.x)+6, i32(rec.y)+18, 12, rl.Color{80, 80, 80, 255})
	draw_text(font, elapsed_line, i32(rec.x)+6, i32(rec.y)+32, 12, rl.Color{80, 80, 80, 255})
}

// --- Math helpers ---

time_to_x :: proc(ts, view_start, view_end: i64, rect: rl.Rectangle) -> f32 {
	span := f64(view_end - view_start)
	if span <= 0 {
		return rect.x
	}
	return rect.x + f32((f64(ts-view_start) / span)) * rect.width
}

choose_tick_step :: proc(span: i64) -> i64 {
	if span <= 30 {
		return 5
	}
	if span <= 120 {
		return 10
	}
	if span <= 300 {
		return 30
	}
	if span <= 900 {
		return 60
	}
	if span <= 3600 {
		return 300
	}
	if span <= 7200 {
		return 600
	}
	return 900
}

max_i32 :: proc(a, b: i32) -> i32 {
	if a > b {
		return a
	}
	return b
}

max_int :: proc(a, b: int) -> int {
	if a > b {
		return a
	}
	return b
}

to_cstring :: proc(s: string) -> cstring {
	c, _ := strings.clone_to_cstring(s, context.temp_allocator)
	return c
}

max_f32 :: proc(a, b: f32) -> f32 {
	if a > b {
		return a
	}
	return b
}

draw_text :: proc(font: rl.Font, text: string, x, y: i32, size: i32, color: rl.Color) {
	rl.DrawTextEx(font, to_cstring(text), rl.Vector2{f32(x), f32(y)}, f32(size), 0, color)
}

measure_text_width :: proc(font: rl.Font, text: string, size: i32) -> f32 {
	return rl.MeasureTextEx(font, to_cstring(text), f32(size), 0).x
}

format_duration :: proc(seconds: i64) -> string {
	secs := seconds
	if secs < 0 {
		secs = -secs
	}
	h := secs / 3600
	m := (secs % 3600) / 60
	s := secs % 60
	if h > 0 {
		return fmt.tprintf("%dh %dm %ds", h, m, s)
	}
	if m > 0 {
		return fmt.tprintf("%dm %ds", m, s)
	}
	if s == 0 {
		return "<1s"
	}
	return fmt.tprintf("%ds", s)
}
