local P = {}
setmetatable(P, {__index = _G})
setfenv(1, P)

local PATH = ...

LOAD = require(PATH..".lib.load_utils")
OBJECT = require(LOAD.relative("lib.object"))

-- tablex
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

-- color
local color = {}
function color.unpack_rgb(rgb)
	local r = math.floor(rgb / 0x10000) % 0x100
	local g = math.floor(rgb / 0x100) % 0x100
	local b = math.floor(rgb) % 0x100
	return r / 255, g / 255, b / 255
end


-- local Layer = LOAD.load_with_fenv("layer")

--[[
	TODO:
	Worlds
	Separate Levels

	I should probably not load everything at once for performance concerns
	I should write a camelcase export, or just use max's

	I should start from just drawing things

	components: definitions, instances


	I should probably not use the definition and instance data for fields
	Just initialize everything upfront

	Should components be created by their parent or LDTK

	Should I do a load as needed for tilesets?

	Worlds and levels don't have instances or definitions

	Maybe I should completely scrap the multiple types as they are
	and not give them functions

	So what, do something like LDTK:draw(instance)

	I could write a way to quickly get the definition associated with something

	I should have a preprocessing step to make things nicer to work with
	like hex to rgb
	and ordered arrays

	The user shouldn't have to use my shit and just have a nice way to access their data

	I could defer creating the textures until it's time to draw them and make that an option
	I guess creating and releasing textures is hard

	For now I'm going to load everything at once
	and then I'll come up with ways to segment it

	Extensions:
	Slick integration with stair steps / slopes
	Animations
	AutoLayer parsing for procgen

		-- unsure if I should keep entities in their own table
	-- probably, the layers can just keep references to them
	-- don't know if I should separate levels and layers though
	-- a level just feels like a collection of layers and I don't think I'd need to use them separately
	-- fields are just gonna be tacked onto entities as opposed to separate

		The fastest way to find quads is to have a direct association
		tile.quad = quad

		To avoid duplication I have to key the quads by their properties

		And I have to use my own tile instance objects...

		oh wait there's tileids

		I'll eat the performance for now

		never mind, I of course need to separate between different tilesets


]]

-- https://ldtk.io/json/#overview
local LDTK = OBJECT:extend()
local json = require(LOAD.relative("lib.json"))

local function index_to_coordinates(i, w, h)
	local x = i % w
	local y = math.floor(i / w)

	return x, y
end


local function convert_hex(ldtk_hex)
	return color.unpack_rgb((ldtk_hex):gsub("#", "0x"))
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

