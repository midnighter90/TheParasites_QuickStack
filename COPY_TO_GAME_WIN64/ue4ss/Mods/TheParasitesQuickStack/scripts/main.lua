-- The Parasites QuickStack
-- Copyright (c) 2026 The Parasites QuickStack Mod Author(s). All rights reserved.
-- Personal, non-commercial use only. Redistribution, reuploading, reposting,
-- mirroring, repackaging, paid distribution, and commercial use are prohibited
-- without explicit written permission from the copyright holder.
-- Provided as-is with no warranty, no support obligation, and no guarantee of
-- compatibility with future game updates. Use at your own risk.

local MOD_NAME = "TheParasitesQuickStack"
local MOD_VERSION = "1.0.0"

local function detect_mod_root()
    local ok, info = pcall(function()
        if debug and debug.getinfo then
            return debug.getinfo(1, "S")
        end
        return nil
    end)
    if not ok or info == nil or type(info.source) ~= "string" then
        return nil
    end

    local source = info.source
    if string.sub(source, 1, 1) == "@" then
        source = string.sub(source, 2)
    end
    source = string.gsub(source, "\\", "/")

    local root = string.match(source, "^(.*)/[Ss]cripts/[Mm]ain%.lua$")
    return root
end

local MOD_ROOT = detect_mod_root()
local LOG_PATH = MOD_ROOT and (MOD_ROOT .. "/QuickStack.log") or "TheParasitesQuickStack.log"

local MAX_GROUP_DETAILS = 140
local MAX_HOOK_HITS_PER_PATH = 30
local MAX_EMPTY_SLOT_PROBE_MATCHES = 3
local QUICKSTACK_DEBUG_MODE = false
local QUICKSTACK_SINGLE_MOVE_LIMIT = 1
local QUICKSTACK_FULL_MOVE_LIMIT = 60
local QUICKSTACK_FULL_MOVE_DELAY_MS = 250
local QUICKSTACK_SINGLE_MOVE_COOLDOWN_SECONDS = 3
local QUICKSTACK_MIN_INVENTORY_GRID_AREA = 6
local QUICKSTACK_ALLOW_SINGLE_MOVE_SUBMIT = false

local last_single_move_test_time = 0
local last_full_quickstack_time = 0
local full_quickstack_active = false
local full_quickstack_run_id = 0
local full_quickstack_player_mp_addr = nil
local full_quickstack_target_addr = nil
local full_quickstack_target_container_id = nil
local full_quickstack_target_mp_addr = nil

local function now()
    return os.date("%Y-%m-%d %H:%M:%S")
end

local function append_log(message)
    local line = string.format("[%s] [%s] %s", now(), MOD_NAME, tostring(message))
    print(line)
    local ok, file = pcall(io.open, LOG_PATH, "a")
    if ok and file then
        file:write(line .. "\n")
        file:close()
    end
end

local function append_debug(message)
    if QUICKSTACK_DEBUG_MODE then
        append_log(message)
    end
end

local function safe_call(fn, fallback)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return fallback
end

local function ue_type(value)
    return safe_call(function()
        if value and value.type then
            return value:type()
        end
        return type(value)
    end, type(value))
end

local function address_number(value)
    return safe_call(function()
        if value and value.GetAddress then
            return value:GetAddress()
        end
        return nil
    end, nil)
end

local function address_text(value)
    local address = address_number(value)
    if address == nil then
        return "<no address>"
    end
    return string.format("0x%X", address)
end

local function is_null_object(value)
    local address = address_number(value)
    return address ~= nil and address == 0
end

local function array_num(value)
    if not value or ue_type(value) ~= "TArray" then
        return nil
    end

    local num = safe_call(function()
        return value:GetArrayNum()
    end, nil)

    if type(num) ~= "number" or num < 0 or num > 10000 then
        return nil
    end
    return num
end

local function array_max(value)
    if not value or ue_type(value) ~= "TArray" then
        return nil
    end

    local max = safe_call(function()
        return value:GetArrayMax()
    end, nil)

    if type(max) ~= "number" or max < 0 or max > 10000 then
        return nil
    end
    return max
end

local function array_get(value, index)
    local ok, element = pcall(function()
        return value[index]
    end)
    if not ok or element == nil then
        return false, nil
    end

    local unwrapped = safe_call(function()
        if element.get then
            return element:get()
        end
        return nil
    end, nil)
    if unwrapped ~= nil then
        return true, unwrapped
    end

    return true, element
end

local function maybe_ftext(value)
    if ue_type(value) ~= "FText" then
        return nil
    end

    return safe_call(function()
        if value.ToString then
            return value:ToString()
        end
        return nil
    end, nil)
end

local function value_summary(value)
    if value == nil then
        return "nil"
    end

    local lua_type = type(value)
    if lua_type == "string" or lua_type == "number" or lua_type == "boolean" then
        return tostring(value)
    end

    local typ = ue_type(value)
    if typ == "TArray" then
        local num = array_num(value)
        local max = array_max(value)
        local data = safe_call(function()
            if value.GetArrayDataAddress then
                return string.format("0x%X", value:GetArrayDataAddress())
            end
            return "?"
        end, "?")
        return string.format("<TArray len=%s max=%s data=%s>", tostring(num), tostring(max), data)
    end

    if lua_type == "userdata" or lua_type == "table" then
        if is_null_object(value) then
            return "<null " .. tostring(typ) .. ">"
        end

        local text_value = maybe_ftext(value)
        if text_value ~= nil and text_value ~= "" then
            return string.format('<FText "%s" addr=%s>', tostring(text_value), address_text(value))
        end

        return string.format("<%s ue4ss=%s addr=%s>", lua_type, tostring(typ), address_text(value))
    end

    return "<" .. lua_type .. ">"
end

local function unwrap_param(param)
    if param == nil then
        return nil
    end
    local unwrapped = safe_call(function()
        if param.get then
            return param:get()
        end
        return nil
    end, nil)
    if unwrapped ~= nil then
        return unwrapped
    end
    return param
end

local function get_property(object, property_name)
    if object == nil then
        return false, nil
    end

    local ok, value = pcall(function()
        return object:GetPropertyValue(property_name)
    end)
    if ok and value ~= nil then
        return true, value
    end

    local ok_index, value_index = pcall(function()
        return object[property_name]
    end)
    if ok_index and value_index ~= nil then
        return true, value_index
    end

    return false, nil
end

local function non_null_property(object, property_name)
    local found, value = get_property(object, property_name)
    if not found or value == nil or is_null_object(value) then
        return false, nil
    end
    return true, value
end

local function call_method(object, method_name)
    if not object then
        return false, nil
    end
    local ok, method = pcall(function()
        return object[method_name]
    end)
    if not ok or not method then
        return false, nil
    end
    local call_ok, value = pcall(function()
        return method(object)
    end)
    if not call_ok then
        return false, nil
    end
    return true, value
end

local function method_summary(object, method_name)
    local ok, value = call_method(object, method_name)
    if ok then
        return value_summary(value)
    end
    return "<unavailable>"
end

local function bool_method(object, method_name)
    local ok, value = call_method(object, method_name)
    if ok and type(value) == "boolean" then
        return value
    end
    return false
end

local function raw_property_summary(object, property_name)
    local found, value = get_property(object, property_name)
    if found then
        return value_summary(value)
    end
    return "<missing>"
end

local function raw_property_value(object, property_name)
    local found, value = get_property(object, property_name)
    if found then
        return value
    end
    return nil
end

local function number_property(object, property_name)
    local value = raw_property_value(object, property_name)
    if type(value) == "number" then
        return value
    end
    return nil
end

local function bool_property(object, property_name)
    local value = raw_property_value(object, property_name)
    if type(value) == "boolean" then
        return value
    end
    return nil
end

local function fname_key(value)
    return safe_call(function()
        if value and value.GetComparisonIndex then
            return value:GetComparisonIndex()
        end
        return nil
    end, nil)
end

local function outer_object(object)
    return safe_call(function()
        if object and object.GetOuter then
            return object:GetOuter()
        end
        return nil
    end, nil)
end

local function parent_object(object)
    local ok, value = call_method(object, "GetParent")
    if ok then
        return value
    end
    return nil
end

local function class_address(object)
    return safe_call(function()
        local class = object:GetClass()
        if class and class.GetAddress then
            return string.format("0x%X", class:GetAddress())
        end
        return "<no class address>"
    end, "<class unavailable>")
end

local custom_properties_registered = false
local item_key_properties_registered = false
local container_properties_registered = false

local slot_class_path = "/Game/JigSInventory/Jigsaw/Widgets/JSI_Slot.JSI_Slot_C"
local container_class_path = "/Game/JigSInventory/Jigsaw/Widgets/JSIContainer.JSIContainer_C"

local function register_custom_properties_once()
    if custom_properties_registered then
        return
    end

    if not RegisterCustomProperty or not PropertyTypes then
        append_log("Custom property registration unavailable")
        return
    end

    custom_properties_registered = true

    local props = {
        { name = "QS_SlotIndex", type = PropertyTypes.IntProperty, offset = 0x378 },
        { name = "QS_UniqueServerID", type = PropertyTypes.IntProperty, offset = 0x428 },
        { name = "QS_MaxStack", type = PropertyTypes.IntProperty, offset = 0x430 },
        { name = "QS_InfoCount", type = PropertyTypes.IntProperty, offset = 0x458 },
        { name = "QS_ItemCount", type = PropertyTypes.IntProperty, offset = 0x734 },
    }

    append_debug("Registering primitive slot custom properties")
    for _, prop in ipairs(props) do
        local ok, err = pcall(function()
            RegisterCustomProperty({
                ["Name"] = prop.name,
                ["Type"] = prop.type,
                ["BelongsToClass"] = slot_class_path,
                ["OffsetInternal"] = prop.offset,
            })
        end)
        if ok then
            append_debug(string.format("  registered %s at 0x%X", prop.name, prop.offset))
        else
            append_log("  failed " .. prop.name .. ": " .. tostring(err))
        end
    end
end

local function register_item_key_properties_once()
    if item_key_properties_registered then
        return
    end

    if not RegisterCustomProperty or not PropertyTypes then
        append_log("Custom item key property registration unavailable")
        return
    end

    item_key_properties_registered = true

    local props = {
        -- FFItemInfo.ItemID is an FName at slot offset 0x420. Read its raw integer parts
        -- instead of constructing a UE4SS FName object, because FName:ToString crashes this build.
        { name = "QS_ItemIDIndex", type = PropertyTypes.IntProperty, offset = 0x420 },
        { name = "QS_ItemIDNumber", type = PropertyTypes.IntProperty, offset = 0x424 },
    }

    append_debug("Registering raw item key custom properties")
    for _, prop in ipairs(props) do
        local ok, err = pcall(function()
            RegisterCustomProperty({
                ["Name"] = prop.name,
                ["Type"] = prop.type,
                ["BelongsToClass"] = slot_class_path,
                ["OffsetInternal"] = prop.offset,
            })
        end)
        if ok then
            append_debug(string.format("  registered %s at 0x%X", prop.name, prop.offset))
        else
            append_log("  failed " .. prop.name .. ": " .. tostring(err))
        end
    end
end

local function register_container_properties_once()
    if container_properties_registered then
        return
    end

    if not RegisterCustomProperty or not PropertyTypes then
        append_log("Custom container property registration unavailable")
        return
    end

    container_properties_registered = true

    local props = {
        { name = "QS_ContainerID", type = PropertyTypes.IntProperty, offset = 0x314 },
        { name = "QS_ContainerColumns", type = PropertyTypes.IntProperty, offset = 0x31C },
        { name = "QS_ContainerRows", type = PropertyTypes.IntProperty, offset = 0x320 },
        { name = "QS_ContainerParentID", type = PropertyTypes.IntProperty, offset = 0x638 },
    }

    append_debug("Registering primitive container custom properties")
    for _, prop in ipairs(props) do
        local ok, err = pcall(function()
            RegisterCustomProperty({
                ["Name"] = prop.name,
                ["Type"] = prop.type,
                ["BelongsToClass"] = container_class_path,
                ["OffsetInternal"] = prop.offset,
            })
        end)
        if ok then
            append_debug(string.format("  registered %s at 0x%X", prop.name, prop.offset))
        else
            append_log("  failed " .. prop.name .. ": " .. tostring(err))
        end
    end
end

local object_property_names = {
    "ContainerName",
    "ContainerName_8_62BB6E054D192CB29D8DACAC2A554DFD",
    "ContainerID",
    "ParentID",
    "NumberOfColumns",
    "NumberOfRows",
    "WSlots",
    "FixedSlotRef",
    "MouseDownPos",
    "IgnoreMouseLocation",
    "AllowToGround",
    "Jig_SDrag_Oper",
    "JigSDragOperation",
    "DropItemBackGwidget",
    "JigContainer",
    "MainContainer",
    "ContainerUID",
    "IsCloseC",
    "Mother",
    "Vendor",
    "MainCharacter",
    "LootContainer",
    "JigInventory",
    "Inventory",
    "ReplicatedContainers",
    "MainReplicatedContainers",
    "MainContainersIDs",
    "MainUIDs",
    "ContainerPickupsInfo",
    "Pickups",
    "CurrentWeight",
    "Visibility",
    "SlotIndex",
    "IsEmpty",
    "ItemCount",
    "ContainerMother",
    "SlotContainer",
    "WindowContainer",
    "HostedItem",
    "ArrayOfHostingItem",
    "ItemInfo",
    "ItemInfo_25_937A083B4BD3D9B590E0A69C76A4F6F7",
    "ItemID_107_1737366145EEBA44086DB6ACE0E9C90F",
    "UniqueServerID_83_19E6C8FE42B778BAE918F79F1D85AE2A",
    "Count_22_BFF3027A4FD5D984887F16B0B821DF3E",
    "MaxStack_8_4ABF8FB44B55528999A71A9403501AF2",
    "CanStack_5_C8C8CA994713D5823B06DDB479DDA7A1",
    "ItemID",
    "ItemID_2_01CA27D84AF7D1014D9E2E83894C1848",
    "Count",
    "Count_8_DD79AF2A46126A338C8DCCB4616D91CD",
}

local function log_object_details(object, prefix, include_properties)
    if object == nil or is_null_object(object) then
        append_log(prefix .. "<null>")
        return
    end

    append_log(prefix .. "addr=" .. address_text(object) ..
        " type=" .. tostring(ue_type(object)) ..
        " class=" .. class_address(object) ..
        " outer=" .. value_summary(outer_object(object)) ..
        " parent=" .. method_summary(object, "GetParent") ..
        " owner=" .. method_summary(object, "GetOwningPlayer"))

    if include_properties then
        local found_any = false
        for _, property_name in ipairs(object_property_names) do
            local found, value = non_null_property(object, property_name)
            if found then
                found_any = true
                append_log(prefix .. "  " .. property_name .. " = " .. value_summary(value))
            end
        end
        if not found_any then
            append_log(prefix .. "  no non-null known properties exposed")
        end
    end
end

