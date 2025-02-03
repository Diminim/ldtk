local PATH = ...

local object = require(PATH..".lib.object")
local batteries = require(PATH..".lib.batteries")

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

--[[
	TODO:
	Worlds
	segmented loading
	camelCase export
	quad sharing
	background image
	enum
	external enum
	level objects

	Extensions:
	Slick integration with stair steps / slopes
	Animations
	AutoLayer parsing for procgen

	I roughly treat tiles and entities the same
	they have coordinates, dimensions, and textures

	So the user has their ldtk file
	and can specify what levels they want to load
	and will get it on load

	I want to have a level object so I can
	level:draw() and stuff

	This library should be concerned with organizing and fetching the ldtk data

	I want to handle separate, connected, and seamless levels

	I prefer having everything separated but provided an option to output layers could be good
]]

-- https://ldtk.io/json/#overview
local LDTK = object:extend()
local json = require(PATH..".lib.json")

function LDTK:__new(path)
	local directory, _, _ = path_splitter(path)
	self.path, self.directory = path, directory
	self.data = json.decode(love.filesystem.read(path))
	self:_check_to_load_external_levels()

	self.defs = self:_map_definitions()
	self.textures = self:_texture_storage()

	self.entities = {}
	self.levels = self:_process_level_data()

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

function LDTK:_check_to_load_external_levels()
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

function LDTK:_process_level_data()
	local levels = {}

	for _, level_data in ipairs(self.data.levels) do
		local level = self:_new_level(level_data)
		table.insert(levels, level)
		levels[level.id] = level
	end

	return levels
end

function LDTK:_new_level(level_data)
	local level = {
		id = level_data.identifier,

		x = level_data.worldX,
		y = level_data.worldY,
		z = level_data.worldDepth,

		background_color = {self:_hex_to_rgb(level_data.__bgColor)},
	}
	level.layers, level.entities, level.tiles, level.grids = self:_new_layers(level_data)
	return level
end

function LDTK:_new_layers(level_data)
	local layers = {}
	local entities = {}
	local tiles = {}
	local grids = {}

	for layer_index, layer_data in batteries.tablex.ripairs(level_data.layerInstances) do
		local layer = {
			id = layer_data.__identifier,

			entities = {},
			tiles = {},
			grid = {}
		}
		layers[layer.id] = layer

		for _, entity_data in ipairs(layer_data.entityInstances) do
			local entity = self:_new_entity(entity_data, layer_index, layer_data, level_data)
			table.insert(layer.entities, entity)
			table.insert(entities, entity)
		end

		for _, tile_data in ipairs(layer_data.autoLayerTiles) do
			local tile = self:_new_tile(tile_data, layer_index, layer_data, level_data)
			table.insert(layer.tiles, tile)
			table.insert(tiles, tile)
		end
		for _, tile_data in ipairs(layer_data.gridTiles) do
			local tile = self:_new_tile(tile_data, layer_index, layer_data, level_data)
			table.insert(layer.tiles, tile)
			table.insert(tiles, tile)
		end

		do
			local grid = self:_new_grid(layer_data.intGridCsv, layer_index, layer_data, level_data)
			layer.grid = grid
			table.insert(grids, grid)
		end

	end

	return layers, entities, tiles, grids
end

function LDTK:_new_entity(entity_data, layer_index, layer_data, level_data)
	local entity = {
		identifier = entity_data.__identifier,
		iid = entity_data.iid,

		translation = {
			level = {level_data.worldX, level_data.worldY},
			layer = {layer_data.__pxTotalOffsetX, layer_data.__pxTotalOffsetY},
			object = {
				entity_data.px[1] - (entity_data.width * entity_data.__pivot[1]),
				entity_data.px[2] - (entity_data.height * entity_data.__pivot[2]),
			}
		},

		z_level = {
			level = level_data.worldDepth,
			layer = layer_index,
		},

		dimensions = {entity_data.width, entity_data.height},

		texture = self:_texture_from_tileRect(entity_data.__tile),
		quad = self:_quad_from_tileRect(entity_data.__tile),

		tags = self:_tag_array_to_map(entity_data.__tags),
		fields = self:_convert_fields(entity_data.fieldInstances),
	}

	self.entities[entity.iid] = entity
	return entity
end