function LDTK:__new(path)
	self.path = path
	local directory, name, extension = LOAD.path_splitter(self.path)

	self.data = json.decode(love.filesystem.read(path))

	-- Create my own copy of definitions for easier searching
	self.defs = {}
	for k, defintion_groups in pairs(self.data.defs) do
		self.defs[k] = {}
		for _, def in ipairs(defintion_groups) do
			self.defs[k][def.uid] = def
		end
	end

	-- Replace the level_ref with the external level data
	if self.data.externalLevels then
		local external_level_data = {}

		for _, external_level_data_refs in ipairs(self.data.levels) do
			local rel_path = external_level_data_refs.externalRelPath
			local level_data = json.decode(love.filesystem.read(directory..rel_path))
			table.insert(external_level_data, level_data)
		end

		self.data.levels = external_level_data
	end

	-- Texture storage
	self.textures = {}
	for _, texture_def in pairs(self.data.defs.tilesets) do
		if texture_def.relPath then
			local texture_path = directory..texture_def.relPath
			self.textures[texture_def.relPath] = love.graphics.newImage(texture_path)
		end
	end

	-- Quad storage
	self.quads = {}

	-- Processed data
	self.levels = {}
	self.entities = {}


	local function new_tile(tile_data, layer_data)
		local tile = {}

		local tileset_def = self.defs.tilesets[layer_data.__tilesetDefUid]

		local quad_x, quad_y = unpack(tile_data.src)
		local quad_w, quad_h = tileset_def.tileGridSize, tileset_def.tileGridSize
		local quad_tex_w, quad_tex_h = tileset_def.pxWid, tileset_def.pxHei
		local quad = love.graphics.newQuad(quad_x, quad_y, quad_w, quad_h, quad_tex_w, quad_tex_h)

		tile.texture = self.textures[layer_data.__tilesetRelPath]
		tile.quad = quad
		tile.x, tile.y = tile_data.px[1], tile_data.px[2]
		tile.sx, tile.sy = flip_x[tile_data.f], flip_y[tile_data.f]
		tile.ox, tile.oy = quad_w/2, quad_h/2

		return tile
	end

	local function new_entity(entity_data, layer_data)
		local entity = {}

		entity.x, entity.y = unpack(entity_data.px)
		entity.w, entity.h = entity_data.width, entity_data.height

		return entity
	end


	for _, level_data in ipairs(self.data.levels) do
		local level = {} table.insert(self.levels, level)
		level.x, level.y = level_data.worldX, level_data.worldY
		level.z = level_data.worldDepth

		level.background_color = {convert_hex(level_data.__bgColor)}

		level.layers = {}
		for _, layer_data in tablex.ripairs(level_data.layerInstances) do -- ripairs because layer_data is sorted by reverse draw order
			local layer = {} table.insert(level.layers, layer)

			layer.x, layer.y = layer_data.__pxTotalOffsetX, layer_data.__pxTotalOffsetY

			layer.grid_size = layer_data.__gridSize
			layer.grid_width = layer_data.__cWid
			layer.grid_height = layer_data.__cHei

			if #layer_data.autoLayerTiles ~= 0 then
				layer.tiles = layer.tiles or {}
				for _, tile_data in ipairs(layer_data.autoLayerTiles) do
					table.insert(layer.tiles, new_tile(tile_data, layer_data))
				end
			end

			if #layer_data.gridTiles ~= 0 then
				layer.tiles = layer.tiles or {}
				for _, tile_data in ipairs(layer_data.gridTiles) do
					table.insert(layer.tiles, new_tile(tile_data, layer_data))
				end
			end

			if #layer_data.entityInstances ~= 0 then
				layer.entities = {}
				for _, entity_data in ipairs(layer_data.entityInstances) do
					table.insert(layer.entities, new_entity(entity_data, layer_data))
				end
			end

			if #layer_data.intGridCsv ~= 0 then
				layer.grid = {}
				for i, v in ipairs(layer_data.intGridCsv) do
					layer.grid[i] = v
				end
			end



		end
	end


	return self
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
	love.graphics.translate(level.x, level.y)

	love.graphics.setBackgroundColor(unpack(level.background_color))

	for _, layer in ipairs(level.layers) do
		love.graphics.push("all")
		love.graphics.translate(layer.x, layer.y)

		if layer.tiles then
			for _, tile in ipairs(layer.tiles) do
				-- love.graphics.rectangle("line", tile.x, tile.y, 16, 16)
				love.graphics.draw(tile.texture, tile.quad, tile.x, tile.y, 0, tile.sx, tile.sy, tile.ox, tile.oy)
			end
		end

		if layer.entities then
			for _, entity in ipairs(layer.entities) do
				-- love.graphics.rectangle("fill", entity.x, entity.y, entity.w, entity.h)
			end
		end

		if layer.grid then
			-- self:draw_grid(layer)
		end

		love.graphics.pop()
	end

	love.graphics.pop()
end

function LDTK:draw_grid(layer)
	-- local definition = self.defs.layers[layer.layerDefUid]
	-- local size = layer.__gridSize
	-- local width, height = layer.__cWid, layer.__cHei

	-- local function get_intGridValue(value)
	-- 	for _, intGridValue in ipairs(definition.intGridValues) do
	-- 		if intGridValue.value == value then
	-- 			return intGridValue
	-- 		end
	-- 	end
	-- end

	local s, w, h = layer.grid_size, layer.grid_width, layer.grid_height

	for i, v in ipairs(layer.grid) do
		if v ~= 0 then
			local x, y = index_to_coordinates(i-1, w, h)
			-- love.graphics.setColor(convert_hex(get_intGridValue(v).color))

			love.graphics.rectangle("fill", x * s, y * s, s, s)

			love.graphics.setColor(1, 1, 1, 1)
		end
	end
