-- =========================================================================
--     Improved Name stealer | Fake name | TXT Clantag
--     Enjoying this script? Leave a +rep on my profile!
--     Profile: https://aimware.net/forum/user/578267  
--     Hugs from Brazil!!
-- =========================================================================

ffi.cdef[[
	void* GetModuleHandleA(const char* lpModuleName);
]]

local NULL = 0x0

local cEngine2Dll = "engine2.dll"

local cEngineCvarOffset = 0x0
local cResolveConvarOffset = 0x0
local cFindConvarOffset = 0xB
local cConvarFlagsOffset = 0x30

local FCVAR_DEVELOPMENTONLY = 0x2
local FCVAR_USERINFO = 0x200

local function get_offset_from_pattern(cDllName, cPattern, cPatternOffset, cInstrSize)
	local pLocation = mem.FindPattern(cDllName, cPattern)
	local cRelativeAddr = ffi.cast("int32_t*", pLocation + cPatternOffset)[0x0]
	return tonumber(pLocation + cRelativeAddr + cInstrSize) - tonumber(ffi.cast("uintptr_t", ffi.C.GetModuleHandleA(cDllName)))
end

cEngineCvarOffset = get_offset_from_pattern(cEngine2Dll, "48 8B 0D ?? ?? ?? ?? 48 8B 16 48 89 7C 24 ?? 4C 89 4C 24 ??", 3, 7)
cResolveConvarOffset = get_offset_from_pattern(cEngine2Dll, "48 8B D3 E8 ?? ?? ?? ?? 48 8B 44 24", 4, 8)

