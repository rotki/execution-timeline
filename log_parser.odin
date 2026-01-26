package main

import "core:fmt"
import "core:os"
import "core:strings"

parse_log_file :: proc(path: string) -> (tasks: [dynamic]Event, requests: [dynamic]Event, ok: bool, first_ts: i64, last_ts: i64) {
	data, read_ok := os.read_entire_file(path)
	if !read_ok {
		return nil, nil, false, 0, 0
	}
	text := string(data)
	lines := strings.split(text, "\n")

	task_stacks := make(map[string]Task_Stack)
	req_stacks := make(map[string]Req_Stack)
	async_pending := make(map[int]Async_Request)

	first_set := false
	min_ts: i64
	max_ts: i64

	for line in lines {
		if len(line) == 0 {
			continue
		}

		open_idx := strings.index(line, "[")
		close_idx := strings.index(line, "]")
		if open_idx == -1 || close_idx == -1 || close_idx <= open_idx {
			continue
		}
		ts_str := line[open_idx+1:close_idx]
		ts_ok, ts := parse_timestamp(ts_str)
		if !ts_ok {
			continue
		}

		if !first_set {
			min_ts = ts
			max_ts = ts
			first_set = true
		} else {
			if ts < min_ts {
				min_ts = ts
			}
			if ts > max_ts {
				max_ts = ts
			}
		}

		after_bracket := line[close_idx+1:]
		local_colon := strings.index(after_bracket, ":")
		if local_colon == -1 {
			continue
		}
		colon_idx := close_idx + 1 + local_colon
		if colon_idx+1 >= len(line) {
			continue
		}

		prefix := strings.trim_space(line[close_idx+1:colon_idx])
		actor := parse_actor(prefix)
		msg := strings.trim_space(line[colon_idx+1:])

		if strings.starts_with(msg, "Enter ") {
			name := strings.trim_space(msg[len("Enter "):])
			stack := task_stacks[actor]
			if stack.len == len(stack.items) {
				append(&stack.items, Task_Stack_Item{name = name, start = ts})
			} else {
				stack.items[stack.len] = Task_Stack_Item{name = name, start = ts}
			}
			stack.len += 1
			task_stacks[actor] = stack
			continue
		}

		if strings.starts_with(msg, "Spawning task manager task") {
			name := strings.trim_space(msg[len("Spawning task manager task"):])
			if len(name) == 0 {
				name = "Spawning task manager task"
			}
			append(&tasks, Event{kind = .Task, name = name, actor = actor, start = ts, end = ts + 5})
			continue
		}
		if strings.starts_with(msg, "Exit ") {
			name := strings.trim_space(msg[len("Exit "):])
			stack := task_stacks[actor]
			if stack.len > 0 {
				idx := -1
				for i := stack.len-1; i >= 0; i -= 1 {
					if stack.items[i].name == name {
						idx = i
						break
					}
				}
				if idx != -1 {
					start := stack.items[idx].start
					append(&tasks, Event{kind = .Task, name = name, actor = actor, start = start, end = ts})
					if idx < stack.len-1 {
						copy(stack.items[idx:], stack.items[idx+1:stack.len])
					}
					stack.len -= 1
					task_stacks[actor] = stack
				}
			}
			continue
		}

		if strings.starts_with(msg, "start rotki api ") {
			name := parse_request_name(msg[len("start rotki api "):])
			stack := req_stacks[actor]
			if stack.len == len(stack.items) {
				append(&stack.items, Req_Stack_Item{name = name, start = ts})
			} else {
				stack.items[stack.len] = Req_Stack_Item{name = name, start = ts}
			}
			stack.len += 1
			req_stacks[actor] = stack
			continue
		}
		if strings.starts_with(msg, "end rotki api GET /api/1/tasks/") {
			// Pop the /api/1/tasks/<id> request itself from the stack.
			stack := req_stacks[actor]
			if stack.len > 0 {
				stack.len -= 1
				req_stacks[actor] = stack
			}
			if task_id, ok := parse_task_id_from_path(msg); ok {
				if async, exists := async_pending[task_id]; exists {
					append(&requests, Event{kind = .Request, name = async.name, actor = async.actor, start = async.start, end = ts})
					delete_key(&async_pending, task_id)
				}
			}
			continue
		}
		if strings.starts_with(msg, "end rotki api ") {
			name := parse_request_name(msg[len("end rotki api "):])
			stack := req_stacks[actor]
			if stack.len > 0 {
				idx := stack.len - 1
				start := stack.items[idx].start
				req_name := stack.items[idx].name
				if len(name) > 0 {
					req_name = name
				}
				if task_id, ok := parse_task_id(msg); ok {
					async_pending[task_id] = Async_Request{name = req_name, actor = actor, start = start}
				} else {
					append(&requests, Event{kind = .Request, name = req_name, actor = actor, start = start, end = ts})
				}
				stack.len -= 1
				req_stacks[actor] = stack
			}
			continue
		}
	}

	if !first_set {
		return nil, nil, false, 0, 0
	}

	// Close any unpaired tasks/requests at the last timestamp.
	for _, stack in task_stacks {
		for i := 0; i < stack.len; i += 1 {
			item := stack.items[i]
			append(&tasks, Event{kind = .Task, name = item.name, actor = "(open)", start = item.start, end = max_ts})
		}
	}
	for _, stack in req_stacks {
		for i := 0; i < stack.len; i += 1 {
			item := stack.items[i]
			append(&requests, Event{kind = .Request, name = item.name, actor = "(open)", start = item.start, end = max_ts})
		}
	}
	for _, async in async_pending {
		append(&requests, Event{kind = .Request, name = async.name, actor = "(open)", start = async.start, end = max_ts})
	}

	return tasks, requests, true, min_ts, max_ts
}

