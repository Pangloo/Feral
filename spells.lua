local spell_queue = require("common/modules/spell_queue")

local function create_spell(id, is_off_gcd)
    return {
        id = id,
        is_off_gcd = is_off_gcd or false,
        last_cast = 0,
        is_learned = function(self)
            return core.spell_book.is_spell_learned(self.id)
        end,
        cooldown_up = function(self)
            return core.spell_book.get_spell_cooldown(self.id) <= 0
        end,
        cooldown_remains = function(self)
            local current = core.spell_book.get_spell_cooldown(self.id)
            return current or 0
        end,
        cast = function(self, target, reason, options)
            if not target then return false end
            -- core.time() returns milliseconds
            local now = core.time()
            if self.is_off_gcd then
                if now - self.last_cast < 0.500 then return false end
            else
                -- GCD spells: throttle re-queues so the dispatcher isn't fed duplicates
                -- while the cast is still starting (before is_casting() flips true).
                if now - self.last_cast < 0.400 then return false end
            end
            options = options or {}
            if not options.skip_castable then
                if not core.spell_book.is_usable_spell(self.id) then
                    return false
                end
            end
            if not self:cooldown_up() then return false end

            if core.input.cast_target_spell(self.id, target) then
                self.last_cast = now
                core.log(reason .. " on target " .. tostring(target:get_name()))
                return true
            end
            return false
        end
    }
end

local Spells = {
    CAT_FORM = create_spell(768),
    PROWL = create_spell(5215, true),
    TIGERS_FURY = create_spell(5217, true),
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
    BERSERK = create_spell(106951, true),
    APEX_PREDATORS_CRAVING = create_spell(391882),

    INCARNATION = create_spell(102543, true),
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
    FLUID_FORM = create_spell(449193),

    -- Adding shadowmeld, berserking, potion, etc.
    SHADOWMELD = create_spell(58984, true),
    BERSERKING = create_spell(26297, true),
    TRAVEL_FORM = create_spell(783),
    SKULL_BASH = create_spell(106839, true),
    REMOVE_CORRUPTION = create_spell(2782),
    MARK_OF_THE_WILD = create_spell(1126),
}

return Spells
