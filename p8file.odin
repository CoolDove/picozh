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
	chunks : map[string]string,

	gfx : [4]P8FileGfxPage,
}

P8FileGfxPage :: [4][8][16*8]u8

p8_load :: proc(raw: string, allocator:= context.allocator) -> P8File {
	p8 : P8File
	p8.copy = strings.clone(raw)
	p8.chunks = make(map[string]string)

	using strings
	current_head : string
	current_chunk : Builder

	builder_init(&current_chunk)

	for line in strings.split_lines_iterator(&p8.copy) {
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
		using strings
		h := head if head != {} else "head"
		map_insert(&p8.chunks, h, clone(to_string(chunk^)))
		builder_reset(chunk)
	}

	// load gfx pages
	gfx_chunk := strings.split_lines(p8.chunks["gfx"])
	chunk_ptr := 0
	for p in 0..<4 {
		for r in 0..<4 {
			for pr in 0..<8 {
				if chunk_ptr == len(gfx_chunk) do break
				for pixel, idx in gfx_chunk[chunk_ptr] {
					p8.gfx[p][r][pr][idx] = u8(strconv._digit_value(pixel))
				}
				chunk_ptr += 1
			}
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
