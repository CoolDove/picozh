package main

import "core:os"
import "core:fmt"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"
import "core:strconv"
import smary "core:container/small_array"

P8File :: struct {
	copy : string,

	head : string,
	chunks : map[string]string,

	gfx : [4]P8FileGfxPage,
}

P8FileGfxPage :: [4*8][16*8]u8

p8_load :: proc(raw: string, allocator:= context.allocator) -> P8File {
	context.allocator = allocator
	p8 : P8File
	p8.copy = strings.clone(raw)
	p8.chunks = make(map[string]string)

	using strings
	current_head : string
	current_chunk : Builder

	builder_init(&current_chunk)

	lines := p8.copy
	for line in strings.split_lines_iterator(&lines) {
		if len(line) > 0 && line[0] == '_' {
			_submit(&p8, current_head, &current_chunk)
			current_head = strings.trim(line, "_")
		} else {
			write_string(&current_chunk, line)
			write_rune(&current_chunk, '\n')
		}
	}
	_submit(&p8, current_head, &current_chunk)

	_submit :: proc(p8: ^P8File, head: string, chunk: ^strings.Builder, allocator:= context.allocator) {
		context.allocator = allocator
		using strings
		str := clone(to_string(chunk^))
		if head == {} {
			p8.head = str
		} else {
			map_insert(&p8.chunks, head, str)
		}
		builder_reset(chunk)
	}

	// load gfx pages
	gfx_chunk := strings.split_lines(p8.chunks["gfx"])
	chunk_ptr := 0
	for p in 0..<4 {
		for r in 0..<32 {
			if chunk_ptr == len(gfx_chunk) do break
			for pixel, idx in gfx_chunk[chunk_ptr] {
				p8.gfx[p][r][idx] = u8(strconv._digit_value(pixel))
			}
			chunk_ptr += 1
		}
	}
	return p8
}
p8_release :: proc(using p8: ^P8File) {
	delete(copy)
	for ch, cd in chunks {
		delete(cd)
	}
	delete(chunks)
}

p8_write :: proc(using p8: ^P8File, allocator:= context.allocator) -> string {
	context.allocator = allocator
	using strings
	sb : Builder
	write_string(&sb, p8.head)
	for ch, cd in p8.chunks {
		write_string(&sb, fmt.tprintf("__{}__\n", ch))
		if ch == "gfx" {
			values := "0123456789abcdef"
			for page, page_idx in p8.gfx {
				for row in page {
					for px in row {
						write_byte(&sb, values[px])
					}
					write_byte(&sb, '\n')
				}
			}
		} else {
			write_string(&sb, cd)
		}
	}
	return to_string(sb)
}

p8colors :[16][3]u8= {
	{0, 0, 0},         // 0  black
	{29, 43, 83},      // 1  dark blue
	{126, 37, 83},     // 2  dark purple
	{0, 135, 81},      // 3  dark green
	{171, 82, 54},     // 4  brown
	{95, 87, 79},      // 5  dark gray
	{194, 195, 199},   // 6  light gray
	{255, 241, 232},   // 7  white
	{255, 0, 77},      // 8  red
	{255, 163, 0},     // 9  orange
	{255, 236, 39},    // 10 yellow
	{0, 228, 54},      // 11 green
	{41, 173, 255},    // 12 blue
	{131, 118, 156},   // 13 indigo
	{255, 119, 168},   // 14 pink
	{255, 204, 170}    // 15 peach
}
