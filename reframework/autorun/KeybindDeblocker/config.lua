local M = {}

local CONFIG_PATH = "KeybindDeblocker_config.json"

function M.defaults()
    return {
        enabled = true,
    }
end

function M.load()
    local config = M.defaults()
    local saved = json.load_file(CONFIG_PATH)
    if type(saved) == "table" and type(saved.enabled) == "boolean" then
        config.enabled = saved.enabled
    end

    json.dump_file(CONFIG_PATH, config)
    return config
end

function M.save(config)
    json.dump_file(CONFIG_PATH, {
        enabled = config.enabled == true,
    })
end

return M
