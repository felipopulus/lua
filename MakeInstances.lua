--- This script instanciates objects in Katana from external data
--- Reads a txt file containing a matrix per line.
--- Each matrix represents the transformation of each of the instances.
--- This script can also limit the amount of instances that will be displayed in the viewport
--- There are 3 methods on how to instanciate geometry --
--- 1. Instance Array -- Single location for all instances
--- 2. Instantiate -- One location per instance
--- 3. HeroUp -- This is a full copy of the source hierachy. This is useful for when things need to be edited manually.

--- Get animation
local current_frame = Interface.GetCurrentTime()
local anim_start = Interface.GetOpArg("user.animationStart"):getValue()
local anim_end = Interface.GetOpArg("user.animationEnd"):getValue()
local prune_paths = Interface.GetOpArg('user.pruneLocationPaths'):getNearestSample(0.0)
local hero_up_paths = Interface.GetOpArg('user.heroUpLocationPaths'):getNearestSample(0.0)

if current_frame < anim_start then
  current_frame = anim_start
end
if current_frame > anim_end then
  current_frame = anim_end
end

--- Get location where intances will be sourced from
local x_gen_data_file_format = Interface.GetOpArg("user.matrixDir"):getValue()
local x_gen_data_file = x_gen_data_file_format.."."..current_frame..".txt"

--- Get location where intances will be sourced from
local instance_location = Interface.GetRootLocationPath()
local instance_source = Interface.GetOpArg("user.instanceSource"):getValue()
local mode = Interface.GetOpArg("user.mode"):getValue()
local as_percentage = Interface.GetOpArg("user.asPercentage"):getValue()
local percentage = Interface.GetOpArg("user.scenegraphVisibility"):getValue()

local source_bounds = Interface.GetBoundAttr(instance_source)

--- Read Data ---
function getMatrixLinesFromFile()
  local file = io.open(x_gen_data_file, "r")
  local lines = {}
  local index = 1
  for line in file:lines() do
      if index ~= 1 then
           table.insert (lines, line)
      end
      index = index + 1
  end
  return lines
end

--- Get Indecies of based on percentage.
function getEvenSpaceIndices(stop, percentage)
  local num = percentage / 100 * stop
  local start = 1
  if num <= 1 then return {start} end
  local step = (stop-start) / (num-1)
  local y = {}
  for i = 0, num-1 do table.insert(y, math.floor(i * step + start)) end
  return y
end

--- We can generate a table will contain paths where instead of instanciating, we'll replicate the full hierarchy
function isInHeroUpTable(inst_full_location)
  for _, v in ipairs(hero_up_paths) do
    if string.find(inst_full_location, v) then
      return true
    end
  end
  return false
end

--- Pruning instances by not loading them is more efficient than loading them and the prunning them
function isInPruneTable(inst_full_location)
  for _, v in ipairs(prune_paths) do
    if string.find(inst_full_location, v) then
      return true
    end
  end
  return false
end

--- Converts strings delimited by space, into Imath matrix tables
function convertStringToMatrix(matrix_str)
  local matrix = string.gmatch(matrix_str, "%S+")
  local matrix_table = {}
  for w in matrix do table.insert(matrix_table, w) end
  local matrix_m44d = Imath.M44d(matrix_table)
  return DoubleAttribute(matrix_m44d:toTable(), 16)
end

function findInstanceMatrix(path)
  local lines = getMatrixLinesFromFile()
  local index_str = string.sub(path, -6)
  for index, line in ipairs(lines) do
    local line = pystring.split(line, " -- ")
      if line[2] == nil then
        return convertStringToMatrix(lines[tonumber(index_str)])
      elseif index_str == line[2] then
        return convertStringToMatrix(line[1])
      end
    end
  end

--- We can generate a table will contain paths where instead of instanciating, we'll replicate the full hierarchy
function heroUp(inst_name, matrix_table_attr, rand_value)
  Interface.CreateChild(inst_name)
  local opArgsGb = GroupBuilder()
  opArgsGb:update(Interface.GetOpArg()) -- Pull in existing op args
  --opArgsGb:set("instance.id", IntAttribute(v)) -- Add a custom op arg we can read from the child
  --opArgsGb:set("instance.otherid", IntAttribute(i+1)) -- Add a custom op arg we can read from the child
  opArgsGb:set("type", StringAttribute("group"))
  opArgsGb:set("forceExpand", IntAttribute(1))
  opArgsGb:set("xform.group0.matrix", matrix_table_attr)
  opArgsGb:set("prmanStatements.attributes.user.randomID", rand_value)

  --  Pass the updated Op args to the child location
  -- this only specifies Op args, but no op to run at the child location
  Interface.ReplaceChildTraversalOp("", opArgsGb:build())
  Interface.CopyLocationToChild(inst_name, instance_source)
