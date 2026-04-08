local M = {}

local BACKUP_REGISTRY_PATH = "KeybindDeblocker_backups.json"
local BACKUP_REGISTRY_VERSION = 1
local KEYBOARD_MENU_VISIBLE_GRACE_SECONDS = 0.25
local INITIAL_BACKUP_STABILITY_CHECK_INTERVAL_SECONDS = 0.25
local INITIAL_BACKUP_STABILITY_MIN_SECONDS = 1.5
local INITIAL_BACKUP_STABILITY_MIN_MATCHES = 3
local HOOK_INSTALL_RETRY_INTERVAL_SECONDS = 1.0
local TITLE_MENU_FLOW_TITLE_MENU = 1

local get_save_flow_type_name

local function safe_log(message)
    if log and log.info then
        log.info("[KeybindDeblocker] " .. message)
    end
end

local function safe_warn(message)
    if log and log.warn then
        log.warn("[KeybindDeblocker] " .. message)
    elseif log and log.info then
        log.info("[KeybindDeblocker] " .. message)
    end
end

local function safe_call(object, method_name, ...)
    if object == nil then
        return false, nil
    end

    local args = { ... }
    local ok, result = pcall(function()
        return object:call(method_name, table.unpack(args))
    end)

    if not ok then
        return false, result
    end

    return true, result
end

local function get_field(object, name)
    if object == nil then
        return nil
    end

    local ok, value = pcall(function()
        return object:get_field(name)
    end)

    if ok then
        return value
    end

    return nil
end

local function set_field(object, name, value)
    if object == nil then
        return false
    end

    local ok = pcall(function()
        object:set_field(name, value)
    end)

    return ok
end

