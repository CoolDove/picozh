function test_gprint()
	gprint("世界, bye", 8, 8)
end

function gprint(text, x, y, col)
	local xx = x
	local yy = y
	for cp in utf8_iter(text) do
		print(cp, xx, yy, col)
		yy += 8
	end
end

function utf8_iter(s)
	local i = 1
	return function()
		if i > #s then return nil end
		local c = ord(s, i)
		local cp, len

		if c < 0x80 then
			cp = c
			len = 1
		elseif c < 0xe0 then
			cp = band(c, 0x1f) << 6 | band(ord(s, i+1), 0x3f)
			len = 2
		elseif c < 0xf0 then
			cp = band(c, 0x0f) << 12 | band(ord(s, i+1), 0x3f) << 6 | band(ord(s, i+2), 0x3f)
			len = 3
		else
			cp = band(c, 0x07) << 18 | band(ord(s, i+1), 0x3f) << 12 | band(ord(s, i+2), 0x3f) << 6 | band(ord(s, i+3), 0x3f)
			len = 4
		end

		i += len
		return cp
	end
end
