-- https://ldtk.io/json/#ldtk-LevelJson
local Level = OBJECT:extend()

function Level:__new(data)
	local Layer = LOAD.load_with_fenv("layer")

	self.layers = {}
	for _, layer_data in ipairs(data.layerInstances) do
		table.insert(self.layers, Layer(layer_data))
	end

	return self
end

return Level