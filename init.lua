local PATH = ...

local object = require(PATH..".lib.object")
local batteries = require(PATH..".lib.batteries")

local function path_splitter(path)
   local directory = path:match(".+/")
   local extension = path:gsub(path:match("^.-%."):sub(1, -2), "")
   local name = path:gsub(directory, ""):gsub(extension, "")

	return directory, name, extension
end


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

	should I collapse all the layers into level?
	There is definitely per layer information but I wonder if that can't be associated
	with the level or grid/tiles/entities inside
	If the user collapses the information for their own use they will lose a lot of implicit
	stuff
]]

-- https://ldtk.io/json/#overview
local LDTK = object:extend()
local json = require(PATH..".lib.json")

function LDTK:__new(path)
	local directory, _, _ = path_splitter(path)
	self.path, self.directory = path, directory
	self.data = json.decode(love.filesystem.read(path))

	self.defs = self:_map_definitions()

	self:_check_to_load_external_levels()

	self:_texture_storage()

	self:_process_level_data()

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
	self.textures = {}
	for _, texture_def in pairs(self.data.defs.tilesets) do
		if texture_def.relPath then
			local texture_path = self.directory..texture_def.relPath
			self.textures[texture_def.relPath] = love.graphics.newImage(texture_path)
		end
	end
end

function LDTK:_process_level_data()
	self.levels = {}
	self.entities = {}

	for _, level_data in ipairs(self.data.levels) do
		local level = self:_new_level(level_data)
		table.insert(self.levels, level)
		self.levels[level.id] = level
	end
end

function LDTK:_new_world()
	-- I don't know if I want to do this, would it get in the way of segmented loading?
end

function LDTK:_new_level(level_data)
	--[[
		create a level that refers to a mt for convenience functions like draw
		This also doubles as a clear documentation of level fields
	--]]
	local level = {
		id = level_data.identifier,

		x = level_data.worldX,
		y = level_data.worldY,
		z = level_data.worldDepth,

		background_color = {self:_hex_to_rgb(level_data.__bgColor)},

		layers = {}
	}

	-- ripairs because layer_data is sorted by reverse draw order
	for _, layer_data in batteries.tablex.ripairs(level_data.layerInstances) do
		local layer = self:_new_layer(layer_data)
		table.insert(level.layers, layer)
	end

	return level
end

function LDTK:_new_layer(layer_data)
	local layer = {
		x = layer_data.__pxTotalOffsetX,
		y = layer_data.__pxTotalOffsetY,

		grid_size = layer_data.__gridSize,
		grid_width = layer_data.__cWid,
		grid_height = layer_data.__cHei,

		entities = self:_new_layer_entities(layer_data),
		tiles = self:_new_layer_tiles(layer_data),
		grid = self:_new_layer_grid(layer_data)
	}

	return layer
end

function LDTK:_new_layer_entities(layer_data)
	if #layer_data.entityInstances == 0 then
		return {}
	end

	local entities = {}
	for _, entity_data in ipairs(layer_data.entityInstances) do
		local entity = self:_new_entity(entity_data, layer_data)
		table.insert(entities, entity)
	end
	return entities
end

function LDTK:_new_layer_tiles(layer_data)
	if #layer_data.autoLayerTiles == 0 and #layer_data.gridTiles == 0 then
		return {}
	end

	local tiles = {}
	for _, tile_data in ipairs(layer_data.autoLayerTiles) do
		table.insert(tiles, self:_new_tile(tile_data, layer_data))
	end
	for _, tile_data in ipairs(layer_data.gridTiles) do
		table.insert(tiles, self:_new_tile(tile_data, layer_data))
	end
	return tiles
end