local function get_elements(container)
    if container == nil then
        return {}
    end

    if type(container) == "table" then
        return container
    end

    local ok, elements = pcall(function()
        return container:get_elements()
    end)

    if ok and type(elements) == "table" and next(elements) ~= nil then
        return elements
    end

    local ok_count, count = safe_call(container, "get_Count")
    if ok_count and type(count) == "number" and count > 0 then
        local items = {}
        for index = 0, count - 1 do
            local item_ok, item = safe_call(container, "get_Item", index)
            if item_ok then
                table.insert(items, item)
            end
        end

        if #items > 0 then
            return items
        end
    end

    local items_field = get_field(container, "_items")
    local size_field = get_field(container, "_size")
    local items = get_elements(items_field)
    if type(size_field) == "number" and size_field >= 0 and #items > 0 then
        local trimmed = {}
        for index = 1, math.min(size_field, #items) do
            trimmed[index] = items[index]
        end

        if #trimmed > 0 then
            return trimmed
        end
    end

    if ok and type(elements) == "table" then
        return elements
    end

    return {}
end

local function set_type_field_data(type_name, object, field_name, value)
    if object == nil then
        return false
    end

    local type_def = sdk.find_type_definition(type_name)
    if type_def == nil then
        return false
    end

    local field = type_def:get_field(field_name)
    if field == nil then
        return false
    end

    local ok = pcall(function()
        field:set_data(object, value)
    end)

    return ok
end

local function get_type_field_data(type_name, object, field_name)
    if object == nil then
        return nil
    end

    local type_def = sdk.find_type_definition(type_name)
    if type_def == nil then
        return nil
    end

    local field = type_def:get_field(field_name)
    if field == nil then
        return nil
    end

    local ok, value = pcall(function()
        return field:get_data(object)
    end)

    if ok then
        return value
    end

    return nil
end

local function get_object_type_name(object)
    if object == nil then
        return nil
    end

    local ok, type_def = pcall(function()
        return object:get_type_definition()
    end)

    if not ok or type_def == nil then
        return nil
    end

    local name_ok, full_name = pcall(function()
        return type_def:get_full_name()
    end)

    if name_ok and type(full_name) == "string" and full_name ~= "" then
        return full_name
    end

    local short_ok, short_name = pcall(function()
        return type_def:get_name()
    end)

    if short_ok and type(short_name) == "string" and short_name ~= "" then
        return short_name
    end

    return nil
end

local function to_plain_value(value)
    local value_type = type(value)
    if value == nil or value_type == "number" or value_type == "string" or value_type == "boolean" then
        return value
    end

    local number_ok, number_value = pcall(function()
        return tonumber(value)
    end)
    if number_ok and type(number_value) == "number" then
        return number_value
    end

    local string_ok, string_value = pcall(function()
        return tostring(value)
    end)
    if string_ok and type(string_value) == "string" then
        return string_value
    end

    return nil
end

local function is_title_flow_active()
    local controller = sdk.get_managed_singleton("app.TitleController")
    if controller == nil then
        return false
    end

    local current_flow = get_type_field_data("app.TitleFlowControllerBase", controller, "_CurFlow")
    local next_flow = get_type_field_data("app.TitleFlowControllerBase", controller, "_NextFlow")

    local current_type_name = get_object_type_name(current_flow)
    local next_type_name = get_object_type_name(next_flow)

    if type(current_type_name) == "string" and current_type_name:find("app.TitleController.", 1, true) == 1 then
        return true
    end

    if type(next_type_name) == "string" and next_type_name:find("app.TitleController.", 1, true) == 1 then
        return true
    end

    return false
end

local function is_title_menu_ready()
    local controller = sdk.get_managed_singleton("app.TitleController")
    if controller == nil then
        return false
    end

    local current_flow = get_type_field_data("app.TitleFlowControllerBase", controller, "_CurFlow")
    if get_object_type_name(current_flow) ~= "app.TitleController.cTitleMenu" then
        return false
    end

    local menu_flow = to_plain_value(get_field(current_flow, "menu_flow"))
    local req_flow = to_plain_value(get_field(current_flow, "req_flow"))

    return menu_flow == TITLE_MENU_FLOW_TITLE_MENU and req_flow == TITLE_MENU_FLOW_TITLE_MENU
end

local function is_in_game_player_state_ready()
    if is_title_flow_active() then
        return false
    end

    local player_manager = sdk.get_managed_singleton("app.PlayerManager")
    if player_manager == nil then
        return false
    end

    local current_max_player_num = get_field(player_manager, "_CurrentMaxPlayerNum")
    if type(current_max_player_num) == "number" and current_max_player_num > 0 then
        return true
    end

    local player_list = get_field(player_manager, "_PlayerList")
    if player_list ~= nil then
        local players = get_elements(player_list)
        if #players > 0 then
            return true
        end
    end

    return false
end

local function update_save_load_completion_state(app)
    local flow = get_save_flow_type_name()
    local current = flow.current

    if current == "app.SaveDataManager.cFlowLoadDone" then
        app.state.initial_backup_saw_save_load_done = true
    end
end

local function is_initial_backup_source_ready(app)
    if app == nil or app.state.initial_backup_saw_save_load_done ~= true then
        return false
    end

    if is_title_menu_ready() then
        return true
    end

    if is_in_game_player_state_ready() then
        return true
    end

    return false
end

local function get_type_methods(type_name)
    local type_def = sdk.find_type_definition(type_name)
    if type_def == nil then
        return {}
    end

    local ok, methods = pcall(function()
        return type_def:get_methods()
    end)

    if ok then
        return get_elements(methods)
    end

    return {}
end

local function find_method(type_name, candidates)
    if type(candidates) == "string" then
        candidates = { candidates }
    end

    local type_def = sdk.find_type_definition(type_name)
    if type_def == nil then
        return nil, nil
    end

    for _, candidate in ipairs(candidates or {}) do
        local ok, method = pcall(function()
            return type_def:get_method(candidate)
        end)

        if ok and method ~= nil then
            return method, candidate
        end
    end

    for _, method in ipairs(get_type_methods(type_name)) do
        local ok, method_name = pcall(function()
            return method:get_name()
        end)

        if ok and type(method_name) == "string" then
            for _, candidate in ipairs(candidates or {}) do
                if method_name == candidate or method_name:find(candidate, 1, true) == 1 then
                    return method, method_name
                end
            end
        end
    end

    return nil, nil
end

local function count_table_entries(values)
    local count = 0
    for _ in pairs(values or {}) do
        count = count + 1
    end
    return count
end

local function trim_string(value)
    local text = tostring(value or "")
    return text:match("^%s*(.-)%s*$")
end

local function make_timestamp_id(app)
    app.state.backup_id_serial = (app.state.backup_id_serial or 0) + 1
    return string.format(
        "%s_%03d_%03d",
        os.date("%Y%m%d_%H%M%S"),
        math.floor((os.clock() * 1000) % 1000),
        app.state.backup_id_serial % 1000
    )
end

local function make_timestamp_label(prefix)
    return string.format("%s %s", prefix, os.date("%Y-%m-%d %H:%M:%S"))
end

local function get_save_chain()
    local manager = sdk.get_managed_singleton("app.SaveDataManager")
    local system_save_data = get_field(manager, "_SystemSaveData")
    local system_save_param = get_field(system_save_data, "_Data")
    local system_common = get_field(system_save_param, "_SystemCommon")
    local keyboard_list = get_field(system_common, "_KeyConfigKeyboard")

    return {
        manager = manager,
        system_save_data = system_save_data,
        system_save_param = system_save_param,
        system_common = system_common,
        keyboard_list = keyboard_list,
    }
end

get_save_flow_type_name = function()
    local chain = get_save_chain()
    return {
        current = get_object_type_name(get_field(chain.manager, "_CurFlow")),
        next = get_object_type_name(get_field(chain.manager, "_NextFlow")),
    }
end

local function run_keyboard_list_post_edit(keyboard_list)
    safe_call(keyboard_list, "setupBeforeSaveUserEdit")
    safe_call(keyboard_list, "runSaveData")
    safe_call(keyboard_list, "setupAfterLoadUserEdit")
end

local function normalize_backup_snapshot(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.configs) ~= "table" then
        return nil
    end

    local normalized = {
        configs = {},
    }

    for _, raw_config in ipairs(snapshot.configs) do
        if type(raw_config) == "table" and type(raw_config.index) == "number" and type(raw_config.entries) == "table" then
            local config = {
                index = raw_config.index,
                sort_id = raw_config.sort_id,
                entries = {},
            }

            for _, raw_entry in ipairs(raw_config.entries) do
                if type(raw_entry) == "table" and type(raw_entry.index) == "number" then
                    table.insert(config.entries, {
                        index = raw_entry.index,
                        main_key = raw_entry.main_key,
                        sub_key = raw_entry.sub_key,
                    })
                end
            end

            table.insert(normalized.configs, config)
        end
    end

    if #normalized.configs == 0 then
        return nil
    end

    return normalized
end

local function new_backup_registry()
    return {
        version = BACKUP_REGISTRY_VERSION,
        initial_backup_created = false,
        backups = {},
    }
end

local function normalize_backup_entry(raw_entry, fallback_index)
    if type(raw_entry) ~= "table" then
        return nil
    end

    local snapshot = normalize_backup_snapshot(raw_entry.snapshot)
    if snapshot == nil then
        return nil
    end

    local created_at_local = trim_string(raw_entry.created_at_local)
    if created_at_local == "" then
        created_at_local = os.date("%Y-%m-%d %H:%M:%S")
    end

    local label = trim_string(raw_entry.label)
    if label == "" then
        label = "Backup " .. created_at_local
    end

    local id = trim_string(raw_entry.id)
    if id == "" then
        id = string.format("legacy_%d", fallback_index)
    end

    return {
        id = id,
        created_at_local = created_at_local,
        label = label,
        snapshot = snapshot,
    }
end

local function normalize_backup_registry(raw_registry)
    local registry = new_backup_registry()

    if type(raw_registry) ~= "table" then
        return registry
    end

    registry.version = BACKUP_REGISTRY_VERSION
    registry.initial_backup_created = raw_registry.initial_backup_created == true

    if type(raw_registry.backups) == "table" then
        for index, raw_entry in ipairs(raw_registry.backups) do
            local entry = normalize_backup_entry(raw_entry, index)
            if entry ~= nil then
                table.insert(registry.backups, entry)
            end
        end
    end

    return registry
end

local function load_backup_registry(app)
    if app.state.backups_registry ~= nil then
        return app.state.backups_registry
    end

    local raw_registry = json.load_file(BACKUP_REGISTRY_PATH)
    local registry = normalize_backup_registry(raw_registry)
    app.state.backups_registry = registry
    json.dump_file(BACKUP_REGISTRY_PATH, registry)
    return registry
end

local function save_backup_registry(app)
    local registry = load_backup_registry(app)
    json.dump_file(BACKUP_REGISTRY_PATH, registry)
end

local function find_backup_entry_by_id(app, backup_id)
    local registry = load_backup_registry(app)
    for index, entry in ipairs(registry.backups) do
        if entry.id == backup_id then
            return entry, index, registry
        end
    end

    return nil, nil, registry
end

local function build_keyboard_snapshot()
    local chain = get_save_chain()
    local keyboard_list = chain.keyboard_list
    if keyboard_list == nil then
        return nil, "live keyboard config list is unavailable"
    end

    local snapshot = {
        configs = {},
    }

    local configs = get_elements(get_field(keyboard_list, "_KeyCon"))
    for config_index, config in ipairs(configs) do
        local saved_config = {
            index = config_index,
            sort_id = get_field(config, "SortID"),
            entries = {},
        }

        local entries = get_elements(get_field(config, "_KeyData"))
        for entry_index, entry in ipairs(entries) do
            table.insert(saved_config.entries, {
                index = entry_index,
                main_key = get_field(entry, "MainKey"),
                sub_key = get_field(entry, "SubKey"),
            })
        end

        table.insert(snapshot.configs, saved_config)
    end

    if #snapshot.configs == 0 then
        return nil, "live keyboard config list is empty"
    end

    return snapshot, nil
end

local function make_snapshot_signature(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.configs) ~= "table" then
        return nil
    end

    local chunks = {}
    for _, config in ipairs(snapshot.configs) do
        chunks[#chunks + 1] = string.format("C:%s:%s|", tostring(config.index), tostring(config.sort_id))
        for _, entry in ipairs(config.entries or {}) do
            chunks[#chunks + 1] = string.format(
                "E:%s:%s:%s|",
                tostring(entry.index),
                tostring(entry.main_key),
                tostring(entry.sub_key)
            )
        end
    end

    return table.concat(chunks)
end

local function apply_keyboard_snapshot(snapshot)
    local normalized_snapshot = normalize_backup_snapshot(snapshot)
    if normalized_snapshot == nil then
        return false, "backup snapshot is missing or invalid"
    end

    local chain = get_save_chain()
    local keyboard_list = chain.keyboard_list
    if keyboard_list == nil then
        return false, "live keyboard config list is unavailable"
    end

    local live_configs = get_elements(get_field(keyboard_list, "_KeyCon"))
    local restored_configs = 0

    for _, saved_config in ipairs(normalized_snapshot.configs) do
        local live_config = live_configs[saved_config.index]
        if live_config ~= nil then
            if saved_config.sort_id ~= nil then
                set_field(live_config, "SortID", saved_config.sort_id)
            end

            local live_entries = get_elements(get_field(live_config, "_KeyData"))
            for _, saved_entry in ipairs(saved_config.entries or {}) do
                local live_entry = live_entries[saved_entry.index]
                if live_entry ~= nil then
                    set_field(live_entry, "MainKey", saved_entry.main_key)
                    set_field(live_entry, "SubKey", saved_entry.sub_key)
                end
            end

            local apply_sort_id = get_field(live_config, "SortID")
            if type(apply_sort_id) == "number" and apply_sort_id >= 0 then
                safe_call(live_config, "applyData", apply_sort_id)
            end

            restored_configs = restored_configs + 1
        end
    end

    run_keyboard_list_post_edit(keyboard_list)
    return restored_configs > 0, restored_configs
end

local function set_backup_error(app, message)
    app.state.backup_error = message
    safe_warn(message)
end

local function clear_backup_error(app)
    app.state.backup_error = nil
end

local function create_backup_entry(app, label)
    local registry = load_backup_registry(app)
    local snapshot, message = build_keyboard_snapshot()
    if snapshot == nil then
        return false, message
    end

    local entry = {
        id = make_timestamp_id(app),
        created_at_local = os.date("%Y-%m-%d %H:%M:%S"),
        label = label,
        snapshot = snapshot,
    }

    table.insert(registry.backups, 1, entry)
    save_backup_registry(app)
    return true, entry
end

local function ensure_initial_backup(app)
    if app.state.initial_backup_checked then
        return
    end

    local registry = load_backup_registry(app)
    local needs_initial_backup = (registry.initial_backup_created ~= true) or (#registry.backups == 0)
    if not needs_initial_backup then
        app.state.initial_backup_checked = true
        return
    end

    update_save_load_completion_state(app)

    if not is_initial_backup_source_ready(app) then
        app.state.initial_backup_candidate_signature = nil
        app.state.initial_backup_candidate_first_seen_clock = nil
        app.state.initial_backup_candidate_match_count = 0
        app.state.initial_backup_next_probe_clock = nil
        return
    end

    local now_clock = os.clock()
    if now_clock < (app.state.initial_backup_next_probe_clock or 0) then
        return
    end
    app.state.initial_backup_next_probe_clock = now_clock + INITIAL_BACKUP_STABILITY_CHECK_INTERVAL_SECONDS

    local snapshot = build_keyboard_snapshot()
    if snapshot == nil then
        app.state.initial_backup_candidate_signature = nil
        app.state.initial_backup_candidate_first_seen_clock = nil
        app.state.initial_backup_candidate_match_count = 0
        return
    end

    local signature = make_snapshot_signature(snapshot)
    if signature == nil then
        return
    end

    if signature ~= app.state.initial_backup_candidate_signature then
        app.state.initial_backup_candidate_signature = signature
        app.state.initial_backup_candidate_first_seen_clock = now_clock
        app.state.initial_backup_candidate_match_count = 1
        return
    end

    app.state.initial_backup_candidate_match_count = (app.state.initial_backup_candidate_match_count or 0) + 1

    local first_seen_clock = app.state.initial_backup_candidate_first_seen_clock or now_clock
    local stable_for_seconds = now_clock - first_seen_clock
    if stable_for_seconds < INITIAL_BACKUP_STABILITY_MIN_SECONDS then
        return
    end

    if (app.state.initial_backup_candidate_match_count or 0) < INITIAL_BACKUP_STABILITY_MIN_MATCHES then
        return
    end

    local entry = {
        id = make_timestamp_id(app),
        created_at_local = os.date("%Y-%m-%d %H:%M:%S"),
        label = make_timestamp_label("Initial backup"),
        snapshot = snapshot,
    }

    table.insert(registry.backups, 1, entry)

    registry.initial_backup_created = true
    save_backup_registry(app)
    app.state.initial_backup_checked = true
    clear_backup_error(app)
    safe_log("Created the initial keybind backup.")
end

local function is_keyboard_config_ui_open(app)
    return os.clock() < (app.state.keyboard_menu_visible_until_clock or 0)
end

local function snapshot_gui010202_state(gui)
    if gui == nil then
        return nil
    end

    return {
        _ErrorIndex = get_field(gui, "_ErrorIndex"),
        _ListError = get_field(gui, "_ListError"),
        _IsNoneOverlapp = get_field(gui, "_IsNoneOverlapp"),
    }
end

local function snapshot_has_gui_error(snapshot)
    if type(snapshot) ~= "table" then
        return false
    end

    if snapshot._ListError == true then
        return true
    end

    return type(snapshot._ErrorIndex) == "number" and snapshot._ErrorIndex >= 0
end

local function snapshot_has_overlap_state(snapshot)
    return type(snapshot) == "table" and snapshot._IsNoneOverlapp == false
end

local function clear_gui010202_error_fields(gui)
    local changed = false
    changed = set_type_field_data("app.GUI010202", gui, "_ListError", false) or changed
    changed = set_type_field_data("app.GUI010202", gui, "_ErrorIndex", -1) or changed
    changed = set_field(gui, "_ListError", false) or changed
    changed = set_field(gui, "_ErrorIndex", -1) or changed
    return changed
end

local function clear_gui010202_root_fields(gui)
    local changed = false
    changed = set_type_field_data("app.GUI010202", gui, "_IsNoneOverlapp", true) or changed
    changed = set_field(gui, "_IsNoneOverlapp", true) or changed
    changed = clear_gui010202_error_fields(gui) or changed
    return changed
end

local function handle_inner_key_list_cancel(app, gui)
    if not app.config.enabled or gui == nil then
        return
    end

    local snapshot = snapshot_gui010202_state(gui)
    local needs_root_clear = snapshot_has_gui_error(snapshot) or snapshot_has_overlap_state(snapshot)
    app.state.pending_root_exit = needs_root_clear

    if snapshot_has_gui_error(snapshot) then
        clear_gui010202_error_fields(gui)
    end
end

local function handle_root_key_list_cancel(app, gui)
    if not app.config.enabled or gui == nil then
        return
    end

    local snapshot = snapshot_gui010202_state(gui)
    local should_clear = app.state.pending_root_exit
        or snapshot_has_gui_error(snapshot)
        or snapshot_has_overlap_state(snapshot)

    if should_clear then
        clear_gui010202_root_fields(gui)
    end

    app.state.pending_root_exit = false
end

local function install_hook_once(app, source, type_name, candidates, pre_hook)
    local hook_state = app.state.native_ui_hooks
    if hook_state.installed_methods[source] ~= nil then
        return true
    end

    local method, matched_name = find_method(type_name, candidates)
    if method == nil then
        hook_state.missing_methods[source] = type_name
        return false
    end

    sdk.hook(method, function(args)
        local ok, result = pcall(pre_hook, args)
        if ok then
            return result
        end

        safe_warn(string.format("%s hook failed: %s", source, tostring(result)))
        return nil
    end, function(retval)
        return retval
    end)

    hook_state.installed_methods[source] = matched_name or candidates[1]
    hook_state.missing_methods[source] = nil
    return true
end

local function install_native_ui_hooks(app)
    local hook_state = app.state.native_ui_hooks
    if hook_state.hooks_installed then
        return
    end

    local now_clock = os.clock()
    if now_clock < (hook_state.next_retry_clock or 0) then
        return
    end

    hook_state.next_retry_clock = now_clock + HOOK_INSTALL_RETRY_INTERVAL_SECONDS
    local required_hook_count = 5
    local was_installed = hook_state.hooks_installed == true

    install_hook_once(
        app,
        "gui010202.guiVisibleUpdate",
        "app.GUI010202",
        { "guiVisibleUpdate1190071", "guiVisibleUpdate" },
        function(args)
            local gui = sdk.to_managed_object(args and args[2] or nil)
            if gui ~= nil then
                app.state.keyboard_menu_visible_until_clock = os.clock() + KEYBOARD_MENU_VISIBLE_GRACE_SECONDS
            end
        end
    )

    install_hook_once(
        app,
        "gui010202.callback_KeyListCancel",
        "app.GUI010202",
        { "callback_KeyListCancel1190106", "callback_KeyListCancel" },
        function(args)
            local gui = sdk.to_managed_object(args and args[2] or nil)
            handle_inner_key_list_cancel(app, gui)
        end
    )

    install_hook_once(
        app,
        "gui010202.callback_MysetListCancel",
        "app.GUI010202",
        { "callback_MysetListCancel1190080", "callback_MysetListCancel" },
        function(args)
            local gui = sdk.to_managed_object(args and args[2] or nil)
            handle_root_key_list_cancel(app, gui)
        end
    )

    install_hook_once(
        app,
        "gui010202.callback_WeaponSelectPanelCancel",
        "app.GUI010202",
        { "callback_WeaponSelectPanelCancel1190115", "callback_WeaponSelectPanelCancel" },
        function(args)
            local gui = sdk.to_managed_object(args and args[2] or nil)
            handle_root_key_list_cancel(app, gui)
        end
    )

    install_hook_once(
        app,
        "title.gui010101.checkKeyConfig",
        "app.GUI010101",
        { "checkKeyConfig820725", "checkKeyConfig" },
        function(_)
            if app.config.enabled then
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end
    )

    local installed_count = count_table_entries(hook_state.installed_methods)
    if installed_count ~= (hook_state.last_logged_installed_count or 0) then
        hook_state.last_logged_installed_count = installed_count
        safe_log(string.format(
            "Installed %d/%d keybind bypass hooks.",
            installed_count,
            required_hook_count
        ))
    end

    hook_state.hooks_installed = installed_count >= required_hook_count
    if hook_state.hooks_installed and not was_installed then
        safe_log("Installed all keybind bypass hooks.")
    end
end

function M.create(app)
    local self = {}

    function self.get_status_snapshot()
        local registry = load_backup_registry(app)
        return {
            enabled = app.config.enabled,
            keyboard_config_open = is_keyboard_config_ui_open(app),
            backups = registry.backups,
            backup_error = app.state.backup_error,
            keyboard_list_ready = get_save_chain().keyboard_list ~= nil,
        }
    end

    function self.create_manual_backup()
        local ok, entry_or_message = create_backup_entry(app, make_timestamp_label("Backup"))
        if not ok then
            set_backup_error(app, entry_or_message)
            return false
        end

        clear_backup_error(app)
        safe_log("Created backup \"" .. entry_or_message.label .. "\".")
        return true
    end

    function self.rename_backup(backup_id, new_label)
        local label = trim_string(new_label)
        if label == "" then
            set_backup_error(app, "Backup name cannot be empty.")
            return false
        end

        local entry, _, registry = find_backup_entry_by_id(app, backup_id)
        if entry == nil then
            set_backup_error(app, "Backup was not found.")
            return false
        end

        entry.label = label
        save_backup_registry(app)
        clear_backup_error(app)
        safe_log("Renamed backup to \"" .. label .. "\".")
        return true
    end

    function self.delete_backup(backup_id)
        local entry, index, registry = find_backup_entry_by_id(app, backup_id)
        if entry == nil or index == nil then
            set_backup_error(app, "Backup was not found.")
            return false
        end

        table.remove(registry.backups, index)
        save_backup_registry(app)
        clear_backup_error(app)
        safe_log("Deleted backup \"" .. entry.label .. "\".")
        return true
    end

    function self.restore_backup(backup_id)
        if is_keyboard_config_ui_open(app) then
            set_backup_error(app, "Restore is unavailable while keyboard configuration is open.")
            return false
        end

        local entry = find_backup_entry_by_id(app, backup_id)
        if entry == nil then
            set_backup_error(app, "Backup was not found.")
            return false
        end

        local ok, restored_or_message = apply_keyboard_snapshot(entry.snapshot)
        if not ok then
            set_backup_error(app, restored_or_message)
            return false
        end

        clear_backup_error(app)
        safe_log("Restored backup \"" .. entry.label .. "\".")
        return true
    end

    function self.update()
        install_native_ui_hooks(app)
        ensure_initial_backup(app)
    end

    return self
end

return M