end


--- Main function (Only runs at root level)
--- This function won't run with newly created locations.
function generateInstanceLocations()
  local lines = getMatrixLinesFromFile()
  local table_len = table.getn(lines)
  local indices = getEvenSpaceIndices(table_len, percentage)
  local index_array = {}
  local matrix_array = {}

  for _, v in ipairs(indices) do
    if lines[v] == nil then
      return
    end
    local line = pystring.split(lines[v], " -- ")
    local inst_number = string.format("%06d", v)
    if line[2] ~= nil then
        inst_number = line[2]
    end
    local matrix_str = line[1]
    local instance_source_name = PathUtils.GetLeafName(instance_source)
    local inst_name = instance_source_name.."_INST_"..tostring(inst_number)
    local full_path = PathUtils.Join(instance_location, inst_name)
    if not isInPruneTable(full_path) then
      local seed_value = ExpressionMath.stablehash(full_path)
      math.randomseed(seed_value)
      local rand_value = IntAttribute(math.random (1, 500))

      --- Matrix ---
      local matrix_table_attr = convertStringToMatrix(matrix_str)

      --- bounds -- Turn out that bounds are calculated automatically by Katana when we set matrix values.
      --local bounds_min, bounds_max = Interface.GetTransformedBoundAttrMinMax(source_bounds, 1, matrix_m44d:toTable())
      --for k,v in pairs(bounds_max) do bounds_min[k+3] = v end
      --local bounds = DoubleAttribute(bounds_min, 2, 3)
      --print(bounds)

      if mode == "Instance Array"  and not isInHeroUpTable(full_path) then
        index_array[#index_array+1] = 0
        for j = 1,16 do
          matrix_array[#matrix_array+1]=tonumber(matrix_table[j])
        end
      elseif mode == "Instantiate" and not isInHeroUpTable(full_path) then
        Interface.CreateChild(inst_name)
        local static_scene_create = OpArgsBuilders.StaticSceneCreate(false)
        static_scene_create:setAttrAtLocation(inst_name, "type", StringAttribute("instance"))
        static_scene_create:setAttrAtLocation(inst_name, "geometry.instanceSource", StringAttribute(instance_source))
        static_scene_create:setAttrAtLocation(inst_name, "xform.group0.matrix", matrix_table_attr)
        static_scene_create:setAttrAtLocation(inst_name, "prmanStatements.attributes.user.randomID", rand_value)

        if source_bounds ~= nil then
          static_scene_create:setAttrAtLocation(inst_name, "bound", source_bounds)
        end
        static_scene_create:setAttrAtLocation(inst_name, "forceExpand", IntAttribute(1))
        Interface.ExecOp("StaticSceneCreate", static_scene_create:build())
      end
    end
  end
  if mode == "Instance Array" then
    Interface.SetAttr('type', StringAttribute('instance array'))
    Interface.SetAttr('geometry.instanceSource', StringAttribute(instance_source))
    Interface.SetAttr('geometry.instanceIndex', IntAttribute(index_array, 1))
    Interface.SetAttr('geometry.instanceMatrix', FloatAttribute(matrix_array, 16))
  end
  -- Always instanciate heroUp loactions
  for _, hero_up_path in ipairs(hero_up_paths) do
    if string.match(hero_up_path, instance_location) then
      heroUp(PathUtils.GetLeafName(hero_up_path), findInstanceMatrix(hero_up_path), IntAttribute(math.random (1, 500)))
    end
  end
end

--- Start Point ---
if Interface.AtRoot() then
  generateInstanceLocations()
else
  root_depth = #pystring.split(instance_location, "/")
  current_depth = #pystring.split(Interface.GetOutputLocationPath(), "/")

  if root_depth == (current_depth-1) then
    local type = Interface.GetOpArg("type")
    Interface.SetAttr("type", type)
    local force_expand = Interface.GetOpArg("forceExpand")
    Interface.SetAttr("forceExpand", force_expand)
    local matrix = Interface.GetOpArg("xform.group0.matrix")
    Interface.SetAttr("xform.group0.matrix", matrix)
    local rand_id = Interface.GetOpArg("prmanStatements.attributes.user.randomID")
    Interface.SetAttr("prmanStatements.attributes.user.randomID", rand_id)
  end
end
