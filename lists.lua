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
    [440313] = true, -- affix
}

Lists.THREAT_BYPASS_UNITS = {
    -- Units that should be attacked even if they have no threat
    [196642] = true, -- hungry_lasher
    [243208] = true, -- dummy
    [259569] = true, -- mana battery 1
}


Lists.ENEMY_BLACKLIST_WITH_BUFFS = {
    [252918] = { 1249714 }, -- abyssal-voidshaper with umbral barrier
    [240435] = { 1253918 }, -- imperators glory
}

Lists.TTD_BYPASS_UNITS = {
    -- Units that should be attacked regardless of TTD
    [214650] = true, -- lura
    [240387] = true, -- beloren
    [244761] = true, -- alleria-windrunner
    [254174] = true, -- morium
    [254173] = true, -- demiar
    [254172] = true, -- vorelus
    [250589] = true, -- war-chaplain-senn
    [250588] = true, -- commander-venel-lightblood
    [250587] = true, -- general-amias-bellamy
    [244552] = true, -- ezzorak
    [242056] = true, -- vaelgor
    [240432] = true, -- fallen-king-salhadaar
    [240434] = true, -- vorasius
    [240435] = true, -- imperator-averzian
    [231865] = true, -- degentrius
    [231863] = true, -- seranel-sunlash
    [231861] = true, -- arcanotron-custos
    [231864] = true, -- gemellus
    [239636] = true, -- gemellus
    [247570] = true, -- murojin
    [248605] = true, -- raktul
    [248595] = true, -- vordaza
    [247572] = true, -- nekraxx
    [254227] = true, -- corewarden-nysarra
    [241546] = true, -- lothraxion
    [241539] = true, -- kasreth
    [231631] = true, -- commander-kroluk
    [231606] = true, -- emberdawn
    [231626] = true, -- kalis
    [231636] = true, -- restless-heart
    [231629] = true, -- latch
    [191736] = true, -- crawth
    [190609] = true, -- echo-of-doragosa
    [196482] = true, -- overgrown-ancient
    [194181] = true, -- vexamus
    [124729] = true, -- lura
    [122316] = true, -- saprish
    [122319] = true, -- darkfang
    [124309] = true, -- viceroy-nezhar
    [122313] = true, -- zuraal-the-ascended
    [76141] = true, -- araknath
    [76266] = true, -- high-sage-viryx
    [75964] = true, -- ranjit
    [76379] = true, -- rukhran
    [36494] = true, -- forgemaster-garfrost
    [36476] = true, -- ick
    [36477] = true, -- krick
    [36658] = true, -- scourgelord-tyrannus
}



return Lists
