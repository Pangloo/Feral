-- main.lua
local plugin = require("header")
if not plugin.load then return end

local spells = require("spells")
local lists = require("lists")
local funcs = require("functions")
local menu = require("menu")
local ui = require("ui")
local spell_queue = require("common/modules/spell_queue")
local control_panel_utility = require("common/utility/control_panel_helper")

local me = core.object_manager.get_local_player()
if not me then return end

--------------------------------------------------------------------------------
-- VARIABLES & MOCKS
--------------------------------------------------------------------------------
local time = 0
local fight_remains = 300 -- mocked

local variable = {
    regrowth = false,
    combat_start_time = 0,
    dotc_rake_threshold = 5,
    algethar_puzzle_box_precombat_cast = 3,
    tfRemains = 0,

    convokeCountRemaining = 0,
    zerkCountRemaining = 0,
    potCountRemaining = 0,
    slot1CountRemaining = 0,
    slot2CountRemaining = 0,

    firstHoldBerserkCondition = false,
    secondHoldBerserkCondition = false,
    holdBerserk = false,
    holdConvoke = false,
    holdPot = false,
    bs_inc_cd = 0,
    convoke_cd = 0,
    pot_cd = 0,
    highestCDremaining = 0,
    lowestCDremaining = 0,
    secondLowestCDremaining = 0,
}

local talent = {
    wild_slashes = false,
    infected_wounds = false,
    berserk_heart_of_the_lion = false,
    frantic_frenzy = false,
    doubleclawed_rake = false,
    lunar_inspiration = false,
    panthers_guile = false,
    primal_wrath = true,
    rampant_ferocity = false,
    saber_jaws = false,
    ashamanes_guidance = false,
    convoke_the_spirits = true,
}

local hero_tree = {
    wildstalker = false,
    druid_of_the_claw = false,
}

local last_talent_check = 0

local function update_talents()
    talent.wild_slashes = core.spell_book.is_spell_learned(spells.WILD_SLASHES.id)
    talent.infected_wounds = core.spell_book.is_spell_learned(spells.INFECTED_WOUNDS.id)
    talent.berserk_heart_of_the_lion = core.spell_book.is_spell_learned(spells.BERSERK_HEART_OF_THE_LION.id)
    talent.frantic_frenzy = core.spell_book.is_spell_learned(spells.FRANTIC_FRENZY.id)
    talent.doubleclawed_rake = core.spell_book.is_spell_learned(spells.DOUBLECLAWED_RAKE.id)
    talent.lunar_inspiration = core.spell_book.is_spell_learned(spells.LUNAR_INSPIRATION.id)
    talent.panthers_guile = core.spell_book.is_spell_learned(spells.PANTHERS_GUILE.id)
    talent.primal_wrath = core.spell_book.is_spell_learned(spells.PRIMAL_WRATH.id)
    talent.rampant_ferocity = core.spell_book.is_spell_learned(spells.RAMPANT_FEROCITY.id)
    talent.saber_jaws = core.spell_book.is_spell_learned(spells.SABER_JAWS.id)
    talent.ashamanes_guidance = core.spell_book.is_spell_learned(spells.ASHAMANES_GUIDANCE.id)
    talent.convoke_the_spirits = core.spell_book.is_spell_learned(spells.CONVOKE_THE_SPIRITS.id)
    talent.thriving_growth = core.spell_book.is_spell_learned(spells.THRIVING_GROWTH.id)

    if talent.wild_slashes and not talent.infected_wounds then
        variable.dotc_rake_threshold = 3
    elseif not talent.wild_slashes and talent.infected_wounds then
        variable.dotc_rake_threshold = 8
    else
        variable.dotc_rake_threshold = 5
    end

    if talent.doubleclawed_rake or talent.thriving_growth then
        variable.dotc_rake_threshold = 50
    end
end

local function update_variables()
    time = core.time() / 1000 -- simple approximation of combat time mostly handled in variables

    if not me:affecting_combat() then
        variable.combat_start_time = 0
    elseif variable.combat_start_time == 0 then
        variable.combat_start_time = time
    end

    variable.regrowth = menu.REGROWTH:get_state()

    -- Update Talents every 2 seconds
    local now = core.time()
    if now - last_talent_check >= 2 then
        last_talent_check = now
        update_talents()
    end

    variable.tfRemains = core.spell_book.get_spell_cooldown(spells.TIGERS_FURY.id)
end

--------------------------------------------------------------------------------
-- ACTION LISTS (SIMC TRANSLATION)
--------------------------------------------------------------------------------
local actionList = {}

