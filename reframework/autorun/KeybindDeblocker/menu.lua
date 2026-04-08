local M = {}

local BAD_TEXT_COLOR = 0xff1947ff
local DELETE_BUTTON_COLOR = 0xff1a35b8
local CREATE_BUTTON_COLOR = 0xff2b8a3e
local CANCEL_BUTTON_COLOR = 0xff1f9aa8

local function draw_multiline_text(text)
    for line in tostring(text or ""):gmatch("([^\n]+)") do
        imgui.text(line)
    end
end

local function push_colored_button_text(color)
    imgui.push_style_color(0, color)
end

local function pop_colored_button_text()
    imgui.pop_style_color(1)
end

function M.create(app)
    local self = {
        rename_backup_id = nil,
        rename_value = "",
        confirm_restore_id = nil,
        confirm_delete_id = nil,
    }

    local function clear_entry_actions(backup_id)
        if self.rename_backup_id == backup_id then
            self.rename_backup_id = nil
            self.rename_value = ""
        end

        if self.confirm_restore_id == backup_id then
            self.confirm_restore_id = nil
        end

        if self.confirm_delete_id == backup_id then
            self.confirm_delete_id = nil
        end
    end

    local function draw_backup_actions(status, backup)
        local id_suffix = "##" .. backup.id
        local restore_disabled = status.keyboard_config_open

        if restore_disabled then
            imgui.begin_disabled(true)
        end
        if imgui.button("Restore" .. id_suffix) then
            self.confirm_restore_id = backup.id
            self.confirm_delete_id = nil
        end
        if restore_disabled then
            imgui.end_disabled()
        end

        imgui.same_line()
        if imgui.button("Rename" .. id_suffix) then
            self.rename_backup_id = backup.id
            self.rename_value = backup.label
            self.confirm_restore_id = nil
            self.confirm_delete_id = nil
        end

        imgui.same_line()
        push_colored_button_text(DELETE_BUTTON_COLOR)
        local pressed_delete = imgui.button("Delete" .. id_suffix)
        pop_colored_button_text()
        if pressed_delete then
            self.confirm_delete_id = backup.id
            self.confirm_restore_id = nil
        end
    end

    local function draw_backup_entry(status, backup, is_final_backup)
        imgui.separator()
        draw_multiline_text(backup.label)
        imgui.text("Created: " .. tostring(backup.created_at_local))

        if is_final_backup then
            imgui.text_colored("Warning: this is your final backup. Deleting it removes your last recovery point.", BAD_TEXT_COLOR)
        end

        if self.rename_backup_id == backup.id then
            local changed, new_value = imgui.input_text("Label##rename_" .. backup.id, self.rename_value)
            if changed then
                self.rename_value = new_value
            end

            if imgui.button("Save##rename_" .. backup.id) then
                if app.runtime.rename_backup(backup.id, self.rename_value) then
                    clear_entry_actions(backup.id)
                end
            end

            imgui.same_line()
            if imgui.button("Cancel##rename_" .. backup.id) then
                clear_entry_actions(backup.id)
            end
        else
            draw_backup_actions(status, backup)
        end

        if self.confirm_restore_id == backup.id then
            imgui.text("Restore this backup?")
            local restore_disabled = status.keyboard_config_open
            if restore_disabled then
                imgui.begin_disabled(true)
            end
            push_colored_button_text(CREATE_BUTTON_COLOR)
            local confirmed_restore = imgui.button("Confirm Restore##" .. backup.id)
            pop_colored_button_text()
            if confirmed_restore then
                if app.runtime.restore_backup(backup.id) then
                    clear_entry_actions(backup.id)
                end
            end
            if restore_disabled then
                imgui.end_disabled()
            end

            imgui.same_line()
            push_colored_button_text(CANCEL_BUTTON_COLOR)
            local cancelled_restore = imgui.button("Cancel##restore_" .. backup.id)
            pop_colored_button_text()
            if cancelled_restore then
                self.confirm_restore_id = nil
            end
        end

        if self.confirm_delete_id == backup.id then
            if is_final_backup then
                imgui.text_colored("Strong warning: deleting the final backup removes your only recovery point.", BAD_TEXT_COLOR)
            else
                imgui.text("Delete this backup?")
            end
            push_colored_button_text(DELETE_BUTTON_COLOR)
            local confirmed_delete = imgui.button("Confirm Delete##" .. backup.id)
            pop_colored_button_text()
            if confirmed_delete then
                if app.runtime.delete_backup(backup.id) then
                    clear_entry_actions(backup.id)
                end
            end

            imgui.same_line()
            push_colored_button_text(CANCEL_BUTTON_COLOR)
            local cancelled_delete = imgui.button("Cancel##delete_" .. backup.id)
            pop_colored_button_text()
            if cancelled_delete then
                self.confirm_delete_id = nil
            end
        end
        imgui.spacing()
    end

    function self.draw()
        local open = imgui.tree_node("Keybind Deblocker")
        if not open then
            return
        end

        local ok, err = pcall(function()
            local status = app.runtime.get_status_snapshot()

            local changed_enabled, new_enabled = imgui.checkbox("Enable mod", status.enabled)
            if changed_enabled then
                app.config.enabled = new_enabled
                app.save_config()
            end

            if imgui.tree_node("Keybind Backups") then
                push_colored_button_text(CREATE_BUTTON_COLOR)
                local pressed_create = imgui.button("Create Backup")
                pop_colored_button_text()
                if pressed_create then
                    app.runtime.create_manual_backup()
                    self.confirm_restore_id = nil
                    self.confirm_delete_id = nil
                end

                if status.keyboard_config_open then
                    imgui.text_colored("Restore is unavailable while keyboard configuration is open.", BAD_TEXT_COLOR)
                end

                if status.backup_error ~= nil then
                    imgui.separator()
                    draw_multiline_text(status.backup_error)
                end

                if not status.keyboard_list_ready then
                    imgui.separator()
                    imgui.text("Live keyboard config is not ready yet.")
                end

                if #status.backups == 0 then
                    imgui.separator()
                    imgui.text("No backups available yet.")
                else
                    local backup_count = #status.backups
                    for index, backup in ipairs(status.backups) do
                        draw_backup_entry(status, backup, backup_count == 1 and index == 1)
                    end
                end

                imgui.tree_pop()
            end
        end)

        imgui.tree_pop()

        if not ok then
            error(err)
        end
    end

    return self
end

return M
