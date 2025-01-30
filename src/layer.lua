-- https://ldtk.io/json/#ldtk-LayerInstanceJson
local Layer = OBJECT:extend()

function Layer:__new(data)
	self.type = data.__type

	self.size = data.__gridSize -- cell size
	self.w, self.h = data.__cWid, data.__cHei

	if self.type == "IntGrid" then
		self.grid = data.intGridCsv
	end

	return self
end

return Layer