local class_candidates = {
    "DragDropOperation",
    "IngameMenuContainerWidgetBP_C",
    "IngameContainerWidgetBP_C",
    "JSIContainer_C",
    "JSI_Slot_C",
    "ContainerWindowWidget_C",
    "JigContextMenuW_C",
    "JigContextMenuComp_C",
    "JigContextMenuCanvas_C",
    "JigSDragOperation_C",
    "HoverDragOperation_C",
    "DragWidget_C",
    "JigSplitWidget_C",
    "DropItemAmountSelector_C",
    "DropItemBackGwidget_C",
    "BP_JigMPComponentSave_C",
    "BP_NetworkReplication_C",
    "BP_JigMultiplayer_C",
    "BP_Multitasking_Interaction_C",
    "BP_AMain_C",
    "BP_PlayerController_C",
    "BP_MPLootContainer_Car_00_C",
    "BP_MPLootContainer_Car_01_C",
    "BP_MPLootContainer_Car_03_C",
    "BP_LootContainer_Car_C",
    "BP_AmmoBox_C",
    "BP__Box_00_C",
    "BP__LunchBox_C",
    "BP__ToolBox_C",
    "BP_Bag_C",
}

local function find_by_class()
    append_log("Class count probe started")
    for _, class_name in ipairs(class_candidates) do
        local ok, objects = pcall(function()
            return FindAllOf(class_name)
        end)
        if ok and objects then
            append_log("FindAllOf(" .. class_name .. ") -> " .. tostring(#objects))
        end
    end
    append_log("Class count probe finished")
end

local function primitive_slot_value(slot, property_name)
    local ok, value = pcall(function()
        return slot:GetPropertyValue(property_name)
    end)
    if ok then
        return value
    end

    local ok_index, value_index = pcall(function()
        return slot[property_name]
    end)
    if ok_index then
        return value_index
    end

    return nil
end

local function primitive_slot_number(slot, property_name)
    local value = primitive_slot_value(slot, property_name)
    if type(value) == "number" then
        return value
    end
    return nil
end

local function primitive_container_number(container, property_name, fallback_name)
    local value = primitive_slot_value(container, property_name)
    if type(value) == "number" then
        return value
    end
    if fallback_name ~= nil then
        return number_property(container, fallback_name)
    end
    return nil
end

local function container_info_text(info)
    if info == nil then
        return "container=<unmatched>"
    end
    return "containerAddr=" .. tostring(info.addr) ..
        " containerID=" .. tostring(info.container_id) ..
        " parentID=" .. tostring(info.parent_id) ..
        " cols=" .. tostring(info.cols) ..
        " rows=" .. tostring(info.rows) ..
        " mp=" .. tostring(info.mp_addr) ..
        " equipTo=" .. tostring(info.is_equip_to)
end

local function build_container_lookup()
    register_container_properties_once()

    local lookup = {}
    local ok, containers = pcall(function()
        return FindAllOf("JSIContainer_C")
    end)
    if not ok or not containers then
        return lookup, 0
    end

    for index = 1, #containers do
        local container = containers[index]
        local addr = address_text(container)
        lookup[addr] = {
            object = container,
            addr = addr,
            container_id = primitive_container_number(container, "QS_ContainerID", "ContainerID"),
            parent_id = primitive_container_number(container, "QS_ContainerParentID", "ParentID"),
            cols = primitive_container_number(container, "QS_ContainerColumns", "NumberOfColumns"),
            rows = primitive_container_number(container, "QS_ContainerRows", "NumberOfRows"),
            mp = raw_property_value(container, "JigMultiplayerComp"),
            mp_addr = address_text(raw_property_value(container, "JigMultiplayerComp")),
            is_equip_to = bool_method(container, "IsEquipTo?"),
            is_slot_container = bool_method(container, "IsSlotContainer"),
        }
    end

    return lookup, #containers
end

local function raw_slot_snapshot(slot)
    local item_id_index = primitive_slot_number(slot, "QS_ItemIDIndex")
    local item_id_number = primitive_slot_number(slot, "QS_ItemIDNumber")
    local item_key = nil
    if item_id_index and item_id_index ~= 0 then
        item_key = tostring(item_id_index) .. ":" .. tostring(item_id_number or 0)
    end

    local unique_id = primitive_slot_number(slot, "QS_UniqueServerID")
    local item_count = primitive_slot_number(slot, "QS_ItemCount")
    local info_count = primitive_slot_number(slot, "QS_InfoCount")
    local max_stack = primitive_slot_number(slot, "QS_MaxStack")

    return {
        slot_index = primitive_slot_number(slot, "QS_SlotIndex"),
        item_id_index = item_id_index,
        item_id_number = item_id_number,
        item_key = item_key,
        unique_id = unique_id,
        info_count = info_count,
        item_count = item_count,
        max_stack = max_stack,
        has_real_uid = unique_id ~= nil and unique_id ~= 0,
        has_count = item_count ~= nil and item_count > 0,
    }
end

local function probe_slot_offsets()
    append_log("")
    append_log("============================================================")
    append_log("Primitive slot offset probe started. Int-only stage; no ItemInfo or FName reads.")
    append_log("============================================================")

    register_custom_properties_once()

    local ok, slots = pcall(function()
        return FindAllOf("JSI_Slot_C")
    end)
    if not ok or not slots then
        append_log("FindAllOf(JSI_Slot_C) failed")
        append_log("Primitive slot offset probe finished")
        return
    end

    append_log("FindAllOf(JSI_Slot_C) -> " .. tostring(#slots))

    local logged = 0
    local nonzero_uid = 0
    local nonzero_count = 0

    for index = 1, #slots do
        local slot = slots[index]
        local slot_index = primitive_slot_number(slot, "QS_SlotIndex")
        local unique_id = primitive_slot_number(slot, "QS_UniqueServerID")
        local info_count = primitive_slot_number(slot, "QS_InfoCount")
        local item_count = primitive_slot_number(slot, "QS_ItemCount")
        local max_stack = primitive_slot_number(slot, "QS_MaxStack")

        if unique_id and unique_id ~= 0 then
            nonzero_uid = nonzero_uid + 1
        end
        if (info_count and info_count ~= 0) or (item_count and item_count ~= 0) then
            nonzero_count = nonzero_count + 1
        end

        if logged < 120 and (
            (unique_id and unique_id ~= 0) or
            (info_count and info_count ~= 0) or
            (item_count and item_count ~= 0)
        ) then
            logged = logged + 1
            append_log("  [slot offset #" .. tostring(index) .. "] " ..
                "addr=" .. address_text(slot) ..
                " slotIndex=" .. tostring(slot_index) ..
                " uid=" .. tostring(unique_id) ..
                " infoCount=" .. tostring(info_count) ..
                " itemCount=" .. tostring(item_count) ..
                " maxStack=" .. tostring(max_stack))
        end
    end

    append_log("Primitive slot offset summary: nonzeroUid=" .. tostring(nonzero_uid) ..
        " nonzeroCount=" .. tostring(nonzero_count) ..
        " logged=" .. tostring(logged))
    append_log("Primitive slot offset probe finished")
end

local function probe_slot_item_keys()
    append_log("")
    append_log("============================================================")
    append_log("Raw item key probe started. Reads FName bytes as integers; no FName object construction.")
    append_log("============================================================")

    register_custom_properties_once()
    register_item_key_properties_once()

    local ok, slots = pcall(function()
        return FindAllOf("JSI_Slot_C")
    end)
    if not ok or not slots then
        append_log("FindAllOf(JSI_Slot_C) failed")
        append_log("Raw item key probe finished")
        return
    end

    append_log("FindAllOf(JSI_Slot_C) -> " .. tostring(#slots))

    local logged = 0
    local nonempty = 0
    local nonzero_item_key = 0
    local item_groups = {}

    for index = 1, #slots do
        local slot = slots[index]
        local slot_index = primitive_slot_number(slot, "QS_SlotIndex")
        local unique_id = primitive_slot_number(slot, "QS_UniqueServerID")
        local info_count = primitive_slot_number(slot, "QS_InfoCount")
        local item_count = primitive_slot_number(slot, "QS_ItemCount")
        local max_stack = primitive_slot_number(slot, "QS_MaxStack")

        if (unique_id and unique_id ~= 0) or (item_count and item_count ~= 0) then
            nonempty = nonempty + 1

            local item_id_index = primitive_slot_number(slot, "QS_ItemIDIndex")
            local item_id_number = primitive_slot_number(slot, "QS_ItemIDNumber")
            if item_id_index and item_id_index ~= 0 then
                nonzero_item_key = nonzero_item_key + 1
                local key = tostring(item_id_index) .. ":" .. tostring(item_id_number or 0)
                item_groups[key] = (item_groups[key] or 0) + 1
            end

            if logged < 120 then
                logged = logged + 1
                append_log("  [item key #" .. tostring(index) .. "] " ..
                    "addr=" .. address_text(slot) ..
                    " slotIndex=" .. tostring(slot_index) ..
                    " itemIdIndex=" .. tostring(item_id_index) ..
                    " itemIdNumber=" .. tostring(item_id_number) ..
                    " uid=" .. tostring(unique_id) ..
                    " infoCount=" .. tostring(info_count) ..
                    " itemCount=" .. tostring(item_count) ..
                    " maxStack=" .. tostring(max_stack))
            end
        end
    end

    local group_rows = {}
    for key, count in pairs(item_groups) do
        table.insert(group_rows, { key = key, count = count })
    end
    table.sort(group_rows, function(a, b)
        if a.count == b.count then
            return a.key < b.key
        end
        return a.count > b.count
    end)

    append_log("Raw item key summary: nonemptySlots=" .. tostring(nonempty) ..
        " nonzeroItemKeys=" .. tostring(nonzero_item_key) ..
        " distinctItemKeys=" .. tostring(#group_rows) ..
        " logged=" .. tostring(logged))

    for i = 1, math.min(#group_rows, 40) do
        append_log("  itemKeyGroup[" .. tostring(i) .. "] key=" .. group_rows[i].key ..
            " slots=" .. tostring(group_rows[i].count))
    end

    append_log("Raw item key probe finished")
end

local function collect_container_slot_items_raw(container)
    local found, slots = non_null_property(container, "WSlots")
    if not found then
        slots = nil
    end
    local len = array_num(slots)
    local items = {}
    local uid_items = {}
    local item_groups = {}
    local empty_count = 0

    if not len then
        return items, uid_items, item_groups, empty_count, 0
    end

    for index = 1, len do
        local ok, slot = array_get(slots, index)
        if ok and slot ~= nil and not is_null_object(slot) then
            local snapshot = raw_slot_snapshot(slot)
            if snapshot.item_key ~= nil and snapshot.has_count then
                local row = { slot = slot, snapshot = snapshot, array_index = index }
                table.insert(items, row)
                item_groups[snapshot.item_key] = (item_groups[snapshot.item_key] or 0) + 1
                if snapshot.has_real_uid then
                    table.insert(uid_items, row)
                end
            else
                empty_count = empty_count + 1
            end
        end
    end

    return items, uid_items, item_groups, empty_count, len
end

local function probe_raw_container_candidates()
    append_log("")
    append_log("============================================================")
    append_log("Raw container candidate probe started. No ItemInfo traversal and no item movement.")
    append_log("============================================================")

    register_custom_properties_once()
    register_item_key_properties_once()

    local ok, containers = pcall(function()
        return FindAllOf("JSIContainer_C")
    end)
    if not ok or not containers then
        append_log("FindAllOf(JSIContainer_C) failed")
        append_log("Raw container candidate probe finished")
        return
    end

    append_log("FindAllOf(JSIContainer_C) -> " .. tostring(#containers))

    local candidates = {}
    local visible_count = 0

    for index = 1, #containers do
        local container = containers[index]
        local found, slots = non_null_property(container, "WSlots")
        if not found then
            slots = nil
        end
        local slot_count = array_num(slots)
        if slot_count and slot_count > 0 then
            local visible = bool_method(container, "IsVisible")
            local focus_desc = bool_method(container, "HasFocusedDescendants")
            local focus = bool_method(container, "HasAnyUserFocus")
            local hovered = bool_method(container, "IsHovered")
            local visibility_prop = raw_property_summary(container, "Visibility")
            local owner = safe_call(function()
                local owner_ok, owner_value = call_method(container, "GetOwningPlayer")
                if owner_ok then
                    return owner_value
                end
                return nil
            end, nil)

            local has_owner = owner ~= nil and not is_null_object(owner)
            local activeish = visible or focus_desc or focus or hovered or visibility_prop == "0" or has_owner
            if activeish then
                visible_count = visible_count + 1
            end

            local items, uid_items, item_groups, empty_count = collect_container_slot_items_raw(container)
            table.insert(candidates, {
                source_index = index,
                container = container,
                slot_count = slot_count,
                item_count = #items,
                uid_item_count = #uid_items,
                empty_count = empty_count,
                item_groups = item_groups,
                items = items,
                activeish = activeish,
                visible = visible,
                focus_desc = focus_desc,
                focus = focus,
                hovered = hovered,
                visibility = visibility_prop,
                owner = owner,
                outer = outer_object(container),
                parent = parent_object(container),
                container_id = number_property(container, "ContainerID"),
                parent_id = number_property(container, "ParentID"),
                cols = number_property(container, "NumberOfColumns"),
                rows = number_property(container, "NumberOfRows"),
            })
        end
    end

    table.sort(candidates, function(a, b)
        local score_a = (a.item_count * 1000000) + (a.uid_item_count * 1000) + (a.activeish and 100 or 0) + a.slot_count
        local score_b = (b.item_count * 1000000) + (b.uid_item_count * 1000) + (b.activeish and 100 or 0) + b.slot_count
        if score_a == score_b then
            return tostring(a.container_id) < tostring(b.container_id)
        end
        return score_a > score_b
    end)

    append_log("Raw container candidates considered: activeOrOwned=" .. tostring(visible_count) ..
        " candidates=" .. tostring(#candidates))

    for index = 1, math.min(#candidates, 30) do
        local candidate = candidates[index]
        append_log("  [raw container #" .. tostring(index) .. "] " ..
            "sourceIndex=" .. tostring(candidate.source_index) ..
            " addr=" .. address_text(candidate.container) ..
            " slots=" .. tostring(candidate.slot_count) ..
            " rawItems=" .. tostring(candidate.item_count) ..
            " uidItems=" .. tostring(candidate.uid_item_count) ..
            " empty=" .. tostring(candidate.empty_count) ..
            " cols=" .. tostring(candidate.cols) ..
            " rows=" .. tostring(candidate.rows) ..
            " containerID=" .. tostring(candidate.container_id) ..
            " parentID=" .. tostring(candidate.parent_id) ..
            " activeish=" .. tostring(candidate.activeish) ..
            " visible=" .. tostring(candidate.visible) ..
            " focusDesc=" .. tostring(candidate.focus_desc) ..
            " focus=" .. tostring(candidate.focus) ..
            " hovered=" .. tostring(candidate.hovered) ..
            " visibility=" .. tostring(candidate.visibility) ..
            " owner=" .. address_text(candidate.owner) ..
            " outer=" .. address_text(candidate.outer) ..
            " parent=" .. address_text(candidate.parent))

        local group_rows = {}
        for key, count in pairs(candidate.item_groups) do
            table.insert(group_rows, { key = key, count = count })
        end
        table.sort(group_rows, function(a, b)
            if a.count == b.count then
                return a.key < b.key
            end
            return a.count > b.count
        end)

        for group_index = 1, math.min(#group_rows, 12) do
            append_log("    keyGroup[" .. tostring(group_index) .. "] key=" .. group_rows[group_index].key ..
                " slots=" .. tostring(group_rows[group_index].count))
        end

        for item_index = 1, math.min(#candidate.items, 8) do
            local item = candidate.items[item_index]
            local snapshot = item.snapshot
            append_log("    item[" .. tostring(item_index) .. "] " ..
                "arrayIndex=" .. tostring(item.array_index) ..
                " slotAddr=" .. address_text(item.slot) ..
                " slotIndex=" .. tostring(snapshot.slot_index) ..
                " key=" .. tostring(snapshot.item_key) ..
                " uid=" .. tostring(snapshot.unique_id) ..
                " itemCount=" .. tostring(snapshot.item_count) ..
                " maxStack=" .. tostring(snapshot.max_stack))
        end
    end

    append_log("Raw container candidate probe finished")
end

local function make_group_key(value)
    if value == nil or value == "" then
        return "<none>"
    end
    return tostring(value)
end

local function increment_group(groups, key)
    key = make_group_key(key)
    groups[key] = (groups[key] or 0) + 1
end

local function sorted_group_lines(groups)
    local rows = {}
    for key, count in pairs(groups) do
        table.insert(rows, { key = key, count = count })
    end
    table.sort(rows, function(a, b)
        if a.count == b.count then
            return a.key < b.key
        end
        return a.count > b.count
    end)
    return rows
end

local function log_groups(title, groups)
    append_log(title)
    local rows = sorted_group_lines(groups)
    if #rows == 0 then
        append_log("  <empty>")
        return
    end

    for index = 1, math.min(#rows, 25) do
        append_log(string.format("  %s -> %d", rows[index].key, rows[index].count))
    end
end

local function sorted_slot_group_rows(groups)
    local rows = {}
    for _, group in pairs(groups) do
        table.insert(rows, group)
    end
    table.sort(rows, function(a, b)
        if a.item_count == b.item_count then
            if a.uid_count == b.uid_count then
                if a.total == b.total then
                    return a.key < b.key
                end
                return a.total > b.total
            end
            return a.uid_count > b.uid_count
        end
        return a.item_count > b.item_count
    end)
    return rows
end

local function probe_raw_slot_groups()
    append_log("")
    append_log("============================================================")
    append_log("Raw slot group probe started. Groups real item slots by widget outer/parent.")
    append_log("============================================================")

    register_custom_properties_once()
    register_item_key_properties_once()

    local ok, slots = pcall(function()
        return FindAllOf("JSI_Slot_C")
    end)
    if not ok or not slots then
        append_log("FindAllOf(JSI_Slot_C) failed")
        append_log("Raw slot group probe finished")
        return
    end

    local groups = {}
    local item_slots = 0
    local uid_slots = 0

    append_log("FindAllOf(JSI_Slot_C) -> " .. tostring(#slots))

    for index = 1, #slots do
        local slot = slots[index]
        local snapshot = raw_slot_snapshot(slot)
        local outer = outer_object(slot)
        local parent = parent_object(slot)
        local outer_addr = address_text(outer)
        local parent_addr = address_text(parent)
        local key = "outer=" .. outer_addr .. " parent=" .. parent_addr

        if not groups[key] then
            groups[key] = {
                key = key,
                total = 0,
                item_count = 0,
                uid_count = 0,
                visible_count = 0,
                hovered_count = 0,
                focus_count = 0,
                key_groups = {},
                samples = {},
            }
        end

        local group = groups[key]
        group.total = group.total + 1
        if bool_method(slot, "IsVisible") then
            group.visible_count = group.visible_count + 1
        end
        if bool_method(slot, "IsHovered") then
            group.hovered_count = group.hovered_count + 1
        end
        if bool_method(slot, "HasAnyUserFocus") or bool_method(slot, "HasFocusedDescendants") then
            group.focus_count = group.focus_count + 1
        end

        if snapshot.item_key ~= nil and snapshot.has_count then
            item_slots = item_slots + 1
            group.item_count = group.item_count + 1
            group.key_groups[snapshot.item_key] = (group.key_groups[snapshot.item_key] or 0) + 1
            if snapshot.has_real_uid then
                uid_slots = uid_slots + 1
                group.uid_count = group.uid_count + 1
            end
            if #group.samples < 8 then
                table.insert(group.samples, {
                    index = index,
                    slot = slot,
                    snapshot = snapshot,
                })
            end
        end
    end

    local rows = sorted_slot_group_rows(groups)
    append_log("Raw slot group summary: groups=" .. tostring(#rows) ..
        " itemSlots=" .. tostring(item_slots) ..
        " uidSlots=" .. tostring(uid_slots))

    for group_index = 1, math.min(#rows, 40) do
        local group = rows[group_index]
        append_log("  [slot group #" .. tostring(group_index) .. "] " ..
            group.key ..
            " total=" .. tostring(group.total) ..
            " itemSlots=" .. tostring(group.item_count) ..
            " uidSlots=" .. tostring(group.uid_count) ..
            " visibleSlots=" .. tostring(group.visible_count) ..
            " hoveredSlots=" .. tostring(group.hovered_count) ..
            " focusSlots=" .. tostring(group.focus_count))

        local key_rows = sorted_group_lines(group.key_groups)
        for key_index = 1, math.min(#key_rows, 8) do
            append_log("    keyGroup[" .. tostring(key_index) .. "] key=" .. key_rows[key_index].key ..
                " slots=" .. tostring(key_rows[key_index].count))
        end

        for sample_index = 1, math.min(#group.samples, 6) do
            local sample = group.samples[sample_index]
            local snapshot = sample.snapshot
            append_log("    sample[" .. tostring(sample_index) .. "] " ..
                "globalIndex=" .. tostring(sample.index) ..
                " slotAddr=" .. address_text(sample.slot) ..
                " slotIndex=" .. tostring(snapshot.slot_index) ..
                " key=" .. tostring(snapshot.item_key) ..
                " uid=" .. tostring(snapshot.unique_id) ..
                " itemCount=" .. tostring(snapshot.item_count) ..
                " maxStack=" .. tostring(snapshot.max_stack))
        end
    end

    append_log("Raw slot group probe finished")
end

local note_container_candidate
local finalize_group_container_info
local merged_slot_group_rows_by_container

local function collect_raw_slot_group_rows()
    register_custom_properties_once()
    register_item_key_properties_once()
    local container_lookup, container_count = build_container_lookup()

    local ok, slots = pcall(function()
        return FindAllOf("JSI_Slot_C")
    end)
    if not ok or not slots then
        return {}, 0, 0, 0, container_count
    end

    local groups = {}
    local item_slots = 0
    local uid_slots = 0

    for index = 1, #slots do
        local slot = slots[index]
        local snapshot = raw_slot_snapshot(slot)
        local outer = outer_object(slot)
        local parent = parent_object(slot)
        local outer_addr = address_text(outer)
        local parent_addr = address_text(parent)
        local key = "outer=" .. outer_addr .. " parent=" .. parent_addr

        if not groups[key] then
            groups[key] = {
                key = key,
                outer_addr = outer_addr,
                parent_addr = parent_addr,
                container_info = container_lookup[outer_addr] or container_lookup[parent_addr],
                total = 0,
                item_count = 0,
                uid_count = 0,
                visible_count = 0,
                hovered_count = 0,
                focus_count = 0,
                key_groups = {},
                items = {},
            }
        end

        local group = groups[key]
        group.total = group.total + 1
        note_container_candidate(group, raw_property_value(slot, "SlotContainer"), container_lookup)
        note_container_candidate(group, raw_property_value(slot, "ContainerMother"), container_lookup)

        local slot_visible = bool_method(slot, "IsVisible")
        if slot_visible then
            group.visible_count = group.visible_count + 1
        end
        if bool_method(slot, "IsHovered") then
            group.hovered_count = group.hovered_count + 1
        end
        if bool_method(slot, "HasAnyUserFocus") or bool_method(slot, "HasFocusedDescendants") then
            group.focus_count = group.focus_count + 1
        end

        if snapshot.item_key ~= nil and snapshot.has_count then
            item_slots = item_slots + 1
            group.item_count = group.item_count + 1
            group.key_groups[snapshot.item_key] = (group.key_groups[snapshot.item_key] or 0) + 1
            if snapshot.has_real_uid then
                uid_slots = uid_slots + 1
                group.uid_count = group.uid_count + 1
            end
            table.insert(group.items, {
                index = index,
                slot = slot,
                snapshot = snapshot,
                visible = slot_visible,
            })
        end
    end

    finalize_group_container_info(groups, container_lookup)
    local rows = merged_slot_group_rows_by_container(groups)
    return rows, item_slots, uid_slots, #slots, container_count
end

local function sorted_key_rows_from_totals(key_totals)
    local rows = {}
    for key, row in pairs(key_totals) do
        table.insert(rows, {
            key = key,
            slots = row.slots,
            count = row.count,
            sources = row.sources,
            details = row.details,
        })
    end
    table.sort(rows, function(a, b)
        if a.count == b.count then
            if a.slots == b.slots then
                return a.key < b.key
            end
            return a.slots > b.slots
        end
        return a.count > b.count
    end)
    return rows
end

local function group_grid_capacity(group)
    local info = group and group.container_info or nil
    if info ~= nil and type(info.cols) == "number" and type(info.rows) == "number" then
        local capacity = info.cols * info.rows
        if capacity > 0 then
            return capacity
        end
    end
    return nil
end

local function is_regular_grid_slot(group, item)
    if group == nil or item == nil or item.visible ~= true then
        return false
    end

    local snapshot = item.snapshot
    if snapshot == nil or type(snapshot.slot_index) ~= "number" then
        return false
    end

    local capacity = group_grid_capacity(group)
    if capacity == nil then
        return false
    end

    return snapshot.slot_index >= 0 and snapshot.slot_index < capacity
end

local function is_quickstack_source_item(group, item)
    local snapshot = item and item.snapshot or nil
    return is_regular_grid_slot(group, item) and
        snapshot.item_key ~= nil and
        snapshot.has_real_uid == true
end

local function is_quickstack_receiver_item(group, item, item_key)
    local snapshot = item and item.snapshot or nil
    return is_regular_grid_slot(group, item) and
        snapshot.item_key == item_key and
        snapshot.has_real_uid == true
end

local function choose_target_receiver(target, item_key)
    local fallback = nil
    for _, item in ipairs(target.items) do
        local snapshot = item.snapshot
        if is_quickstack_receiver_item(target, item, item_key) then
            if fallback == nil then
                fallback = item
            end

            local max_stack = snapshot.max_stack or 0
            local count = snapshot.item_count or snapshot.info_count or 0
            if max_stack > 0 and count < max_stack then
                return item
            end
        end
    end
    return fallback
end

local function group_contains_uid(group, uid)
    if group == nil or uid == nil or uid == 0 then
        return false
    end

    for _, item in ipairs(group.items or {}) do
        local snapshot = item.snapshot
        if snapshot ~= nil and snapshot.unique_id == uid then
            return true
        end
    end

    return false
end

function note_container_candidate(group, container, container_lookup)
    if container == nil or is_null_object(container) then
        return
    end

    local addr = address_text(container)
    if group.container_counts == nil then
        group.container_counts = {}
    end
    group.container_counts[addr] = (group.container_counts[addr] or 0) + 1

    if group.container_info == nil and container_lookup[addr] ~= nil then
        group.container_info = container_lookup[addr]
    end
end

function finalize_group_container_info(groups, container_lookup)
    for _, group in pairs(groups) do
        if group.container_info == nil and group.container_counts ~= nil then
            local best_addr = nil
            local best_count = -1
            for addr, count in pairs(group.container_counts) do
                if container_lookup[addr] ~= nil and count > best_count then
                    best_addr = addr
                    best_count = count
                end
            end

            if best_addr ~= nil then
                group.container_info = container_lookup[best_addr]
            end
        end
    end
end

local function merge_group_values(target, source)
    target.total = (target.total or 0) + (source.total or 0)
    target.item_count = (target.item_count or 0) + (source.item_count or 0)
    target.uid_count = (target.uid_count or 0) + (source.uid_count or 0)
    target.visible_count = (target.visible_count or 0) + (source.visible_count or 0)
    target.hovered_count = (target.hovered_count or 0) + (source.hovered_count or 0)
    target.focus_count = (target.focus_count or 0) + (source.focus_count or 0)

    for key, count in pairs(source.key_groups or {}) do
        target.key_groups[key] = (target.key_groups[key] or 0) + count
    end

    for _, item in ipairs(source.items or {}) do
        table.insert(target.items, item)
    end
end

function merged_slot_group_rows_by_container(groups)
    local merged = {}

    for _, group in pairs(groups) do
        local merge_key = group.key
        if group.container_info ~= nil and group.container_info.addr ~= nil then
            merge_key = "container=" .. tostring(group.container_info.addr)
        end

        if merged[merge_key] == nil then
            merged[merge_key] = {
                key = merge_key,
                outer_addr = group.outer_addr,
                parent_addr = group.parent_addr,
                container_info = group.container_info,
                total = 0,
                item_count = 0,
                uid_count = 0,
                visible_count = 0,
                hovered_count = 0,
                focus_count = 0,
                key_groups = {},
                items = {},
                merged_parts = 0,
            }
        elseif merged[merge_key].container_info == nil then
            merged[merge_key].container_info = group.container_info
        end

        merged[merge_key].merged_parts = merged[merge_key].merged_parts + 1
        merge_group_values(merged[merge_key], group)
    end

    return sorted_slot_group_rows(merged)
end

local function group_capacity_score(group)
    if group == nil then
        return 0
    end

    local capacity = group_grid_capacity(group)
    if capacity ~= nil then
        return capacity
    end

    return group.total or 0
end

local function is_inventory_like_group(group)
    if group == nil then
        return false
    end

    -- Equipment slots and weapon attachment containers can have multiple slots, but they are tiny fixed layouts.
    -- Clothing/backpack inventories are real grids, so require enough visible/capacity slots while allowing any cols/rows.
    if group.visible_count < QUICKSTACK_MIN_INVENTORY_GRID_AREA then
        return false
    end

    return group_capacity_score(group) >= QUICKSTACK_MIN_INVENTORY_GRID_AREA
end

local function group_mp_addr(group)
    if group == nil or group.container_info == nil then
        return nil
    end
    return group.container_info.mp_addr
end

local function is_valid_mp_addr(mp_addr)
    return mp_addr ~= nil and mp_addr ~= "" and mp_addr ~= "<no address>" and mp_addr ~= "0x0"
end

local function collect_visible_inventory_groups(rows)
    local visible_groups = {}
    local excluded_equipment_like = 0
    for _, group in ipairs(rows) do
        if group.visible_count > 0 then
            if is_inventory_like_group(group) then
                table.insert(visible_groups, group)
            else
                excluded_equipment_like = excluded_equipment_like + 1
            end
        end
    end

    table.sort(visible_groups, function(a, b)
        if a.item_count == b.item_count then
            return a.visible_count > b.visible_count
        end
        return a.item_count > b.item_count
    end)

    return visible_groups, excluded_equipment_like
end

local function count_matching_source_slots(target, source)
    if target == nil or source == nil then
        return 0, 0
    end

    local matched_slots = 0
    local matched_count = 0
    for _, item in ipairs(source.items) do
        local snapshot = item.snapshot
        if is_quickstack_source_item(source, item) and choose_target_receiver(target, snapshot.item_key) ~= nil then
            matched_slots = matched_slots + 1
            matched_count = matched_count + (snapshot.item_count or snapshot.info_count or 0)
        end
    end
    return matched_slots, matched_count
end

local function choose_direction_by_matching(visible_groups)
    local candidates = {}
    for target_index, target in ipairs(visible_groups) do
        if target.item_count > 0 and target.uid_count > 0 then
            local matched_slots = 0
            local matched_count = 0
            local source_groups = {}
            for source_index, source in ipairs(visible_groups) do
                if source_index ~= target_index and source.item_count > 0 and source.uid_count > 0 then
                    local source_slots, source_count = count_matching_source_slots(target, source)
                    if source_slots > 0 then
                        matched_slots = matched_slots + source_slots
                        matched_count = matched_count + source_count
                        table.insert(source_groups, source)
                    end
                end
            end

            if matched_slots > 0 then
                table.insert(candidates, {
                    target = target,
                    source_groups = source_groups,
                    matched_slots = matched_slots,
                    matched_count = matched_count,
                })
            end
        end
    end

    table.sort(candidates, function(a, b)
        local capacity_a = group_capacity_score(a.target)
        local capacity_b = group_capacity_score(b.target)
        if capacity_a == capacity_b then
            if a.target.item_count == b.target.item_count then
                return a.matched_slots > b.matched_slots
            end
            return a.target.item_count > b.target.item_count
        end
        return capacity_a > capacity_b
    end)

    if #candidates == 0 then
        return nil, {}, "no matching target/source pair found"
    end

    return candidates[1].target, candidates[1].source_groups, nil
end

local function choose_player_mp_from_all_rows(visible_groups, all_rows)
    if all_rows == nil then
        return nil, false
    end

    local visible_mp_addrs = {}
    for _, group in ipairs(visible_groups) do
        local mp_addr = group_mp_addr(group)
        if is_valid_mp_addr(mp_addr) then
            visible_mp_addrs[mp_addr] = true
        end
    end

    local counts = {}
    for _, group in ipairs(all_rows) do
        local mp_addr = group_mp_addr(group)
        if visible_mp_addrs[mp_addr] == true then
            if counts[mp_addr] == nil then
                counts[mp_addr] = { groups = 0, slots = 0, items = 0 }
            end
            counts[mp_addr].groups = counts[mp_addr].groups + 1
            counts[mp_addr].slots = counts[mp_addr].slots + (group.total or 0)
            counts[mp_addr].items = counts[mp_addr].items + (group.item_count or 0)
        end
    end

    local best_addr = nil
    local best = nil
    local tied = false
    for mp_addr, count in pairs(counts) do
        if best == nil or
            count.groups > best.groups or
            (count.groups == best.groups and count.slots > best.slots) or
            (count.groups == best.groups and count.slots == best.slots and count.items > best.items) then
            best_addr = mp_addr
            best = count
            tied = false
        elseif best ~= nil and count.groups == best.groups and count.slots == best.slots and count.items == best.items then
            tied = true
        end
    end

    return best_addr, tied
end

local function choose_quickstack_direction(visible_groups, all_rows)
    local mp_counts = {}
    for _, group in ipairs(visible_groups) do
        local mp_addr = group_mp_addr(group)
        if is_valid_mp_addr(mp_addr) then
            mp_counts[mp_addr] = (mp_counts[mp_addr] or 0) + 1
        end
    end

    local player_mp_addr = nil
    local player_mp_count = 0
    local tied = false
    for mp_addr, count in pairs(mp_counts) do
        if count > player_mp_count then
            player_mp_addr = mp_addr
            player_mp_count = count
            tied = false
        elseif count == player_mp_count then
            tied = true
        end
    end

    local global_player_mp_addr, global_tied = choose_player_mp_from_all_rows(visible_groups, all_rows)
    if (not is_valid_mp_addr(player_mp_addr) or tied or player_mp_count <= 1) and
        is_valid_mp_addr(global_player_mp_addr) and not global_tied then
        player_mp_addr = global_player_mp_addr
        tied = false
    end

    if not is_valid_mp_addr(player_mp_addr) then
        local fallback_target, fallback_sources, fallback_reason = choose_direction_by_matching(visible_groups)
        if fallback_target ~= nil then
            return fallback_target, fallback_sources, nil, { fallback_target }, nil
        end
        return nil, {}, nil, {}, "no valid JigMultiplayer component addresses found; " .. tostring(fallback_reason)
    end

    if tied then
        local fallback_target, fallback_sources, fallback_reason = choose_direction_by_matching(visible_groups)
        if fallback_target ~= nil then
            return fallback_target, fallback_sources, player_mp_addr, { fallback_target }, nil
        end
        return nil, {}, player_mp_addr, {}, "ambiguous player/container direction because JigMultiplayer component counts are tied; " .. tostring(fallback_reason)
    end

    local source_groups = {}
    local target_groups = {}
    for _, group in ipairs(visible_groups) do
        local mp_addr = group_mp_addr(group)
        if mp_addr == player_mp_addr then
            table.insert(source_groups, group)
        elseif is_valid_mp_addr(mp_addr) then
            table.insert(target_groups, group)
        end
    end

    table.sort(target_groups, function(a, b)
        if a.item_count == b.item_count then
            return a.visible_count > b.visible_count
        end
        return a.item_count > b.item_count
    end)

    if #source_groups == 0 then
        return nil, {}, player_mp_addr, target_groups, "no player inventory source groups found"
    end

    if #target_groups == 0 then
        local fallback_target, fallback_sources, fallback_reason = choose_direction_by_matching(visible_groups)
        if fallback_target ~= nil then
            return fallback_target, fallback_sources, player_mp_addr, { fallback_target }, nil
        end
        return nil, source_groups, player_mp_addr, target_groups, "no opened non-player container group found; " .. tostring(fallback_reason)
    end

    return target_groups[1], source_groups, player_mp_addr, target_groups, nil
end

local function pack_values(...)
    return { n = select("#", ...), ... }
end

local function capture_results(fn)
    local packed = pack_values(pcall(fn))
    if not packed[1] then
        return false, packed[2]
    end

    local results = { n = packed.n - 1 }
    for index = 2, packed.n do
        results[index - 1] = packed[index]
    end
    return true, results
end

local function log_call_results(prefix, ok, result)
    if not ok then
        append_log(prefix .. " error=" .. tostring(result))
        return false
    end

    append_log(prefix .. " ok returnCount=" .. tostring(result.n))
    for index = 1, math.min(result.n or 0, 8) do
        append_log(prefix .. " return[" .. tostring(index) .. "]=" .. value_summary(unwrap_param(result[index])))
    end

    return result.n ~= nil and result.n > 0
end

local function lua_table_summary(value)
    if type(value) ~= "table" then
        return value_summary(value)
    end

    local parts = {}
    local count = 0
    local ok = pcall(function()
        for key, field_value in pairs(value) do
            count = count + 1
            if #parts < 8 then
                table.insert(parts, tostring(key) .. "=" .. value_summary(unwrap_param(field_value)))
            end
        end
    end)

    if not ok then
        return "<table unreadable>"
    end

    if count == 0 then
        return "{}"
    end

    if count > #parts then
        table.insert(parts, "...")
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function read_jsi_empty_spot(comp, target_container, source_slot)
    if comp == nil or is_null_object(comp) then
        return false, nil, nil, "missing comp", nil
    end
    if target_container == nil or is_null_object(target_container) then
        return false, nil, nil, "missing target container", nil
    end
    if source_slot == nil or is_null_object(source_slot) then
        return false, nil, nil, "missing source slot", nil
    end

    local found_out = {}
    local index_out = {}
    local final_rotation_out = {}
    local direct_ok, direct_results = capture_results(function()
        return comp:JSIFindEmptySpot(target_container, source_slot, found_out, index_out, final_rotation_out)
    end)

    if not direct_ok then
        return false, nil, nil, tostring(direct_results), {
            found = found_out,
            index = index_out,
            final_rotation = final_rotation_out,
            results = nil,
        }
    end

    -- UE4SS currently writes all non-struct out values into the first out table for this function.
    local found_value = found_out.Found
    local index_value = found_out.Index
    local final_rotation_value = found_out.FinalRotation

    if found_value == nil then
        found_value = index_out.Found
    end
    if index_value == nil then
        index_value = index_out.Index
    end
    if final_rotation_value == nil then
        final_rotation_value = final_rotation_out.FinalRotation
    end

    return found_value == true, index_value, final_rotation_value == true, nil, {
        found = found_out,
        index = index_out,
        final_rotation = final_rotation_out,
        results = direct_results,
    }
end

local function try_jsi_find_empty_spot(label, comp, target_container, source_slot)
    local found, index, final_rotation, err, debug = read_jsi_empty_spot(comp, target_container, source_slot)
    if err ~= nil then
        append_log("    " .. label .. " outTables error=" .. tostring(err))
    else
        log_call_results("    " .. label .. " outTables", true, debug and debug.results or { n = 0 })
    end
    append_log("    " .. label .. " outTables values: " ..
        "Found=" .. value_summary(found) ..
        " Index=" .. value_summary(index) ..
        " FinalRotation=" .. value_summary(final_rotation) ..
        " foundTable=" .. lua_table_summary(debug and debug.found or nil) ..
        " indexTable=" .. lua_table_summary(debug and debug.index or nil) ..
        " finalRotationTable=" .. lua_table_summary(debug and debug.final_rotation or nil))
end

local function collect_quickstack_matches(target, source_groups, max_matches)
    local matches = {}
    for source_index, source in ipairs(source_groups) do
        for _, item in ipairs(source.items) do
            local snapshot = item.snapshot
            local receiver = choose_target_receiver(target, snapshot.item_key)
            if is_quickstack_source_item(source, item) and receiver ~= nil then
                table.insert(matches, {
                    source_index = source_index,
                    source = source,
                    source_item = item,
                    receiver = receiver,
                })
                if #matches >= (max_matches or MAX_EMPTY_SLOT_PROBE_MATCHES) then
                    return matches
                end
            end
        end
    end
    return matches
end

local function probe_quickstack_empty_slot()
    append_log("")
    append_log("============================================================")
    append_log("QuickStack empty-slot probe started. No item movement.")
    append_log("============================================================")

    local rows, item_slots, uid_slots, total_slots, container_count = collect_raw_slot_group_rows()
    local visible_groups, excluded_equipment_like = collect_visible_inventory_groups(rows)
    append_log("QuickStack empty-slot scan: totalSlots=" .. tostring(total_slots) ..
        " groups=" .. tostring(#rows) ..
        " jsiContainers=" .. tostring(container_count) ..
        " itemSlots=" .. tostring(item_slots) ..
        " uidSlots=" .. tostring(uid_slots) ..
        " visibleInventoryGroups=" .. tostring(#visible_groups) ..
        " excludedEquipmentLikeGroups=" .. tostring(excluded_equipment_like))

    for group_index = 1, math.min(#visible_groups, 12) do
        local group = visible_groups[group_index]
        append_log("  inventoryGroup[" .. tostring(group_index) .. "] " ..
            group.key ..
            " " .. container_info_text(group.container_info) ..
            " total=" .. tostring(group.total) ..
            " itemSlots=" .. tostring(group.item_count) ..
            " uidSlots=" .. tostring(group.uid_count) ..
            " visibleSlots=" .. tostring(group.visible_count) ..
            " mergedParts=" .. tostring(group.merged_parts))
    end

    local target, source_groups, player_mp_addr, target_groups, reason = choose_quickstack_direction(visible_groups, rows)
    append_log("QuickStack direction: playerMp=" .. tostring(player_mp_addr) ..
        " sourceGroups=" .. tostring(#source_groups) ..
        " targetGroups=" .. tostring(#target_groups))
    if #target_groups > 1 then
        append_log("  note: multiple non-player target groups found; probing the largest visible candidate only")
    end

    if target == nil then
        append_log("QuickStack empty-slot probe aborted: " .. tostring(reason))
        append_log("QuickStack empty-slot probe finished")
        return
    end

    local target_info = target.container_info
    if target_info == nil or target_info.object == nil or target_info.mp == nil or is_null_object(target_info.mp) then
        append_log("QuickStack empty-slot probe aborted: target container or target JigMultiplayer component is missing")
        append_log("QuickStack empty-slot probe finished")
        return
    end

    append_log("  selectedTarget " .. target.key .. " " .. container_info_text(target_info))
    local matches = collect_quickstack_matches(target, source_groups, MAX_EMPTY_SLOT_PROBE_MATCHES)
    append_log("QuickStack matching source slots selected for empty-slot probe: " .. tostring(#matches))
    if #matches == 0 then
        append_log("QuickStack empty-slot probe finished")
        return
    end

    local jsi_find_path = "/Game/JigSInventory/Jigsaw/Components/BP_JigMultiplayer.BP_JigMultiplayer_C:JSIFindEmptySpot"
    local jsi_find_function = safe_call(function()
        if StaticFindObject then
            return StaticFindObject(jsi_find_path)
        end
        return nil
    end, nil)
    append_log("  JSIFindEmptySpot static lookup: " .. value_summary(jsi_find_function))

    for match_index, match in ipairs(matches) do
        local source_info = match.source.container_info
        local source_snapshot = match.source_item.snapshot
        local receiver_snapshot = match.receiver and match.receiver.snapshot or nil

        append_log("  match[" .. tostring(match_index) .. "] " ..
            "sourceGroup=" .. tostring(match.source_index) ..
            " key=" .. tostring(source_snapshot.item_key) ..
            " sourceUID=" .. tostring(source_snapshot.unique_id) ..
            " sourceSlotIndex=" .. tostring(source_snapshot.slot_index) ..
            " sourceCount=" .. tostring(source_snapshot.item_count) ..
            " targetContainerID=" .. tostring(target_info.container_id) ..
            " sourceMp=" .. tostring(source_info and source_info.mp_addr or nil) ..
            " targetMp=" .. tostring(target_info.mp_addr) ..
            " receiverUID=" .. tostring(receiver_snapshot and receiver_snapshot.unique_id or nil) ..
            " receiverSlotIndex=" .. tostring(receiver_snapshot and receiver_snapshot.slot_index or nil) ..
            " receiverCount=" .. tostring(receiver_snapshot and receiver_snapshot.item_count or nil) ..
            " receiverMaxStack=" .. tostring(receiver_snapshot and receiver_snapshot.max_stack or nil))

        try_jsi_find_empty_spot("match[" .. tostring(match_index) .. "] targetMp", target_info.mp, target_info.object, match.source_item.slot)
        if source_info ~= nil and source_info.mp ~= nil and address_text(source_info.mp) ~= address_text(target_info.mp) then
            try_jsi_find_empty_spot("match[" .. tostring(match_index) .. "] sourceMp", source_info.mp, target_info.object, match.source_item.slot)
        end
    end

    append_log("QuickStack empty-slot probe finished")
end

local function call_client_move_item_to_index(comp, item_uid, to_container_id, to_index, final_rotation)
    if comp == nil or is_null_object(comp) then
        return false, "missing component"
    end

    local ok, err = pcall(function()
        return comp:CLIENT_MoveItemToIndex(
            item_uid,
            to_container_id,
            to_index,
            final_rotation == true
        )
    end)

    if ok then
        return true, nil
    end
    return false, tostring(err)
end

local function call_server_first_cleanup_comp_move(source_container, source_slot, source_comp, target_comp, item_uid, to_container_id, to_index, final_rotation, amount)
    if source_container == nil or is_null_object(source_container) then
        return false, "missing source container"
    end
    if source_slot == nil or is_null_object(source_slot) then
        return false, "missing source slot"
    end
    if source_comp == nil or is_null_object(source_comp) then
        return false, "missing source component"
    end
    if target_comp == nil or is_null_object(target_comp) then
        return false, "missing target component"
    end

    local server_ok, server_err = pcall(function()
        return source_comp:SERVER_RequestMoveItemToAnotherComp(
            source_comp,
            target_comp,
            item_uid,
            final_rotation == true,
            to_index,
            to_container_id,
            amount,
            0,
            0
        )
    end)
    if not server_ok then
        return false, "SERVER_RequestMoveItemToAnotherComp failed before local cleanup: " .. tostring(server_err)
    end
    append_debug("    server-first cleanup: SERVER_RequestMoveItemToAnotherComp submitted")

    local removed_out = {}
    local remove_ok, remove_err = pcall(function()
        return source_container:RemoveInventoryItemByRef(source_slot, true, removed_out)
    end)
    if not remove_ok then
        return false, "SERVER submitted, but RemoveInventoryItemByRef cleanup failed: " .. tostring(remove_err)
    end
    append_debug("    server-first cleanup: RemoveInventoryItemByRef submitted removedOut=" .. lua_table_summary(removed_out))

    local client_removed_ok, client_removed_err = pcall(function()
        return source_comp:CLIENT_ItemRemoved(item_uid, target_comp)
    end)
    if not client_removed_ok then
        return false, "SERVER submitted and source cleanup submitted, but CLIENT_ItemRemoved failed: " .. tostring(client_removed_err)
    end
    append_debug("    server-first cleanup: CLIENT_ItemRemoved submitted")

    return true, nil
end

local function reset_full_quickstack_anchor()
    full_quickstack_player_mp_addr = nil
    full_quickstack_target_addr = nil
    full_quickstack_target_container_id = nil
    full_quickstack_target_mp_addr = nil
end

local function anchor_full_quickstack_target(target, player_mp_addr)
    local target_info = target and target.container_info or nil
    full_quickstack_player_mp_addr = player_mp_addr
    full_quickstack_target_addr = target_info and target_info.addr or nil
    full_quickstack_target_container_id = target_info and target_info.container_id or nil
    full_quickstack_target_mp_addr = target_info and target_info.mp_addr or nil
end

local function find_full_quickstack_anchored_target(visible_groups)
    for _, group in ipairs(visible_groups) do
        local info = group.container_info
        if info ~= nil and full_quickstack_target_addr ~= nil and info.addr == full_quickstack_target_addr then
            return group
        end
    end

    for _, group in ipairs(visible_groups) do
        local info = group.container_info
        if info ~= nil and
            full_quickstack_target_container_id ~= nil and info.container_id == full_quickstack_target_container_id and
            full_quickstack_target_mp_addr ~= nil and info.mp_addr == full_quickstack_target_mp_addr then
            return group
        end
    end

    return nil
end

local function choose_full_quickstack_target_and_sources(step_index, visible_groups, rows)
    if step_index <= 1 or full_quickstack_target_addr == nil then
        local target, source_groups, player_mp_addr, target_groups, reason = choose_quickstack_direction(visible_groups, rows)
        if target ~= nil then
            anchor_full_quickstack_target(target, player_mp_addr)
        end
        return target, source_groups, player_mp_addr, target_groups, reason
    end

    local target = find_full_quickstack_anchored_target(visible_groups)
    if target == nil then
        return nil, {}, full_quickstack_player_mp_addr, {}, "anchored target container is no longer visible"
    end

    local source_groups = {}
    local target_groups = { target }
    for _, group in ipairs(visible_groups) do
        local info = group.container_info
        local is_target = info ~= nil and
            ((full_quickstack_target_addr ~= nil and info.addr == full_quickstack_target_addr) or
            (full_quickstack_target_container_id ~= nil and info.container_id == full_quickstack_target_container_id and info.mp_addr == full_quickstack_target_mp_addr))
        if not is_target and group_mp_addr(group) == full_quickstack_player_mp_addr then
            table.insert(source_groups, group)
        end
    end

    if #source_groups == 0 then
        return nil, {}, full_quickstack_player_mp_addr, target_groups, "anchored player inventory groups are no longer visible"
    end

    return target, source_groups, full_quickstack_player_mp_addr, target_groups, nil
end

local function run_quickstack_single_move_test(submit_override, client_update_after_submit)
    local current_time = os.time()
    if current_time - last_single_move_test_time < QUICKSTACK_SINGLE_MOVE_COOLDOWN_SECONDS then
        append_log("QuickStack SINGLE-MOVE TEST ignored: cooldown is active")
        return
    end
    last_single_move_test_time = current_time

    local submit_enabled = QUICKSTACK_ALLOW_SINGLE_MOVE_SUBMIT == true or submit_override == true

    append_log("")
    append_log("============================================================")
    if client_update_after_submit == "server_first_cleanup" then
        append_log("QuickStack EXPERIMENTAL SERVER-FIRST CLEANUP SINGLE-MOVE TEST started. This can move one inventory stack.")
    elseif submit_enabled then
        append_log("QuickStack EXPERIMENTAL SINGLE-MOVE TEST started. This can move one inventory stack.")
    else
        append_log("QuickStack SINGLE-MOVE CANDIDATE TEST started. Submit is disabled; no item movement.")
    end
    append_log("============================================================")

    local rows, item_slots, uid_slots, total_slots, container_count = collect_raw_slot_group_rows()
    local visible_groups, excluded_equipment_like = collect_visible_inventory_groups(rows)
    append_log("QuickStack single-move scan: totalSlots=" .. tostring(total_slots) ..
        " groups=" .. tostring(#rows) ..
        " jsiContainers=" .. tostring(container_count) ..
        " itemSlots=" .. tostring(item_slots) ..
        " uidSlots=" .. tostring(uid_slots) ..
        " visibleInventoryGroups=" .. tostring(#visible_groups) ..
        " excludedEquipmentLikeGroups=" .. tostring(excluded_equipment_like))

    for group_index = 1, math.min(#visible_groups, 12) do
        local group = visible_groups[group_index]
        append_log("  inventoryGroup[" .. tostring(group_index) .. "] " ..
            group.key ..
            " " .. container_info_text(group.container_info) ..
            " total=" .. tostring(group.total) ..
            " itemSlots=" .. tostring(group.item_count) ..
            " uidSlots=" .. tostring(group.uid_count) ..
            " visibleSlots=" .. tostring(group.visible_count) ..
            " mergedParts=" .. tostring(group.merged_parts))
    end

    local target, source_groups, player_mp_addr, target_groups, reason = choose_quickstack_direction(visible_groups, rows)
    append_log("QuickStack direction: playerMp=" .. tostring(player_mp_addr) ..
        " sourceGroups=" .. tostring(#source_groups) ..
        " targetGroups=" .. tostring(#target_groups))

    if target == nil then
        append_log("QuickStack single-move aborted: " .. tostring(reason))
        append_log("QuickStack SINGLE-MOVE TEST finished")
        return
    end

    local target_info = target.container_info
    if target_info == nil or target_info.object == nil or target_info.mp == nil or is_null_object(target_info.mp) then
        append_log("QuickStack single-move aborted: target container or target JigMultiplayer component is missing")
        append_log("QuickStack SINGLE-MOVE TEST finished")
        return
    end

    append_log("  selectedTarget " .. target.key .. " " .. container_info_text(target_info))
    local matches = collect_quickstack_matches(target, source_groups, QUICKSTACK_SINGLE_MOVE_LIMIT)
    if #matches == 0 then
        append_log("QuickStack single-move aborted: no matching source item found")
        append_log("QuickStack SINGLE-MOVE TEST finished")
        return
    end

    local moved = 0
    for match_index, match in ipairs(matches) do
        local source_info = match.source.container_info
        local source_snapshot = match.source_item.snapshot
        local receiver_snapshot = match.receiver and match.receiver.snapshot or nil
        if source_info == nil or source_info.mp == nil or is_null_object(source_info.mp) then
            append_log("  move[" .. tostring(match_index) .. "] skipped: missing source JigMultiplayer component")
        else
            local amount = source_snapshot.item_count or source_snapshot.info_count or 0
            local receiver_count = receiver_snapshot and (receiver_snapshot.item_count or receiver_snapshot.info_count or 0) or 0
            local receiver_max_stack = receiver_snapshot and (receiver_snapshot.max_stack or 0) or 0
            local can_stack_into_receiver = receiver_snapshot ~= nil and
                receiver_snapshot.unique_id ~= nil and receiver_snapshot.unique_id ~= 0 and
                receiver_max_stack > 0 and receiver_count < receiver_max_stack

            local found, to_index, final_rotation, err, debug = false, nil, false, nil, nil
            if not can_stack_into_receiver then
                found, to_index, final_rotation, err, debug = read_jsi_empty_spot(target_info.mp, target_info.object, match.source_item.slot)
            end

            append_log("  move[" .. tostring(match_index) .. "] planned: " ..
                "action=" .. (can_stack_into_receiver and "stack " or "move ") ..
                "key=" .. tostring(source_snapshot.item_key) ..
                " sourceUID=" .. tostring(source_snapshot.unique_id) ..
                " sourceSlotIndex=" .. tostring(source_snapshot.slot_index) ..
                " amount=" .. tostring(amount) ..
                " receiverUID=" .. tostring(receiver_snapshot and receiver_snapshot.unique_id or nil) ..
                " receiverCount=" .. tostring(receiver_count) ..
                " receiverMaxStack=" .. tostring(receiver_max_stack) ..
                " targetContainerID=" .. tostring(target_info.container_id) ..
                " found=" .. tostring(found) ..
                " toIndex=" .. tostring(to_index) ..
                " finalRotation=" .. tostring(final_rotation) ..
                " out=" .. lua_table_summary(debug and debug.found or nil) ..
                " err=" .. tostring(err))

            if amount <= 0 or source_snapshot.unique_id == nil or source_snapshot.unique_id == 0 then
                append_log("  move[" .. tostring(match_index) .. "] skipped: invalid source UID/count")
            elseif group_contains_uid(target, source_snapshot.unique_id) then
                append_log("  move[" .. tostring(match_index) .. "] skipped: source UID is already present in target, avoiding duplicate/ghost move")
            elseif submit_enabled ~= true then
                append_log("  move[" .. tostring(match_index) .. "] skipped: submit disabled while investigating source ghosting")
            elseif can_stack_into_receiver then
                append_log("  move[" .. tostring(match_index) .. "] skipped: experimental submit only tests move-to-empty-slot path, not stack path yet")
            elseif err ~= nil then
                append_log("  move[" .. tostring(match_index) .. "] skipped: empty-slot lookup failed")
            elseif found ~= true or type(to_index) ~= "number" then
                append_log("  move[" .. tostring(match_index) .. "] skipped: no valid empty destination or source UID/count")
            else
                local ok, call_err
                if client_update_after_submit == "server_first_cleanup" then
                    ok, call_err = call_server_first_cleanup_comp_move(
                        source_info.object,
                        match.source_item.slot,
                        source_info.mp,
                        target_info.mp,
                        source_snapshot.unique_id,
                        target_info.container_id,
                        to_index,
                        final_rotation == true,
                        amount
                    )
                else
                    ok, call_err = pcall(function()
                        return source_info.mp:SERVER_RequestMoveItemToAnotherComp(
                            source_info.mp,
                            target_info.mp,
                            source_snapshot.unique_id,
                            final_rotation == true,
                            to_index,
                            target_info.container_id,
                            amount,
                            0,
                            0
                        )
                    end)
                end

                if ok then
                    moved = moved + 1
                    append_log("  move[" .. tostring(match_index) .. "] submitted: sourceUID=" ..
                        tostring(source_snapshot.unique_id) ..
                        " toIndex=" .. tostring(to_index) ..
                        " amount=" .. tostring(amount))
                    if client_update_after_submit == true then
                        local client_ok, client_err = call_client_move_item_to_index(
                            source_info.mp,
                            source_snapshot.unique_id,
                            target_info.container_id,
                            to_index,
                            final_rotation == true
                        )
                        if client_ok then
                            append_log("  move[" .. tostring(match_index) .. "] submitted CLIENT_MoveItemToIndex local update")
                        else
                            append_log("  move[" .. tostring(match_index) .. "] CLIENT_MoveItemToIndex local update failed: " .. tostring(client_err))
                        end
                    end
                else
                    append_log("  move[" .. tostring(match_index) .. "] call failed: " .. tostring(call_err))
                end
            end
        end
    end

    if client_update_after_submit == "server_first_cleanup" then
        append_log("QuickStack EXPERIMENTAL SERVER-FIRST CLEANUP SINGLE-MOVE TEST finished. submittedMoves=" .. tostring(moved))
    elseif submit_enabled then
        append_log("QuickStack EXPERIMENTAL SINGLE-MOVE TEST finished. submittedMoves=" .. tostring(moved))
    else
        append_log("QuickStack SINGLE-MOVE CANDIDATE TEST finished. submittedMoves=" .. tostring(moved))
    end
end

local function submit_one_full_quickstack_move(step_index)
    local rows, item_slots, uid_slots, total_slots, container_count = collect_raw_slot_group_rows()
    local visible_groups, excluded_equipment_like = collect_visible_inventory_groups(rows)
    append_debug("QuickStack full step[" .. tostring(step_index) .. "] scan: totalSlots=" .. tostring(total_slots) ..
        " groups=" .. tostring(#rows) ..
        " jsiContainers=" .. tostring(container_count) ..
        " itemSlots=" .. tostring(item_slots) ..
        " uidSlots=" .. tostring(uid_slots) ..
        " visibleInventoryGroups=" .. tostring(#visible_groups) ..
        " excludedEquipmentLikeGroups=" .. tostring(excluded_equipment_like))

    local target, source_groups, player_mp_addr, target_groups, reason = choose_full_quickstack_target_and_sources(step_index, visible_groups, rows)
    append_debug("QuickStack full step[" .. tostring(step_index) .. "] direction: playerMp=" .. tostring(player_mp_addr) ..
        " sourceGroups=" .. tostring(#source_groups) ..
        " targetGroups=" .. tostring(#target_groups) ..
        " anchoredTarget=" .. tostring(full_quickstack_target_container_id))

    if target == nil then
        return false, "no target selected: " .. tostring(reason)
    end

    local target_info = target.container_info
    if target_info == nil or target_info.object == nil or target_info.mp == nil or is_null_object(target_info.mp) then
        return false, "target container or target JigMultiplayer component is missing"
    end

    local matches = collect_quickstack_matches(target, source_groups, QUICKSTACK_FULL_MOVE_LIMIT)
    append_debug("QuickStack full step[" .. tostring(step_index) .. "] selectedTarget " ..
        target.key .. " " .. container_info_text(target_info) ..
        " matches=" .. tostring(#matches))
    if #matches == 0 then
        return false, "no matching source item found"
    end

    for match_index, match in ipairs(matches) do
        local source_info = match.source.container_info
        local source_snapshot = match.source_item.snapshot
        local receiver_snapshot = match.receiver and match.receiver.snapshot or nil
        local amount = source_snapshot.item_count or source_snapshot.info_count or 0

        if source_info == nil or source_info.mp == nil or is_null_object(source_info.mp) then
            append_debug("  full step[" .. tostring(step_index) .. "] match[" .. tostring(match_index) .. "] skipped: missing source JigMultiplayer component")
        elseif amount <= 0 or source_snapshot.unique_id == nil or source_snapshot.unique_id == 0 then
            append_debug("  full step[" .. tostring(step_index) .. "] match[" .. tostring(match_index) .. "] skipped: invalid source UID/count")
        elseif group_contains_uid(target, source_snapshot.unique_id) then
            append_debug("  full step[" .. tostring(step_index) .. "] match[" .. tostring(match_index) .. "] skipped: source UID is already present in target")
        else
            local found, to_index, final_rotation, err, debug = read_jsi_empty_spot(target_info.mp, target_info.object, match.source_item.slot)
            append_debug("  full step[" .. tostring(step_index) .. "] match[" .. tostring(match_index) .. "] planned: " ..
                "key=" .. tostring(source_snapshot.item_key) ..
                " sourceUID=" .. tostring(source_snapshot.unique_id) ..
                " sourceSlotIndex=" .. tostring(source_snapshot.slot_index) ..
                " amount=" .. tostring(amount) ..
                " receiverUID=" .. tostring(receiver_snapshot and receiver_snapshot.unique_id or nil) ..
                " targetContainerID=" .. tostring(target_info.container_id) ..
                " found=" .. tostring(found) ..
                " toIndex=" .. tostring(to_index) ..
                " finalRotation=" .. tostring(final_rotation) ..
                " out=" .. lua_table_summary(debug and debug.found or nil) ..
                " err=" .. tostring(err))

            if err ~= nil then
                append_debug("  full step[" .. tostring(step_index) .. "] match[" .. tostring(match_index) .. "] skipped: empty-slot lookup failed")
            elseif found ~= true or type(to_index) ~= "number" then
                append_debug("  full step[" .. tostring(step_index) .. "] match[" .. tostring(match_index) .. "] skipped: no valid empty destination")
            else
                local ok, call_err = call_server_first_cleanup_comp_move(
                    source_info.object,
                    match.source_item.slot,
                    source_info.mp,
                    target_info.mp,
                    source_snapshot.unique_id,
                    target_info.container_id,
                    to_index,
                    final_rotation == true,
                    amount
                )

                if ok then
                    return true, "moved sourceUID=" .. tostring(source_snapshot.unique_id) ..
                        " key=" .. tostring(source_snapshot.item_key) ..
                        " toIndex=" .. tostring(to_index) ..
                        " amount=" .. tostring(amount)
                end

                return false, "move call failed: " .. tostring(call_err)
            end
        end
    end

    return false, "no movable match selected"
end

local full_quickstack_step

local function schedule_full_quickstack_step(run_id, moved_count)
    if not ExecuteWithDelay then
        full_quickstack_active = false
        reset_full_quickstack_anchor()
        append_log("QuickStack FULL stopped after " .. tostring(moved_count) .. " move(s): ExecuteWithDelay is unavailable")
        return
    end

    local ok, err = pcall(function()
        ExecuteWithDelay(QUICKSTACK_FULL_MOVE_DELAY_MS, function()
            if ExecuteInGameThread then
                ExecuteInGameThread(function()
                    full_quickstack_step(run_id, moved_count)
                end)
            else
                full_quickstack_step(run_id, moved_count)
            end
        end)
    end)

    if not ok then
        full_quickstack_active = false
        reset_full_quickstack_anchor()
        append_log("QuickStack FULL stopped after " .. tostring(moved_count) .. " move(s): delay scheduling failed: " .. tostring(err))
    end
end

full_quickstack_step = function(run_id, moved_count)
    if full_quickstack_active ~= true or run_id ~= full_quickstack_run_id then
        return
    end

    if moved_count >= QUICKSTACK_FULL_MOVE_LIMIT then
        full_quickstack_active = false
        reset_full_quickstack_anchor()
        append_log("QuickStack FULL finished: safety move limit reached. moved=" .. tostring(moved_count))
        return
    end

    local next_index = moved_count + 1
    local moved, reason = submit_one_full_quickstack_move(next_index)
    if moved then
        append_log("QuickStack FULL step[" .. tostring(next_index) .. "] submitted: " .. tostring(reason))
        schedule_full_quickstack_step(run_id, next_index)
        return
    end

    full_quickstack_active = false
    reset_full_quickstack_anchor()
    append_log("QuickStack FULL finished. moved=" .. tostring(moved_count) .. " reason=" .. tostring(reason))
end

local function run_quickstack_full()
    local current_time = os.time()
    if full_quickstack_active == true then
        append_log("QuickStack FULL ignored: a run is already active")
        return
    end
    if current_time - last_full_quickstack_time < QUICKSTACK_SINGLE_MOVE_COOLDOWN_SECONDS then
        append_log("QuickStack FULL ignored: cooldown is active")
        return
    end

    last_full_quickstack_time = current_time
    full_quickstack_active = true
    full_quickstack_run_id = full_quickstack_run_id + 1
    reset_full_quickstack_anchor()

    append_log("QuickStack started: Ctrl+F9, moving matching inventory stacks to the opened container")

    full_quickstack_step(full_quickstack_run_id, 0)
end

local function probe_quickstack_dry_run_candidates()
    append_log("")
    append_log("============================================================")
    append_log("QuickStack target dry-run started. No item movement.")
    append_log("============================================================")

    local rows, item_slots, uid_slots, total_slots, container_count = collect_raw_slot_group_rows()
    append_log("QuickStack dry-run scan: totalSlots=" .. tostring(total_slots) ..
        " groups=" .. tostring(#rows) ..
        " jsiContainers=" .. tostring(container_count) ..
        " itemSlots=" .. tostring(item_slots) ..
        " uidSlots=" .. tostring(uid_slots))

    local visible_groups = {}
    local excluded_equipment_like = 0
    for _, group in ipairs(rows) do
        if group.item_count > 0 and group.uid_count > 0 and group.visible_count > 0 then
            if is_inventory_like_group(group) then
                table.insert(visible_groups, group)
            else
                excluded_equipment_like = excluded_equipment_like + 1
            end
        end
    end

    table.sort(visible_groups, function(a, b)
        if a.item_count == b.item_count then
            return a.visible_count > b.visible_count
        end
        return a.item_count > b.item_count
    end)

    append_log("Visible inventory-like groups considered: " .. tostring(#visible_groups) ..
        " excludedEquipmentLikeGroups=" .. tostring(excluded_equipment_like))
    for group_index = 1, math.min(#visible_groups, 12) do
        local group = visible_groups[group_index]
        append_log("  inventoryGroup[" .. tostring(group_index) .. "] " ..
            group.key ..
            " " .. container_info_text(group.container_info) ..
            " total=" .. tostring(group.total) ..
            " itemSlots=" .. tostring(group.item_count) ..
            " uidSlots=" .. tostring(group.uid_count) ..
            " visibleSlots=" .. tostring(group.visible_count) ..
            " mergedParts=" .. tostring(group.merged_parts))
    end

    for target_index = 1, math.min(#visible_groups, 5) do
        local target = visible_groups[target_index]
        local move_totals = {}
        local matched_slots = 0
        local matched_count = 0

        for source_index, source in ipairs(visible_groups) do
            if source_index ~= target_index then
                for _, item in ipairs(source.items) do
                    local snapshot = item.snapshot
                    local receiver = choose_target_receiver(target, snapshot.item_key)
                    if is_quickstack_source_item(source, item) and receiver ~= nil then
                        local count = snapshot.item_count or snapshot.info_count or 0
                        matched_slots = matched_slots + 1
                        matched_count = matched_count + count
                        if not move_totals[snapshot.item_key] then
                            move_totals[snapshot.item_key] = { slots = 0, count = 0, sources = {}, details = {} }
                        end
                        local move_total = move_totals[snapshot.item_key]
                        move_total.slots = move_total.slots + 1
                        move_total.count = move_total.count + count
                        move_total.sources[source_index] = true
                        if #move_total.details < 8 then
                            table.insert(move_total.details, {
                                source_index = source_index,
                                source_item = item,
                                receiver = receiver,
                            })
                        end
                    end
                end
            end
        end

        local move_rows = sorted_key_rows_from_totals(move_totals)
        append_log("  [target candidate " .. tostring(target_index) .. "] " ..
            target.key ..
            " " .. container_info_text(target.container_info) ..
            " targetSlots=" .. tostring(target.total) ..
            " targetItems=" .. tostring(target.item_count) ..
            " visibleSlots=" .. tostring(target.visible_count) ..
            " matchingSourceSlots=" .. tostring(matched_slots) ..
            " matchingItemCount=" .. tostring(matched_count) ..
            " distinctMoveKeys=" .. tostring(#move_rows))

        local target_key_rows = sorted_group_lines(target.key_groups)
        for key_index = 1, math.min(#target_key_rows, 8) do
            append_log("    targetKey[" .. tostring(key_index) .. "] key=" .. target_key_rows[key_index].key ..
                " slots=" .. tostring(target_key_rows[key_index].count))
        end

        for move_index = 1, math.min(#move_rows, 12) do
            local move = move_rows[move_index]
            local source_list = {}
            for source_index, _ in pairs(move.sources) do
                table.insert(source_list, tostring(source_index))
            end
            table.sort(source_list)
            append_log("    wouldMove[" .. tostring(move_index) .. "] key=" .. tostring(move.key) ..
                " slots=" .. tostring(move.slots) ..
                " count=" .. tostring(move.count) ..
                " fromInventoryGroups=" .. table.concat(source_list, ","))
            for detail_index, detail in ipairs(move.details or {}) do
                local source_snapshot = detail.source_item.snapshot
                local receiver_snapshot = nil
                if detail.receiver ~= nil then
                    receiver_snapshot = detail.receiver.snapshot
                end

                append_log("      moveSlot[" .. tostring(detail_index) .. "] " ..
                    "fromGroup=" .. tostring(detail.source_index) ..
                    " sourceUID=" .. tostring(source_snapshot.unique_id) ..
                    " sourceSlotIndex=" .. tostring(source_snapshot.slot_index) ..
                    " sourceCount=" .. tostring(source_snapshot.item_count) ..
                    " -> targetUID=" .. tostring(receiver_snapshot and receiver_snapshot.unique_id or nil) ..
                    " targetSlotIndex=" .. tostring(receiver_snapshot and receiver_snapshot.slot_index or nil) ..
                    " targetCount=" .. tostring(receiver_snapshot and receiver_snapshot.item_count or nil) ..
                    " targetMaxStack=" .. tostring(receiver_snapshot and receiver_snapshot.max_stack or nil))
            end
        end
    end

    append_log("QuickStack target dry-run finished")
end

local function probe_widgets_by_activity()
    local ok, objects = pcall(function()
        return FindAllOf("JSIContainer_C")
    end)
    if not ok or not objects then
        append_log("JSIContainer_C probe unavailable")
        return
    end

    local total = #objects
    local active = 0
    local logged = 0
    local by_outer = {}
    local by_outer_visibility = {}
    local by_outer_name = {}
    local by_owner = {}
    local outer_objects = {}
    local parent_objects = {}

    append_log("Focused JSIContainer_C widget probe started")

    for index = 1, total do
        local object = objects[index]
        local visible = bool_method(object, "IsVisible")
        local hovered = bool_method(object, "IsHovered")
        local focus = bool_method(object, "HasAnyUserFocus")
        local focus_desc = bool_method(object, "HasFocusedDescendants")
        local enabled = method_summary(object, "GetIsEnabled")
        local visibility_prop = raw_property_summary(object, "Visibility")
        local name_summary = raw_property_summary(object, "ContainerName")
        local outer = outer_object(object)
        local parent = parent_object(object)
        local owner = safe_call(function()
            local owner_ok, owner_value = call_method(object, "GetOwningPlayer")
            if owner_ok then
                return owner_value
            end
            return nil
        end, nil)

        local should_log = visible or hovered or focus or focus_desc or visibility_prop == "0"
        if should_log then
            active = active + 1

            local outer_addr = address_text(outer)
            local parent_addr = address_text(parent)
            local owner_addr = address_text(owner)
            increment_group(by_outer, outer_addr)
            increment_group(by_outer_visibility, outer_addr .. " visibility=" .. visibility_prop)
            increment_group(by_outer_name, outer_addr .. " name=" .. name_summary)
            increment_group(by_owner, owner_addr)

            if outer and not is_null_object(outer) then
                outer_objects[outer_addr] = outer
            end
            if parent and not is_null_object(parent) then
                parent_objects[parent_addr] = parent
            end

            if logged < MAX_GROUP_DETAILS then
                logged = logged + 1
                append_log(string.format(
                    "  [JSIContainer_C #%d] addr=%s visible=%s enabled=%s focus=%s focusDesc=%s hovered=%s visibility=%s outer=%s parent=%s owner=%s name=%s",
                    index,
                    address_text(object),
                    tostring(visible),
                    enabled,
                    tostring(focus),
                    tostring(focus_desc),
                    tostring(hovered),
                    visibility_prop,
                    outer_addr,
                    parent_addr,
                    owner_addr,
                    name_summary
                ))
            end
        end
    end

    append_log("Active-ish JSIContainer_C: " .. tostring(active) .. " / " .. tostring(total) .. " (logged " .. tostring(logged) .. ")")
    log_groups("JSIContainer_C groups by outer:", by_outer)
    log_groups("JSIContainer_C groups by outer + visibility:", by_outer_visibility)
    log_groups("JSIContainer_C groups by outer + ContainerName:", by_outer_name)
    log_groups("JSIContainer_C groups by owning player:", by_owner)

    append_log("JSIContainer_C outer object details:")
    local outer_count = 0
    for key, object in pairs(outer_objects) do
        outer_count = outer_count + 1
        if outer_count <= 12 then
            log_object_details(object, "  [outer " .. key .. "] ", true)
        end
    end

    append_log("JSIContainer_C parent object details:")
    local parent_count = 0
    for key, object in pairs(parent_objects) do
        parent_count = parent_count + 1
        if parent_count <= 18 then
            log_object_details(object, "  [parent " .. key .. "] ", true)
        end
    end

    append_log("Focused JSIContainer_C widget probe finished")
end

local function probe_context_objects()
    local context_classes = {
        "DragDropOperation",
        "IngameMenuContainerWidgetBP_C",
        "ContainerWindowWidget_C",
        "JigContextMenuW_C",
        "JigContextMenuComp_C",
        "JigContextMenuCanvas_C",
        "HoverDragOperation_C",
        "JigSDragOperation_C",
        "DragWidget_C",
        "JigSplitWidget_C",
        "DropItemAmountSelector_C",
        "DropItemBackGwidget_C",
    }

    append_log("Context object probe started")
    for _, class_name in ipairs(context_classes) do
        local ok, objects = pcall(function()
            return FindAllOf(class_name)
        end)
        if ok and objects and #objects > 0 then
            append_log("FindAllOf(" .. class_name .. ") -> " .. tostring(#objects))
            for index = 1, math.min(#objects, 10) do
                log_object_details(objects[index], "  [" .. class_name .. " #" .. tostring(index) .. "] ", true)
            end
        end
    end
    append_log("Context object probe finished")
end

local fitem_info_fields = {
    item_id = "ItemID_107_1737366145EEBA44086DB6ACE0E9C90F",
    unique_id = "UniqueServerID_83_19E6C8FE42B778BAE918F79F1D85AE2A",
    count = "Count_22_BFF3027A4FD5D984887F16B0B821DF3E",
    max_stack = "MaxStack_8_4ABF8FB44B55528999A71A9403501AF2",
    can_stack = "CanStack_5_C8C8CA994713D5823B06DDB479DDA7A1",
    slot_dimension = "SlotDimension_19_F030B0224A638DF8046DFBA1A9F61992",
    data_table = "DataTableRef_110_A7EA1E9840AD592F445E1DA473381D6E",
}

local function get_item_info(slot)
    local found, info = non_null_property(slot, "ItemInfo")
    if found then
        return info
    end
    return nil
end

local function get_slot_item_snapshot(slot)
    local info = get_item_info(slot)
    local item_id = info and raw_property_value(info, fitem_info_fields.item_id) or nil
    local item_id_key = fname_key(item_id)
    local count_from_info = info and number_property(info, fitem_info_fields.count) or nil
    local count_from_slot = number_property(slot, "ItemCount")
    local count = count_from_slot or count_from_info
    local unique_id = info and number_property(info, fitem_info_fields.unique_id) or nil
    local max_stack = info and number_property(info, fitem_info_fields.max_stack) or nil
    local can_stack = info and bool_property(info, fitem_info_fields.can_stack) or nil
    local is_empty = bool_property(slot, "IsEmpty")
    local slot_index = number_property(slot, "SlotIndex")
    local slot_vector = raw_property_summary(info, fitem_info_fields.slot_dimension)
    local data_table = info and raw_property_value(info, fitem_info_fields.data_table) or nil

    return {
        info = info,
        item_id_key = item_id_key,
        item_id_summary = value_summary(item_id),
        unique_id = unique_id,
        count = count,
        max_stack = max_stack,
        can_stack = can_stack,
        is_empty = is_empty,
        slot_index = slot_index,
        slot_vector = slot_vector,
        data_table = data_table,
    }
end

local function is_real_item_slot(slot)
    if slot == nil or is_null_object(slot) then
        return false
    end

    local snapshot = get_slot_item_snapshot(slot)
    if snapshot.is_empty == true then
        return false
    end
    if snapshot.unique_id ~= nil and snapshot.unique_id > 0 and snapshot.item_id_key ~= nil then
        return true
    end
    if snapshot.count ~= nil and snapshot.count > 0 and snapshot.item_id_key ~= nil then
        return true
    end
    return false
end

local function log_slot_brief(slot, prefix)
    if slot == nil or is_null_object(slot) then
        append_log(prefix .. "<null slot>")
        return nil
    end

    local snapshot = get_slot_item_snapshot(slot)
    append_log(prefix ..
        "addr=" .. address_text(slot) ..
        " slotIndex=" .. tostring(snapshot.slot_index) ..
        " empty=" .. tostring(snapshot.is_empty) ..
        " idKey=" .. tostring(snapshot.item_id_key) ..
        " uid=" .. tostring(snapshot.unique_id) ..
        " count=" .. tostring(snapshot.count) ..
        " maxStack=" .. tostring(snapshot.max_stack) ..
        " canStack=" .. tostring(snapshot.can_stack) ..
        " vector=" .. tostring(snapshot.slot_vector) ..
        " mother=" .. value_summary(raw_property_value(slot, "ContainerMother")) ..
        " slotContainer=" .. value_summary(raw_property_value(slot, "SlotContainer")) ..
        " window=" .. value_summary(raw_property_value(slot, "WindowContainer")))
    return snapshot
end

local function container_slot_array(container)
    local found, slots = non_null_property(container, "WSlots")
    if found then
        return slots
    end
    return nil
end

local function collect_container_slot_items(container)
    local slots = container_slot_array(container)
    local len = array_num(slots)
    local items = {}
    local empty_slots = {}
    if not len then
        return items, empty_slots, 0
    end

    for index = 1, len do
        local ok, slot = array_get(slots, index)
        if ok and slot ~= nil and not is_null_object(slot) then
            local snapshot = get_slot_item_snapshot(slot)
            if is_real_item_slot(slot) then
                table.insert(items, { slot = slot, snapshot = snapshot })
            elseif snapshot.is_empty == true and snapshot.slot_index ~= nil then
                table.insert(empty_slots, { slot = slot, snapshot = snapshot })
            end
        end
    end

    return items, empty_slots, len
end

local function collect_container_candidates()
    local ok, containers = pcall(function()
        return FindAllOf("JSIContainer_C")
    end)
    if not ok or not containers then
        return {}
    end

    local candidates = {}
    for index = 1, #containers do
        local container = containers[index]
        local slots = container_slot_array(container)
        local slot_count = array_num(slots)
        if slot_count and slot_count > 0 then
            local owner = safe_call(function()
                local owner_ok, owner_value = call_method(container, "GetOwningPlayer")
                if owner_ok then
                    return owner_value
                end
                return nil
            end, nil)
            local visible = bool_method(container, "IsVisible")
            local focus_desc = bool_method(container, "HasFocusedDescendants")
            local visibility_prop = raw_property_summary(container, "Visibility")
            if visible or focus_desc or not is_null_object(owner) or visibility_prop == "0" then
                local items, empty_slots = collect_container_slot_items(container)
                table.insert(candidates, {
                    index = index,
                    container = container,
                    slot_count = slot_count,
                    item_count = #items,
                    empty_count = #empty_slots,
                    owner = owner,
                    visible = visible,
                    focus_desc = focus_desc,
                    visibility = visibility_prop,
                    container_id = number_property(container, "ContainerID"),
                    parent_id = number_property(container, "ParentID"),
                    cols = number_property(container, "NumberOfColumns"),
                    rows = number_property(container, "NumberOfRows"),
                    mp = raw_property_value(container, "JigMultiplayerComp"),
                    items = items,
                    empty_slots = empty_slots,
                })
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.slot_count == b.slot_count then
            if a.item_count == b.item_count then
                return tostring(a.container_id) < tostring(b.container_id)
            end
            return a.item_count > b.item_count
        end
        return a.slot_count > b.slot_count
    end)

    return candidates
end

local function log_container_candidate(candidate, prefix, max_items)
    append_log(prefix ..
        "containerAddr=" .. address_text(candidate.container) ..
        " containerID=" .. tostring(candidate.container_id) ..
        " parentID=" .. tostring(candidate.parent_id) ..
        " slots=" .. tostring(candidate.slot_count) ..
        " items=" .. tostring(candidate.item_count) ..
        " empty=" .. tostring(candidate.empty_count) ..
        " cols=" .. tostring(candidate.cols) ..
        " rows=" .. tostring(candidate.rows) ..
        " visible=" .. tostring(candidate.visible) ..
        " focusDesc=" .. tostring(candidate.focus_desc) ..
        " visibility=" .. tostring(candidate.visibility) ..
        " owner=" .. address_text(candidate.owner) ..
        " mp=" .. value_summary(candidate.mp))

    for item_index = 1, math.min(#candidate.items, max_items or 8) do
        log_slot_brief(candidate.items[item_index].slot, prefix .. "  item[" .. tostring(item_index) .. "] ")
    end
end

local function probe_slot_contents()
    append_log("Container slot content probe started")
    append_log("Slot item struct reads are disabled. UE4SS crashed while auto-constructing ItemInfo/slot UObject values on this game build.")
    append_log("Next safe path is offset-based custom properties, not reflected struct traversal.")
    append_log("Container slot content probe finished")
end

local function build_item_key_set(candidate)
    local set = {}
    for _, item in ipairs(candidate.items) do
        local key = item.snapshot.item_id_key
        if key ~= nil then
            set[key] = true
        end
    end
    return set
end

local function quickstack_dry_run()
    append_log("")
    append_log("============================================================")
    append_log("QuickStack dry-run started. No item movement will be performed.")
    append_log("============================================================")

    append_log("QuickStack dry-run is temporarily disabled after the ItemInfo struct-read crash.")
    append_log("No item movement or slot traversal was performed.")
    append_log("QuickStack dry-run finished")
end

local replicated_container_fields = {
    "ActorUID_28_EB27D09649B6E02591DCA98708B06332",
    "MainContainerUID_2_DD5641AA43979D881976F6A78AE96630",
    "ReplicationUID_2_EB27D09649B6E02591DCA98708B06332",
    "InContainerUID_19_D1504ED7438699C73EA046AD734E79BF",
    "InUID9_D1504ED7438699C73EA046AD734E79BF",
    "ContainerIndex_22_9A211B86466A9D1C57E1FC839A5B0896",
    "Columns_4_1D84448048078D988999ABA138CE1809",
    "Rows_6_78B4BC5B449017D63758E79844375AE9",
    "Items_16_16E3D87B4C0AC5D6C9C861B96B5ABA8B",
    "Slot3_97B5C4324E23EC5C1D899EA59CCDD3AC",
    "MainsIDs_36_9D84D2CB451E9E8269A7FAB8D86BC5E1",
}

local item_fields = {
    "ItemID_2_01CA27D84AF7D1014D9E2E83894C1848",
    "ID_2_A45B60654D588805C5D52BA4BC5CD4FD",
    "ID_8_A4671602429751065B0F1A847C871333",
    "Count_8_DD79AF2A46126A338C8DCCB4616D91CD",
    "Count_8_E62F0FA548FC7DB0BDB860B4C0D695B6",
    "Count_4_3A0BA4F14039FFC27BBB0DA42FD44C10",
    "MaxStack_41_AAD92B96405F302224DC958A7D7A26C9",
    "ItemVec_13_4DB12E4E4F80730BD25ACFA6FA51AD0A",
    "Column_8_9DA4613F40CC2041C80ABCB18A87215D",
    "Row_9_CA37F3CADEDF5689CFC291998901F8",
}

local function log_struct_selected_fields(value, prefix, fields)
    if value == nil or is_null_object(value) then
        append_log(prefix .. "<null>")
        return false
    end

    append_log(prefix .. "summary=" .. value_summary(value) .. " type=" .. tostring(ue_type(value)))
    local found_any = false
    for _, field_name in ipairs(fields) do
        local found, field_value = non_null_property(value, field_name)
        if found then
            found_any = true
            append_log(prefix .. field_name .. " = " .. value_summary(field_value))
        end
    end
    if not found_any then
        append_log(prefix .. "no non-null selected fields")
    end
    return found_any
end

local function log_array_shallow(array_value, prefix, item_field_list, max_items)
    local num = array_num(array_value)
    local max = array_max(array_value)
    if num == nil then
        append_log(prefix .. "not a sane TArray: " .. value_summary(array_value))
        return
    end

    append_log(prefix .. "array len=" .. tostring(num) .. " max=" .. tostring(max))
    for index = 1, math.min(num, max_items or 8) do
        local ok, element = array_get(array_value, index)
        if ok then
            if type(element) == "number" or type(element) == "string" or type(element) == "boolean" then
                append_log(prefix .. "[" .. tostring(index) .. "] = " .. tostring(element))
            else
                log_struct_selected_fields(element, prefix .. "[" .. tostring(index) .. "] ", item_field_list)
            end
        else
            append_log(prefix .. "[" .. tostring(index) .. "] <unavailable>")
        end
    end
end

local function probe_replication_class(class_name)
    local ok, objects = pcall(function()
        return FindAllOf(class_name)
    end)
    if not ok or not objects or #objects == 0 then
        return
    end

    append_log("FindAllOf(" .. class_name .. ") -> " .. tostring(#objects))
    local interesting = 0
    for index = 1, math.min(#objects, 25) do
        local object = objects[index]
        local prefix = "  [" .. class_name .. " #" .. tostring(index) .. "] "
        local found_main_repl, main_repl = non_null_property(object, "MainReplicatedContainers")
        local found_main_ids, main_ids = non_null_property(object, "MainContainersIDs")
        local found_repl, repl = non_null_property(object, "ReplicatedContainers")
        local main_repl_len = found_main_repl and array_num(main_repl) or nil
        local main_ids_len = found_main_ids and array_num(main_ids) or nil
        local repl_len = found_repl and array_num(repl) or nil

        if (main_repl_len and main_repl_len > 0) or (main_ids_len and main_ids_len > 0) or (repl_len and repl_len > 0) then
            interesting = interesting + 1
            append_log(prefix .. "addr=" .. address_text(object) ..
                " outer=" .. value_summary(outer_object(object)) ..
                " MainReplicatedContainers=" .. tostring(main_repl_len) ..
                " MainContainersIDs=" .. tostring(main_ids_len) ..
                " ReplicatedContainers=" .. tostring(repl_len))

            log_object_details(object, prefix, true)

            if found_main_ids then
                log_array_shallow(main_ids, prefix .. "MainContainersIDs ", item_fields, 12)
            end
            if found_main_repl then
                log_array_shallow(main_repl, prefix .. "MainReplicatedContainers ", replicated_container_fields, 12)
            end
            if found_repl and repl_len and repl_len > 0 then
                log_array_shallow(repl, prefix .. "ReplicatedContainers ", replicated_container_fields, 8)
            end
        end
    end

    append_log(class_name .. " interesting replication objects: " .. tostring(interesting))
end

local function probe_replication_objects()
    append_log("Replication/container data probe started")
    probe_replication_class("BP_JigMultiplayer_C")
    probe_replication_class("BP_NetworkReplication_C")
    probe_replication_class("BP_JigMPComponentSave_C")
    append_log("Replication/container data probe finished")
end

local function fname_index(name)
    return safe_call(function()
        local fname
        if EFindName and EFindName.FNAME_Find then
            fname = FName(name, EFindName.FNAME_Find)
        else
            fname = FName(name)
        end
        if fname and fname.GetComparisonIndex then
            return fname:GetComparisonIndex()
        end
        return nil
    end, nil)
end

local candidate_function_names = {
    "AddItem",
    "AddItemToContainer",
    "AddToContainer",
    "AddToSlot",
    "Clear",
    "ClearItem",
    "ClearSlot",
    "Construct",
    "Destruct",
    "Drop",
    "Init",
    "Initialize",
    "MoveItem",
    "MoveItemToContainer",
    "MoveItemToIndex",
    "OnDragCancelled",
    "OnDragDetected",
    "OnButtonDown",
    "OnDrop",
    "OnMouseButtonDown",
    "OnMouseButtonUp",
    "PreConstruct",
    "Refresh",
    "RefreshContainer",
    "RefreshInventory",
    "RefreshJigsaw",
    "RefreshSlot",
    "RefreshSlots",
    "RemoveFromContainer",
    "RemoveFromParent",
    "RemoveItem",
    "RemoveItemFromContainer",
    "RemoveItemFromSlot",
    "RemoveSlot",
    "Reset",
    "SetEmpty",
    "SetInfo",
    "SetItem",
    "SetItemInfo",
    "SetSlot",
    "SetSlotInfo",
    "SetVisibility",
    "Tick",
    "TransferItem",
    "TryMoveItem",
    "Update",
    "GetC_Count",
    "UpdateContainer",
    "UpdateInventory",
    "UpdateItem",
    "UpdateItemPosition",
    "UpdateJigSlot",
    "UpdateSlot",
    "UpdateSlots",
    "UpdateSlotWidget",
}

local function probe_class_functions()
    append_log("Candidate UFunction probe started")
    local wanted = {}
    for _, name in ipairs(candidate_function_names) do
        local index = fname_index(name)
        if index ~= nil then
            wanted[index] = name
        end
    end

    for _, class_name in ipairs({
        "IngameMenuContainerWidgetBP_C",
        "IngameContainerWidgetBP_C",
        "JSIContainer_C",
        "JSI_Slot_C",
        "ContainerWindowWidget_C",
        "JigContextMenuCanvas_C",
        "DropItemBackGwidget_C",
        "DropItemAmountSelector_C",
        "JigSDragOperation_C",
        "HoverDragOperation_C",
        "DragWidget_C",
        "JigSplitWidget_C",
        "JigContextMenuW_C",
        "JigContextMenuComp_C",
        "BP_JigMultiplayer_C",
        "BP_NetworkReplication_C",
    }) do
        local ok, objects = pcall(function()
            return FindAllOf(class_name)
        end)
        if ok and objects and #objects > 0 then
            local class = safe_call(function()
                return objects[1]:GetClass()
            end, nil)
            if class and class.ForEachFunction then
                local found = {}
                safe_call(function()
                    class:ForEachFunction(function(function_object)
                        local index = safe_call(function()
                            return function_object:GetFName():GetComparisonIndex()
                        end, nil)
                        if index and wanted[index] then
                            table.insert(found, wanted[index] .. "@" .. address_text(function_object))
                        end
                        return false
                    end)
                end, nil)
                if #found > 0 then
                    append_log("  " .. class_name .. " matched functions: " .. table.concat(found, ", "))
                else
                    append_log("  " .. class_name .. " matched functions: <none>")
                end
            end
        end
    end
    append_log("Candidate UFunction probe finished")
end

local hook_paths = {
    -- Narrow game Blueprint hooks only. Broad native UMG drag hooks can freeze this game build.
    "/Game/JigSInventory/Jigsaw/Components/BP_JigMultiplayer.BP_JigMultiplayer_C:SERVER_RequestStackItem",
    "/Game/JigSInventory/Jigsaw/Components/BP_JigMultiplayer.BP_JigMultiplayer_C:SERVER_RequestMoveItemToAnotherComp",
    "/Game/JigSInventory/Jigsaw/Components/BP_JigMultiplayer.BP_JigMultiplayer_C:SERVER_SameContainer_MoveToIndex",
    "/Game/JigSInventory/Jigsaw/Components/BP_JigMultiplayer.BP_JigMultiplayer_C:CLIENT_MoveItemToIndex",
    "/Game/JigSInventory/Jigsaw/Components/BP_JigMultiplayer.BP_JigMultiplayer_C:MC_MoveItemToIndex",
    "/Game/JigSInventory/Jigsaw/Components/BP_JigMultiplayer.BP_JigMultiplayer_C:CLIENT_UpdateStack",
    "/Game/JigSInventory/Jigsaw/Components/BP_JigMultiplayer.BP_JigMultiplayer_C:MC_UpdateStack",
    "/Game/JigSInventory/Jigsaw/Components/BP_JigMultiplayer.BP_JigMultiplayer_C:CLIENT_ItemRemoved",
    "/Game/JigSInventory/Jigsaw/Components/BP_JigMultiplayer.BP_JigMultiplayer_C:MC_ItemRemoved",
    "/Game/JigSInventory/Jigsaw/Components/BP_JigMultiplayer.BP_JigMultiplayer_C:CLIENT_NewItemAdded",
    "/Game/JigSInventory/Jigsaw/Components/BP_JigMultiplayer.BP_JigMultiplayer_C:MC_NewItemAdded",
    "/Game/JigSInventory/Jigsaw/Components/BP_JigMultiplayer.BP_JigMultiplayer_C:CLIENT_UpdateCount",
    "/Game/JigSInventory/Jigsaw/Components/BP_JigMultiplayer.BP_JigMultiplayer_C:MC_UpdateCount",
    "/Game/JigSInventory/Jigsaw/Components/BP_JigMultiplayer.BP_JigMultiplayer_C:HandleClientMoveItemToIndex",
    "/Game/JigSInventory/Jigsaw/Components/BP_JigMultiplayer.BP_JigMultiplayer_C:Handle Comp to Comp Move",
    "/Game/JigSInventory/Jigsaw/Widgets/JSIContainer.JSIContainer_C:RemoveItemByUniqueID",
    "/Game/JigSInventory/Jigsaw/Widgets/JSIContainer.JSIContainer_C:RemoveInventoryItemByRef",
    "/Game/JigSInventory/Jigsaw/Widgets/JSIContainer.JSIContainer_C:ClearItemFromArr",
    "/Game/JigSInventory/Jigsaw/Widgets/JSIContainer.JSIContainer_C:AddItemFromJigRef",
    "/Game/JigSInventory/Jigsaw/Widgets/JSIContainer.JSIContainer_C:MoveItemToIndexByItemRef",
    "/Game/JigSInventory/Jigsaw/Widgets/JSIContainer.JSIContainer_C:PerfromDrop",
    "/Game/JigSInventory/Jigsaw/Widgets/JSIContainer.JSIContainer_C:OnDrop",
    "/Game/JigSInventory/Jigsaw/Widgets/JSIContainer.JSIContainer_C:HandleContainerOnContainer",
    "/Game/JigSInventory/Jigsaw/Widgets/JSIContainer.JSIContainer_C:EventOnInventoryAction",
    "/Game/JigSInventory/Jigsaw/Widgets/JSIContainer.JSIContainer_C:CombineItemRequest",
    "/Game/JigSInventory/Jigsaw/Widgets/JSI_Slot.JSI_Slot_C:ClearSlot",
    "/Game/JigSInventory/Jigsaw/Widgets/JSI_Slot.JSI_Slot_C:RemoveFromJSIParent",
    "/Game/JigSInventory/Jigsaw/Widgets/JSI_Slot.JSI_Slot_C:OnDrop",
}

local registered_hooks = {}
local hook_hit_counts = {}

local function log_hook_param(prefix, value)
    value = unwrap_param(value)
    append_log(prefix .. value_summary(value))
end

local function make_hook_callback(path)
    return function(context, ...)
        hook_hit_counts[path] = (hook_hit_counts[path] or 0) + 1
        local count = hook_hit_counts[path]
        if count > MAX_HOOK_HITS_PER_PATH then
            if count == MAX_HOOK_HITS_PER_PATH + 1 then
                append_log("HOOK " .. path .. " reached logging cap")
            end
            return
        end

        append_log("HOOK HIT #" .. tostring(count) .. ": " .. path)
        log_hook_param("  context = ", context)

        local param_count = select("#", ...)
        append_log("  param_count = " .. tostring(param_count))
        for index = 1, math.min(param_count, 12) do
            local param = select(index, ...)
            log_hook_param("  param[" .. tostring(index) .. "] = ", param)
        end

        if string.find(path, "SERVER_RequestMoveItemToAnotherComp", 1, true) then
            append_log("  decoded SERVER_RequestMoveItemToAnotherComp: " ..
                "FromComp=" .. value_summary(unwrap_param(select(1, ...))) ..
                " ToComp=" .. value_summary(unwrap_param(select(2, ...))) ..
                " ItemUID=" .. tostring(unwrap_param(select(3, ...))) ..
                " FinalRotation=" .. tostring(unwrap_param(select(4, ...))) ..
                " ToIndex=" .. tostring(unwrap_param(select(5, ...))) ..
                " ToContainerUID=" .. tostring(unwrap_param(select(6, ...))) ..
                " VendorAmount=" .. tostring(unwrap_param(select(7, ...))) ..
                " VendorMoneyToUID=" .. tostring(unwrap_param(select(8, ...))) ..
                " VendorMoneyToIndex=" .. tostring(unwrap_param(select(9, ...))))
        elseif string.find(path, "SERVER_RequestStackItem", 1, true) then
            append_log("  decoded SERVER_RequestStackItem: " ..
                "FromComp=" .. value_summary(unwrap_param(select(1, ...))) ..
                " ToComp=" .. value_summary(unwrap_param(select(2, ...))) ..
                " DroppedUID=" .. tostring(unwrap_param(select(3, ...))) ..
                " ReceiverUID=" .. tostring(unwrap_param(select(4, ...))) ..
                " MaxStack=" .. tostring(unwrap_param(select(5, ...))))
        elseif string.find(path, "MoveItemToIndex", 1, true) then
            append_log("  decoded MoveItemToIndex: " ..
                "ItemUID=" .. tostring(unwrap_param(select(1, ...))) ..
                " ToContainerUID=" .. tostring(unwrap_param(select(2, ...))) ..
                " ToIndex=" .. tostring(unwrap_param(select(3, ...))) ..
                " FinalRotation=" .. tostring(unwrap_param(select(4, ...))))
        elseif string.find(path, "UpdateStack", 1, true) then
            append_log("  decoded UpdateStack: " ..
                "DroppedUID=" .. tostring(unwrap_param(select(1, ...))) ..
                " DropNewCount=" .. tostring(unwrap_param(select(2, ...))) ..
                " ReceiverUID=" .. tostring(unwrap_param(select(3, ...))) ..
                " ReceiverNewCount=" .. tostring(unwrap_param(select(4, ...))))
        end
    end
end

local function static_find_summary(path)
    return safe_call(function()
        if not StaticFindObject then
            return "<StaticFindObject unavailable>"
        end
        local object = StaticFindObject(path)
        if object == nil or is_null_object(object) then
            return "<not found>"
        end
        return value_summary(object)
    end, "<find failed>")
end

local function register_hook_candidates()
    if not RegisterHook then
        append_log("RegisterHook unavailable")
        return
    end

    if #hook_paths == 0 then
        append_log("Hook registration skipped: snapshot-only safe mode is active")
        return
    end

    append_log("Hook registration probe started")
    for _, path in ipairs(hook_paths) do
        if not registered_hooks[path] then
            local static_summary = static_find_summary(path)
            append_log("  candidate " .. path .. " static=" .. static_summary)
            if static_summary ~= "<not found>" and static_summary ~= "<find failed>" and static_summary ~= "<StaticFindObject unavailable>" then
                local ok, pre_id, post_id = pcall(function()
                    local callback = make_hook_callback(path)
                    if string.sub(path, 1, 8) == "/Script/" then
                        return RegisterHook(path, callback, callback)
                    end
                    return RegisterHook(path, callback)
                end)
                if ok and pre_id then
                    registered_hooks[path] = { pre = pre_id, post = post_id }
                    append_log("  registered " .. path .. " pre=" .. tostring(pre_id) .. " post=" .. tostring(post_id))
                else
                    append_log("  register failed " .. path .. " error=" .. tostring(pre_id))
                end
            else
                append_log("  skipped " .. path .. " because the UFunction is not loaded/found")
            end
        end
    end
    append_log("Hook registration probe finished")
end

local function find_by_name_scan()
    append_log("Name scan skipped. UObject:GetFullName/FName:ToString crashed this game build earlier.")
end

local function dump_probe_snapshot(reason)
    append_log("")
    append_log("============================================================")
    append_log("Probe snapshot: " .. reason)
    append_log("Open a container in-game before taking a diagnostic snapshot. No drag/drop hook is active in this build.")
    append_log("============================================================")
    register_hook_candidates()
    find_by_class()
    probe_widgets_by_activity()
    probe_context_objects()
    probe_slot_contents()
    probe_replication_objects()
    probe_class_functions()
    find_by_name_scan()
    append_log("Snapshot finished")
end

local function try_dump_all_objects()
    append_log("UE4SS object dump is disabled because UObject name dumping can crash this game build.")
end

local function try_generate_sdk()
    append_log("")
    append_log("============================================================")
    append_log("GenerateSDK requested. This may pause the game while UE4SS writes CXXHeaderDump.")
    append_log("============================================================")

    if not GenerateSDK then
        append_log("GenerateSDK unavailable in this UE4SS build")
        return
    end

    local ok, err = pcall(function()
        GenerateSDK()
    end)

    if ok then
        append_log("GenerateSDK finished")
    else
        append_log("GenerateSDK failed: " .. tostring(err))
    end
end

local function register_probe_key(key, modifiers, callback)
    if RegisterKeyBindAsync then
        if IsKeyBindRegistered and IsKeyBindRegistered(key, modifiers) then
            append_log("Keybind is already registered, skipping duplicate registration")
            return
        end
        RegisterKeyBindAsync(key, modifiers, callback)
        return
    end

    if RegisterKeyBind then
        RegisterKeyBind(key, modifiers, callback)
        return
    end

    append_log("No UE4SS keybind registration function is available")
end

append_log("Loaded v" .. MOD_VERSION .. ". Hotkey: Ctrl+F9 = QuickStack matching inventory stacks into the opened container.")

if QUICKSTACK_DEBUG_MODE then
    ExecuteInGameThread(function()
        register_hook_candidates()
    end)
end

if Key and ModifierKey then
    if Key.F9 then
        register_probe_key(Key.F9, { ModifierKey.CONTROL }, function()
            ExecuteInGameThread(function()
                run_quickstack_full()
            end)
        end)
    else
        append_log("Ctrl+F9 QuickStack hotkey unavailable: Key.F9 is not defined by this UE4SS build")
    end
else
    append_log("Key/ModifierKey is unavailable. Ensure the UE4SS Keybinds mod is enabled.")
end
