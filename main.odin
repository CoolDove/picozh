package main

import "core:os"
import "core:fmt"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"
import "core:strconv"
import smary "core:container/small_array"

data := #load("quan.bdf", string)

chars : map[rune]CharInfo
CharInfo :: struct {
	box   : [4]int,
	glyph     : smary.Small_Array(8, u8),
	glyphline : smary.Small_Array(8, string),
}

State :: struct {
	process_line : proc(s: ^State, line: string) -> bool
}

state_size :State= {
	process_line = proc(s: ^State, line: string) -> bool {
		elems := strings.split(line, " ", context.temp_allocator)
		if elems[0] == "SIZE" {
			change_state(&state_get_char)
		}
		return false
	},
}

StateGetChar :: struct {
	using _ : State,
	idx       : int,
	using _to_reset : struct {
		codepoint  : rune,
		glyph      : smary.Small_Array(8, u8),
		glyphline  : smary.Small_Array(8, string),
		open_glyph : bool,
		box        : [4]int,
	}
}
state_get_char :StateGetChar= {
	process_line = proc(s: ^State, line: string) -> bool {
		s := cast(^StateGetChar)s
		elems := strings.split(line, " "); defer delete(elems)
		if s.codepoint == 0 {
			if elems[0] == "STARTCHAR" && strings.starts_with(elems[1], "U+") {
				if codepoint, ok := strconv.parse_int(elems[1][2:], 16); ok {
					s.codepoint = rune(codepoint)
				}
			}
		} else {
			if s.open_glyph {
				if elems[0] == "ENDCHAR" {
					map_insert(&chars, s.codepoint, CharInfo{ glyph = s.glyph, glyphline = s.glyphline, box = s.box })
					s.idx += 1
					s._to_reset = {}
				} else {
					glyph, ok := strconv.parse_int(elems[0], 16)
					smary.push(&s.glyph, u8(glyph))
					smary.push(&s.glyphline, elems[0])
				}
			} else {
				if elems[0] == "BITMAP" {
					s.open_glyph = true
				} else if elems[0] == "BBX" {
					for i in 0..<4 do s.box[i], _ = strconv.parse_int(elems[1+i])
				}
			}
		}
		return false
	}
}

state : ^State = &state_size

change_state :: proc(s: ^State) {
	state = s
}

sources : strings.Builder
target : string

main :: proc() {
	if len(os.args) < 2 do return

	strings.builder_init(&sources); defer strings.builder_destroy(&sources)

	argsok := args_read(
		{ argr_follow_by("-to"), arga_action(
			proc(arg:string, user_data: rawptr) -> bool {
				target = arg
				return true
			})
		},
		{ argr_any(), arga_action(
			proc(arg:string, user_data: rawptr) -> bool {
				source, ok := os.read_entire_file(arg)
				if ok {
					strings.write_string(&sources, string(source))
					return true
				}
				return false
			}) 
		}
	)
	if !argsok {
		fmt.eprintf("Invalid args.\n`picozh {sourcefile...} -to {targetfile}`")
		os.exit(255)
	}

	if target == "" do target = "./unicode.lua"

	for i in 32..<127 do strings.write_rune(&sources, rune(i))

	chars = make(map[rune]CharInfo); defer delete(chars)

	for line in strings.split_lines_iterator(&data) {
		if state->process_line(line) do break
	}

	using strings
	sb : Builder
	builder_init(&sb); defer builder_destroy(&sb)

	template_head := #load("head.lua", string)
	for line in split_lines_iterator(&template_head) {
		write_string(&sb, line)
		write_rune(&sb, '\n')
	}

	runes := make(map[rune]CharInfo); defer delete(runes)
	srcrunes := utf8.string_to_runes(to_string(sources)); defer delete(srcrunes)
	for r in srcrunes {
		cinfo, ok := chars[r]
		if !ok && !(r in runes) do continue
		map_insert(&runes, r, cinfo)
	}
	for r, info in runes {
		box := info.box
		if r == ' ' || r == '　' {
			box.x = 4
		}

		using strings
		glyphline : Builder
		builder_init(&glyphline); defer builder_destroy(&glyphline)
		for i in 0..<smary.len(info.glyphline) {
			write_string(&glyphline, smary.get(info.glyphline, i))
			write_rune(&glyphline, ',')
		}
		write_string(&sb, fmt.tprintf("regchar({}, {}, {}, {}, {}, '{}') -- {}\n",
			int(r),
			box[0], box[1], box[2], box[3],
			to_string(glyphline),
			r))
	}
	os.write_entire_file(target, transmute([]u8)to_string(sb))
	fmt.printf("{} characters generated.\n", len(runes))
}

_draw_glyph :: proc(r: rune) -> bool {
	cinfo, ok := chars[r]
	if !ok do return false
	fmt.printf("box: {}\n", cinfo.box)
	for y in 0..<8 {
		l := smary.get(cinfo.glyph, y)
		for x in 0..<8 {
			x := 8-cast(uint)x
			if 1<<x & l > 0 {
				fmt.print("[]")
			} else {
				fmt.print("  ")
			}
		}
		fmt.print('\n')
	}
	return true
}
