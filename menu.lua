-- menu.lua
local Menu = {}
local ID = "feral_reality_"

local main_tree = core.menu.tree_node()
local tree_rotation = core.menu.tree_node()
local tree_settings = core.menu.tree_node()

Menu.ENABLED = core.menu.checkbox(true, ID .. "enabled")
Menu.ENABLE_ROTATION = core.menu.checkbox(true, ID .. "rot_enabled")
Menu.ENABLE_DPS = core.menu.checkbox(true, ID .. "dps_enabled")

Menu.USE_COOLDOWNS = core.menu.checkbox(true, ID .. "use_cds")
Menu.AUTO_INTERRUPT = core.menu.checkbox(true, ID .. "auto_interrupt")

Menu.REGROWTH = core.menu.checkbox(false, ID .. "regrowth")
Menu.USE_CUSTOM_TIMERS = core.menu.checkbox(false, ID .. "use_custom_timers")

function Menu.draw()
    main_tree:render("Feral Druid", function()
        tree_rotation:render("General & Rotation", function()
            Menu.ENABLED:render("Enable Plugin")
            Menu.ENABLE_ROTATION:render("Enable Rotation")
            Menu.ENABLE_DPS:render("DPS Enabled")
            Menu.USE_COOLDOWNS:render("Use Cooldowns")
            Menu.AUTO_INTERRUPT:render("Auto Interrupt")
        end)
        tree_settings:render("Settings", function()
            Menu.REGROWTH:render("Use Regrowth with Predatory Swiftness")
            Menu.USE_CUSTOM_TIMERS:render("Use Custom Timers (Advanced)")
        end)
    end)
end

function Menu.is_enabled()
    return Menu.ENABLED:get_state()
end

function Menu.is_rotation_enabled()
    return Menu.ENABLE_ROTATION:get_state()
end

return Menu
