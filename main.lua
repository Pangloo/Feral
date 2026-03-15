-- main.lua
local enums = require("common/enums")
local plugin = require("header")
if not plugin.load then return end

local spells = require("spells")
local lists = require("lists")
local funcs = require("functions")
local menu = require("menu")
local ui = require("ui")

local me = core.object_manager.get_local_player()
if not me then return end

--------------------------------------------------------------------------------
-- VARIABLES & MOCKS
--------------------------------------------------------------------------------
local time = 0
local fight_remains = 300 -- mocked

local variable = {
    regrowth = false,
    use_custom_timers = false,
    combat_start_time = 0,
    nextTFTimer = 0,
    nextBSTimer = 1,
    dotc_rake_threshold = 5,
    algethar_puzzle_box_precombat_cast = 3,
    tfRemains = 0,
    tfNow = false,
    currentTFTimer = -10,
    currentBSTimer = -10,
    zerkNow = false,

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

local function update_variables()
    time = core.time() / 1000 -- simple approximation of combat time mostly handled in variables

    if not me:affecting_combat() then
        variable.combat_start_time = 0
        variable.nextTFTimer = 0
        variable.nextBSTimer = 1
        variable.currentTFTimer = -10
        variable.currentBSTimer = -10
    elseif variable.combat_start_time == 0 then
        variable.combat_start_time = time
    end

    local combat_time = variable.combat_start_time > 0 and (time - variable.combat_start_time) or 0

    variable.regrowth = menu.REGROWTH:get_state()
    variable.use_custom_timers = menu.USE_CUSTOM_TIMERS:get_state()

    -- Update Talents
    talent.wild_slashes = spells.WILD_SLASHES:is_learned()
    talent.infected_wounds = spells.INFECTED_WOUNDS:is_learned()
    talent.berserk_heart_of_the_lion = spells.BERSERK_HEART_OF_THE_LION:is_learned()
    talent.frantic_frenzy = spells.FRANTIC_FRENZY:is_learned()
    talent.doubleclawed_rake = spells.DOUBLECLAWED_RAKE:is_learned()
    talent.lunar_inspiration = spells.LUNAR_INSPIRATION:is_learned()
    talent.panthers_guile = spells.PANTHERS_GUILE:is_learned()
    talent.primal_wrath = spells.PRIMAL_WRATH:is_learned()
    talent.rampant_ferocity = spells.RAMPANT_FEROCITY:is_learned()
    talent.saber_jaws = spells.SABER_JAWS:is_learned()
    talent.ashamanes_guidance = spells.ASHAMANES_GUIDANCE:is_learned()
    talent.convoke_the_spirits = spells.CONVOKE_THE_SPIRITS:is_learned()

    if talent.wild_slashes and not talent.infected_wounds then
        variable.dotc_rake_threshold = 3
    elseif not talent.wild_slashes and talent.infected_wounds then
        variable.dotc_rake_threshold = 8
    else
        variable.dotc_rake_threshold = 5
    end

    if variable.use_custom_timers then
        if variable.tfNow then
            variable.tfRemains = 0
        else
            variable.tfRemains = math.max(0, variable.nextTFTimer - combat_time)
        end
    else
        variable.tfRemains = spells.TIGERS_FURY:cooldown_remains()
    end
end

--------------------------------------------------------------------------------
-- ACTION LISTS (SIMC TRANSLATION)
--------------------------------------------------------------------------------
local actionList = {}

-- APL: cd_variable
actionList.cd_variable = function()
    local combat_time = variable.combat_start_time > 0 and (time - variable.combat_start_time) or 0
    -- Mocked math for cooldown variable tracking
    variable.bs_inc_cd = not variable.use_custom_timers and (spells.BERSERK:cooldown_remains() + 10) or
        (variable.nextBSTimer - combat_time + 10)
    variable.convoke_cd = spells.CONVOKE_THE_SPIRITS:cooldown_remains() + 10

    local cds_enabled = menu.USE_COOLDOWNS:get_state()
    variable.holdBerserk = not cds_enabled or variable.firstHoldBerserkCondition or variable.secondHoldBerserkCondition or
        (variable.use_custom_timers and (variable.nextBSTimer - 5 > combat_time) and not variable.zerkNow)
    variable.holdConvoke = not cds_enabled
end

-- APL: custom_timers
actionList.custom_timers = function()
    local combat_time = variable.combat_start_time > 0 and (time - variable.combat_start_time) or 0

    if combat_time > variable.nextTFTimer then
        variable.currentTFTimer = variable.nextTFTimer
        variable.nextTFTimer = variable.currentTFTimer + 30
    end
    if combat_time > variable.nextBSTimer then
        variable.currentBSTimer = variable.nextBSTimer
        variable.nextBSTimer = variable.currentBSTimer + 180
    end

    variable.use_custom_timers = menu.USE_CUSTOM_TIMERS:get_state()
    variable.tfNow = variable.use_custom_timers and
        ((variable.currentTFTimer + 4 > combat_time) and (combat_time >= variable.currentTFTimer))
    variable.zerkNow = variable.use_custom_timers and
        ((variable.currentBSTimer + 4 > combat_time) and (combat_time >= variable.currentBSTimer))
end

-- APL: cooldown
actionList.cooldown = function(target, spell_targets)
    actionList.cd_variable()

    local has_tf = me:has_buff(lists.BUFFS.TIGERS_FURY)

    -- incarnation / berserk
    if has_tf and not variable.holdBerserk and not variable.use_custom_timers or variable.zerkNow then
        if spells.INCARNATION:is_learned() and spells.INCARNATION:cooldown_up() then
            if spells.INCARNATION:cast(me, "Incarnation") then return true end
        elseif spells.BERSERK:is_learned() and spells.BERSERK:cooldown_up() then
            if spells.BERSERK:cast(me, "Berserk") then return true end
        end
    end

    local combo_points = me:get_power(4) or 0
    local has_bs = me:has_buff(lists.BUFFS.BERSERK) or me:has_buff(lists.BUFFS.INCARNATION)

    -- feral_frenzy
    if talent.frantic_frenzy then
        if spells.FRANTIC_FRENZY:is_learned() and spells.FRANTIC_FRENZY:cooldown_up() then
            if spells.FRANTIC_FRENZY:cast(target, "Frantic Frenzy") then return true end
        end
    else
        if spells.FERAL_FRENZY:is_learned() and spells.FERAL_FRENZY:cooldown_up() then
            if combo_points <= 2 + (has_bs and 2 or 0) then
                if spells.FERAL_FRENZY:cast(target, "Feral Frenzy") then return true end
            end
        end
    end

    -- convoke_the_spirits
    if spells.CONVOKE_THE_SPIRITS:is_learned() and spells.CONVOKE_THE_SPIRITS:cooldown_up() then
        local has_bs = me:has_buff(lists.BUFFS.BERSERK)
        if has_bs or (has_tf and not variable.holdConvoke) then
            if spells.CONVOKE_THE_SPIRITS:cast(me, "Convoke") then return true end
        end
    end
    return false
end

-- APL: aoe_builder
actionList.aoe_builder = function(target, spell_targets, combo_points, energy)
    -- Rake conditions simplified (Scan and Spread)
    local rake_target = funcs.get_best_dot_target(lists.DEBUFFS.RAKE, 8, 4.5, target)
    if rake_target then
        if energy < 35 then return true end
        if spells.RAKE:cast(rake_target, "Rake (refresh/spread)") then return true end
    end

    -- Thrash
    if spells.THRASH_CAT:is_learned() and spells.THRASH_CAT:cooldown_up() then
        local thrash_target = funcs.get_best_dot_target(lists.DEBUFFS.THRASH, 8, 4.5, target)
        if thrash_target then
            if energy < 40 then return true end
            if spells.THRASH_CAT:cast(thrash_target, "Thrash (AoE)") then return true end
        end
    end

    -- Moonfire (Lunar Inspiration) - Only prioritized dynamically on lower target counts
    if talent.lunar_inspiration and spell_targets <= 3 then
        local moonfire_target = funcs.get_best_dot_target(lists.DEBUFFS.MOONFIRE, 8, 4.2, target)
        if moonfire_target then
            if energy < 30 then return true end
            if spells.MOONFIRE_CAT:cast(moonfire_target, "Moonfire (AoE)") then return true end
        end
    end

    -- Swipe / Brutal Slash
    if spells.BRUTAL_SLASH:is_learned() and spells.BRUTAL_SLASH:cooldown_up() then
        if me:has_buff(lists.BUFFS.SUDDEN_AMBUSH) and spell_targets >= 5 then
            if spells.BRUTAL_SLASH:cast(target, "Brutal Slash (Sudden Ambush)") then return true end
        end
    elseif spells.SWIPE_CAT:is_learned() and spells.SWIPE_CAT:cooldown_up() then
        if me:has_buff(lists.BUFFS.SUDDEN_AMBUSH) and spell_targets >= 5 then
            if spells.SWIPE_CAT:cast(target, "Swipe (Sudden Ambush)") then return true end
        end
    end

    if combo_points <= 1 and spell_targets == 2 and talent.panthers_guile then
        if energy < 40 then return true end
        if spells.SHRED:cast(target, "Shred (Guile)") then return true end
    end

    if combo_points > 1 or spell_targets > 2 or not talent.panthers_guile then
        if spells.BRUTAL_SLASH:is_learned() and spells.BRUTAL_SLASH:cooldown_up() then
            if energy < 25 then return true end
            if spells.BRUTAL_SLASH:cast(target, "Brutal Slash") then return true end
        elseif spells.SWIPE_CAT:is_learned() and spells.SWIPE_CAT:cooldown_up() then
            if energy < 35 then return true end
            if spells.SWIPE_CAT:cast(target, "Swipe") then return true end
        end
    end
    return false
end

-- APL: aoe_finisher
actionList.aoe_finisher = function(target, spell_targets, combo_points, energy)
    local has_bs = me:has_buff(lists.BUFFS.BERSERK) or me:has_buff(lists.BUFFS.INCARNATION)
    local pw_remains = funcs.get_debuff_remains(target, lists.DEBUFFS.PRIMAL_WRATH)
    local pw_ticking = pw_remains > 0

    if spells.PRIMAL_WRATH:is_learned() and combo_points >= 5 and spell_targets > 1 then
        if pw_remains < 6.5 and not has_bs or not pw_ticking then
            if energy < 20 then return true end
            if spells.PRIMAL_WRATH:cast(target, "Primal Wrath") then return true end
        end
    end

    if me:has_buff(lists.BUFFS.RAVAGE) and combo_points >= 4 and not talent.primal_wrath and spell_targets >= 2 then
        if energy < 50 and not me:has_buff(lists.BUFFS.APEX_PREDATORS_CRAVING) then return true end
        if spells.FEROCIOUS_BITE:cast(target, "Ferocious Bite (Ravage)") then return true end
    end

    if not talent.primal_wrath and combo_points >= 4 then
        local rip_target = funcs.get_best_dot_target(lists.DEBUFFS.RIP, 8, 7, target)
        if rip_target then
            if energy < 30 then return true end
            if spells.RIP:cast(rip_target, "Rip (spread)") then return true end
        end
    end

    if spells.PRIMAL_WRATH:is_learned() and combo_points >= 5 then
        if energy < 20 then return true end
        if spells.PRIMAL_WRATH:cast(target, "Primal Wrath (Fallback)") then return true end
    end

    if combo_points >= 4 + (talent.primal_wrath and 1 or 0) or me:has_buff(lists.BUFFS.APEX_PREDATORS_CRAVING) then
        if energy < 50 and not me:has_buff(lists.BUFFS.APEX_PREDATORS_CRAVING) then return true end
        if spells.FEROCIOUS_BITE:cast(target, "Ferocious Bite (AoE)") then return true end
    end

    return false
end

-- APL: builder
actionList.builder = function(target, spell_targets, combo_points, energy)
    local is_prowled = me:has_buff(lists.BUFFS.PROWL) or me:has_buff(lists.BUFFS.SHADOWMELD)
    if not is_prowled and funcs.get_debuff_remains(target, lists.DEBUFFS.RAKE) < 4.5 then
        if spells.SHADOWMELD:is_learned() and spells.SHADOWMELD:cooldown_up() then
            if spells.SHADOWMELD:cast(me, "Shadowmeld") then return true end
        end
    end

    -- Ensure basic Rake uptime securely and spread if able
    local rake_target = funcs.get_best_dot_target(lists.DEBUFFS.RAKE, 8, 4.5, target)
    if rake_target then
        if energy < 35 then return true end
        if spells.RAKE:cast(rake_target, "Rake") then return true end
    end

    -- Moonfire (Lunar Inspiration)
    if talent.lunar_inspiration then
        local moonfire_target = funcs.get_best_dot_target(lists.DEBUFFS.MOONFIRE, 8, 4.2, target)
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
actionList.finisher = function(target, spell_targets, combo_points, energy)
    if combo_points >= 4 then
        local rip_target = funcs.get_best_dot_target(lists.DEBUFFS.RIP, 8, 7, target)
        if rip_target then
            if energy < 30 then return true end
            if spells.RIP:cast(rip_target, "Rip") then return true end
        end
    end

    local has_bs = me:has_buff(lists.BUFFS.BERSERK) or me:has_buff(lists.BUFFS.INCARNATION)
    if combo_points >= 4 + (has_bs and 1 or 0) then
        if energy < 50 and not me:has_buff(lists.BUFFS.APEX_PREDATORS_CRAVING) then return true end
        if spells.FEROCIOUS_BITE:cast(target, "Ferocious Bite") then return true end
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

    update_variables()

    local spell_targets = funcs.count_enemies_in_range(8)
    local combo_points = me:get_power(4) or 0
    local target = funcs.get_dps_target(25)

    -- Precombat
    if not me:affecting_combat() then
        if not me:has_buff(lists.BUFFS.CAT_FORM) then
            spells.CAT_FORM:cast(me, "Cat Form")
            return
        end
        if not me:has_buff(lists.BUFFS.PROWL) and not me:has_buff(lists.BUFFS.SHADOWMELD) then
            spells.PROWL:cast(me, "Prowl")
            return
        end
        return
    end

    if not target then return end

    local has_bs = me:has_buff(lists.BUFFS.BERSERK) or me:has_buff(lists.BUFFS.INCARNATION)
    local is_prowled = me:has_buff(lists.BUFFS.PROWL) or me:has_buff(lists.BUFFS.SHADOWMELD)

    -- APL Main Loop
    if variable.use_custom_timers then
        actionList.custom_timers()
    end

    local tf_dur = 10 -- aprox duration
    if (not variable.use_custom_timers and (spells.TIGERS_FURY:cooldown_remains() < tf_dur - 1.5)) or (variable.tfNow and spells.TIGERS_FURY:cooldown_up()) then
        if spells.TIGERS_FURY:cast(me, "Tiger's Fury") then return end
    end

    if is_prowled then
        if spells.RAKE:cast(target, "Rake out of stealth") then return end
    end

    -- if buff.chomp_enabler then cast chomp (ravage) (NYI in simple version unless mapped to FB with ravage)
    if actionList.cooldown(target, spell_targets) then return end

    if me:has_buff(lists.BUFFS.APEX_PREDATORS_CRAVING) then
        if spells.FEROCIOUS_BITE:cast(target, "Ferocious Bite (Apex)") then return end
    end

    local is_aoe = spell_targets >= 2
    local energy = me:get_power(3) or 0

    if is_aoe then
        if actionList.aoe_finisher(target, spell_targets, combo_points, energy) then return end
    else
        if actionList.finisher(target, spell_targets, combo_points, energy) then return end
    end

    if is_aoe then
        if combo_points <= 4 then
            if actionList.aoe_builder(target, spell_targets, combo_points, energy) then return end
        end
    else
        if combo_points <= 4 then
            if actionList.builder(target, spell_targets, combo_points, energy) then return end
        end
    end

    if me:has_buff(lists.BUFFS.PREDATORY_SWIFTNESS) and variable.regrowth then
        local hp_pct = me:get_health_percentage()
        if hp_pct < 80 then
            if spells.REGROWTH:cast(me, "Regrowth (Swiftness)") then return end
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
