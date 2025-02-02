local tablex = {}
local function _ripairs_iter(t, i)
	i = i - 1
	local v = t[i]
	if v then
		return i, v
	end
end

--iterator that works like ipairs, but in reverse order, with indices from #t to 1
--similar to ipairs, it will only consider sequential until the first nil value in the table.
function tablex.ripairs(t)
	return _ripairs_iter, t, #t + 1
end



local color = {}
function color.unpack_rgb(rgb)
	local r = math.floor(rgb / 0x10000) % 0x100
	local g = math.floor(rgb / 0x100) % 0x100
	local b = math.floor(rgb) % 0x100
	return r / 255, g / 255, b / 255
end

return {
	tablex = tablex,
	color = color
}
