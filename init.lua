-- TODO
--[[
	Worlds
	segmented loading
	camelCase export
	background image
	external enums
]]

-- Example
--[[
	local LDTK = require("ldtk")
	local world = LDTK("file.ldtk")

	local tile_layer = world:get(1, "Tiles")
	local collision_layer = world:get(1, "IntGrid")
]]

-- Objects
--[[
	local level_object = {
		id = level_data.identifier,
		iid = level_data.iid,

		x = level_data.worldX,
		y = level_data.worldY,
		z = level_data.worldDepth,

		w = level_data.pxWid,
		h = level_data.pxHei,

		background_color = {self:_hex_to_rgb(level_data.__bgColor)},

		layers = self:_new_layer_objects(level_data)
	}

	local layer_object = {
		id = layer_data.__identifier,
		iid = layer_data.iid,

		x = layer_data.__pxTotalOffsetX,
		y = layer_data.__pxTotalOffsetY,
		z = layer_index,

		entities = self:_new_entity_objects(layer_data),
		tiles = self:_new_tile_objects(layer_data),
		grid = self:_new_grid_object(layer_data)
	}

	local entity_object = {
		id = entity_data.__identifier,
		iid = entity_data.iid,

		x = entity_data.px[1] - (entity_data.width * entity_data.__pivot[1]),
		y = entity_data.px[2] - (entity_data.height * entity_data.__pivot[2]),

		w = entity_data.width,
		h = entity_data.height,

		texture = self:_texture_from_tileRect(entity_data.__tile),
		quad = self:_quad_from_tileRect(entity_data.__tile),

		tags = self:_tag_array_to_map(entity_data.__tags),
		fields = self:_convert_fields(entity_data.fieldInstances),
	}

	local tile_object = {
		x = tile_data.px[1],
		y = tile_data.px[2],

		w = tileset_def.tileGridSize,
		h = tileset_def.tileGridSize,

		mx = flip_x[tile_data.f],
		my = flip_y[tile_data.f],

		texture = self.textures[layer_data.__tilesetRelPath],
		quad = self:_get_quad(
			tile_data.src[1], tile_data.src[2],
			tileset_def.tileGridSize, tileset_def.tileGridSize,
			tileset_def.pxWid, tileset_def.pxHei
		),
	}

	local grid_object = {
		w = layer_data.__cWid,
		h = layer_data.__cHei,
		cell_size = layer_data.__gridSize,
		dimensions = {layer_data.__cWid, layer_data.__cHei},

		map = {},
		array = {},
	}

]]

local PATH = ...
local json = require(PATH..".lib.json") -- https://github.com/rxi/json.lua

local function _ripairs_iter(t, i)
	i = i - 1
	local v = t[i]
	if v then
		return i, v
	end
end
local batteries = {
	tablex = {
	ripairs = function(t)
		return _ripairs_iter, t, #t + 1
	end
	},

	color = {
	unpack_rgb = function(rgb)
		local r = math.floor(rgb / 0x10000) % 0x100
		local g = math.floor(rgb / 0x100) % 0x100
		local b = math.floor(rgb) % 0x100
		return r / 255, g / 255, b / 255
	end
}
}

local function path_splitter(path)
   local directory = path:match(".+/")
   local extension = path:gsub(path:match("^.-%."):sub(1, -2), "")
   local name = path:gsub(directory, ""):gsub(extension, "")

	return directory, name, extension
end

local flip_x = {
	[0] = 1,
	[1] = -1,
	[2] = 1,
	[3] = -1
}
local flip_y = {
	[0] = 1,
	[1] = 1,
	[2] = -1,
	[3] = -1
}


-- https://ldtk.io/json/#overview
local LDTK = {}
LDTK.__mt = {
	__index = LDTK
}

function LDTK:_new(path)
	local directory, _, _ = path_splitter(path)
	self.path, self.directory = path, directory
	self.data = json.decode(love.filesystem.read(path))
	self:_load_external_levels()

	self.iids = {}
	self.defs = self:_map_definitions()
	-- self:_load_external_enums()

	self.extern_enums = {}
	self.quads = {}
	self.textures = self:_texture_storage()

	self.entities = {}
	self.levels = self:_new_level_objects()

	return self
end

function LDTK:_map_definitions()
	-- Create my own copy of definitions for easier searching
	local defs = {}
	for k, defintion_groups in pairs(self.data.defs) do
		defs[k] = {}
		for _, def in ipairs(defintion_groups) do
			defs[k][def.uid] = def
		end
	end

	return defs
end

function LDTK:_load_external_levels()
	if self.data.externalLevels then
		local external_level_data = {}

		for _, external_level_data_refs in ipairs(self.data.levels) do
			local rel_path = external_level_data_refs.externalRelPath
			local level_data = json.decode(love.filesystem.read(self.directory..rel_path))
			table.insert(external_level_data, level_data)
		end

		self.data.levels = external_level_data
	end
