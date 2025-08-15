package main

import "core:os"
import "core:fmt"
import "core:strings"
import "core:unicode"
import "core:slice"
import "core:unicode/utf8"
import "core:strconv"
import smary "core:container/small_array"

data := #load("quan.bdf", string)

chars : map[rune]CharInfo
CharInfo :: struct {
	r         : rune,
	box       : [4]int,
	glyph     : smary.Small_Array(8, u8),
	glyphline : smary.Small_Array(8, string),

	_appear_times : int,
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
					map_insert(&chars, s.codepoint, CharInfo{ r=s.codepoint, glyph = s.glyph, glyphline = s.glyphline, box = s.box })
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

options : struct {
	slim_mode : bool,
	p8file_path : string,
}

sources : strings.Builder
target : string

p8file : P8File
sprite_pages : [dynamic]int

main :: proc() {
	if len(os.args) < 2 do return

	strings.builder_init(&sources); defer strings.builder_destroy(&sources)

	sprite_pages = make([dynamic]int); defer delete(sprite_pages)
	argsok := args_read(
		{argr_follow_by("-p8"), arga_set(&options.p8file_path)},
		{argr_prefix("--sprite-page:"), arga_action(
			proc(arg:string, user_data: rawptr) -> bool {
				if page, ok := strconv.parse_int(arg); ok {
					if page>3 || page<0 do return false
					for p in sprite_pages do if p == page do return false
					append(&sprite_pages, page)
					return true
				} else {
					return false
				}
			}
		)},
		{argr_follow_by("-to"), arga_action(
			proc(arg:string, user_data: rawptr) -> bool {
				target = arg
				return true
			}
		)},
		{argr_is("--slim"), arga_set(&options.slim_mode)},
		{argr_any(), arga_action(
			proc(arg:string, user_data: rawptr) -> bool {
				source, ok := os.read_entire_file(arg)
				if ok {
					strings.write_string(&sources, string(source))
					return true
				}
				return false
			}
		)}
	)
	if !argsok {
		fmt.eprint("Invalid args.\n`picozh {sourcefile...} -to {targetfile} [--sprite-page:x(0,1,2,3)] [-p8 p8file]`")
		os.exit(255)
	} else {
		fmt.printf("pages: {}\n", sprite_pages)
		fmt.printf("p8file: {}\n", options.p8file_path)
	}

	p8file_loaded : bool
	if options.p8file_path != "" {
		if f, o := os.read_entire_file(options.p8file_path); o {
			p8file = p8_load(string(f))
			p8file_loaded = true
			// for page, page_idx in p8file.gfx {
			// 	fmt.printf("page {}\n", page_idx)
			// 	for row in page {
			// 		for px in row {
			// 			col := p8colors[px]
			// 			fmt.printf("\x1b[48;2;{};{};{}m \x1b[0m", col.r, col.g, col.b)
			// 		}
			// 		fmt.print('\n')
			// 	}
			// }
		} else {
			fmt.printf("failed to read p8 file\n")
		}
	}
	defer if p8file_loaded do p8_release(&p8file)

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
		if !(r in runes) {
			map_insert(&runes, r, cinfo)
		}
		i := runes[r]
		i._appear_times += 1
		runes[r] = i
	}
	available_sprite := make([dynamic]int)
	for p in sprite_pages {
		for i in 0..<64 {
			append(&available_sprite, p * 64 + i)
		}
	}
	sprite_slot_ptr := 0

	sorted_runes, _ := slice.map_values(runes); defer delete(sorted_runes)
	slice.sort_by_cmp(sorted_runes[:], proc(i,j : CharInfo) -> slice.Ordering {
		if i._appear_times > j._appear_times do return slice.Ordering.Greater
		else if i._appear_times > j._appear_times do return slice.Ordering.Equal
		else do return slice.Ordering.Less
	})

	for info in sorted_runes {
		r := info.r
		box := info.box
		if r == ' ' || r == '　' {
			box.x = 4
		}

		if box.x == 7 && box.y == 7 && sprite_slot_ptr < len(available_sprite) { // write to sprite
			slot := available_sprite[sprite_slot_ptr]
			page_idx := slot / 64
			x := (slot%64)%16
			y := (slot%64)/16
			px, py := x * 8, y * 8
			for i in 0..<smary.len(info.glyphline) {
				glyphline := smary.get(info.glyphline, i)
				value, _ := strconv.parse_uint(glyphline, 16)
				for b in 0..<8 {
					paint := value & (1 << u8(b)) > 0
					p8file.gfx[page_idx][py][px+(8-b)-1] = 7 if paint else 0
				}
				py += 1
			}
			if options.slim_mode {
				write_string(&sb, fmt.tprintf("_unicode_table[{}] = {} ", int(r), slot))
			} else {
				write_string(&sb, fmt.tprintf("_unicode_table[{}] = {} -- {} ({})\n", int(r), slot, r, info._appear_times))
			}
			sprite_slot_ptr += 1
		} else {
			using strings
			glyphline : Builder
			builder_init(&glyphline); defer builder_destroy(&glyphline)
			for i in 0..<smary.len(info.glyphline) {
				write_string(&glyphline, smary.get(info.glyphline, i))
				write_rune(&glyphline, ',')
			}
			if options.slim_mode {
				write_string(&sb, fmt.tprintf("regchar\"{};{};{};{};{};{}\" ",
					int(r),
					box[0], box[1], box[2], box[3],
					to_string(glyphline))
				)
			} else {
				write_string(&sb, fmt.tprintf("regchar\"{};{};{};{};{};{}\" -- {} ({})\n",
					int(r),
					box[0], box[1], box[2], box[3],
					to_string(glyphline),
					r, info._appear_times)
				)
			}
		}
	}
	if p8file_loaded {
		outputp8 := p8_write(&p8file); defer delete(outputp8)
		os.write_entire_file(options.p8file_path, transmute([]u8)outputp8)
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
