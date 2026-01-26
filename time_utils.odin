package main

import "core:fmt"

// Parse timestamps like "25/01/2026 14:07:38 CET" into seconds since Unix epoch.
parse_timestamp :: proc(s: string) -> (ok: bool, ts: i64) {
	// Expect "DD/MM/YYYY HH:MM:SS" at the start.
	if len(s) < 19 {
		return false, 0
	}

	parse_2 :: proc(x: string) -> (bool, i32) {
		if len(x) != 2 {
			return false, 0
		}
		if x[0] < '0' || x[0] > '9' || x[1] < '0' || x[1] > '9' {
			return false, 0
		}
		return true, i32(x[0]-'0')*10 + i32(x[1]-'0')
	}

	parse_4 :: proc(x: string) -> (bool, i32) {
		if len(x) != 4 {
			return false, 0
		}
		for ch in x {
			if ch < '0' || ch > '9' {
				return false, 0
			}
		}
		return true, i32(x[0]-'0')*1000 + i32(x[1]-'0')*100 + i32(x[2]-'0')*10 + i32(x[3]-'0')
	}

	d_ok, day := parse_2(s[0:2])
	m_ok, month := parse_2(s[3:5])
	y_ok, year := parse_4(s[6:10])
	h_ok, hour := parse_2(s[11:13])
	min_ok, minute := parse_2(s[14:16])
	s_ok, second := parse_2(s[17:19])
	if !(d_ok && m_ok && y_ok && h_ok && min_ok && s_ok) {
		return false, 0
	}

	days := days_from_civil(year, month, day)
	if days == -1 {
		return false, 0
	}

	return true, i64(days)*86400 + i64(hour)*3600 + i64(minute)*60 + i64(second)
}

// Gregorian calendar to days since 1970-01-01. Returns -1 on invalid input.
days_from_civil :: proc(year, month, day: i32) -> i64 {
	if month < 1 || month > 12 || day < 1 || day > 31 {
		return -1
	}
	// Normalize months so March is the first month.
	y := year
	m := month
	if m <= 2 {
		y -= 1
		m += 12
	}
	era := y / 400
	if y < 0 && y % 400 != 0 {
		era -= 1
	}
	yoe := y - era*400
	doy := (153*(m-3) + 2)/5 + day - 1
	doe := yoe*365 + yoe/4 - yoe/100 + doy
	return i64(era*146097 + doe - 719468)
}

format_hms :: proc(ts: i64) -> string {
	secs := ts % 86400
	if secs < 0 {
		secs += 86400
	}
	h := secs / 3600
	m := (secs % 3600) / 60
	s := secs % 60
	return fmt.tprintf("%02d:%02d:%02d", h, m, s)
}
