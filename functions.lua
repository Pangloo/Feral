local enums = require("common/enums")
local menu = require("menu")
local spells = require("spells")
local lists = require("lists")
local target_selector = require("common/modules/target_selector")
local health_pred = require("common/modules/health_prediction")
local buff_manager = require("common/modules/buff_manager")
local unit_helper = require("common/utility/unit_helper")
local spell_helper = require("common/utility/spell_helper")

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

function Functions.has_debuff(unit, debuff_id)
    if not unit or not unit:is_valid() then return false end
    if type(debuff_id) == "number" then
        debuff_id = { debuff_id }
    end
    local debuff_info = buff_manager:get_debuff_data(unit, debuff_id)
    return debuff_info and debuff_info.is_active == true
end

function Functions.has_buff(unit, buff_id)
    if not unit or not unit:is_valid() then return false end
    if type(buff_id) == "number" then
        buff_id = { buff_id }
    end
    local buff_info = buff_manager:get_buff_data(unit, buff_id)
    return buff_info and buff_info.is_active == true
end

local cached_dps_target = nil
local cached_dps_target_valid = false
local cached_party = {}
local cached_enemies = {}
local last_party_scan = 0
local last_enemy_scan = 0
local dispel_queue = {}
local last_dispel_check = 0
local last_motw_check = 0
local motw_cast_time = 0
local motw_is_missing = false

local ttd_cache = {}
local last_ttd_clear = 0

