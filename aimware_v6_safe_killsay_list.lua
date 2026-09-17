-- AIMWARE V6 safe Killsay/Deathsay with multiline lists.
-- GetByIndex is used only for the optional player-name lookup after safely
-- reducing a Source 2 handle to its validated 15-bit entity entry index.

if _G.__AIMWARE_V6_SAFE_KILLSAY_LIST_LOADED then
    print("[V6 Killsay list] already loaded; duplicate callback not registered")
    return
end
_G.__AIMWARE_V6_SAFE_KILLSAY_LIST_LOADED = true

local NAME_FALLBACK = "Unknown"

-- GUI layout reconstructed from the original V6 script.
local menu_reference = _G.__AIMWARE_V6_KILLSAY_MENU_PARENT
if menu_reference == nil then
    menu_reference = gui.Reference("Miscellaneous", "Features")
end
local ui_killsay = gui.Checkbox(menu_reference, "safe_v6_killsay_enable", "Enable Killsay", false)
local ui_deathsay = gui.Checkbox(menu_reference, "safe_v6_deathsay_enable", "Enable Deathsay", false)
local ui_list_type = gui.Combobox(menu_reference, "safe_v6_killsay_list_type", "Message List", "Default", "Custom", "TXT File")
local ui_order = gui.Combobox(menu_reference, "safe_v6_killsay_order", "Message Order", "Sequential", "Random")
local ui_custom_kill = gui.Editbox(menu_reference, "safe_v6_killsay_custom", "Custom Killsays (newline or |)")
local ui_custom_death = gui.Editbox(menu_reference, "safe_v6_deathsay_custom", "Custom Deathsays (newline or |)")
local ui_txt_kill = gui.Combobox(menu_reference, "safe_v6_killsay_txt_select", "Killsay TXT", "(scan folder)")
local ui_txt_death = gui.Combobox(menu_reference, "safe_v6_deathsay_txt_select", "Deathsay TXT", "(scan folder)")
local scan_kill_folder
local scan_death_folder
local ui_scan_kill_button = gui.Button(menu_reference, "Scan kill_say folder", function()
    if scan_kill_folder ~= nil then scan_kill_folder() end
end)
local ui_scan_death_button = gui.Button(menu_reference, "Scan death_say folder", function()
    if scan_death_folder ~= nil then scan_death_folder() end
end)
local ui_txt_hint = gui.Text(menu_reference, "Folders: kill_say/ and death_say/ (TXT only; use each scan button)")
local ui_before_name_spacing = gui.Text(menu_reference, " ")
local ui_insert_name = gui.Checkbox(menu_reference, "safe_v6_killsay_insert_name", "Insert Player Name", true)
local ui_name_hint = gui.Text(menu_reference, "Hint: use {name} where the player name should appear")
local ui_before_log_spacing = gui.Text(menu_reference, " ")
local ui_console_log = gui.Checkbox(menu_reference, "safe_v6_killsay_console_log", "Console Log", false)
local ui_ignore_trailing_comma = gui.Checkbox(
    menu_reference,
    "safe_v6_ignore_trailing_comma",
    "Ignore Trailing Comma (Kill / Death / Spam)",
    false
)
local ui_comma_hint = gui.Text(menu_reference, "Removes one comma only when it is the final character of a message")
local ui_after_log_spacing = gui.Text(menu_reference, " ")

