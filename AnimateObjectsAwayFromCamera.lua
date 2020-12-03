
function mdd4ToAttr(matrix)
  return DoubleAttribute(matrix:toTable(), 4, 4)
end

function vectorToAttr(vector)
  return DoubleAttribute(vector:toTable(), 3)
end

function distance2(point_a, point_b)
  local x = (point_a.x - point_b.x)*(point_a.x - point_b.x)
  local y = (point_a.y - point_b.y)*(point_a.y - point_b.y)
  local z = (point_a.z - point_b.z)*(point_a.z - point_b.z)
  return x + y + z
end

function find_furthest_bound_from_cam(bounds, cam_pos)
  local furthest_point = Imath.V3d(0,0,0)
  local furthest_dist = 0
  for _, bound_point in pairs(bounds) do
    bound_point = Imath.V3d(bound_point[1], bound_point[2], bound_point[3])
    local current_dist = distance2(bound_point, cam_pos)
    if current_dist > furthest_dist then
      furthest_dist = current_dist
      furthest_point = bound_point
    end
  end
  return furthest_point
end

-- Extract time attributes from 'timeSlice'
local time_attr = Interface.GetOpArg("system.timeSlice")
local time = time_attr:getChildByName("currentTime"):getValue()
local shutter_open = time_attr:getChildByName("shutterOpen"):getValue()
local shutter_close = time_attr:getChildByName("shutterClose"):getValue()
local sample_times = {shutter_open, 0.0, shutter_close}

-- Read User Parameters
local debug_mode = Interface.GetOpArg("user.debugMode"):getValue()
local obj_speed = Interface.GetOpArg("user.objectSpeed"):getValue()
local camera = Interface.GetOpArg("user.camera"):getValue()

-- Camera
local cam_xform = Interface.GetGlobalXFormGroup(camera)
local cam_matrix_attr = XFormUtils.CalcTransformMatrixAtTimes(cam_xform, sample_times)

-- Threshold
local threshold = Interface.GetOpArg("user.threshold"):getValue()
local threshold_xform = Interface.GetGlobalXFormGroup(threshold)
local threshold_matrix_attr = XFormUtils.CalcTransformMatrixAtTimes(threshold_xform, sample_times)

-- Object
local obj_xform = Interface.GetGlobalXFormGroup(Interface.GetRootLocationPath())
local obj_matrix_attr = XFormUtils.CalcTransformMatrixAtTimes(obj_xform, sample_times)
local obj_matrix_table = obj_matrix_attr:getNearestSample(0.0) -- Objects should be static, better performance by quering it only once
local obj_matrix = Imath.M44d(obj_matrix_table)
local bounds_attr = Interface.GetBoundAttr(Interface.GetRootLocationPath())

local final_obj_pos = {}
-- Iterate through all the time sameples
for index, time_sample in pairs(sample_times) do
  -- Camera
  local cam_matrix_table = cam_matrix_attr:getNearestSample(time_sample)
  local cam_matrix = Imath.M44d(cam_matrix_table)

  -- Threshold
  local threshold_matrix_table = threshold_matrix_attr:getNearestSample(time_sample)
  local threshold_matrix = Imath.M44d(threshold_matrix_table)

  -- This is where the magic happens
  -- https://www.geogebra.org/3d/vtwmpsps
  local t = threshold_matrix:translation()
  local pCam = cam_matrix:translation()
  local A = obj_matrix:translation()
  if bounds_attr ~= nil then
    local bounds = Interface.GetTransformedBoundAttrPoints(bounds_attr, 0, obj_matrix_table)
    A = find_furthest_bound_from_cam(bounds, pCam)
  end
  local vCamToThreshold = t - pCam
  local thresholdPlaneOffset = vCamToThreshold:dot(t)
  local cameraPlaneOffset = vCamToThreshold:dot(pCam)
  local distObjToThreshold = (thresholdPlaneOffset - vCamToThreshold:dot(A))/vCamToThreshold:length2()
  local B = vCamToThreshold * distObjToThreshold + A
  local u = B-A
  local D = A + (u*u*u*u*obj_speed)
  local E = D + (obj_matrix:translation()-A)

  final_obj_pos[time_sample] = (obj_matrix:translation() * obj_matrix:inverse()):toTable()
  if distObjToThreshold > 0 then
    final_obj_pos[time_sample] = (E * obj_matrix:inverse()):toTable()
  end
end

if Interface.AtRoot() then
  if debug_mode == 1 then
    local locator = Interface.GetOpArg("user.locator"):getValue()
    Interface.CopyLocationToChild("loc1", locator)
    Interface.CopyLocationToChild("loc2", locator)
    Interface.CopyLocationToChild("loc3", locator)
    Interface.CopyLocationToChild("loc4", locator)
    Interface.CopyLocationToChild("loc5", locator)
    Interface.CopyLocationToChild("loc6", locator)
    Interface.CopyLocationToChild("loc7", locator)
    Interface.CopyLocationToChild("loc8", locator)
  end
  Interface.SetAttr("xform.group0.translate", DoubleAttribute(final_obj_pos, 3))
else
  local bounds = Interface.GetTransformedBoundAttrPoints(bounds_attr, 0, obj_matrix_table)
  local loc_num = tonumber(string.sub(Interface.GetOutputName(), 4))
  local bound = Imath.V3d(bounds[loc_num][1], bounds[loc_num][2], bounds[loc_num][3])
  local vec = bound * obj_matrix:inverse()
  Interface.SetAttr("xform.group0.translate", DoubleAttribute(vec:toTable(), 3))
end