-- APL: cd_variable
actionList.cd_variable = function()
    local combat_time = variable.combat_start_time > 0 and (time - variable.combat_start_time) or 0
    -- Mocked math for cooldown variable tracking
    variable.bs_inc_cd = core.spell_book.get_spell_cooldown(spells.BERSERK.id) + 10
    variable.convoke_cd = core.spell_book.get_spell_cooldown(spells.CONVOKE_THE_SPIRITS.id) + 10

    local cds_enabled = menu.USE_COOLDOWNS:get_toggle_state()
    variable.holdBerserk = not cds_enabled or variable.firstHoldBerserkCondition or variable.secondHoldBerserkCondition
    variable.holdConvoke = not cds_enabled
end

local function frenzy_tf_check()
    local frenzy_spell = talent.frantic_frenzy and spells.FRANTIC_FRENZY or spells.FERAL_FRENZY
    local cd = core.spell_book.get_spell_cooldown(frenzy_spell.id)
    if cd < 12 or cd > 19 then
        return true
    end
    if not menu.FRENZY_TF_ONLY:get_state() then return true end
    return false
end



-- APL: cooldown
actionList.cooldown = function(target, spell_targets)
    actionList.cd_variable()

    local has_tf = me:has_buff(lists.BUFFS.TIGERS_FURY)

    -- incarnation / berserk
    if has_tf and not variable.holdBerserk then
        if core.spell_book.is_spell_learned(spells.INCARNATION.id) and spells.INCARNATION:cooldown_up() then
            if spells.INCARNATION:cast(me, "Incarnation") then return true end
        elseif core.spell_book.is_spell_learned(spells.BERSERK.id) and spells.BERSERK:cooldown_up() then
            if not menu.USE_PUZZLE_BOX:get_state() or not core.spell_book.is_item_usable(193701) or me:has_buff(383781) then
                if spells.BERSERK:cast(me, "Berserk") then return true end
            end
        end
    end

    local combo_points = me:get_power(4) or 0
    local has_bs = me:has_buff(lists.BUFFS.BERSERK) or me:has_buff(lists.BUFFS.INCARNATION)

    -- feral_frenzy
    local frenzy_tf_only = menu.FRENZY_TF_ONLY:get_state()
    local can_cast_frenzy = not frenzy_tf_only or has_tf

    if menu.USE_MINI_CDS:get_toggle_state() and can_cast_frenzy and funcs.get_group_time_to_die(8) >= 15 then
        if talent.frantic_frenzy then
            if core.spell_book.is_spell_learned(spells.FRANTIC_FRENZY.id) and spells.FRANTIC_FRENZY:cooldown_up() then
                if spells.FRANTIC_FRENZY:cast(target, "Frantic Frenzy") then return true end
            end
        else
            if spells.FERAL_FRENZY:cooldown_up() then
                if spells.FERAL_FRENZY:cast(target, "Feral Frenzy") then return true end
            end
        end
    end

    -- convoke_the_spirits
    if core.spell_book.is_spell_learned(spells.CONVOKE_THE_SPIRITS.id) and spells.CONVOKE_THE_SPIRITS:cooldown_up() then
        if has_bs or (has_tf and not variable.holdConvoke) then
            if not funcs.any_missing_rip(8, 5, 7) then
                if spells.CONVOKE_THE_SPIRITS:cast(me, "Convoke (All Rip up)") then return true end
            end
        end
    end
    return false
end