function LDTK:_new_tile(tile_data, layer_index, layer_data, level_data)
	local tileset_def = self.defs.tilesets[layer_data.__tilesetDefUid]

	local tile = {
		translation = {
			level = {level_data.worldX, level_data.worldY},
			layer = {layer_data.__pxTotalOffsetX, layer_data.__pxTotalOffsetY},
			object = {tile_data.px[1], tile_data.px[2]}
		},

		z_level = {
			level = level_data.worldDepth,
			layer = layer_index,
		},

		grid_coordinates = {
			tile_data.px[1] / tileset_def.tileGridSize,
			tile_data.px[2] / tileset_def.tileGridSize
		},

		texture = self.textures[layer_data.__tilesetRelPath],
		quad = love.graphics.newQuad(
			tile_data.src[1], tile_data.src[2],
			tileset_def.tileGridSize, tileset_def.tileGridSize,
			tileset_def.pxWid, tileset_def.pxHei
		),

		dimensions = {tileset_def.tileGridSize, tileset_def.tileGridSize},
		mirror = {flip_x[tile_data.f], flip_y[tile_data.f]}
	}

	return tile
end
function LDTK:_new_grid(grid_data, layer_index, layer_data, level_data)
	local grid = {
		translation = {
			level = {level_data.worldX, level_data.worldY},
			layer = {layer_data.__pxTotalOffsetX, layer_data.__pxTotalOffsetY},
		},

		z_level = {
			level = level_data.worldDepth,
			layer = layer_index,
		},

		map = {},
		array = {},

		cell_size = layer_data.__gridSize,
		dimensions = {layer_data.__cWid, layer_data.__cHei},
	}
	for _, intGridValue in ipairs(self.defs.layers[layer_data.layerDefUid].intGridValues) do
		grid.map[intGridValue.value] = {
			id = intGridValue.identifier,
			color = {self:_hex_to_rgb(intGridValue.color)}
		}
	end
	for i, v in ipairs(layer_data.intGridCsv) do
		grid.array[i] = v
	end

	return grid
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
	return love.graphics.newQuad(tileRect.x, tileRect.y, tileRect.w, tileRect.h, tileset_def.pxWid, tileset_def.pxHei)
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

		end,

		["Point"] = function (v)
			return {v.cx, v.cy}
		end,

		["Tile"] = function (v)
			local tileset_def = self.definitions[v.tilesetUid]
			return {
				texture = self.textures[tileset_def.relPath],
				quad = love.graphics.newQuad(v.x, v.y, v.w, v.h, tileset_def.pxWid, tileset_def.pxHei)
			}
		end,

		["EntityRef"] = function (v)
			return v.Iid
		end,
	}

	local function convert(field, type, id, value)
		if field_type_conversions[type] then
			field[id] = field_type_conversions[type](value)
		else
			field[id] = value
		end
	end

	for _, field_data in pairs(fieldInstances) do
		local type = field_data.__type
		local id = field_data.__identifier
		local value = field_data.__value
		-- print(id, type, value)


		if value ~= nil then
			if string.find(type, "Array") then
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

function LDTK:get_world()
	return self.levels
end
function LDTK:get_level(id)
	return self.levels[id]
end

function LDTK:get_layer()

end
function LDTK:get_entity()

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

function LDTK:grid_get(grid, x, y)
	local i = grid.array[_coordinates_to_index(x, y, grid.dimensions[1]) + 1]
	return i
end

function LDTK:draw()
	for _, level in ipairs(self.levels) do
		for _, grid in ipairs(level.grids) do
			local t_x, t_y = 0, 0
			for _, translation in pairs(grid.translation) do
				t_x = t_x + translation[1]
				t_y = t_y + translation[2]
			end

			for i, v, x, y, w, h in self:iterate_grid(grid) do
				if v ~= 0 then
					love.graphics.push("all")
					love.graphics.setColor(grid.map[v].color)
					love.graphics.rectangle("fill", x + t_x, y + t_y, w, h)
					love.graphics.pop()
				end
			end
		end

		for _, tile in ipairs(level.tiles) do
			local x, y = 0, 0
			for _, translation in pairs(tile.translation) do
				x = x + translation[1]
				y = y + translation[2]
			end

			local x = x + tile.dimensions[1]/2
			local y = y + tile.dimensions[2]/2
			local r = 0
			local sx = tile.mirror[1]
			local sy = tile.mirror[2]
			local ox = tile.dimensions[1]/2
			local oy = tile.dimensions[2]/2

			love.graphics.draw(tile.texture, tile.quad, x, y, r, sx, sy, ox, oy)
		end

		for _, entity in ipairs(level.entities) do
			local x, y = 0, 0
			for _, translation in pairs(entity.translation) do
				x = x + translation[1]
				y = y + translation[2]
			end

			if entity.texture then
				love.graphics.draw(entity.texture, entity.quad, x, y)
			else
				love.graphics.rectangle("fill", x, y, entity.dimensions[1], entity.dimensions[2])
			end
		end
	end
end

-- write a function to output a pretty entity?






return LDTK
