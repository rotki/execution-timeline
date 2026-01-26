package main

Event_Kind :: enum { Task, Request }

Event :: struct {
	kind  : Event_Kind,
	name  : string,
	actor : string,
	start : i64,
	end   : i64,
	lane  : int,
	args  : string,
}

Task_Stack_Item :: struct {
	name  : string,
	start : i64,
}

Req_Stack_Item :: struct {
	name  : string,
	start : i64,
	args  : string,
}

Task_Stack :: struct {
	items : [dynamic]Task_Stack_Item,
	len   : int,
}

Req_Stack :: struct {
	items : [dynamic]Req_Stack_Item,
	len   : int,
}

Async_Request :: struct {
	name  : string,
	actor : string,
	start : i64,
	args  : string,
}

Task_Manager_Pending :: struct {
	name  : string,
	actor : string,
	start : i64,
}