local function patch_convar(cConvarName)
	local cEngineBase = tonumber(ffi.cast("uintptr_t", ffi.C.GetModuleHandleA(cEngine2Dll)))

	if cEngineBase == nil or cEngineBase == NULL then
		return
	end

	local pVtableEngineAddr = tonumber(ffi.cast("uintptr_t*", cEngineBase + cEngineCvarOffset)[0x0])
	local pVtableEngineTable = tonumber(ffi.cast("uintptr_t*", pVtableEngineAddr)[0x0])

	local pFindConvarFuncAddr = ffi.cast("uintptr_t*", pVtableEngineTable)[cFindConvarOffset]
	local pFindConvarFunc = ffi.cast("void* (*)(void*, void*, const char*, int)", pFindConvarFuncAddr)

	local pFindOutput = ffi.new("void*[1]")
	local pFindName = ffi.new("char[?]", #cConvarName + 0x1, cConvarName)

	pFindConvarFunc(ffi.cast("void*", pVtableEngineAddr), pFindOutput, pFindName, 0x0)

	local pResolveFunc = ffi.cast("void* (*)(int64_t*, int32_t, int16_t)", tonumber(ffi.cast("uintptr_t", cEngineBase + cResolveConvarOffset)))
	local pResolveOutput = ffi.new("int64_t[0x2]")

	pResolveFunc(pResolveOutput, ffi.cast("int32_t", pFindOutput[0x0]), 0x0)
	
	local cCurrentConvarAddr = tonumber(pResolveOutput[0x1])
	local pCurrentFlags = ffi.cast("uintptr_t*", cCurrentConvarAddr + cConvarFlagsOffset)

	pCurrentFlags[0x0] = bit.band(pCurrentFlags[0x0], bit.bnot(FCVAR_DEVELOPMENTONLY))
	pCurrentFlags[0x0] = bit.bor(pCurrentFlags[0x0], FCVAR_USERINFO)
end

-- Clan-tag presets are loaded from clan_tag/*.txt at runtime.
local misc_tab = gui.Reference("Miscellaneous", "Features")

local enable_name_changer = gui.Checkbox(misc_tab, "nc_master_enable", "Enable Name Changer", false)
local mode_combo = gui.Combobox(misc_tab, "nc_mode_v2", "Name Changer Mode", "Name stealer", "Fake name", "Clantag")

local fake_input = gui.Editbox(misc_tab, "nc_fake_input", " Custom Name:") 
local fake_anim_cb = gui.Checkbox(misc_tab, "nc_fake_anim", "Animated name", true)
local fake_speed_slider = gui.Slider(misc_tab, "nc_fake_speed", "Speed:", 0.10, 0.01, 1.00, 0.01)

local stealer_speed_slider = gui.Slider(misc_tab, "nc_stealer_speed", "Speed:", 0.07, 0.07, 1.00, 0.01)
local stealer_player_combo = gui.Combobox(misc_tab, "nc_stealer_player", "Player to steal", "(no teammates)")
local stealer_spam_cb = gui.Checkbox(misc_tab, "nc_stealer_spam", "Random name spam", false)

-- TXT clan-tag selector populated only by the scan button.
local clan_preset_combo = gui.Combobox(misc_tab, "nc_clan_txt_select", "Clan Tag TXT", "(scan clan_tag folder)")
local scan_clantag_files
local clan_scan_button = gui.Button(misc_tab, "Scan clan_tag folder", function()
    if scan_clantag_files ~= nil then scan_clantag_files() end
end)
local clan_folder_hint = gui.Text(misc_tab, "Each TXT line is one clan-tag animation frame")

local clan_bar_cb = gui.Checkbox(misc_tab, "nc_clan_bar", "Use middle bar '|'", true)
local clan_speed_slider = gui.Slider(misc_tab, "nc_clan_speed", "Speed:", 0.10, 0.01, 1.00, 0.01)

local clan_fake_toggle = gui.Checkbox(misc_tab, "nc_clan_fake_toggle", "Fake name", false)
local clan_fake_input = gui.Editbox(misc_tab, "nc_clan_fake_input", " Custom Name:") 
local clan_fake_anim_cb = gui.Checkbox(misc_tab, "nc_clan_fake_anim", "Animated name", true)
local clan_fake_speed_slider = gui.Slider(misc_tab, "nc_clan_fake_speed", "Speed:", 0.10, 0.01, 1.00, 0.01)

local version_text = gui.Text(misc_tab, "\n-> Name Changer ver. 1.3 + Presets | by 1722% capa sem hack")

local cOldRealName = " "
local bNameWasSaved = false
local bNameWasChanged = false
local bForceExit = false

local RawNames = {}       
local FilteredNames = {}   
local StealerSelectableNames = {}
local cLastNamesSignature = ""

local TxtClanTagPresets = {}
local ClanTagFiles = {}

local cLastMapName = ""
local cHalftimePause = 0
local bPauseTriggered = false

local cLastMode = 0
local cModeSwitchTime = 0

-- Preset index tracking
local cLastPreset = 0
local cLastStealTarget = ""

local cSpammerIdx = 0
local cSpammerDir = 1
local cFakeIdx = 0
local cFakeDir = 1
local cClanFakeIdx = 0
local cClanFakeDir = 1

local cCurrClanStr = ""
local cCurrFakeStr = ""
local cLastClanTime = 0
local cLastFakeTime = 0
local cLastCombineTime = 0

local function set_network_name(cTargetName)
	if cTargetName == nil or cTargetName == "" then return end
	client.Command("name " .. cTargetName, true)
	client.Command("setinfo name " .. '"' .. cTargetName .. '"', true)
end

local function get_utf8_chars(cStr)
	local pChars = {}
	if type(cStr) ~= "string" then return pChars end
	local i = 1
	local cLen = #cStr
	while i <= cLen do
		local b = string.byte(cStr, i)
		local cCharLen = 1
		if b >= 240 then cCharLen = 4
		elseif b >= 224 then cCharLen = 3
		elseif b >= 192 then cCharLen = 2
		end
		table.insert(pChars, string.sub(cStr, i, i + cCharLen - 1))
		i = i + cCharLen
	end
	return pChars
end

local function get_local_userid()
	local me = entities.GetLocalPlayer()
	if not me then return 0 end
	local ok, uid = pcall(function() return me:GetPropInt("m_nUserID") end)
	if ok and type(uid) == "number" and uid ~= 0 then return uid end
	ok, uid = pcall(function() return me:GetUserID() end)
	if ok and type(uid) == "number" and uid ~= 0 then return uid end
	return 0
end

local function update_memory_cache()
	FilteredNames = {}
	
	for uid, pName in pairs(RawNames) do
		if type(pName) == "string" and #pName > 1 and pName ~= cOldRealName and pName ~= "GOTV" and pName ~= "Player" and pName ~= "DemoRecorder" and pName ~= "DemoAutoRecorder" then
			local cCleanName = pName:gsub("[%c%z]", "")
			
			if #cCleanName > 1 and not cCleanName:match("^[`#%?%s@]+$") then
				local bIsDuplicate = false
				for _, pRegistered in ipairs(FilteredNames) do
					if pRegistered == cCleanName then bIsDuplicate = true break end
				end
				if bIsDuplicate == false then
					table.insert(FilteredNames, cCleanName)
				end
			end
		end
	end

	table.sort(FilteredNames)
	local previous = StealerSelectableNames[(stealer_player_combo:GetValue() or 0) + 1]
	local signature = table.concat(FilteredNames, "\31")
	if signature ~= cLastNamesSignature then
		cLastNamesSignature = signature
		StealerSelectableNames = {}
		for i = 1, #FilteredNames do StealerSelectableNames[i] = FilteredNames[i] end

		local labels = {}
		for i = 1, #StealerSelectableNames do labels[i] = StealerSelectableNames[i] end
		if #labels == 0 then labels[1] = "(no teammates)" end
		stealer_player_combo:SetOptions(unpack(labels))

		local selected = 0
		if previous ~= nil then
			for i = 1, #StealerSelectableNames do
				if StealerSelectableNames[i] == previous then selected = i - 1 break end
			end
		end
		stealer_player_combo:SetValue(selected)
	end
end

local function get_team_by_ent(ent)
	if not ent then return 0 end
	local ok, v = pcall(function() return ent:GetPropInt("m_iTeamNum") end)
	if ok and type(v) == "number" and v ~= 0 then return v end
	ok, v = pcall(function() return ent:GetTeamNumber() end)
	if ok and type(v) == "number" then return v end
	return 0
end

local function get_team_by_uid(uid)
	if not uid or uid == 0 then return 0 end
	local ok, idx = pcall(function() return client.GetPlayerIndexByUserID(uid) end)
	if not ok or not idx or idx == 0 then return 0 end
	local ok2, ent = pcall(function() return entities.GetByIndex(idx) end)
	if not ok2 or not ent then return 0 end
	return get_team_by_ent(ent)
end

local function scan_players()
	RawNames = {}

	local pLocalPlayer = entities.GetLocalPlayer()
	if pLocalPlayer == nil then
		update_memory_cache()
		return
	end

	local myTeam = get_team_by_ent(pLocalPlayer)
	if myTeam == 0 then
		update_memory_cache()
		return
	end

	local cLocalIdx = -1
	pcall(function() cLocalIdx = pLocalPlayer:GetIndex() end)

	local pList = nil
	pcall(function() pList = entities.FindByClass("C_CSPlayerPawn") end)

	if pList == nil then 
		update_memory_cache()
		return 
	end

	for i = 1, #pList do
		local pEnt = pList[i]
		if pEnt ~= nil then
			local cIdx = -1
			pcall(function() cIdx = pEnt:GetIndex() end)

			if cIdx ~= -1 and cIdx ~= cLocalIdx then
				local entTeam = get_team_by_ent(pEnt)
				-- 팀원만 수집 (적군 제외)
				if entTeam == myTeam then
					local cCls = ""
					pcall(function() cCls = pEnt:GetClass() end)

					if cCls ~= "C_CSGO_PreviewPlayer" and cCls ~= "C_CSGO_PreviewPlayerAlias_csgo_player_previewmodel" then
						local pTempName = nil
						pcall(function() pTempName = pEnt:GetName() end)

						if pTempName ~= nil and pTempName ~= "" and pTempName ~= "Player" and pTempName ~= "unconnected" and not pTempName:match("^C_") then
							RawNames[cIdx] = pTempName
						end
					end
				end
			end
		end
	end
	update_memory_cache()
end

local cLastScan = 0

local function get_current_mode()
	if enable_name_changer:GetValue() ~= true then return 0 end
	return mode_combo:GetValue() + 1
end

local function read_clantag_frames(path)
	local ok_open, handle = pcall(file.Open, path, "r")
	if not ok_open or handle == nil then return nil end
	local ok_read, contents = pcall(function() return handle:Read() end)
	pcall(function() handle:Close() end)
	if not ok_read or type(contents) ~= "string" then return nil end
	if contents:sub(1, 3) == "\239\187\191" then contents = contents:sub(4) end
	contents = contents:gsub("\r\n", "\n"):gsub("\r", "\n")
	local frames = {}
	for line in (contents .. "\n"):gmatch("(.-)\n") do
		-- Preserve spaces because they can be meaningful animation frames.
		if line ~= "" then frames[#frames + 1] = line end
	end
	if #frames == 0 then return nil end
	return frames
end

scan_clantag_files = function()
	local paths = {}
	local seen = {}
	local ok, scan_error = pcall(file.Enumerate, function(candidate)
		if type(candidate) ~= "string" then return end
		local path = candidate:gsub("\\", "/"):gsub("^/", "")
		local lower = path:lower()
		if lower:sub(1, 9) == "clan_tag/" then
			local basename = path:sub(10)
			if basename ~= "" and not basename:find("/", 1, true)
				and not basename:find("..", 1, true)
				and lower:sub(-4) == ".txt" and not seen[path] then
				seen[path] = true
				paths[#paths + 1] = path
			end
		end
	end)
	if not ok then
		print("[Name Changer] clan_tag scan failed: " .. tostring(scan_error))
		return
	end

	table.sort(paths)
	ClanTagFiles = {}
	TxtClanTagPresets = {}
	local labels = {}
	for i = 1, #paths do
		local frames = read_clantag_frames(paths[i])
		if frames ~= nil then
			ClanTagFiles[#ClanTagFiles + 1] = paths[i]
			TxtClanTagPresets[#TxtClanTagPresets + 1] = frames
			labels[#labels + 1] = paths[i]:sub(10)
		end
	end
	if #labels == 0 then labels[1] = "(no valid TXT files)" end
	clan_preset_combo:SetOptions(unpack(labels))
	clan_preset_combo:SetValue(0)
	cLastPreset = -1
	cSpammerIdx = 0
	cCurrClanStr = ""
	print("[Name Changer] loaded " .. tostring(#TxtClanTagPresets) .. " clan-tag TXT file(s)")
end

callbacks.Register("FireGameEvent", "NameChanger_Events", function(e)
    if e == nil then return end
    local cEventName = e:GetName()

	if cEventName == "round_start" then
		cLastScan = globals.CurTime()
		scan_players()
		return
	end

	if cEventName == "cs_win_panel_match" then
		if get_current_mode() ~= 0 then
			if bPauseTriggered == false then
				bPauseTriggered = true
				cHalftimePause = globals.CurTime() + 30.0
				print("\n[Name Changer] MATCH END DETECTED! Pausing the Lua script for 30 seconds to prevent a crash...\n")
			end
		end
		return
	end

    if cEventName == "player_connect" or cEventName == "player_info" then
        local cUid = e:GetInt("userid")
		local cName = e:GetString("name")
		-- 자신 제외
		if cUid ~= nil and cUid ~= 0 and cUid == get_local_userid() then
			return
		end
		-- 팀원만 허용 (적군 animated name 필터링)
		if cUid ~= nil and cUid ~= 0 then
			local entTeam = get_team_by_uid(cUid)
			local pLocalPlayer = entities.GetLocalPlayer()
			local myTeam = 0
			if pLocalPlayer ~= nil then
				myTeam = get_team_by_ent(pLocalPlayer)
			end
			if entTeam ~= myTeam or myTeam == 0 then
				return
			end
		end
		if cUid ~= nil and cName ~= nil and cName ~= "" then
			RawNames[cUid] = cName
			update_memory_cache()
		end
		return
	end

	if cEventName == "player_disconnect" then
		local cUid = e:GetInt("userid")
		if cUid ~= nil then
			RawNames[cUid] = nil
			update_memory_cache()
		end
		return
	end

	if cEventName == "client_disconnect" then
		RawNames = {}
		FilteredNames = {}
		bNameWasSaved = false
		bNameWasChanged = false
		cOldRealName = " "
		cLastMapName = ""
		
		cHalftimePause = 0
		bPauseTriggered = false

		cClanFakeIdx = 0
		cClanFakeDir = 1
		cCurrClanStr = ""
		cCurrFakeStr = ""
		cLastClanTime = 0
		cLastFakeTime = 0
		cLastCombineTime = 0
	end
end)

client.AllowListener("player_connect")
client.AllowListener("player_info")
client.AllowListener("player_disconnect")
client.AllowListener("client_disconnect")
client.AllowListener("cs_win_panel_match")
client.AllowListener("round_start")

local cInitTime = globals.CurTime()
local cLastLogicTime = -1
local cLastMenuTime = -1

local function logic_handler()
	if bForceExit == true then return end

	if engine.GetServerIP() == nil then
		cInitTime = globals.CurTime()
		bNameWasSaved = false
		cLastMapName = ""
		cLastScan = 0
		return
	end

	local cCurrentMap = engine.GetMapName()
	if cCurrentMap == nil or cCurrentMap == "" then
		cInitTime = globals.CurTime()
		bNameWasSaved = false
		cLastMapName = ""
		return
	end

	if cCurrentMap ~= cLastMapName then
		cLastMapName = cCurrentMap
		
		RawNames = {}
		FilteredNames = {}
		bNameWasSaved = false
		bNameWasChanged = false
		cOldRealName = " "
		
		cHalftimePause = 0
		bPauseTriggered = false

		cClanFakeIdx = 0
		cClanFakeDir = 1
		cCurrClanStr = ""
		cCurrFakeStr = ""
		cLastClanTime = 0
		cLastFakeTime = 0
		cLastCombineTime = 0
	end

	local pLocalPlayer = entities.GetLocalPlayer()

	if pLocalPlayer == nil then
		cInitTime = globals.CurTime()
		bNameWasSaved = false
		return
	end

	if (globals.CurTime() - cInitTime) < 0.3 then
		bNameWasSaved = false
		return
	end

	if bPauseTriggered == true and globals.CurTime() < cHalftimePause then
		if bNameWasChanged == true then
			set_network_name(cOldRealName)
			bNameWasChanged = false
		end
		return
	end

	if bPauseTriggered == true and globals.CurTime() >= cHalftimePause then
		bPauseTriggered = false
	end

	if (globals.CurTime() - cLastScan) > 20.0 or #FilteredNames == 0 then
		cLastScan = globals.CurTime()
		scan_players()
	end

	local cCurrentMode = get_current_mode()

	if cCurrentMode ~= cLastMode then
		if cCurrentMode ~= 0 then
			cModeSwitchTime = globals.CurTime()
		end
		if cCurrentMode == 1 then cLastStealTarget = "" end
		cLastMode = cCurrentMode
	end

	if bNameWasSaved == false then
		local bForceStart = (cCurrentMode ~= 0) and (globals.CurTime() > cModeSwitchTime + 2.0)

		-- IsPlayer() 체크 제거: 관전/재접속 상태에서도 작동
		local cTempName = nil
		pcall(function() cTempName = pLocalPlayer:GetName() end)

		if cTempName ~= nil and cTempName ~= "" and not cTempName:match("^C_") then
			cOldRealName = cTempName
		end

		if cTempName ~= nil or bForceStart then
			bNameWasSaved = true
			patch_convar("name")
			-- 재접속/관전 직후 팀원 즉시 스캔
			if #FilteredNames == 0 then
				scan_players()
			end
		else
			return 
		end
	end

	if globals.CurTime() < cLastLogicTime then
		cLastLogicTime = globals.CurTime()
	end

	if cCurrentMode == 0 and bNameWasChanged == true then
		set_network_name(cOldRealName)
		bNameWasChanged = false
	end

	if cCurrentMode == 1 then
		local spam_enabled = stealer_spam_cb:GetValue() == true
		local cSpeedRate = spam_enabled and stealer_speed_slider:GetValue() or 0.4
		if (globals.CurTime() - cLastLogicTime) > cSpeedRate then
			cLastLogicTime = globals.CurTime()
			
			if #StealerSelectableNames > 0 then
				local cPicked
				if spam_enabled then
					cPicked = StealerSelectableNames[math.random(1, #StealerSelectableNames)]
				else
					cPicked = StealerSelectableNames[(stealer_player_combo:GetValue() or 0) + 1]
				end
				if cPicked ~= nil and (spam_enabled or cPicked ~= cLastStealTarget) then
				set_network_name(cPicked)
				bNameWasChanged = true
				cLastStealTarget = cPicked
				end
			end
		end
	end

	if cCurrentMode == 2 then
		local cBaseFake = fake_input:GetString()
		
		if cBaseFake == nil or cBaseFake == "" then
			cBaseFake = cOldRealName
		end

		if fake_anim_cb:GetValue() == true then
			local cSpeedRate = fake_speed_slider:GetValue()
			if (globals.CurTime() - cLastLogicTime) > cSpeedRate then
				cLastLogicTime = globals.CurTime()

				local pUtf8Chars = get_utf8_chars(cBaseFake)
				local cMaxLen = #pUtf8Chars

				if cMaxLen > 0 then
					cFakeIdx = cFakeIdx + cFakeDir

					if cFakeIdx >= cMaxLen then
						cFakeIdx = cMaxLen
						cFakeDir = -1
					elseif cFakeIdx <= 1 then
						cFakeIdx = 1
						cFakeDir = 1
					end

					local cAnimText = table.concat(pUtf8Chars, "", 1, cFakeIdx)
					set_network_name(cAnimText)
					bNameWasChanged = true
				end
			end
		else
			if (globals.CurTime() - cLastLogicTime) > 0.4 then
				cLastLogicTime = globals.CurTime()
				set_network_name(cBaseFake)
				bNameWasChanged = true
			end
		end
	end

	if cCurrentMode == 3 then
		local cPreset = clan_preset_combo:GetValue()

		-- Reset index when preset changes
		if cPreset ~= cLastPreset then
			cSpammerIdx = 0
			cSpammerDir = 1
			cLastPreset = cPreset
		end

		local bUseBar = clan_bar_cb:GetValue()
		local cSeparator = bUseBar and " | " or " "
		local bClanTicked = false

		local cSpeedRate = clan_speed_slider:GetValue()
		if (globals.CurTime() - cLastClanTime) > cSpeedRate then
			cLastClanTime = globals.CurTime()
			local presetTable = TxtClanTagPresets[cPreset + 1]
			if presetTable and #presetTable > 0 then
				cSpammerIdx = cSpammerIdx + 1
				if cSpammerIdx > #presetTable then cSpammerIdx = 1 end
				cCurrClanStr = presetTable[cSpammerIdx]
				bClanTicked = true
			else
				cCurrClanStr = ""
			end
		end

		local bUseFake = clan_fake_toggle:GetValue()
		local bFakeTicked = false

		if bUseFake == true then
			local cBaseFake = clan_fake_input:GetString()
			
			if cBaseFake == nil or cBaseFake == "" then
				cBaseFake = cOldRealName
			end

			if clan_fake_anim_cb:GetValue() == true then
				local cFakeSpeed = clan_fake_speed_slider:GetValue()
				if (globals.CurTime() - cLastFakeTime) > cFakeSpeed then
					cLastFakeTime = globals.CurTime()
					
					local pUtf8Fake = get_utf8_chars(cBaseFake)
					local cMaxFake = #pUtf8Fake
					
					if cMaxFake > 0 then
						cClanFakeIdx = cClanFakeIdx + cClanFakeDir
						if cClanFakeIdx >= cMaxFake then
							cClanFakeIdx = cMaxFake
							cClanFakeDir = -1
						elseif cClanFakeIdx <= 1 then
							cClanFakeIdx = 1
							cClanFakeDir = 1
						end
						cCurrFakeStr = table.concat(pUtf8Fake, "", 1, cClanFakeIdx)
						bFakeTicked = true
					end
				end
			else
				cCurrFakeStr = cBaseFake
			end
		else
			cCurrFakeStr = cOldRealName
		end

		local bIsAnyAnimActive = (#TxtClanTagPresets > 0) or (bUseFake and clan_fake_anim_cb:GetValue())
		
		if (bIsAnyAnimActive == true and (bClanTicked == true or bFakeTicked == true)) or (bIsAnyAnimActive == false and (globals.CurTime() - cLastCombineTime) > 0.4) then
			cLastCombineTime = globals.CurTime()
			
			local cFinalString = ""
			if #cCurrClanStr > 0 then
				cFinalString = cCurrClanStr .. cSeparator .. cCurrFakeStr
			else
				cFinalString = cCurrFakeStr
			end
			
			set_network_name(cFinalString)
			bNameWasChanged = true
		end
	end
end

local function menu_handler()
	if bForceExit == true then return end

	if globals.CurTime() < cLastMenuTime then
		cLastMenuTime = globals.CurTime()
	end

	if (globals.CurTime() - cLastMenuTime) > 0.01 then
		cLastMenuTime = globals.CurTime()
		-- Menu visibility follows the selected mode even while the master toggle
		-- is off, so every option can be configured before enabling it.
		local cCurrentMode = mode_combo:GetValue() + 1

		fake_input:SetInvisible(true)
		fake_anim_cb:SetInvisible(true)
		fake_speed_slider:SetInvisible(true)
		stealer_speed_slider:SetInvisible(true)
		stealer_player_combo:SetInvisible(true)
		stealer_spam_cb:SetInvisible(true)
		clan_preset_combo:SetInvisible(true)
		clan_scan_button:SetInvisible(true)
		clan_folder_hint:SetInvisible(true)
		clan_bar_cb:SetInvisible(true)
		clan_speed_slider:SetInvisible(true)
		clan_fake_toggle:SetInvisible(true)
		clan_fake_input:SetInvisible(true)
		clan_fake_anim_cb:SetInvisible(true)
		clan_fake_speed_slider:SetInvisible(true)

		if cCurrentMode == 1 then
			stealer_spam_cb:SetInvisible(false)
			if stealer_spam_cb:GetValue() == true then
				stealer_speed_slider:SetInvisible(false)
			else
				stealer_player_combo:SetInvisible(false)
			end
			
		elseif cCurrentMode == 2 then
			fake_input:SetInvisible(false)
			fake_anim_cb:SetInvisible(false)
			
			if fake_anim_cb:GetValue() == true then
				fake_speed_slider:SetInvisible(false)
			end
			
		elseif cCurrentMode == 3 then
			clan_preset_combo:SetInvisible(false)
			clan_scan_button:SetInvisible(false)
			clan_folder_hint:SetInvisible(false)
			clan_bar_cb:SetInvisible(false)
			clan_speed_slider:SetInvisible(false)

			clan_fake_toggle:SetInvisible(false)
			
			if clan_fake_toggle:GetValue() == true then
				clan_fake_input:SetInvisible(false)
				clan_fake_anim_cb:SetInvisible(false)
				
				if clan_fake_anim_cb:GetValue() == true then
					clan_fake_speed_slider:SetInvisible(false)
				end
			end
		end
	end
end

callbacks.Register("Draw", "Logic_Hook", logic_handler)
callbacks.Register("Draw", "Menu_Hook", menu_handler)

callbacks.Register("Unload", "Unload_Hook", function()
	bForceExit = true
	if bNameWasSaved == true and get_current_mode() ~= 0 then
		local pLocalPlayer = entities.GetLocalPlayer()
		if pLocalPlayer ~= nil then
			set_network_name(cOldRealName)
		end
	end
end)