parse_actor :: proc(prefix: string) -> string {
	parts := strings.split(prefix, " ")
	if len(parts) >= 2 {
		last := parts[len(parts)-1]
		prev := parts[len(parts)-2]
		if last == "Greenlet" && prev == "Main" {
			return "Main Greenlet"
		}
		if strings.starts_with(last, "Greenlet-") {
			return last
		}
	}
	if len(parts) > 0 {
		return parts[len(parts)-1]
	}
	return "unknown"
}

parse_request_name :: proc(rest: string) -> string {
	tokens := strings.split(rest, " ")
	if len(tokens) >= 2 {
		return fmt.aprintf("%s %s", tokens[0], tokens[1])
	}
	if len(tokens) == 1 {
		return tokens[0]
	}
	return "request"
}

parse_task_id :: proc(msg: string) -> (id: int, ok: bool) {
	idx := strings.index(msg, "task_id")
	if idx == -1 {
		return 0, false
	}
	for idx < len(msg) && msg[idx] != ':' {
		idx += 1
	}
	if idx >= len(msg) {
		return 0, false
	}
	idx += 1
	for idx < len(msg) && (msg[idx] == ' ' || msg[idx] == '\'' || msg[idx] == '\"') {
		idx += 1
	}
	return parse_int_at(msg, idx)
}

parse_task_id_from_path :: proc(msg: string) -> (id: int, ok: bool) {
	path_idx := strings.index(msg, "/api/1/tasks/")
	if path_idx == -1 {
		return 0, false
	}
	start := path_idx + len("/api/1/tasks/")
	return parse_int_at(msg, start)
}

parse_int_at :: proc(s: string, start: int) -> (id: int, ok: bool) {
	if start < 0 || start >= len(s) {
		return 0, false
	}
	i := start
	for i < len(s) && s[i] >= '0' && s[i] <= '9' {
		i += 1
	}
	if i == start {
		return 0, false
	}
	value := 0
	for j := start; j < i; j += 1 {
		value = value*10 + int(s[j]-'0')
	}
	return value, true
}