end

-- function LDTK:_load_external_enums()
-- 	for _, enum_def in ipairs(self.defs.externalEnums) do

-- 	end
-- end

function LDTK:_get_quad(x, y, w, h, tw, th)
	local id = ("%d:%d:%d:%d:%d:%d"):format(x, y, w, h, tw, th)
	if not self.quads[id] then
		self.quads[id] = love.graphics.newQuad(x, y, w, h, tw, th)
	end

	return self.quads[id]
end

function LDTK:_texture_storage()
	local textures = {}
	for _, texture_def in pairs(self.data.defs.tilesets) do
		if texture_def.relPath then
			local texture_path = self.directory..texture_def.relPath
			textures[texture_def.relPath] = love.graphics.newImage(texture_path)
		end
	end

	return textures
end

function LDTK:_new_level_objects()
	local level_objects = {}

	for _, level_data in ipairs(self.data.levels) do
		local level_object = {
			id = level_data.identifier,
			iid = level_data.iid,

			x = level_data.worldX,
			y = level_data.worldY,
			z = level_data.worldDepth,

			w = level_data.pxWid,
			h = level_data.pxHei,

			background_color = {self:_hex_to_rgb(level_data.__bgColor)},

			layers = self:_new_layer_objects(level_data)
		}

		table.insert(level_objects, level_object)
		level_objects[level_object.id] = level_object
		self.iids[level_object.iid] = level_object
	end

	return level_objects
end

function LDTK:_new_layer_objects(level_data)
	local layer_objects = {}

	for layer_index, layer_data in batteries.tablex.ripairs(level_data.layerInstances) do
		local layer_object = {
			id = layer_data.__identifier,
			iid = layer_data.iid,

			x = layer_data.__pxTotalOffsetX,
			y = layer_data.__pxTotalOffsetY,
			z = layer_index,

			entities = self:_new_entity_objects(layer_data),
			tiles = self:_new_tile_objects(layer_data),
			grid = self:_new_grid_object(layer_data)
		}

		table.insert(layer_objects, layer_object)
		layer_objects[layer_object.id] = layer_object
		self.iids[layer_object.iid] = layer_object
	end

	return layer_objects
end

function LDTK:_new_entity_objects(layer_data)
	local entity_objects = {}

	for _, entity_data in ipairs(layer_data.entityInstances) do
		local entity_object = {
			id = entity_data.__identifier,
			iid = entity_data.iid,

			x = entity_data.px[1] - (entity_data.width * entity_data.__pivot[1]),
			y = entity_data.px[2] - (entity_data.height * entity_data.__pivot[2]),

			w = entity_data.width,
			h = entity_data.height,

			texture = self:_texture_from_tileRect(entity_data.__tile),
			quad = self:_quad_from_tileRect(entity_data.__tile),

			tags = self:_tag_array_to_map(entity_data.__tags),
			fields = self:_convert_fields(entity_data.fieldInstances),
		}

		table.insert(entity_objects, entity_object)
		entity_objects[entity_object.id] = entity_object
		self.iids[entity_object.iid] = entity_object
	end

	return entity_objects
end

