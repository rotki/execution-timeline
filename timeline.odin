package main

assign_lanes :: proc(events: ^[dynamic]Event) -> (max_lanes: int) {
	if len(events^) == 0 {
		return 0
	}

	sort_events_by_start(events)

	lane_end, _ := make([dynamic]i64, 0, 8)

	for i in 0..<len(events^) {
		assigned := false
		for lane := 0; lane < len(lane_end); lane += 1 {
			if lane_end[lane] <= events^[i].start {
				events^[i].lane = lane
				lane_end[lane] = events^[i].end
				assigned = true
				break
			}
		}
		if !assigned {
			events^[i].lane = len(lane_end)
			append(&lane_end, events^[i].end)
		}
	}

	return len(lane_end)
}

sort_events_by_start :: proc(events: ^[dynamic]Event) {
	// Simple insertion sort; log sizes are modest and this avoids extra dependencies.
	for i := 1; i < len(events^); i += 1 {
		key := events^[i]
		j := i - 1
		for j >= 0 {
			prev := events^[j]
			if prev.start < key.start || (prev.start == key.start && prev.end <= key.end) {
				break
			}
			events^[j+1] = prev
			j -= 1
		}
		events^[j+1] = key
	}
}