-- APL: aoe_builder
actionList.aoe_builder = function(target, spell_targets, combo_points, energy)
    local tf_remains = funcs.get_buff_remains(me, lists.BUFFS.TIGERS_FURY)
    local tf_expiring = tf_remains > 0 and tf_remains < 3
    local rake_thresh = tf_expiring and 8 or 3.6
    local thrash_thresh = tf_expiring and 8 or 3.6
    local has_cc = me:has_buff(lists.BUFFS.CLEARCASTING)

    -- Clearcasting: spend on Swipe/Brutal Slash in AoE (free ability)
    if has_cc then
        if core.spell_book.is_spell_learned(spells.BRUTAL_SLASH.id) and spells.BRUTAL_SLASH:cooldown_up() then
            if spells.BRUTAL_SLASH:cast(me, "Brutal Slash (Clearcasting)") then return true end
        elseif core.spell_book.is_spell_learned(spells.SWIPE_CAT.id) and spells.SWIPE_CAT:cooldown_up() then
            if spells.SWIPE_CAT:cast(me, "Swipe (Clearcasting)") then return true end
        end
    end

    -- Rake conditions simplified (Scan and Spread) - Only if targets < 4
    if spell_targets <= variable.dotc_rake_threshold then
        local rake_target = funcs.get_best_dot_target(lists.DEBUFFS.RAKE, spells.RAKE.id, rake_thresh, target, 9)
        if rake_target then
            if energy < 35 then return true end
            if spells.RAKE:cast(rake_target, "Rake (refresh/spread)") then return true end
        end
    end

    -- Thrash
    if core.spell_book.is_spell_learned(spells.THRASH_CAT.id) and spells.THRASH_CAT:cooldown_up() then
        local thrash_target = funcs.get_best_dot_target(lists.DEBUFFS.THRASH, spells.THRASH_CAT.id, thrash_thresh, target,
            7)
        if thrash_target then
            if energy < 40 then return true end
            if spells.THRASH_CAT:cast(thrash_target, "Thrash (AoE)") then return true end
        end
    end

    -- Moonfire (Lunar Inspiration) - Only prioritized dynamically on lower target counts
    if talent.lunar_inspiration and spell_targets <= 3 then
        local moonfire_target = funcs.get_best_dot_target(lists.DEBUFFS.MOONFIRE, spells.MOONFIRE_CAT.id, 4.2, target, 9)
        if moonfire_target then
            if energy < 30 then return true end
            if spells.MOONFIRE_CAT:cast(moonfire_target, "Moonfire (AoE)") then return true end
        end
    end

    -- Swipe / Brutal Slash
    if core.spell_book.is_spell_learned(spells.BRUTAL_SLASH.id) and spells.BRUTAL_SLASH:cooldown_up() then
        if me:has_buff(lists.BUFFS.SUDDEN_AMBUSH) and spell_targets >= 5 then
            if spells.BRUTAL_SLASH:cast(me, "Brutal Slash (Sudden Ambush)") then return true end
        end
    elseif core.spell_book.is_spell_learned(spells.SWIPE_CAT.id) and spells.SWIPE_CAT:cooldown_up() then
        if me:has_buff(lists.BUFFS.SUDDEN_AMBUSH) and spell_targets >= 5 then
            if spells.SWIPE_CAT:cast(me, "Swipe (Sudden Ambush)") then return true end
        end
    end

    if combo_points <= 1 and spell_targets == 2 and talent.panthers_guile then
        if energy < 40 then return true end
        if spells.SHRED:cast(target, "Shred (Guile)") then return true end
    end

    if combo_points > 1 or spell_targets > 2 or not talent.panthers_guile then
        if core.spell_book.is_spell_learned(spells.BRUTAL_SLASH.id) and spells.BRUTAL_SLASH:cooldown_up() then
            if energy < 25 then return true end
            if spells.BRUTAL_SLASH:cast(me, "Brutal Slash") then return true end
        elseif core.spell_book.is_spell_learned(spells.SWIPE_CAT.id) and spells.SWIPE_CAT:cooldown_up() then
            if energy < 35 then return true end
            if spells.SWIPE_CAT:cast(me, "Swipe") then return true end
        end
    end
    return false
end

-- APL: aoe_finisher
actionList.aoe_finisher = function(target, spell_targets, combo_points, energy)
    local rip_thresh = 5

    -- Primal Wrath: Only cast if a target in range has the dot expiring within 5 seconds
    if core.spell_book.is_spell_learned(spells.PRIMAL_WRATH.id) and combo_points >= 5 and spell_targets > 1 then
        local pw_target = funcs.get_best_dot_target(lists.DEBUFFS.RIP, spells.PRIMAL_WRATH.id, rip_thresh, target, 7)
        if pw_target then
            if energy < 20 then return true end
            if spells.PRIMAL_WRATH:cast(me, "Primal Wrath") then return true end
        end
    end

    -- Manual Rip Spread (Only if Primal Wrath is not learned)
    if not talent.primal_wrath and combo_points >= 5 then
        local rip_spread_thresh = 7
        local rip_target = funcs.get_best_dot_target(lists.DEBUFFS.RIP, spells.RIP.id, rip_spread_thresh, target, 7)
        if rip_target then
            if energy < 30 then return true end
            if spells.RIP:cast(rip_target, "Rip (spread)") then return true end
        end
    end

    -- Ferocious Bite / Ravage (Prioritized if no dot maintenance was performed)
    local has_bs = me:has_buff(lists.BUFFS.BERSERK) or me:has_buff(lists.BUFFS.INCARNATION)
    local bite_cost = has_bs and 25 or 50
    local min_cp = 4 + (has_bs and 1 or 0)
    if (combo_points >= min_cp or me:has_buff(lists.BUFFS.APEX_PREDATORS_CRAVING)) and not funcs.any_missing_rip(8, 5, 7) then
        if energy < bite_cost and not me:has_buff(lists.BUFFS.APEX_PREDATORS_CRAVING) then return true end
        local reason = me:has_buff(lists.BUFFS.RAVAGE) and "Ferocious Bite (Ravage)" or "Ferocious Bite (AoE)"
        if spells.FEROCIOUS_BITE:cast(target, reason) then return true end
    end

    return false