end

-- function LDTK:draw()
-- 	love.graphics.push()
-- 	love.graphics.scale(2)

-- 	for i, level in ipairs(self.data.levels) do
-- 		-- I should have an option to use the level xy or a user input

-- 		love.graphics.setBackgroundColor(convert_hex(level.__bgColor))

-- 		for _, layer in tablex.ripairs(level.layerInstances) do

-- 			if #layer.entityInstances ~= 0 then
-- 				self:draw_entities(layer)
-- 			end

-- 			if #layer.autoLayerTiles ~= 0 then
-- 				self:draw_tiles(layer)
-- 			end

-- 			-- if #layer.intGridCsv ~= 0 then
-- 			-- 	self:draw_intGrid(layer)
-- 			-- end

-- 		end
-- 	end

-- 	love.graphics.pop()
-- end

-- function LDTK:draw_tiles(layer)
-- 	local tileset_def = self.defs.tilesets[layer.__tilesetDefUid]

-- 	local texture = self.textures[layer.__tilesetRelPath]

-- 	for _, tile in ipairs(layer.autoLayerTiles) do
-- 		local x, y = unpack(tile.px)

-- 		local quad_x, quad_y = unpack(tile.src)
-- 		local quad_w, quad_h = tileset_def.tileGridSize, tileset_def.tileGridSize
-- 		local quad_tex_w, quad_tex_h = tileset_def.pxWid, tileset_def.pxHei
-- 		local quad = love.graphics.newQuad(quad_x, quad_y, quad_w, quad_h, quad_tex_w, quad_tex_h)

-- 		love.graphics.draw(texture, quad, x, y, 0, flip_x[tile.f], flip_y[tile.f], quad_w/2, quad_h/2)
-- 	end
-- end

-- function LDTK:draw_intGrid(layer)
-- 	local definition = self.defs.layers[layer.layerDefUid]
-- 	local size = layer.__gridSize
-- 	local width, height = layer.__cWid, layer.__cHei

-- 	local function get_intGridValue(value)
-- 		for _, intGridValue in ipairs(definition.intGridValues) do
-- 			if intGridValue.value == value then
-- 				return intGridValue
-- 			end
-- 		end
-- 	end

-- 	for i, v in ipairs(layer.intGridCsv) do
-- 		if v ~= 0 then
-- 			local x, y = index_to_coordinates(i-1, width, height)
-- 			love.graphics.setColor(convert_hex(get_intGridValue(v).color))

-- 			love.graphics.rectangle("fill", x * size, y * size, size, size)

-- 			love.graphics.setColor(1, 1, 1, 1)
-- 		end
-- 	end
-- end

-- function LDTK:draw_entities(layer)
-- 	for _, entity in ipairs(layer.entityInstances) do
-- 		local entity_def = self.defs.entities[entity.defUid]

-- 		local tile_rect = entity_def.tileRect

-- 		local tileset_def = self.defs.tilesets[tile_rect.tilesetUid]

-- 		if tileset_def.relPath then
-- 			local texture = self.textures[tileset_def.relPath]

-- 			local quad_x, quad_y = tile_rect.x, tile_rect.y
-- 			local quad_w, quad_h = tile_rect.w, tile_rect.h
-- 			local quad_tex_w, quad_tex_h = tileset_def.pxWid, tileset_def.pxHei
-- 			local quad = love.graphics.newQuad(quad_x, quad_y, quad_w, quad_h, quad_tex_w, quad_tex_h)

-- 			local x, y = unpack(entity.px)
-- 			love.graphics.draw(texture, quad, x, y)

-- 		else

-- 			local x, y = unpack(entity.px)
-- 			local w, h = entity.width, entity.height
-- 			love.graphics.rectangle("fill", x, y, w, h)
-- 		end
-- 	end
-- end



return LDTK
