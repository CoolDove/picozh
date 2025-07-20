package main

import "core:os"
import "core:strings"
import "core:strconv"
import "core:fmt"
import "core:reflect"



ArgsReaderContext :: struct {
	fallback_action : ArgsReaderAction,
}

ArgsReaderConfig :: struct {
	rule : ArgsReaderRule,
	action : ArgsReaderAction,
}

ArgsReaderRule :: union {
	ArgsRuleIs,
	ArgsRuleFollowBy,
	ArgsRulePrefix,
	ArgsRuleAny, // should be the last one
}

ArgsReaderAction :: union {
	ArgsReaderActionHandler,
	ArgsReaderActionSetValue,
}
ArgsReaderActionHandlerFunc :: #type proc(arg:string, user_data: rawptr) -> bool
ArgsReaderActionHandler :: struct {
	func : ArgsReaderActionHandlerFunc,
	data : rawptr,
}
ArgsReaderActionSetValue :: struct {
	data : rawptr,
	type : typeid,
}

ArgsRuleIs :: struct {
	text: string,
}
ArgsRuleFollowBy :: struct {
	text: string,
	count: int,
}
ArgsRulePrefix :: distinct ArgsRuleIs
ArgsRuleAny :: struct {}

args_read :: proc(configs : ..ArgsReaderConfig) -> bool {
	count := cast(i32)len(os.args)
	rctx : ArgsReaderContext
	idx :i32= 1
	ite_args: for idx < count {
		arg := os.args[idx]
		for &config in configs {
			if ok, after := _apply(&config, &idx, &rctx); ok {
				if after == nil {
					rctx.fallback_action = nil
				} else {
					switch aft in after {
					case AfterApplyRule_SetFallbackAction:
						rctx.fallback_action = aft.action
					case AfterApplyRule_Terminate:
						return false
					}
				}
				continue ite_args
			}
		}
		if rctx.fallback_action != nil {
			if _action(&rctx.fallback_action, arg) {
				idx += 1
			} else {
				return false
			}
		} else do return false
	}
	return true
}

argr_is :: proc(text: string) -> ArgsRuleIs {
	return {text}
}

ARGR_FOLLOW_TILL_END : int = -1
ARGR_FOLLOW_FALLBACK : int = -9
argr_follow_by :: proc(text: string, count: int=1) -> ArgsRuleFollowBy {
	return {text, count}
}
argr_prefix :: proc(text: string) -> ArgsRulePrefix {
	return {text}
}
argr_any :: proc() -> ArgsRuleAny {
	return {}
}

arga_action :: proc(func: ArgsReaderActionHandlerFunc, data: rawptr=nil) -> ArgsReaderAction {
	return ArgsReaderActionHandler{func,data}
}
arga_set :: proc(data: ^$T) -> ArgsReaderAction {
	return ArgsReaderActionSetValue{data,T}
}

@(private="file")
_apply :: proc(using config: ^ArgsReaderConfig, arg_idx: ^i32, rctx: ^ArgsReaderContext) -> ( bool, AfterApplyRule ) {
	arg := os.args[arg_idx^]
	switch r in rule {
	case ArgsRuleIs:
		if r.text == arg {
			arg_idx^ += 1
			succ := _action(&action, "true")
			return true, nil if succ else AfterApplyRule_Terminate{}
		}
	case ArgsRuleFollowBy:
		if r.text == arg {
			arg_idx^ += 1
			count := 1
			if r.count == ARGR_FOLLOW_TILL_END {
				count = len(os.args) - cast(int)(arg_idx^)
			} else if r.count == ARGR_FOLLOW_FALLBACK {
				return true, AfterApplyRule_SetFallbackAction{action}
			} 
			for c in 0..<count {
				if arg_idx^ >= auto_cast len(os.args) { return false, nil }
				succ := _action(&action, os.args[arg_idx^])
				arg_idx^ += 1
				if !succ do return true, AfterApplyRule_SetFallbackAction{action}
			}
			return true, nil
		}
	case ArgsRulePrefix:
		if strings.has_prefix(arg, r.text) {
			arg_idx^ += 1
			succ := _action(&action, arg[len(r.text):])
			return true, nil if succ else AfterApplyRule_Terminate{}
		}
	case ArgsRuleAny:
		_action(&action, os.args[arg_idx^])
		arg_idx^ += 1
		return true, nil
	}
	return false, nil
}

@(private="file")
AfterApplyRule :: union {
	AfterApplyRule_SetFallbackAction,
	AfterApplyRule_Terminate,
}
AfterApplyRule_SetFallbackAction :: struct {
	action : ArgsReaderAction,
}
AfterApplyRule_Terminate :: struct {
}

@(private="file")
_action :: proc(action: ^ArgsReaderAction, arg: string) -> bool {
	if action == nil do return false
	switch a in action {
	case ArgsReaderActionHandler:
		return a.func(arg, a.data)
	case ArgsReaderActionSetValue:
		return _action_set_value(a, arg)
	}
	return false
}

@(private="file")
_action_set_value :: proc(a : ArgsReaderActionSetValue, text: string) -> bool {
	tinfo := type_info_of(a.type)
	if a.type == bool {
		if value,ok := strconv.parse_bool(text); ok {
			ptr := cast(^bool)a.data
			ptr^ = value
			return true
		} else {
			return false
		}
	} else if a.type == i64 || a.type == int {
		if value,ok := strconv.parse_i64(text); ok {
			ptr := cast(^i64)a.data
			ptr^ = value
			return true
		} else {
			return false
		}
	} else if a.type == i32 {
		if value,ok := strconv.parse_i64(text); ok {
			ptr := cast(^i32)a.data
			ptr^ = cast(i32)value
			return true
		} else {
			return false
		}
	} else if a.type == f64 {
		if value,ok := strconv.parse_f64(text); ok {
			ptr := cast(^f64)a.data
			ptr^ = cast(f64)value
			return true
		} else {
			return false
		}
	} else if a.type == f32 {
		if value,ok := strconv.parse_f64(text); ok {
			ptr := cast(^f32)a.data
			ptr^ = cast(f32)value
			return true
		} else {
			return false
		}
	} else if a.type == f32 {
		if value,ok := strconv.parse_f64(text); ok {
			ptr := cast(^f32)a.data
			ptr^ = cast(f32)value
			return true
		} else {
			return false
		}
	} else if a.type == string {
		ptr := cast(^string)a.data
		ptr^ = cast(string)text
		return true
	} else if reflect.is_enum(tinfo) {
		if value, ok := reflect.enum_from_name_any(a.type, text); ok {
			ptr := cast(^i64)a.data
			ptr^ = transmute(i64)value
			return true
		} else do return false
	} else {
		return false
	}
}