function LDTK:_new_layer_grid(layer_data)
	if #layer_data.intGridCsv == 0 then
		return {}
	end

	local grid = {
		map = {},
		array = {}
	}
	for _, intGridValue in ipairs(self.defs.layers[layer_data.layerDefUid].intGridValues) do
		grid.map[intGridValue.value] = {
			color = {self:_hex_to_rgb(intGridValue.color)}
		}
	end
	for i, v in ipairs(layer_data.intGridCsv) do
		grid.array[i] = v
	end
	return grid
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
function LDTK:_new_tile(tile_data, layer_data)
	local tile = {}

	local tileset_def = self.defs.tilesets[layer_data.__tilesetDefUid]

	local quad_x, quad_y = unpack(tile_data.src)
	local quad_w, quad_h = tileset_def.tileGridSize, tileset_def.tileGridSize
	local quad_tex_w, quad_tex_h = tileset_def.pxWid, tileset_def.pxHei
	local quad = love.graphics.newQuad(quad_x, quad_y, quad_w, quad_h, quad_tex_w, quad_tex_h)

	tile.texture = self.textures[layer_data.__tilesetRelPath]
	tile.quad = quad
	tile.x, tile.y = tile_data.px[1], tile_data.px[2]
	tile.w, tile.h = quad_w, quad_h
	tile.sx, tile.sy = flip_x[tile_data.f], flip_y[tile_data.f]
	tile.ox, tile.oy = quad_w/2, quad_h/2

	return tile
end

function LDTK:_new_entity(entity_data, layer_data)
	local entity = {
		identifier = entity_data.__identifier,
		iid = entity_data.iid,

		x = entity_data.px[1] - (entity_data.width * entity_data.__pivot[1]),
		y = entity_data.px[2] - (entity_data.height * entity_data.__pivot[2]),
		w = entity_data.width,
		h = entity_data.height,

		texture = self:_texture_from_tileRect(entity_data.__tile),
		quad = self:_quad_from_tileRect(entity_data.__tile),

		fields = self:_convert_fields(entity_data.fieldInstances)
	}

	self.entities[entity.iid] = entity
	return entity
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

function LDTK:draw_world()
	for i, level in ipairs(self.levels) do
		if self.levels[i].z == 0 then
			self:draw_level(i)
		end
	end
end
function LDTK:draw_level(i)
	local level = self.levels[i]

	love.graphics.push("all")

	-- need to think about if I should implicitly translate all the elements based on the level/layer coordinates
	love.graphics.translate(level.x, level.y)

	love.graphics.setBackgroundColor(unpack(level.background_color))

	for _, layer in ipairs(level.layers) do
		love.graphics.push("all")
		love.graphics.translate(layer.x, layer.y)

		if layer.tiles then
			for _, tile in ipairs(layer.tiles) do
				-- love.graphics.rectangle("line", tile.x, tile.y, 16, 16)
				love.graphics.draw(tile.texture, tile.quad, tile.x + tile.w/2, tile.y + tile.h/2, 0, tile.sx, tile.sy, tile.ox, tile.oy)
			end
		end

		if layer.entities then
			for _, entity in ipairs(layer.entities) do
				if entity.texture then
					love.graphics.draw(entity.texture, entity.quad, entity.x, entity.y)
				else
					love.graphics.rectangle("fill", entity.x, entity.y, entity.w, entity.h)
				end
			end
		end

		if layer.grid then
			-- self:_draw_grid(layer)
		end

		love.graphics.pop()
	end

	love.graphics.pop()
end
function LDTK:_draw_grid(layer)
	love.graphics.push("all")
	for i, v, x, y, w, h in self:iterate_grid(layer) do
		if v ~= 0 then
			love.graphics.setColor(layer.grid.map[v].color)
			love.graphics.rectangle("fill", x, y, w, h)
		end
	end
	love.graphics.pop()
end


local function _index_to_coordinates(i, w, h)
	local x = i % w
	local y = math.floor(i / w)

	return x, y
end
local function _grid_iter(t, i)
	i = i + 1

	if t.grid.array == nil then return end
	local v = t.grid.array[i]

	if v then
		local grid_w, grid_h = t.grid_width, t.grid_height
		local x, y = _index_to_coordinates(i - 1, grid_w, grid_h)
		local w, h = t.grid_size, t.grid_size

		return i, v, x * w, y * h, w, h
	end
end
function LDTK:iterate_grid(layer)
	return _grid_iter, layer, 0
end




return LDTK
