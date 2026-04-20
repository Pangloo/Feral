local enums = require("common/enums")
local menu = require("menu")
local spells = require("spells")
local lists = require("lists")
local buff_manager = require("common/modules/buff_manager")
local unit_helper = require("common/utility/unit_helper")
local spell_helper = require("common/utility/spell_helper")

local Functions = {}

-- Wipe a table without creating a new one
local function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

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

local cached_party = {}
local cached_unit_data = {}   -- per-ally: in_los, is_dead
local cached_enemies = {}
local cached_enemy_data = {}  -- per-enemy: in_los, facing, melee_dist
local last_party_scan = 0
local last_enemy_scan = 0
local last_motw_check = 0
local motw_cast_time = 0
local motw_is_missing = false

local ttd_cache = {}
local last_ttd_clear = 0
local TTD_CLEANUP_INTERVAL = 5 -- seconds between cleanup sweeps
local TTD_STALE_TIME = 30      -- seconds before an entry is considered stale
local TTD_HISTORY_WINDOW = 30  -- seconds of history retained for DPS estimate

-- Bosses and miniboss-tier units should never return a short fallback TTD.
-- NOTE: In M+ every trash mob is classified ELITE, so ELITE itself is NOT a
-- signal of "big unit" — only WORLD_BOSS and the boss flag are reliable, plus
-- a max-HP heuristic to catch minibosses that aren't flagged as bosses.
local function is_big_unit(unit, max_health)
    if unit_helper:is_boss(unit) then return true end
    if unit.get_classification then
        local c = unit:get_classification()
        if c == enums.classification.WORLD_BOSS then return true end
    end
    return (max_health or 0) > 15000000
end

