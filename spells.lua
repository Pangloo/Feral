local spell_helper = require("common/utility/spell_helper")
local spell_queue = require("common/modules/spell_queue")

local function create_spell(id)
    return {
        id = id,
        is_learned = function(self)
            return core.spell_book.is_spell_learned(self.id)
        end,
        cooldown_up = function(self)
            return not spell_helper:is_spell_on_cooldown(self.id)
        end,
        cooldown_remains = function(self)
            local current = core.spell_book.get_spell_cooldown(self.id)
            return current or 0
        end,
        cast = function(self, target, reason, options)
            options = options or {}
            local local_player = core.object_manager.get_local_player()
            if not spell_helper:is_spell_castable(self.id, local_player, target, options.skip_facing, true) then
                return false
            end
            spell_queue:queue_spell_target(self.id, target, 1, reason or "Casting Spell")
            return true
        end,
        is_castable_to_unit = function(self, unit, options)
            options = options or {}
            local local_player = core.object_manager.get_local_player()
            return spell_helper:is_spell_castable(self.id, local_player, unit, options.skip_facing, true)
        end
    }
end

local Spells = {
    CAT_FORM = create_spell(768),
    PROWL = create_spell(5215),
    TIGERS_FURY = create_spell(5217),
    RAKE = create_spell(1822),
    FEROCIOUS_BITE = create_spell(22568),
    REGROWTH = create_spell(8936),
    MOONFIRE_CAT = create_spell(8921),
    SWIPE_CAT = create_spell(213764),
    BRUTAL_SLASH = create_spell(202028),
    THRASH_CAT = create_spell(77758),
    SHRED = create_spell(5221),
    PRIMAL_WRATH = create_spell(285381),
    RIP = create_spell(1079),
    BERSERK = create_spell(106951),
    APEX_PREDATORS_CRAVING = create_spell(391882),

    INCARNATION = create_spell(102543),
    FERAL_FRENZY = create_spell(274837),
    CONVOKE_THE_SPIRITS = create_spell(391528),

    -- Talents
    WILD_SLASHES = create_spell(390864),
    INFECTED_WOUNDS = create_spell(48484),
    BERSERK_HEART_OF_THE_LION = create_spell(391174),
    FRANTIC_FRENZY = create_spell(1243807),
    DOUBLECLAWED_RAKE = create_spell(391700),
    LUNAR_INSPIRATION = create_spell(155580),
    PANTHERS_GUILE = create_spell(1280316),
    RAMPANT_FEROCITY = create_spell(391709),
    SABER_JAWS = create_spell(421432),
    ASHAMANES_GUIDANCE = create_spell(391548),
    THRIVING_GROWTH = create_spell(439528),

    -- Adding shadowmeld, berserking, potion, etc.
    SHADOWMELD = create_spell(58984),
    BERSERKING = create_spell(26297),
    TRAVEL_FORM = create_spell(783),
    SKULL_BASH = create_spell(106839),
    REMOVE_CORRUPTION = create_spell(2782),
    MARK_OF_THE_WILD = create_spell(1126),
}

return Spells