function Functions.get_time_to_die(unit)
    if not unit or not unit:is_valid() or unit:is_dead() then return 0 end
    if unit_helper:is_boss(unit) then return 9999 end

    local guid = tostring(unit:get_guid())
    local now = core.time()

    -- Cleanup cache every 30 seconds
    if now - last_ttd_clear > 30000 then
        for k, v in pairs(ttd_cache) do
            if now - v.last_seen > 15000 then
                ttd_cache[k] = nil
            end
        end
        last_ttd_clear = now
    end

    local health = unit:get_health()
    local max_health = unit:get_max_health()
    if max_health == 0 then return 9999 end
    local health_pct = unit:get_health_percentage()

    if not ttd_cache[guid] then
        ttd_cache[guid] = { history = {}, last_seen = now }
    end

    ttd_cache[guid].last_seen = now
    local history = ttd_cache[guid].history

    -- Insert once every 500ms to avoid bloating
    if #history == 0 or (now - history[#history].time >= 500) then
        table.insert(history, { time = now, health = health })
    end

    -- Keep only the last 8 seconds of history
    while #history > 0 and (now - history[1].time > 8000) do
        table.remove(history, 1)
    end

    -- Fallback TTD based on health percentage if history isn't useful
    -- We assume roughly 1.5% health loss per second as a conservative estimate for new targets
    local fallback_ttd = health_pct / 1.5
    if health_pct > 50 then fallback_ttd = 9999 end

    if #history < 2 then
        return fallback_ttd
    end

    local first = history[1]
    local last = history[#history]

    local time_diff = (last.time - first.time) / 1000.0
    if time_diff <= 0.5 then
        return fallback_ttd
    end

    local health_diff = first.health - last.health
    if health_diff <= 0 then
        -- No recent damage detected.
        -- If health is high (e.g. boss pooling), assume it will live.
        -- If health is low, use the fallback to avoid wasting CDs.
        return health_pct > 30 and 9999 or fallback_ttd
    end

    local dps = health_diff / time_diff
    if dps <= 0 then return fallback_ttd end

    return last.health / dps
end

function Functions.get_group_time_to_die(range)
    local enemies = Functions.get_all_enemies_in_range(range)
    if #enemies == 0 then return 0 end

    local max_ttd = 0
    for _, e in ipairs(enemies) do
        local ttd = Functions.get_time_to_die(e)
        if ttd > max_ttd then
            max_ttd = ttd
        end
    end
    return max_ttd
end

function Functions.validate_unit(unit, range)
    if not unit or not unit:is_valid() or unit:is_dead() or not (unit:is_party_member() or unit:is_unit(core.object_manager.get_local_player())) then return false end
    if range then
        local me = core.object_manager.get_local_player()
        local dist = unit:distance()
        if me then
            dist = math.max(0, dist - unit:get_bounding_radius() - me:get_bounding_radius())
        end
        if dist > range then return false end
    end
    return true
end

function Functions.update_party_cache()
    local now = core.time()
    if now - last_party_scan >= 0.2 then
        last_party_scan = now
        cached_party = unit_helper:get_ally_list_around(core.object_manager.get_local_player():get_position(), 40, true,
            true)
    end
end

local function Chimaeruscheck(obj)
    local me = core.object_manager.get_local_player()
    if not me then return false end
    local has_phase_buff = Functions.has_buff(obj, 1245727)
    local has_phase_debuff = Functions.has_debuff(me, 1245698)

    if has_phase_debuff then return has_phase_buff end
    if has_phase_buff then return false end

    return true
end

function Functions.update_enemy_cache()
    local now = core.time()
    if now - last_enemy_scan >= 0.2 then
        last_enemy_scan = now
        cached_enemies = {}
        local me = core.object_manager.get_local_player()
        if not me then return end

        local objects = core.object_manager.get_visible_objects()
        for _, obj in ipairs(objects) do
            if obj:is_valid() and obj:is_unit() and not obj:is_dead() and me:can_attack(obj) and (me:get_threat_situation(obj) ~= nil or lists.THREAT_BYPASS_UNITS[obj:get_npc_id()]) then
                local is_blacklisted = false
                local npc_id = obj:get_npc_id()
                if lists.ENEMY_BLACKLIST_WITH_BUFFS and lists.ENEMY_BLACKLIST_WITH_BUFFS[npc_id] then
                    for _, buff_id in ipairs(lists.ENEMY_BLACKLIST_WITH_BUFFS[npc_id]) do
                        if Functions.get_buff_remains(obj, buff_id) > 0 then
                            is_blacklisted = true
                            break
                        end
                    end
                end

                if not is_blacklisted and Chimaeruscheck(obj) then
                    table.insert(cached_enemies, obj)
                end
            end
        end
    end
end

function Functions.get_cached_party()
    return cached_party
end

function Functions.validate_enemy(unit, spell_id, facing)
    if not unit or not unit:is_valid() or unit:is_dead() or unit:is_player() then return false end

    local npc_id = unit:get_npc_id()
    if lists.ENEMY_BLACKLIST_WITH_BUFFS and lists.ENEMY_BLACKLIST_WITH_BUFFS[npc_id] then
        for _, buff_id in ipairs(lists.ENEMY_BLACKLIST_WITH_BUFFS[npc_id]) do
            if Functions.get_buff_remains(unit, buff_id) > 0 then
                return false
            end
        end
    end

    if not Chimaeruscheck(unit) then
        return false
    end

    local me = core.object_manager.get_local_player()
    if spell_id then
        if not spell_helper:is_spell_in_range(spell_id, unit, me:get_position(), unit:get_position()) then
            return false
        end
    end

    if me and facing and not me:is_looking_at(unit) then return false end
    return true
end

function Functions.get_enemies_around_me(range)
    local raw_enemies = {}
    local me = core.object_manager.get_local_player()
    local checkspell = spells.SHRED.id
    if not me then return raw_enemies end
    if range == 8 then checkspell = spells.THRASH_CAT.id end

    for _, obj in ipairs(cached_enemies) do
        if obj:is_valid() and not obj:is_dead() then
            if spell_helper:is_spell_in_range(checkspell, obj, me:get_position(), obj:get_position()) then
                table.insert(raw_enemies, obj)
            end
        end
    end
    return raw_enemies
end

function Functions.get_dps_target(range)
    range = range or 5
    local me = core.object_manager.get_local_player()
    local target = me:get_target()
    local spell_target = spells.SHRED.id
    if target and Functions.validate_enemy(target, spell_target, true) then
        return target
    end
    -- Fallback to nearest
    local raw_enemies = Functions.get_enemies_around_me(range)
    local best_enemy = nil
    local min_dist = 999
    for _, enemy in ipairs(raw_enemies) do
        local spell_target = spells.SHRED.id
        if Functions.validate_enemy(enemy, spell_target, true) then
            local dist = enemy:distance()
            if me then
                dist = math.max(0, dist - enemy:get_bounding_radius() - me:get_bounding_radius())
            end
            if dist < min_dist then
                min_dist = dist
                best_enemy = enemy
            end
        end
    end
    return best_enemy
end

function Functions.count_enemies_in_range(range)
    local raw_enemies = Functions.get_enemies_around_me(range)
    local count = 0
    for _, enemy in ipairs(raw_enemies) do
        local spell_target = spells.THRASH_CAT.id
        if Functions.validate_enemy(enemy, spell_target, false) then
            count = count + 1
        end
    end
    return math.max(1, count)
end

function Functions.get_all_enemies_in_range(range, spell_id)
    local raw_enemies = Functions.get_enemies_around_me(range)
    local enemies = {}
    for _, enemy in ipairs(raw_enemies) do
        local target_spell = spell_id or spells.THRASH_CAT.id
        local facingcheck = true
        if spell_id == spells.PRIMAL_WRATH.id then
            facingcheck = false
        end
        if Functions.validate_enemy(enemy, target_spell, facingcheck) then
            table.insert(enemies, enemy)
        end
    end
    return enemies
end

function Functions.get_best_dot_target(debuff_id, spell_id, refresh_time, current_target, min_ttd)
    min_ttd = min_ttd or 0
    local facingcheck = true
    if spell_id == spells.PRIMAL_WRATH.id then
        facingcheck = false
    end
    if current_target and Functions.validate_enemy(current_target, spell_id, facingcheck) then
        if Functions.get_debuff_remains(current_target, debuff_id) < refresh_time and Functions.get_time_to_die(current_target) >= min_ttd then
            return current_target
        end
    end

    local search_range = 8
    if spell_id == spells.MOONFIRE_CAT.id then
        search_range = 40
    end
    local enemies = Functions.get_all_enemies_in_range(search_range, spell_id)
    local best_target = nil
    local min_remains = 999

    for _, e in ipairs(enemies) do
        local rem = Functions.get_debuff_remains(e, debuff_id)
        if rem < refresh_time and rem < min_remains and Functions.get_time_to_die(e) >= min_ttd then
            min_remains = rem
            best_target = e
        end
    end

    return best_target
end

function Functions.any_missing_rip(range, threshold, min_ttd)
    local raw_enemies = Functions.get_enemies_around_me(range)
    for _, enemy in ipairs(raw_enemies) do
        if Functions.validate_enemy(enemy, spells.THRASH_CAT.id, false) then
            local remains = Functions.get_debuff_remains(enemy, lists.DEBUFFS.RIP)
            if remains < (threshold or 5) and Functions.get_time_to_die(enemy) >= (min_ttd or 7) then
                return true
            end
        end
    end
    return false
end

local interrupt_cache = {}
local last_interrupt_clear = 0

function Functions.get_interrupt_target(range)
    local raw_enemies = Functions.get_enemies_around_me(range)
    local now = core.game_time()
    local real_now = core.time()

    if real_now - last_interrupt_clear > 15000 then
        interrupt_cache = {}
        last_interrupt_clear = real_now
    end

    for _, enemy in ipairs(raw_enemies) do
        local spell_target = spells.SKULL_BASH.id
        if Functions.validate_enemy(enemy, spell_target, false) then
            if enemy:is_casting_spell() and enemy:is_active_spell_interruptable() then
                local start_time = enemy:get_active_spell_cast_start_time()
                local end_time = enemy:get_active_spell_cast_end_time()
                if start_time and end_time and end_time > start_time then
                    local identifier = tostring(enemy:get_guid()) .. "_" .. tostring(start_time)
                    if not interrupt_cache[identifier] then
                        interrupt_cache[identifier] = math.random(30, 75)
                    end
                    local delay = interrupt_cache[identifier]

                    local pct = ((now - start_time) / (end_time - start_time)) * 100
                    if pct >= delay then
                        return enemy
                    end
                end
            elseif enemy:is_channelling_spell() and enemy:is_active_spell_interruptable() then
                local start_time = enemy:get_active_channel_cast_start_time()
                local end_time = enemy:get_active_channel_cast_end_time()
                if start_time and end_time and end_time > start_time then
                    local identifier = tostring(enemy:get_guid()) .. "_channel_" .. tostring(start_time)
                    if not interrupt_cache[identifier] then
                        interrupt_cache[identifier] = math.random(15, 45)
                    end
                    local delay = interrupt_cache[identifier]

                    local pct = ((now - start_time) / (end_time - start_time)) * 100
                    if pct >= delay then
                        return enemy
                    end
                end
            end
        end
    end
    return nil
end

function Functions.check_all_dispels(range)
    if not menu.AUTO_DISPEL or not menu.AUTO_DISPEL:get_toggle_state() then
        return nil, nil, nil
    end

    if not spells.REMOVE_CORRUPTION:is_learned() or not spells.REMOVE_CORRUPTION:cooldown_up() then
        return nil, nil, nil
    end

    -- Throttle expensive aura checks
    local now = core.time()
    if now - last_dispel_check < 0.25 then
        return nil, nil, nil
    end
    last_dispel_check = now

    local me = core.object_manager.get_local_player()
    range = range or 40
    local allies = {}
    table.insert(allies, me)
    for _, ally in ipairs(cached_party) do
        if not ally:is_unit(me) then
            table.insert(allies, ally)
        end
    end

    local current_active = {}
    local ready_ally, ready_buff, ready_type = nil, nil, nil

    for _, ally in ipairs(allies) do
        if Functions.validate_unit(ally, range) then
            local guid = tostring(ally:get_guid())

            -- 1. Check special whitelist
            local auras = ally:get_auras()
            if auras then
                for _, aura in ipairs(auras) do
                    if aura.buff_id and lists.SPECIAL_DISPELS and lists.SPECIAL_DISPELS[aura.buff_id] then
                        local buff_id = aura.buff_id
                        local q_key = guid .. "_" .. tostring(buff_id)
                        current_active[q_key] = true

                        if not dispel_queue[q_key] then
                            dispel_queue[q_key] = now + (math.random(80, 120) / 100)
                        end

                        if not ready_ally and now >= dispel_queue[q_key] then
                            ready_ally, ready_buff, ready_type = ally, buff_id, aura.type
                        end
                    end
                end
            end

            -- 2. Check standard dispellable debuffs (Poison and Curse for Druid)
            local debuffs = ally:get_debuffs()
            if debuffs then
                for _, debuff in pairs(debuffs) do
                    local t = debuff.type
                    if t == enums.buff_type.POISON or t == enums.buff_type.CURSE then
                        local buff_id = debuff.buff_id or 0
                        local q_key = guid .. "_" .. tostring(buff_id)
                        current_active[q_key] = true

                        if not dispel_queue[q_key] then
                            dispel_queue[q_key] = now + (math.random(80, 120) / 100)
                        end

                        if not ready_ally and now >= dispel_queue[q_key] then
                            ready_ally, ready_buff, ready_type = ally, buff_id, t
                        end
                    end
                end
            end
        end
    end

    -- Cleanup queue
    for key, _ in pairs(dispel_queue) do
        if not current_active[key] then
            dispel_queue[key] = nil
        end
    end

    return ready_ally, ready_buff, ready_type
end

function Functions.check_mark_of_the_wild()
    if not spells.MARK_OF_THE_WILD:is_learned() or not spells.MARK_OF_THE_WILD:cooldown_up() then
        return false
    end

    local me = core.object_manager.get_local_player()
    if not me or me:is_mounted() then
        return false
    end

    local now = core.time()

    if now - last_motw_check >= 5 then
        last_motw_check = now
        local party = Functions.get_cached_party()
        local missing_buff = false

        if Functions.get_buff_remains(me, 1126) == 0 then
            missing_buff = true
        else
            for _, ally in ipairs(party) do
                if Functions.validate_unit(ally, 40) then
                    if Functions.get_buff_remains(ally, 1126) == 0 then
                        missing_buff = true
                        break
                    end
                end
            end
        end

        if missing_buff and not motw_is_missing then
            motw_is_missing = true
            motw_cast_time = now + math.random(3, 8)
        elseif not missing_buff then
            motw_is_missing = false
        end
    end

    if motw_is_missing and now >= motw_cast_time then
        motw_is_missing = false
        return spells.MARK_OF_THE_WILD:cast(me, "Mark of the Wild (Missing from party)")
    end

    return false
end

return Functions