function Functions.get_time_to_die(unit)
    if not unit or not unit:is_valid() or unit:is_dead() then return 0 end
    if unit.get_npc_id then
        local npc_id = unit:get_npc_id()
        if lists.TTD_BYPASS_UNITS[npc_id] or lists.BOSS_BYPASS_UNITS[npc_id] then return 9999 end
    end

    local guid = tostring(unit:get_guid())
    local now = core.time() -- seconds

    -- Cleanup cache periodically (seconds, matches Augmentation/Preservation)
    if now - last_ttd_clear > TTD_CLEANUP_INTERVAL then
        for k, v in pairs(ttd_cache) do
            if now - v.last_seen > TTD_STALE_TIME then
                ttd_cache[k] = nil
            end
        end
        last_ttd_clear = now
    end

    local health = unit:get_health()
    local max_health = unit:get_max_health()
    if max_health == 0 then return 9999 end
    local health_pct = unit:get_health_percentage()

    if is_big_unit(unit, max_health) then return 9999 end

    if not ttd_cache[guid] then
        ttd_cache[guid] = { history = {}, last_seen = now }
    end

    ttd_cache[guid].last_seen = now
    local history = ttd_cache[guid].history

    -- Insert once every 500ms (seconds) to avoid bloating
    if #history == 0 or (now - history[#history].time >= 0.5) then
        table.insert(history, { time = now, health = health })
    end

    -- Retain up to TTD_HISTORY_WINDOW seconds of history for stable estimates on big HP pools
    while #history > 0 and (now - history[1].time > TTD_HISTORY_WINDOW) do
        table.remove(history, 1)
    end

    -- Fallback TTD based on health percentage if history isn't useful.
    -- Assumes ~1.5% HP/sec — only safe for brand-new trash. Big units are bypassed above.
    local fallback_ttd = health_pct / 1.5
    if health_pct > 50 then fallback_ttd = 9999 end

    if #history < 2 then
        return fallback_ttd
    end

    local first = history[1]
    local last = history[#history]

    local time_diff = last.time - first.time -- seconds
    if time_diff < 2 then
        return fallback_ttd
    end

    local health_diff = first.health - last.health
    if health_diff <= 0 then
        -- No net damage over the window: unit is pooling, healed, or shielded.
        -- Treat as effectively infinite rather than burning CDs at low HP.
        return 9999
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

local function Chimaeruscheck(obj)
    local me = core.object_manager.get_local_player()
    if not me then return false end
    return me:get_unit_phase() == obj:get_unit_phase()
end

function Functions.validate_unit(unit)
    if not unit or not unit:is_valid() then return false end
    local guid = unit:get_guid()
    local data = cached_unit_data[guid]
    if not data then return false end
    if data.is_dead then return false end
    return data.in_los
end

function Functions.update_party_cache()
    local now = core.time()
    if now - last_party_scan >= 0.2 then
        last_party_scan = now
        local me = core.object_manager.get_local_player()
        if not me then return end
        cached_party = unit_helper:get_ally_list_around(me:get_position(), 40, false, true)
        wipe(cached_unit_data)
        table.insert(cached_party, me)

        local my_guid = me:get_guid()
        local check_spell = spells.REGROWTH.id

        for _, ally in ipairs(cached_party) do
            if ally and ally:is_valid() and Chimaeruscheck(ally) then
                local guid = ally:get_guid()
                local is_dead = ally:is_dead()
                local in_los = false
                if not is_dead then
                    if guid == my_guid then
                        in_los = true
                    else
                        in_los = spell_helper:is_spell_in_line_of_sight(check_spell, me, ally)
                    end
                end
                cached_unit_data[guid] = {
                    in_los = in_los,
                    is_dead = is_dead,
                }
            end
        end
    end
end

function Functions.update_enemy_cache()
    local now = core.time()
    if now - last_enemy_scan >= 0.2 then
        last_enemy_scan = now
        local idx = 0
        local me = core.object_manager.get_local_player()
        if not me then
            wipe(cached_enemies)
            wipe(cached_enemy_data)
            return
        end

        wipe(cached_enemy_data)
        local check_spell = spells.SHRED.id
        local my_bounding = me:get_bounding_radius()
        local blacklist = lists.ENEMY_BLACKLIST_WITH_BUFFS
        local bypass = lists.THREAT_BYPASS_UNITS
        local boss_bypass = lists.BOSS_BYPASS_UNITS

        local my_phase = me:get_unit_phase()
        local objects = core.object_manager.get_visible_objects()
        for _, obj in ipairs(objects) do
            if obj:is_valid() and obj:is_unit() and not obj:is_dead() and me:can_attack(obj) then
                local npc_id = obj:get_npc_id()
                if (me:get_threat_situation(obj) ~= nil and obj:is_in_combat()) or bypass[npc_id] or boss_bypass[npc_id] then
                    if obj:get_unit_phase() == my_phase then
                        local is_blacklisted = false
                        local bl = blacklist and blacklist[npc_id]
                        if bl then
                            for _, buff_id in ipairs(bl) do
                                if Functions.get_buff_remains(obj, buff_id) > 0 then
                                    is_blacklisted = true
                                    break
                                end
                            end
                        end

                        if not is_blacklisted then
                            idx = idx + 1
                            cached_enemies[idx] = obj

                            local guid = obj:get_guid()
                            local in_los = spell_helper:is_spell_in_line_of_sight(check_spell, me, obj)
                            local melee_dist = math.max(0, obj:distance() - obj:get_bounding_radius() - my_bounding)
                            local in_shred_range = core.spell_book.is_spell_in_range(check_spell, obj)
                            cached_enemy_data[guid] = {
                                in_los = in_los,
                                facing = in_los and me:is_looking_at(obj) or false,
                                melee_dist = melee_dist,
                                in_shred_range = in_shred_range and in_los,
                            }
                        end
                    end
                end
            end
        end
        for i = idx + 1, #cached_enemies do
            cached_enemies[i] = nil
        end
    end
end

function Functions.get_cached_party()
    return cached_party
end

-- facing: require facing check; melee_only: restrict to 8yd melee range
function Functions.validate_enemy(unit, facing, melee_only)
    if not unit or not unit:is_valid() then return false end
    local guid = unit:get_guid()
    local data = cached_enemy_data[guid]
    if not data then return false end
    if not data.in_los then return false end
    if facing and not data.facing then return false end
    if melee_only and data.melee_dist > 8 then return false end
    if not melee_only and not data.in_shred_range then return false end
    return true
end

-- range == 8 returns melee enemies, anything else returns shred-range enemies
function Functions.get_enemies_around_me(range)
    local melee = (range == 8)
    local result = {}
    for _, obj in ipairs(cached_enemies) do
        local guid = obj:get_guid()
        local data = cached_enemy_data[guid]
        if data and data.in_los then
            if melee then
                if data.melee_dist <= 8 then
                    result[#result + 1] = obj
                end
            else
                if data.in_shred_range then
                    result[#result + 1] = obj
                end
            end
        end
    end
    return result
end

function Functions.get_dps_target()
    local me = core.object_manager.get_local_player()
    if not me then return nil end
    local target = me:get_target()
    if target and Functions.validate_enemy(target, true) then
        return target
    end
    -- Fallback to nearest melee enemy
    local best_enemy = nil
    local min_dist = 999
    for _, enemy in ipairs(cached_enemies) do
        local guid = enemy:get_guid()
        local data = cached_enemy_data[guid]
        if data and data.in_los and data.facing and data.in_shred_range then
            if data.melee_dist < min_dist then
                min_dist = data.melee_dist
                best_enemy = enemy
            end
        end
    end
    return best_enemy
end

function Functions.count_enemies_in_range(range)
    local melee = (range == 8)
    local count = 0
    for _, enemy in ipairs(cached_enemies) do
        local guid = enemy:get_guid()
        local data = cached_enemy_data[guid]
        if data and data.in_los then
            if melee then
                if data.melee_dist <= 8 then count = count + 1 end
            else
                if data.in_shred_range then count = count + 1 end
            end
        end
    end
    return math.max(1, count)
end

-- Per-tick memoization: callers (get_best_dot_target, get_group_time_to_die,
-- rotation queries) frequently ask for the same (range, spell_id) combination
-- multiple times per frame. Reuse the result list until the enemy cache refreshes.
local all_enemies_cache = {}
local all_enemies_cache_tick = -1
function Functions.get_all_enemies_in_range(range, spell_id)
    if all_enemies_cache_tick ~= last_enemy_scan then
        all_enemies_cache_tick = last_enemy_scan
        wipe(all_enemies_cache)
    end
    local key = tostring(range) .. "_" .. tostring(spell_id)
    local cached = all_enemies_cache[key]
    if cached then return cached end

    local melee = (range == 8) or (spell_id == spells.SWIPE_CAT.id)
    local need_facing = (spell_id ~= spells.SWIPE_CAT.id)
    local result = {}
    for _, enemy in ipairs(cached_enemies) do
        local guid = enemy:get_guid()
        local data = cached_enemy_data[guid]
        if data and data.in_los then
            if need_facing and not data.facing then
                -- skip
            elseif melee then
                if data.melee_dist <= 8 then result[#result + 1] = enemy end
            else
                if data.in_shred_range then result[#result + 1] = enemy end
            end
        end
    end
    all_enemies_cache[key] = result
    return result
end

function Functions.get_best_dot_target(debuff_id, spell_id, refresh_time, current_target, min_ttd)
    min_ttd = min_ttd or 0
    local need_facing = (spell_id ~= spells.SWIPE_CAT.id)
    local is_melee = (spell_id ~= spells.MOONFIRE_CAT.id)
    if current_target then
        local data = cached_enemy_data[current_target:is_valid() and current_target:get_guid() or 0]
        if data and data.in_los and (not need_facing or data.facing) and (not is_melee or data.melee_dist <= 8) then
            if Functions.get_debuff_remains(current_target, debuff_id) < refresh_time and Functions.get_time_to_die(current_target) >= min_ttd then
                return current_target
            end
        end
    end

    local search_range = is_melee and 8 or 40
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
    for _, enemy in ipairs(cached_enemies) do
        local data = cached_enemy_data[enemy:get_guid()]
        if data and data.in_los and data.melee_dist <= 8 then
            local remains = Functions.get_debuff_remains(enemy, lists.DEBUFFS.RIP)
            if remains < (threshold or 5) and Functions.get_time_to_die(enemy) >= (min_ttd or 7) then
                return true
            end
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- INTERRUPT (time-elapsed delay: kick between 1.1s and 1.4s after cast start)
--------------------------------------------------------------------------------
local interrupt_cache = {}
local last_interrupt_clear = 0
local INTERRUPT_CLEANUP_INTERVAL = 5
local INTERRUPT_MIN_DELAY_MS = 900
local INTERRUPT_MAX_DELAY_MS = 1050

function Functions.get_interrupt_target()
    local now = core.game_time()
    local real_now = core.time()

    if real_now - last_interrupt_clear > INTERRUPT_CLEANUP_INTERVAL then
        for k in pairs(interrupt_cache) do interrupt_cache[k] = nil end
        last_interrupt_clear = real_now
    end

    for _, enemy in ipairs(cached_enemies) do
        if Functions.validate_enemy(enemy, true) and not lists.INTERRUPT_NPC_BLACKLIST[enemy:get_npc_id()] then
            local start_time, end_time, key
            if enemy:is_casting_spell() and enemy:is_active_spell_interruptable() then
                start_time = enemy:get_active_spell_cast_start_time()
                end_time = enemy:get_active_spell_cast_end_time()
                key = tostring(enemy:get_guid()) .. "_" .. tostring(start_time)
            elseif enemy:is_channelling_spell() and enemy:is_active_spell_interruptable() then
                start_time = enemy:get_active_channel_cast_start_time()
                end_time = enemy:get_active_channel_cast_end_time()
                key = tostring(enemy:get_guid()) .. "_c_" .. tostring(start_time)
            end

            if start_time and end_time and end_time > start_time then
                if not interrupt_cache[key] then
                    interrupt_cache[key] = math.random(INTERRUPT_MIN_DELAY_MS, INTERRUPT_MAX_DELAY_MS)
                end
                local delay = interrupt_cache[key]

                local elapsed = now - start_time
                -- Only fire if we still have time before the cast finishes,
                -- otherwise we'd waste the kick on a spell that's already done.
                if elapsed >= delay and now < end_time then
                    return enemy
                end
            end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- DISPEL (time-elapsed delay: dispel between 0.9s and 1.5s after debuff seen)
--------------------------------------------------------------------------------
local dispel_cache_target = nil
local dispel_cache_buff = nil
local dispel_cache_type = nil

-- Throttle the full-group aura/debuff sweep (most expensive call in raids:
-- 20 allies × many auras × buff_manager lookups). Reaction delay is already
-- 0.9–1.5s so polling at 100ms is imperceptible.
local DISPEL_SCAN_INTERVAL = 0.1
local last_dispel_scan = 0
local dispel_last_target = nil
local dispel_last_buff = nil
local dispel_last_type = nil

-- Per-(ally,buff) first-seen tracking so we delay reaction by a human-like amount.
-- key = ally_guid .. "_" .. buff_id  →  { first_seen = <core.time()>, delay = <seconds> }
local dispel_seen = {}
local last_dispel_seen_clear = 0
local DISPEL_SEEN_CLEANUP_INTERVAL = 5
local DISPEL_SEEN_STALE_TIME = 10
local DISPEL_MIN_DELAY = 0.9
local DISPEL_MAX_DELAY = 1.5

local function dispel_seen_key_str(guid_str, buff_id)
    return guid_str .. "_" .. tostring(buff_id)
end

local function dispel_record_seen(guid_str, buff_id, now)
    local key = dispel_seen_key_str(guid_str, buff_id)
    local entry = dispel_seen[key]
    if not entry then
        entry = {
            first_seen = now,
            delay = DISPEL_MIN_DELAY + math.random() * (DISPEL_MAX_DELAY - DISPEL_MIN_DELAY),
        }
        dispel_seen[key] = entry
    end
    return entry
end

-- Single full-group sweep: records first_seen for every dispelable aura/debuff
-- on every ally, then returns the first ally whose delay has elapsed AND who
-- is castable now. Recording is intentionally NOT gated on cooldown or LoS so
-- the timer reflects when the debuff actually appeared, not when we could act.
function Functions.check_all_dispels()
    if not menu.AUTO_DISPEL:get_toggle_state() then
        dispel_cache_target = nil
        dispel_last_target = nil
        return nil, nil, nil
    end

    local now = core.time()

    -- Throttle: return last scan's result between full sweeps.
    if (now - last_dispel_scan) < DISPEL_SCAN_INTERVAL then
        if dispel_last_target and dispel_last_target:is_valid() and not dispel_last_target:is_dead() then
            return dispel_last_target, dispel_last_buff, dispel_last_type
        end
        return nil, nil, nil
    end
    last_dispel_scan = now

    -- Periodically drop stale first-seen entries (debuff fell off, ally despawned, etc.)
    if now - last_dispel_seen_clear > DISPEL_SEEN_CLEANUP_INTERVAL then
        for k, v in pairs(dispel_seen) do
            if now - v.first_seen > DISPEL_SEEN_STALE_TIME then
                dispel_seen[k] = nil
            end
        end
        last_dispel_seen_clear = now
    end

    local can_act = spells.REMOVE_CORRUPTION:is_learned() and spells.REMOVE_CORRUPTION:cooldown_up()

    -- Fast path: previously chosen target still has the debuff and is ready.
    if can_act and dispel_cache_target and dispel_cache_target:is_valid() and not dispel_cache_target:is_dead() then
        if Functions.has_debuff(dispel_cache_target, dispel_cache_buff) or Functions.has_buff(dispel_cache_target, dispel_cache_buff) then
            local guid_str = tostring(dispel_cache_target:get_guid())
            local entry = dispel_record_seen(guid_str, dispel_cache_buff, now)
            if (now - entry.first_seen) >= entry.delay and Functions.validate_unit(dispel_cache_target) then
                dispel_last_target = dispel_cache_target
                dispel_last_buff = dispel_cache_buff
                dispel_last_type = dispel_cache_type
                return dispel_cache_target, dispel_cache_buff, dispel_cache_type
            end
        else
            dispel_cache_target = nil
        end
    end

    local allies = cached_party
    local num_allies = #allies
    if num_allies == 0 then return nil, nil, nil end

    local ready_target, ready_buff, ready_type = nil, nil, nil

    for i = 1, num_allies do
        local ally = allies[i]
        if ally and ally:is_valid() and not ally:is_dead() then
            local guid_str = tostring(ally:get_guid())
            local in_los = Functions.validate_unit(ally)

            local auras = ally:get_auras()
            if auras then
                for _, aura in ipairs(auras) do
                    local bid = aura.buff_id
                    if bid and lists.SPECIAL_DISPELS and lists.SPECIAL_DISPELS[bid] then
                        local entry = dispel_record_seen(guid_str, bid, now)
                        if not ready_target and can_act and in_los
                            and (now - entry.first_seen) >= entry.delay then
                            ready_target = ally
                            ready_buff = bid
                            ready_type = aura.type
                        end
                    end
                end
            end

            local debuffs = ally:get_debuffs()
            if debuffs then
                for _, debuff in pairs(debuffs) do
                    local t = debuff.type
                    if t == enums.buff_type.POISON or t == enums.buff_type.CURSE then
                        local bid = debuff.buff_id or 0
                        local entry = dispel_record_seen(guid_str, bid, now)
                        if not ready_target and can_act and in_los
                            and (now - entry.first_seen) >= entry.delay then
                            ready_target = ally
                            ready_buff = bid
                            ready_type = t
                        end
                    end
                end
            end
        end
    end

    if ready_target then
        dispel_cache_target = ready_target
        dispel_cache_buff = ready_buff
        dispel_cache_type = ready_type
        dispel_last_target = ready_target
        dispel_last_buff = ready_buff
        dispel_last_type = ready_type
        return ready_target, ready_buff, ready_type
    end

    dispel_last_target = nil
    dispel_last_buff = nil
    dispel_last_type = nil
    return nil, nil, nil
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
                if Functions.validate_unit(ally) then
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
