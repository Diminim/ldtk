local P = {}
setmetatable(P, {__index = _G})
setfenv(1, P)

local PATH = ...

LOAD = require(PATH..".lib.load_utils")
OBJECT = require(LOAD.relative("lib.object"))

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
]]

-- https://ldtk.io/json/#overview
local LDTK = OBJECT:extend()

local World = OBJECT:extend()
local Level = OBJECT:extend()
local Layer = OBJECT:extend()
local Entity = OBJECT:extend()
local Field = OBJECT:extend()

---@param path string
function LDTK:__new(path)
	self.data = require(LOAD.relative("lib.json")).decode(love.filesystem.read(path))
	self.defs = self.data.defs


	-- Load levels differently if true
	self.external_levels = self.data.externalLevels

	return self
end


-- function LDTK:new_level()
-- 	return Level(self.)
-- end

-- function LDTK:new_layer()

-- end

-- function LDTK:new_component(typedata)

-- end



---@param id string|integer
-- function LDTK:load_level(id)
-- 	return Level(self.data.levels[id])
-- end

-- function World:__new(data)
-- end

function Level:__new(def, inst)

	self.layers = {}
	for _, layer_data in ipairs(inst.layerInstances) do
		table.insert(self.layers, Layer(layer_data))
	end

	return self
end


-- function Level:draw()
-- 	-- this should draw every layer that the user wants
-- 	-- Could do intgrid and static entities for debugging
-- end

function Layer:__new(def, inst)
	self.type = inst.__type

	self.size = inst.__gridSize -- cell size
	self.width, self.height = inst.__cWid, inst.__cHei

	if self.type == "IntGrid" then
		self.grid = inst.intGridCsv
	end
end

-- local function index_to_coordinates(i, w, h)
-- 	local x = i % w
-- 	local y = math.floor(i / w)

-- 	return x, y
-- end
-- function Layer:draw()
-- 	for i, v in ipairs(self.grid) do
-- 		if v ~= 0 then
-- 			local x, y = index_to_coordinates(i, self.width, self.height)

-- 			-- I want to do the color thing
-- 			love.graphics.rectangle("fill", x * self.size, y * self.size, self.size, self.size)
-- 		end
-- 	end
-- end

-- function Entity:__new(data)
-- end

-- function Field:__new(data)
-- end



return LDTK
