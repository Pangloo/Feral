-- menu.lua
local Menu = {}
local ID = "feral_reality_"
local control_panel_utility = require("common/utility/control_panel_helper")

local main_tree = core.menu.tree_node()
local tree_rotation = core.menu.tree_node()
local tree_settings = core.menu.tree_node()

Menu.ENABLED = core.menu.checkbox(true, ID .. "enabled")
Menu.SHOW_UI = core.menu.checkbox(true, ID .. "show_ui")
Menu.ENABLE_ROTATION = core.menu.keybind(999, true, ID .. "rot_enabled")

Menu.USE_COOLDOWNS = core.menu.keybind(999, true, ID .. "use_cds")
Menu.AUTO_INTERRUPT = core.menu.keybind(999, true, ID .. "auto_interrupt")
Menu.AUTO_DISPEL = core.menu.keybind(999, true, ID .. "auto_dispel")

Menu.REGROWTH = core.menu.checkbox(false, ID .. "regrowth")
Menu.FRENZY_TF_ONLY = core.menu.checkbox(true, ID .. "frenzy_tf_only")
Menu.AUTO_TRAVEL = core.menu.checkbox(true, ID .. "auto_travel")

function Menu.draw()
    main_tree:render("Feral Druid", function()
        tree_rotation:render("General & Rotation", function()
            Menu.ENABLED:render("Enable Plugin")
            Menu.SHOW_UI:render("Show UI Hotbar")
            Menu.ENABLE_ROTATION:render("Enable Rotation")
            Menu.USE_COOLDOWNS:render("Use Cooldowns")
            Menu.AUTO_INTERRUPT:render("Auto Interrupt")
            Menu.AUTO_DISPEL:render("Auto Dispel")
        end)
        tree_settings:render("Settings", function()
            Menu.REGROWTH:render("Use Regrowth with Predatory Swiftness")
            Menu.FRENZY_TF_ONLY:render("Feral/Frantic Frenzy with Tiger's Fury only")
            Menu.AUTO_TRAVEL:render("Auto Travel Form")
        end)
    end)
end

function Menu.is_enabled()
    return Menu.ENABLED:get_state()
end

function Menu.is_rotation_enabled()
    return Menu.ENABLE_ROTATION:get_toggle_state()
end

core.register_on_render_control_panel_callback(function()
    local cp_table = {}
    control_panel_utility:insert_toggle_(cp_table, "Rotation", Menu.ENABLE_ROTATION, false)
    control_panel_utility:insert_toggle_(cp_table, "CDs", Menu.USE_COOLDOWNS, false)
    control_panel_utility:insert_toggle_(cp_table, "Kick", Menu.AUTO_INTERRUPT, false)
    control_panel_utility:insert_toggle_(cp_table, "Dispel", Menu.AUTO_DISPEL, false)
    return cp_table
end)

return Menu
