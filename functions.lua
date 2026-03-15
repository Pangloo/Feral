local enums = require("common/enums")
local spells = require("spells")
local lists = require("lists")
local target_selector = require("common/modules/target_selector")
local health_pred = require("common/modules/health_prediction")
local buff_manager = require("common/modules/buff_manager")

local Functions = {}

function Functions.get_debuff_remains(unit, debuff_id)
    if not unit or not unit:is_valid() then return 0 end
    if type(debuff_id) == "number" then
        debuff_id = { debuff_id }
    end
    local debuff_info = buff_manager:get_debuff_data(unit, debuff_id)
    if debuff_info and debuff_info.is_active then
        -- Returns seconds to be compatible with typical simc timing logic
        return debuff_info.remaining / 1000.0
    end
    return 0
end

function Functions.get_buff_remains(unit, buff_id)
    if not unit or not unit:is_valid() then return 0 end
    if type(buff_id) == "number" then
        buff_id = { buff_id }
    end
    local buff_info = buff_manager:get_buff_data(unit, buff_id)
    if buff_info and buff_info.is_active then
        return buff_info.remaining / 1000.0
    end
    return 0
end

local cached_dps_target = nil
local cached_dps_target_valid = false

function Functions.validate_enemy(unit, range)
    if not unit or not unit:is_valid() or unit:is_dead() then return false end
    if range and unit:distance() > range then return false end
    local me = core.object_manager.get_local_player()
    if me and not me:is_looking_at(unit) then return false end
    return true
end

function Functions.get_dps_target(range)
    range = range or 5
    -- always prioritize checking current target first
    local target = core.object_manager.get_local_player():get_target()
    if target and Functions.validate_enemy(target, range) then
         return target
    end
    -- Fallback to nearest
    local raw_enemies = target_selector:get_targets()
    local best_enemy = nil
    local min_dist = 999
    for _, enemy in ipairs(raw_enemies) do
         if Functions.validate_enemy(enemy, range) then
             local dist = enemy:distance()
             if dist < min_dist then
                  min_dist = dist
                  best_enemy = enemy
             end
         end
    end
    return best_enemy
end

function Functions.count_enemies_in_range(range)
    local raw_enemies = target_selector:get_targets()
    local count = 0
    for _, enemy in ipairs(raw_enemies) do
         if Functions.validate_enemy(enemy, range) then
              count = count + 1
         end
    end
    return math.max(1, count)
end

function Functions.get_all_enemies_in_range(range)
    local raw_enemies = target_selector:get_targets()
    local enemies = {}
    for _, enemy in ipairs(raw_enemies) do
         if Functions.validate_enemy(enemy, range) then
              table.insert(enemies, enemy)
         end
    end
    return enemies
end

function Functions.get_best_dot_target(debuff_id, range, refresh_time, current_target)
    if current_target and Functions.validate_enemy(current_target, range) then
        if Functions.get_debuff_remains(current_target, debuff_id) < refresh_time then
            return current_target
        end
    end
    
    local enemies = Functions.get_all_enemies_in_range(range)
    local best_target = nil
    local min_remains = 999
    
    for _, e in ipairs(enemies) do
        local rem = Functions.get_debuff_remains(e, debuff_id)
        if rem < refresh_time and rem < min_remains then
            min_remains = rem
            best_target = e
        end
    end
    
    return best_target
end

return Functions