local ui_spammer = gui.Checkbox(menu_reference, "safe_v6_spammer_enable", "Enable Spammer", false)
local ui_spam_source = gui.Combobox(menu_reference, "safe_v6_spammer_source", "Spammer List", "Default", "Custom", "TXT File")
local ui_spam_order = gui.Combobox(menu_reference, "safe_v6_spammer_order", "Spammer Order", "Sequential", "Random", "Sequential Once")
local ui_spam_custom = gui.Editbox(menu_reference, "safe_v6_spammer_custom", "Custom Spam (newline or |)")
local ui_spam_txt = gui.Combobox(menu_reference, "safe_v6_spammer_txt_select", "Spammer TXT", "(scan folder)")
local scan_spam_folder
local ui_spam_scan = gui.Button(menu_reference, "Scan spam folder", function()
    if scan_spam_folder ~= nil then scan_spam_folder() end
end)
local ui_spam_txt_hint = gui.Text(menu_reference, "Folder: spam/ (TXT files only; scan runs only on button click)")
local ui_spam_delay = gui.Slider(menu_reference, "safe_v6_spammer_delay", "Spammer Delay", 1.00, 0.30, 5.00, 0.01)
local ui_spam_chat = gui.Combobox(menu_reference, "safe_v6_spammer_chat", "Spammer Chat", "All Chat", "Team Chat")

local function log(message)
    if ui_console_log:GetValue() then
        print("[V6 Killsay list] " .. tostring(message))
    end
end

-- Put one message on each line. Blank lines are ignored.
local KILLSAY_TEXT = [[
good fight
nice try
gg
custom kill message
]]

local DEATHSAY_TEXT = [[
nice shot
good one
custom death message
]]

local SPAM_TEXT = [[
test spam message 1
test spam message 2
test spam message 3
]]