end

-- APL: builder
actionList.builder = function(target, spell_targets, combo_points, energy)
    local tf_remains = funcs.get_buff_remains(me, lists.BUFFS.TIGERS_FURY)
    local tf_expiring = tf_remains > 0 and tf_remains < 3
    local rake_thresh = tf_expiring and 10 or 4.5

    local is_prowled = me:has_buff(lists.BUFFS.PROWL) or me:has_buff(lists.BUFFS.SHADOWMELD)
    if not is_prowled and funcs.get_debuff_remains(target, lists.DEBUFFS.RAKE) < rake_thresh then
        if core.spell_book.is_spell_learned(spells.SHADOWMELD.id) and spells.SHADOWMELD:cooldown_up() then
            if spells.SHADOWMELD:cast(me, "Shadowmeld") then return true end
        end
    end

    -- Clearcasting: spend on Shred in ST (free ability)
    local has_cc = me:has_buff(lists.BUFFS.CLEARCASTING)
    if has_cc then
        if spells.SHRED:cast(target, "Shred (Clearcasting)") then return true end
    end

    -- Ensure basic Rake uptime securely and spread if able
    local rake_target = funcs.get_best_dot_target(lists.DEBUFFS.RAKE, spells.RAKE.id, rake_thresh, target, 9)
    if rake_target then
        if energy < 35 then return true end
        if spells.RAKE:cast(rake_target, "Rake") then return true end
    end

    -- Moonfire (Lunar Inspiration)
    if talent.lunar_inspiration then
        local moonfire_target = funcs.get_best_dot_target(lists.DEBUFFS.MOONFIRE, spells.MOONFIRE_CAT.id, 4.2, target, 7)
        if moonfire_target then
            if energy < 30 then return true end
            if spells.MOONFIRE_CAT:cast(moonfire_target, "Moonfire") then return true end
        end
    end

    if energy < 40 then return true end
    if spells.SHRED:cast(target, "Shred (Builder)") then return true end
    return false
end

-- APL: finisher
actionList.finisher = function(target, spell_targets, combo_points, energy, has_bs)
    local rip_thresh = 7

    if combo_points >= 5 then
        local rip_target = funcs.get_best_dot_target(lists.DEBUFFS.RIP, spells.RIP.id, rip_thresh, target, 7)
        if rip_target then
            if energy < 30 then return true end
            if spells.RIP:cast(rip_target, "Rip") then return true end
        end
    end

    local bite_cost = has_bs and 25 or 50
    if combo_points >= 4 + (has_bs and 1 or 0) and not funcs.any_missing_rip(8, 5, 7) then
        if energy < bite_cost and not me:has_buff(lists.BUFFS.APEX_PREDATORS_CRAVING) then return true end
        if spells.FEROCIOUS_BITE:cast(target, "Ferocious Bite") then return true end
    end
    return false
end

-- APL: utility
actionList.utility = function()
    if menu.AUTO_INTERRUPT:get_toggle_state() then
        if core.spell_book.is_spell_learned(spells.SKULL_BASH.id) and spells.SKULL_BASH:cooldown_up() then
            local target = funcs.get_interrupt_target(13) -- Skull Bash range is 13 yards
            if target then
                if spells.SKULL_BASH:cast(target, "Skull Bash") then return true end
            end
        end
    end

    -- Dispel
    if menu.AUTO_DISPEL:get_toggle_state() then
        if core.spell_book.is_spell_learned(spells.REMOVE_CORRUPTION.id) and spells.REMOVE_CORRUPTION:cooldown_up() then
            local dispel_target = funcs.check_all_dispels(40)
            if dispel_target then
                if spells.REMOVE_CORRUPTION:cast(dispel_target, "Remove Corruption") then return true end
            end
        end
    end

    return false
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
local function shouldbox()
    if not menu.USE_PUZZLE_BOX:get_state() then return false end
    if not variable.holdBerserk and spells.TIGERS_FURY:cooldown_up() and frenzy_tf_check() and menu.USE_MINI_CDS:get_toggle_state() then
        if core.spell_book.is_item_usable(193701) and me:get_item_cooldown(193701) <= 15 then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- MAIN UPDATE
