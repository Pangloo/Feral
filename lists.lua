local Lists = {}

Lists.BUFFS = {
    CAT_FORM = 768,
    PROWL = 5215,
    TIGERS_FURY = 5217,
    SHADOWMELD = 58984,
    BERSERK = 106951,
    INCARNATION = 102543,
    CLEARCASTING = 135700,
    APEX_PREDATORS_CRAVING = 391882,
    PREDATORY_SWIFTNESS = 69369,
    SUDDEN_AMBUSH = 385009,
    RAVAGE = 400494,        -- Just placeholder for ravage/chomp enabler
    CHOMP_ENABLER = 400494, -- placeholder
    TRAVEL_FORM = 783,
}

Lists.DEBUFFS = {
    RAKE = 155722,
    RIP = 1079,
    PRIMAL_WRATH = 285381,
    THRASH = 106830,
    MOONFIRE = 155625,
    BLOODSEEKER_VINES = 400495, -- placeholder
}

Lists.DISPEL_LOGIC = {
    -- Example: [spell_id] = { priority = 1, stacks = 1 }
}

Lists.SPECIAL_DISPELS = {
    -- White-listed dangerous spells that might not show up as standard debuff types
}

Lists.THREAT_BYPASS_UNITS = {
    -- Units that should be attacked even if they have no threat
    [196642] = true, -- hungry_lasher
    [243208] = true, -- dummy
    [259569] = true, -- mana battery 1
    [252825] = true, -- mana battery 2
}


Lists.ENEMY_BLACKLIST_WITH_BUFFS = {
    [252918] = { 1249714 }, -- abyssal-voidshaper with umbral barrier
    [240435] = { 1253918 }, -- imperators glory
}

return Lists