function LDTK:_new_tile_objects(layer_data)
	local tile_objects = {}

	local tileset_def = self.defs.tilesets[layer_data.__tilesetDefUid]
	for _, tile_data in ipairs(#layer_data.gridTiles ~= 0 and layer_data.gridTiles or layer_data.autoLayerTiles) do
		local tile_object = {
			x = tile_data.px[1],
			y = tile_data.px[2],

			w = tileset_def.tileGridSize,
			h = tileset_def.tileGridSize,

			mx = flip_x[tile_data.f],
			my = flip_y[tile_data.f],

			texture = self.textures[layer_data.__tilesetRelPath],
			quad = self:_get_quad(
				tile_data.src[1], tile_data.src[2],
				tileset_def.tileGridSize, tileset_def.tileGridSize,
				tileset_def.pxWid, tileset_def.pxHei
			),
		}

		table.insert(tile_objects, tile_object)
	end

	return tile_objects
end

function LDTK:_new_grid_object(layer_data)
	local grid_object = {
		w = layer_data.__cWid,
		h = layer_data.__cHei,
		cell_size = layer_data.__gridSize,
		dimensions = {layer_data.__cWid, layer_data.__cHei},

		map = {},
		array = {},
	}
	for _, intGridValue in ipairs(self.defs.layers[layer_data.layerDefUid].intGridValues) do
		grid_object.map[intGridValue.value] = {
			id = intGridValue.identifier,
			color = {self:_hex_to_rgb(intGridValue.color)}
		}
	end
	for i, v in ipairs(layer_data.intGridCsv) do
		grid_object.array[i] = v
	end

	return grid_object
end

function LDTK:_texture_from_tileRect(tileRect)
	if not tileRect then
		return
	end

	local tileset_def = self.defs.tilesets[tileRect.tilesetUid]
	return self.textures[tileset_def.relPath]
end
function LDTK:_quad_from_tileRect(tileRect)
	if not tileRect then
		return
	end

	local tileset_def = self.defs.tilesets[tileRect.tilesetUid]
	return self:_get_quad(tileRect.x, tileRect.y, tileRect.w, tileRect.h, tileset_def.pxWid, tileset_def.pxHei)
end

function LDTK:_tag_array_to_map(tag_array)
	local tag_map = {}
	for _, tag_key in ipairs(tag_array) do
		tag_map[tag_key] = true
	end
	return tag_map
end

function LDTK:_convert_fields(fieldInstances)
	local fields = {}

	local field_type_conversions = {
		["Color"] = function (v)
			return {self:_hex_to_rgb(v)}
		end,

		["Enum"] = function (v)
			return v
		end,

		["Point"] = function (v)
			return {v.cx, v.cy}
		end,

		["Tile"] = function (v)
			local tileset_def = self.definitions[v.tilesetUid]
			return {
				texture = self.textures[tileset_def.relPath],
				quad = self:_get_quad(v.x, v.y, v.w, v.h, tileset_def.pxWid, tileset_def.pxHei)
			}
		end,

		["EntityRef"] = function (v)
			return v
		end,
	}

	local function convert(fields, type, id, value)
		if string.find(type, "LocalEnum.") then
			value = {(type):gsub("LocalEnum.", ""), value}
			type = "Enum"
		elseif string.find(type, "ExternEnum.") then
		end


		if field_type_conversions[type] then
			fields[id] = field_type_conversions[type](value)
		else
			fields[id] = value
		end
	end

	for _, field_data in pairs(fieldInstances) do
		local type = field_data.__type
		local id = field_data.__identifier
		local value = field_data.__value

		if value ~= nil then
			if string.find(type, "Array") then
				local type = (type):match("%b<>"):sub(2, -2)

				-- print(id)
				fields[id] = {}

				for i, v in ipairs(value) do
					convert(fields[id], type, i, v)
				end
			else
				convert(fields, type, id, value)
			end
		end
	end

	return fields
end

function LDTK:_hex_to_rgb(ldtk_hex)
	return batteries.color.unpack_rgb((ldtk_hex):gsub("#", "0x"))
end

function LDTK:get(level_id, layer_id, entity_id)
	local ret = self.levels
	if level_id  then ret = ret[level_id]  end
	if layer_id  then ret = ret.layers[layer_id]  end
	if entity_id then ret = ret.entities[entity_id] end
	return ret
end
function LDTK:get_iid(iid)
	return self.iids[iid]
end

local function _index_to_coordinates(i, w, h)
	local x = i % w
	local y = math.floor(i / w)

	return x, y
end

local function _coordinates_to_index(x, y, w, h)
   return x + y * w
end

local function _grid_iter(t, i)
	i = i + 1

	local v = t.array[i]

	if v then
		local grid_w, grid_h = t.dimensions[1], t.dimensions[2]
		local x, y = _index_to_coordinates(i - 1, grid_w, grid_h)
		local w, h = t.cell_size, t.cell_size

		return i, v, x * w, y * h, w, h
	end
end

function LDTK:iterate_grid(grid)
	return _grid_iter, grid, 0
end
function LDTK:get_grid_value(grid, x, y)
	local i = grid.array[_coordinates_to_index(x, y, grid.dimensions[1]) + 1]
	return i
end

function LDTK:draw()
	for _, level in ipairs(self.levels) do
		love.graphics.push()
		love.graphics.translate(level.x, level.y)

		for _, layer in ipairs(level.layers) do
			love.graphics.push()
			love.graphics.translate(layer.x, layer.y)

			if layer.grid then
				for i, v, x, y, w, h in self:iterate_grid(layer.grid) do
					if v ~= 0 then
						love.graphics.push("all")
						love.graphics.setColor(layer.grid.map[v].color)
						love.graphics.rectangle("fill", x, y, w, h)
						love.graphics.pop()
					end
				end
			end

			for _, tile in ipairs(layer.tiles) do
				love.graphics.draw(
					tile.texture, tile.quad,
					tile.x + tile.w/2, tile.y + tile.h/2,
					0,
					tile.mx, tile.my,
					tile.w/2, tile.h/2
				)
			end

			for _, entity in ipairs(layer.entities) do
				if entity.texture then
					love.graphics.draw(entity.texture, entity.quad, entity.x, entity.y)
				else
					love.graphics.rectangle("fill", entity.x, entity.y, entity.w, entity.h)
				end
			end

			love.graphics.pop()
		end

		love.graphics.pop()
	end
end

return setmetatable(LDTK, {
	__call = function(_, ...)
		 return LDTK:_new(...)
	end
})
