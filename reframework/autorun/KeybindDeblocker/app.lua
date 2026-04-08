local Config = require("KeybindDeblocker.config")
local Runtime = require("KeybindDeblocker.runtime")
local Menu = require("KeybindDeblocker.menu")

local M = {}

function M.init()
    local config = Config.load()
    local app = {
        config_module = Config,
        config = config,
        state = {
            backup_error = nil,
            backups_registry = nil,
            backup_id_serial = 0,
            initial_backup_checked = false,
            initial_backup_saw_save_load_done = false,
            keyboard_menu_visible_until_clock = 0,
            pending_root_exit = false,
            native_ui_hooks = {
                hooks_installed = false,
                next_retry_clock = 0,
                last_logged_installed_count = 0,
                installed_methods = {},
                missing_methods = {},
            },
        },
    }

    app.runtime = Runtime.create(app)
    app.menu = Menu.create(app)

    app.save_config = function()
        Config.save(app.config)
    end

    re.on_frame(function()
        app.runtime.update()
    end)

    re.on_draw_ui(function()
        app.menu.draw()
    end)
end

return M