--------------------------------------------------------------------------------
local function on_update()
    me = core.object_manager.get_local_player()
    if not me or not me:is_valid() or me:is_mounted() or me:is_dead_or_ghost() then return end

    if not menu.is_enabled() then return end
    if not menu.is_rotation_enabled() then return end

    if me:is_casting() or me:is_channeling() then return end

    funcs.update_party_cache()
    funcs.update_enemy_cache()
    update_variables()

    control_panel_utility:on_update(menu)

    if funcs.check_mark_of_the_wild() then return end

    local spell_targets = funcs.count_enemies_in_range(8)
    local combo_points = me:get_power(4) or 0
    local target = funcs.get_dps_target()

    -- Precombat
    if not me:affecting_combat() then
        if menu.AUTO_TRAVEL:get_state() and me:is_outdoors() then
            if not me:has_buff(lists.BUFFS.TRAVEL_FORM) then
                if spells.TRAVEL_FORM:cast(me, "Auto Travel Form") then return end
            end
        elseif me:is_indoors() or not menu.AUTO_TRAVEL:get_state() then
            if me:has_buff(lists.BUFFS.TRAVEL_FORM) then return end
            if not me:has_buff(lists.BUFFS.CAT_FORM) then
                if spells.CAT_FORM:cast(me, "Cat Form") then return end
            end
            if not me:has_buff(lists.BUFFS.PROWL) and not me:has_buff(lists.BUFFS.SHADOWMELD) then
                if spells.PROWL:cast(me, "Prowl") then return end
            end
        end
        return
    end

    if me:affecting_combat() then
        if not me:has_buff(lists.BUFFS.CAT_FORM) and not me:is_flying() then
            if spells.CAT_FORM:cast(me, "Cat Form") then return end
        end
    end

    if me:has_buff(lists.BUFFS.PREDATORY_SWIFTNESS) and variable.regrowth then
        local hp_pct = me:get_health_percentage()
        if hp_pct < 80 then
            if spells.REGROWTH:cast(me, "Regrowth (Swiftness)") then return end
        end
    end

    -- Kicks and dispels run before anything else, even without a target
    if actionList.utility() then return end

    if not target then return end

    local has_bs = me:has_buff(lists.BUFFS.BERSERK) or me:has_buff(lists.BUFFS.INCARNATION)
    local is_prowled = me:has_buff(lists.BUFFS.PROWL) or me:has_buff(lists.BUFFS.SHADOWMELD)

    -- APL Main Loop
    local want_box = shouldbox()
    if want_box and not me:is_moving() and me:get_item_cooldown(193701) == 0 then
        if core.input.use_item(193701) then return true end
    end

    if not want_box and menu.USE_MINI_CDS:get_toggle_state() and spells.TIGERS_FURY:cooldown_up() and frenzy_tf_check() and funcs.get_group_time_to_die(8) >= 15 then
        if spells.TIGERS_FURY:cast(me, "Tiger's Fury") then return end
    end

    if is_prowled then
        if spells.RAKE:cast(target, "Rake out of stealth") then return end
    end

    -- if buff.chomp_enabler then cast chomp (ravage) (NYI in simple version unless mapped to FB with ravage)
    if actionList.cooldown(target, spell_targets) then return end

    local is_aoe = spell_targets >= 2
    local energy = me:get_power(3) or 0

    -- Run finishers first so Rip doesn't fall off before spending Apex proc
    if is_aoe then
        if actionList.aoe_finisher(target, spell_targets, combo_points, energy) then return end
    else
        if actionList.finisher(target, spell_targets, combo_points, energy, has_bs) then return end
    end

    -- Apex Predator's Craving: free bite after Rip is confirmed safe
    if me:has_buff(lists.BUFFS.APEX_PREDATORS_CRAVING) then
        if spells.FEROCIOUS_BITE:cast(target, "Ferocious Bite (Apex)") then return true end
    end

    local builder_threshold = 4 + (has_bs and 1 or 0)
    if is_aoe then
        if combo_points <= builder_threshold then
            if actionList.aoe_builder(target, spell_targets, combo_points, energy) then return end
        end
    else
        if combo_points <= builder_threshold then
            if actionList.builder(target, spell_targets, combo_points, energy) then return end
        end
    end
end

local function on_render()
    menu.draw()
end

core.register_on_update_callback(on_update)
core.register_on_render_menu_callback(on_render)
core.register_on_render_window_callback(ui.draw)

core.log("[Feral Druid] " .. plugin.version .. " Loaded successfully!")
