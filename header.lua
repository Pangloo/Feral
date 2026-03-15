local plugin = {}

plugin.name = "Feral"
plugin.version = "1.0.0"
plugin.author = "Panglo"
plugin.load = true

local local_player = core.object_manager.get_local_player()
if not local_player then
    plugin.load = false
    return plugin
end

-- Check if druid (class id 11)
if local_player:get_class() ~= 11 then
    plugin.load = false
    return plugin
end

-- check if spec id is Feral (2)
if core.spell_book.get_specialization_id() ~= 2 then
    plugin.load = false
    return plugin
end

return plugin