local function parse_lines(text, split_pipe)
    local result = {}
    text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    if split_pipe ~= false then
        text = text:gsub("|", "\n")
    end

    for line in (text .. "\n"):gmatch("(.-)\n") do
        -- Trim leading/trailing whitespace and ignore empty/comment lines.
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line:sub(1, 2) ~= "--" then
            result[#result + 1] = line
        end
    end

    return result
end

local function valid_txt_path(filename, folder)
    if type(filename) ~= "string" then return false end
    if type(folder) ~= "string" or folder == "" then return false end
    filename = filename:gsub("^%s+", ""):gsub("%s+$", "")
    filename = filename:gsub("\\", "/")
    if filename == "" or #filename > 160 then return false end
    local prefix = folder:lower() .. "/"
    if filename:sub(1, #prefix):lower() ~= prefix then return false end
    local basename = filename:sub(#prefix + 1)
    if basename == "" or basename:find("/", 1, true) then return false end
    if basename:find("..", 1, true) then return false end
    if filename:find(":", 1, true) then return false end
    if filename:lower():sub(-4) ~= ".txt" then return false end
    return true, filename
end

local function read_txt_lines(filename, folder)
    local valid, clean_name = valid_txt_path(filename, folder)
    if not valid then
        log("Invalid TXT selection; scan the " .. tostring(folder) .. " folder first")
        return nil
    end

    local ok_open, handle = pcall(file.Open, clean_name, "r")
    if not ok_open or handle == nil then
        log("Invalid file or unable to open: " .. clean_name)
        return nil
    end

    local ok_read, contents = pcall(function()
        return handle:Read()
    end)

    -- Always attempt to close a successfully opened handle.
    local ok_close, close_error = pcall(function()
        handle:Close()
    end)
    if not ok_close then
        log("Unable to close TXT: " .. tostring(close_error))
    end

    if not ok_read or type(contents) ~= "string" then
        log("Invalid file or unable to read: " .. clean_name)
        return nil
    end

    -- Remove an optional UTF-8 BOM before parsing the first line.
    if contents:sub(1, 3) == "\239\187\191" then
        contents = contents:sub(4)
    end

    -- TXT files already support real newlines, so preserve | as normal text.
    local lines = parse_lines(contents, false)
    if #lines == 0 then
        log("TXT contains no usable lines: " .. clean_name)
        return nil
    end
    return lines
end

local txt_kill_cache = nil
local txt_death_cache = nil
local txt_kill_loaded_name = nil
local txt_death_loaded_name = nil
local kill_txt_files = {}
local death_txt_files = {}
local kill_txt_file_cache = {}
local death_txt_file_cache = {}
local last_visible_source = nil
local last_spam_visibility = nil

local function update_source_visibility()
    local source = ui_list_type:GetValue()
    if source ~= last_visible_source then
        last_visible_source = source
        local show_custom = source == 1
        local show_txt = source == 2
        ui_custom_kill:SetInvisible(not show_custom)
        ui_custom_death:SetInvisible(not show_custom)
        ui_txt_kill:SetInvisible(not show_txt)
        ui_txt_death:SetInvisible(not show_txt)
        ui_scan_kill_button:SetInvisible(not show_txt)
        ui_scan_death_button:SetInvisible(not show_txt)
        ui_txt_hint:SetInvisible(not show_txt)
    end

    local spam_source = ui_spam_source:GetValue()
    local spam_visibility = tostring(spam_source)
    if spam_visibility ~= last_spam_visibility then
        last_spam_visibility = spam_visibility
        ui_spam_source:SetInvisible(false)
        ui_spam_order:SetInvisible(false)
        ui_spam_delay:SetInvisible(false)
        ui_spam_chat:SetInvisible(false)
        ui_spam_custom:SetInvisible(spam_source ~= 1)
        ui_spam_txt:SetInvisible(spam_source ~= 2)
        ui_spam_scan:SetInvisible(spam_source ~= 2)
        ui_spam_txt_hint:SetInvisible(spam_source ~= 2)
    end
end

local function scan_message_folder(folder, control, target_files, target_cache, kind)
    local discovered = {}
    local seen = {}
    local ok, enumerate_error = pcall(file.Enumerate, function(candidate)
        if type(candidate) ~= "string" then return end
        local normalized = candidate:gsub("\\", "/"):gsub("^/", "")
        local valid, clean_path = valid_txt_path(normalized, folder)
        if valid and not seen[clean_path] then
            seen[clean_path] = true
            discovered[#discovered + 1] = clean_path
        end
    end)

    if not ok then
        log(kind .. " folder scan failed: " .. tostring(enumerate_error))
        return
    end

    table.sort(discovered)
    for key in pairs(target_files) do target_files[key] = nil end
    for key in pairs(target_cache) do target_cache[key] = nil end
    for i = 1, #discovered do
        target_files[i] = discovered[i]
        target_cache[discovered[i]] = read_txt_lines(discovered[i], folder)
    end

    local labels = {}
    for i = 1, #target_files do
        labels[i] = target_files[i]:sub(#folder + 2)
    end
    if #labels == 0 then labels[1] = "(no TXT files found)" end
    control:SetOptions(unpack(labels))
    control:SetValue(0)
    log(kind .. " scan complete: " .. tostring(#target_files) .. " TXT file(s) found and cached")
end

scan_kill_folder = function()
    txt_kill_cache = nil
    txt_kill_loaded_name = nil
    scan_message_folder("kill_say", ui_txt_kill, kill_txt_files, kill_txt_file_cache, "Killsay")
end

scan_death_folder = function()
    txt_death_cache = nil
    txt_death_loaded_name = nil
    scan_message_folder("death_say", ui_txt_death, death_txt_files, death_txt_file_cache, "Deathsay")
end

local spam_files = {}
local spam_file_cache = {}
local spam_txt_cache = nil
local spam_loaded_path = nil

scan_spam_folder = function()
    local discovered = {}
    local seen = {}
    local ok, enumerate_error = pcall(file.Enumerate, function(candidate)
        if type(candidate) ~= "string" then return end
        local normalized = candidate:gsub("\\", "/"):gsub("^/", "")
        local valid, clean_path = valid_txt_path(normalized, "spam")
        if valid and not seen[clean_path] then
            seen[clean_path] = true
            discovered[#discovered + 1] = clean_path
        end
    end)
    if not ok then
        log("Spam folder scan failed: " .. tostring(enumerate_error))
        return
    end

    table.sort(discovered)
    spam_files = discovered
    spam_file_cache = {}
    for i = 1, #spam_files do
        spam_file_cache[spam_files[i]] = read_txt_lines(spam_files[i], "spam")
    end
    spam_txt_cache = nil
    spam_loaded_path = nil

    local labels = {}
    for i = 1, #spam_files do labels[i] = spam_files[i]:sub(6) end
    if #labels == 0 then labels[1] = "(no TXT files found)" end
    ui_spam_txt:SetOptions(unpack(labels))
    ui_spam_txt:SetValue(0)
    log("Spam scan complete: " .. tostring(#spam_files) .. " TXT file(s) found and cached")
end

local function refresh_txt_cache()
    update_source_visibility()

    -- This callback only updates GUI/cache references. All file enumeration,
    -- opening, and reading is restricted to the scan button callback.
    if ui_spam_source:GetValue() == 2 then
        local spam_path = spam_files[(ui_spam_txt:GetValue() or 0) + 1]
        if spam_path ~= spam_loaded_path then
            spam_loaded_path = spam_path
            spam_txt_cache = spam_path and spam_file_cache[spam_path] or nil
            if spam_txt_cache ~= nil then
                log("Loaded " .. tostring(#spam_txt_cache) .. " spam lines from " .. spam_path)
            end
        end
    end

    if ui_list_type:GetValue() ~= 2 then return end

    local kill_name = kill_txt_files[(ui_txt_kill:GetValue() or 0) + 1]
    if kill_name ~= txt_kill_loaded_name then
        txt_kill_loaded_name = kill_name
        txt_kill_cache = kill_name and kill_txt_file_cache[kill_name] or nil
        if txt_kill_cache ~= nil then
            log("Loaded " .. tostring(#txt_kill_cache) .. " killsays from " .. kill_name)
        end
    end

    local death_name = death_txt_files[(ui_txt_death:GetValue() or 0) + 1]
    if death_name ~= txt_death_loaded_name then
        txt_death_loaded_name = death_name
        txt_death_cache = death_name and death_txt_file_cache[death_name] or nil
        if txt_death_cache ~= nil then
            log("Loaded " .. tostring(#txt_death_cache) .. " deathsays from " .. death_name)
        end
    end
end

local killsays = parse_lines(KILLSAY_TEXT)
local deathsays = parse_lines(DEATHSAY_TEXT)
local default_spam = parse_lines(SPAM_TEXT)
local kill_position = 0
local death_position = 0
local spam_position = 0

local function choose_message(list, mode, position)
    if #list == 0 then
        return nil, position
    end

    if mode == "sequential" then
        position = (position % #list) + 1
        return list[position], position
    end

    return list[math.random(1, #list)], position
end

local function handle_to_index(value)
    if type(value) ~= "number" then
        return nil
    end

    -- Source 2 CEntityHandle: low 15 bits contain the entity entry index.
    local index = math.floor(value) % 32768
    if index <= 0 then
        return nil
    end
    return index
end

local function get_local_indices()
    local controller_index = nil
    local pawn_index = nil

    local ok_controller, controller = pcall(client.GetLocalPlayerIndex)
    if ok_controller and type(controller) == "number" then
        controller_index = math.floor(controller)
    end

    local ok_player, player = pcall(entities.GetLocalPlayer)
    if ok_player and player ~= nil then
        local ok_index, index = pcall(function()
            return player:GetIndex()
        end)
        if ok_index and type(index) == "number" then
            pawn_index = math.floor(index)
        end
    end

    return controller_index, pawn_index
end

local function is_local_index(value, controller_index, pawn_index)
    return value ~= nil and (value == controller_index or value == pawn_index)
end

local function get_player_name(index)
    if not ui_insert_name:GetValue() or type(index) ~= "number" then
        return nil
    end
    if index <= 0 or index >= 32768 then
        return NAME_FALLBACK
    end

    -- The original V6 payload uses entities.GetByIndex followed by GetName.
    -- Only the already-decoded 15-bit entry index reaches this native call.
    local ok_entity, entity = pcall(entities.GetByIndex, index)
    if not ok_entity or entity == nil then
        return NAME_FALLBACK
    end

    local ok_name, name = pcall(function()
        return entity:GetName()
    end)
    if not ok_name or type(name) ~= "string" or name == "" then
        return NAME_FALLBACK
    end

    return name
end

local function insert_player_name(message, name)
    if not ui_insert_name:GetValue() or name == nil or name == "" then
        return message
    end

    -- Replace every {name} tag at exactly the position chosen by the user.
    if message:find("{name}", 1, true) then
        return (message:gsub("{name}", function() return name end))
    end
    return message
end

local function apply_common_message_rules(message)
    if type(message) ~= "string" then return message end
    if ui_ignore_trailing_comma:GetValue() then
        -- Only remove the final comma. Commas inside the sentence stay intact.
        message = message:gsub(",%s*$", "")
        message = message:gsub("%s+$", "")
    end
    return message
end

-- All Kill Say, Death Say, and Spammer output passes through this single FIFO.
-- AIMWARE/CS2 can swallow messages sent too close together, so only one queued
-- message is released per 0.30 seconds regardless of its source.
local CHAT_SEND_INTERVAL = 0.30
local chat_queue = {}
local last_chat_send_time = -1000
local spam_once_cycle_queued = false
local spam_auto_finished = false

local function remove_queued_spam()
    for i = #chat_queue, 1, -1 do
        if chat_queue[i].is_spam == true then
            table.remove(chat_queue, i)
        end
    end
end

local function queue_message(kind, message, team_chat, is_spam, finish_spam_once)
    message = apply_common_message_rules(message)
    if message == nil or message == "" then
        log(kind .. " list is empty")
        return false
    end

    chat_queue[#chat_queue + 1] = {
        kind = kind,
        message = message,
        team_chat = team_chat == true,
        is_spam = is_spam == true,
        finish_spam_once = finish_spam_once == true
    }
    log(kind .. " queued (#" .. tostring(#chat_queue) .. "): " .. message)
    return true
end

local function process_chat_queue()
    if #chat_queue == 0 then return end

    local ok_time, now = pcall(common.Time)
    if not ok_time or type(now) ~= "number" then return end
    if now < last_chat_send_time then
        last_chat_send_time = now - CHAT_SEND_INTERVAL
    end
    if now - last_chat_send_time < CHAT_SEND_INTERVAL then return end

    local item = table.remove(chat_queue, 1)
    local ok_send, send_error
    if item.team_chat then
        ok_send, send_error = pcall(client.ChatTeamSay, item.message)
    else
        ok_send, send_error = pcall(client.ChatSay, item.message)
    end
    last_chat_send_time = now

    if ok_send then
        log(item.kind .. ": " .. item.message)
    else
        log(item.kind .. " chat failed: " .. tostring(send_error))
    end

    -- Turn the GUI toggle off only after the final line has actually been sent.
    if item.finish_spam_once == true then
        spam_once_cycle_queued = false
        spam_auto_finished = true
        ui_spammer:SetValue(false)
        log("SPAMMER Sequential Once completed; Enable Spammer turned off")
    end
end

local function send_message(kind, message)
    queue_message(kind, message, false, false)
end

local function get_active_list(default_list, custom_control, txt_cache)
    -- AIMWARE Combobox values are zero-based: 0=Default, 1=Custom, 2=TXT.
    local source = ui_list_type:GetValue()
    if source == 0 then
        return default_list
    elseif source == 1 then
        return parse_lines(custom_control:GetValue())
    end
    return txt_cache
end

local function get_order_mode()
    return ui_order:GetValue() == 0 and "sequential" or "random"
end

local spam_last_time = 0
local spam_was_enabled = false

local function get_spam_list()
    local source = ui_spam_source:GetValue()
    if source == 0 then return default_spam end
    if source == 1 then return parse_lines(ui_spam_custom:GetValue()) end
    return spam_txt_cache
end

local function spammer_logic()
    local enabled = ui_spammer:GetValue()
    if not enabled then
        if spam_was_enabled then
            spam_position = 0
            spam_last_time = 0
            spam_once_cycle_queued = false
            if spam_auto_finished then
                -- The final line was already sent; preserve unrelated queued
                -- Kill/Death messages and do not treat this as a manual stop.
                spam_auto_finished = false
                log("SPAMMER one-cycle sequence reset to first line")
            else
                remove_queued_spam()
                log("SPAMMER stopped; sequence reset to first line")
            end
        end
        spam_was_enabled = false
        return
    end
    spam_was_enabled = true

    local ok_time, now = pcall(common.Time)
    if not ok_time or type(now) ~= "number" then return end
    if now < spam_last_time then spam_last_time = now end
    if now - spam_last_time < ui_spam_delay:GetValue() then return end
    if spam_once_cycle_queued then return end
    local ok_server, server_ip = pcall(engine.GetServerIP)
    if not ok_server or server_ip == nil then return end

    local list = get_spam_list()
    if list == nil or #list == 0 then
        spam_last_time = now
        log("SPAMMER list is empty")
        return
    end

    local order_value = ui_spam_order:GetValue()
    local message
    local is_once_final = false
    if order_value == 2 then
        spam_position = spam_position + 1
        if spam_position < 1 or spam_position > #list then spam_position = 1 end
        message = list[spam_position]
        is_once_final = spam_position >= #list
    else
        local mode = order_value == 0 and "sequential" or "random"
        message, spam_position = choose_message(list, mode, spam_position)
    end

    if queue_message("SPAMMER", message, ui_spam_chat:GetValue() == 1, true, is_once_final) then
        spam_last_time = now
        if is_once_final then spam_once_cycle_queued = true end
    end
end

local function on_game_event(event)
    if event == nil then return end

    local ok_name, name = pcall(function() return event:GetName() end)
    if not ok_name or name ~= "player_death" then return end

    local ok_victim, victim_handle = pcall(function()
        return event:GetInt("userid_pawn")
    end)
    local ok_attacker, attacker_handle = pcall(function()
        return event:GetInt("attacker_pawn")
    end)
    if not ok_victim or not ok_attacker then return end

    local victim = handle_to_index(victim_handle)
    local attacker = handle_to_index(attacker_handle)
    if victim == nil or attacker == nil then return end

    local controller_index, pawn_index = get_local_indices()
    local local_kill = is_local_index(attacker, controller_index, pawn_index)
    local local_death = is_local_index(victim, controller_index, pawn_index)

    if local_kill and attacker ~= victim and ui_killsay:GetValue() then
        local active_killsays = get_active_list(killsays, ui_custom_kill, txt_kill_cache)
        if active_killsays == nil then return end
        local message
        message, kill_position = choose_message(active_killsays, get_order_mode(), kill_position)
        if message ~= nil then
            message = insert_player_name(message, get_player_name(victim))
        end
        send_message("KILLSAY", message)
    elseif local_death and ui_deathsay:GetValue() then
        local active_deathsays = get_active_list(deathsays, ui_custom_death, txt_death_cache)
        if active_deathsays == nil then return end
        local message
        message, death_position = choose_message(active_deathsays, get_order_mode(), death_position)
        if message ~= nil then
            message = insert_player_name(message, get_player_name(attacker))
        end
        send_message("DEATHSAY", message)
    end
end

client.AllowListener("player_death")
callbacks.Register("FireGameEvent", on_game_event)
callbacks.Register("Draw", function()
    refresh_txt_cache()
    spammer_logic()
    process_chat_queue()
end)

log(string.format(
    "GUI loaded: %d default kill lines, %d default death lines, %d default spam lines",
    #killsays,
    #deathsays,
    #default_spam
))
