local DEBUG_STATUS = false

-- User settings (seconds).
local INITIAL_LOG_START_SECONDS = 120
local INITIAL_LOG_INTERVAL_SECONDS = 10
local RECONNECT_COUNTDOWN_SECONDS = 90

ffi.cdef[[
	int RegOpenKeyExA(void* hKey, const char* lpSubKey, unsigned long ulOptions, unsigned long samDesired, void** phkResult);
	int RegQueryValueExA(void* hKey, const char* lpValueName, unsigned long* lpReserved, unsigned long* lpType, unsigned char* lpData, unsigned long* lpcbData);
	int RegCloseKey(void* hKey);

	void* ShellExecuteA(void* hwnd, const char* lpOperation, const char* lpFile, const char* lpParameters, const char* lpDirectory, int nShowCmd);

	void* CreateFileA(const char* lpFileName, unsigned long dwDesiredAccess, unsigned long dwShareMode, void* lpSecurityAttributes, unsigned long dwCreationDisposition, unsigned long dwFlagsAndAttributes, void* hTemplateFile);
	int CloseHandle(void* hObject);
]]

local SW_HIDE = 0x0
local SW_SHOW = 0x5

local SW_POWERSHELL = SW_HIDE

if DEBUG_STATUS == true then
	SW_POWERSHELL = SW_SHOW
end

local ERROR_SUCCESS = 0x0

local HKEY_CURRENT_USER 	= ffi.cast("void*", 0x80000001)
local HKEY_STEAM_SUB_PATH 	= "Software\\Valve\\Steam"

local KEY_QUERY_VALUE		= 0x0001

local GENERIC_ALL 		= 0x10000000
local CREATE_ALWAYS 		= 0x2
local FILE_ATTRIBUTE_NORMAL	= 0x80
local INVALID_HANDLE_VALUE 	= ffi.cast("void*", -0x1)

local Advapi32 	= ffi.load("Advapi32")
local Shell32 	= ffi.load("Shell32")
local Kernel32 	= ffi.load("Kernel32")

local cReconnectBypassStatus_Text_Active 	= "Status: Active"
local cReconnectBypassStatus_Text_Disabled 	= "Status: Disabled"
local cReconnectBypassStatus_Text_Unknown 	= "Status: Unknown"

local bReconnectBypassStatusEnabled 		= -1

local cPowerShell_BlockFileName 	= "FILE_ENABLE.dat"
local cPowerShell_UnlockFileName 	= "FILE_DISABLE.dat"
local cPowerShell_ExitFileName 		= "FILE_EXIT.dat"

local cPowerShell_RuleName 		= "7XnIUxGt4Tw13Lzm"
local cPowerShell_WindowTitle 		= "z0tPP1Gfyo49xlZK"

local cFullSteamPath 	= ""
local cBackupSteamPath 	= "C:\\Program Files (x86)\\Steam\\steam.exe"
local cSteamExeRegName  = "SteamExe"

local TempBridgePath 	= ""

local cReconnectBypassInfo_Text = 	" Getting kicked by team? Wanna Grief teammate? \n\n" ..
					" Go ahead! Enable it!\n\n\n\n" ..
					" You should be able to reconnect for about ~2minutes, \n\n" ..
					" as many times as you like!"

local ReconnectBypass_Window_Ref 		= nil

local ReconnectBypass_Menu_GroupBox_Ref 	= nil
local ReconnectBypass_Enable_Button_Ref 	= nil
local ReconnectBypass_Disable_Button_Ref 	= nil

local ReconnectBypassStatus_GroupBox_Ref 	= nil
local ReconnectBypassStatus_Text_Ref 		= nil
local ReconnectBypassTimer_Text_Ref 		= nil

local ReconnectBypassInfo_GroupBox_Ref 		= nil
local ReconnectBypassInfo_Text_Ref 		= nil

local bTimerRunning = false
local cTimerStartedAt = 0
local bWasInMatch = false
local cLastTimerDisplaySecond = -1
local cTimerMode = "initial_elapsed"
local bWaitingForReconnect = false
local cLastInitialLogStep = -1
local cLastCountdownRemaining = -1

local function GetSafeTime()
	local ok, value = pcall(common.Time)
	if ok and type(value) == "number" then return value end
	return 0
end

local function ResetReconnectTimer(reason)
	cTimerStartedAt = GetSafeTime()
	bTimerRunning = true
	cLastTimerDisplaySecond = -1
	cTimerMode = "initial_elapsed"
	bWaitingForReconnect = false
	cLastInitialLogStep = -1
	cLastCountdownRemaining = -1
	if DEBUG_STATUS == true then
		print("[Reconnect Bypass] Timer reset: " .. tostring(reason))
	end
end

local function StartReconnectCountdown()
	cTimerStartedAt = GetSafeTime()
	bTimerRunning = true
	cTimerMode = "reconnect_countdown"
	bWaitingForReconnect = false
	cLastTimerDisplaySecond = -1
	cLastCountdownRemaining = RECONNECT_COUNTDOWN_SECONDS + 1
	print("[Reconnect Bypass] Reconnected; 01:30 countdown started")
end

local function StopReconnectTimer()
	bTimerRunning = false
	cTimerStartedAt = 0
	cTimerMode = "initial_elapsed"
	bWaitingForReconnect = false
	cLastTimerDisplaySecond = -1
	cLastInitialLogStep = -1
	cLastCountdownRemaining = -1
	if ReconnectBypassTimer_Text_Ref ~= nil then
		ReconnectBypassTimer_Text_Ref:SetText("Timer: Disabled")
	end
end

-------------- / Function_1 \ --------------
local function InitPowerShellScript()
	TempBridgePath = cFullSteamPath:gsub("\\steam%.exe", "")

	local PowerShellScriptRAW = string.format([[Start-Sleep -Milliseconds 150; Remove-Item -Path '%s' -Force -ErrorAction SilentlyContinue; Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\mpssvc' -Name 'Start' -Value 2;  Start-Sleep -Milliseconds 100; net start mpssvc; Start-Sleep -Milliseconds 100; netsh advfirewall set allprofiles state on; Get-Process 'powershell' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match '%s' } | Stop-Process -Force; Start-Sleep -Milliseconds 100; $host.UI.RawUI.WindowTitle = '%s'; while ([bool](Get-Process -Name 'cs2' -ErrorAction SilentlyContinue)) { if (Test-Path -Path '%s') { Start-Sleep -Milliseconds 100; Remove-Item -Path '%s' -Force; Remove-NetFirewallRule -DisplayName '%s'; New-NetFirewallRule -DisplayName '%s' -Direction Outbound -Action Block -Program '%s'; } if (Test-Path -Path '%s') { Start-Sleep -Milliseconds 100; Remove-Item -Path '%s' -Force; Remove-NetFirewallRule -DisplayName '%s'; } if (Test-Path -Path '%s') { Start-Sleep -Milliseconds 100; Remove-Item -Path '%s' -Force; Remove-NetFirewallRule -DisplayName '%s'; break; } Start-Sleep -Milliseconds 100; } Remove-NetFirewallRule -DisplayName '%s'; Start-Sleep -Milliseconds 3000; ]],

		TempBridgePath .. '\\' .. cPowerShell_ExitFileName,

		cPowerShell_WindowTitle, cPowerShell_WindowTitle,

		TempBridgePath .. '\\' ..cPowerShell_BlockFileName, TempBridgePath .. '\\' .. cPowerShell_BlockFileName,
		cPowerShell_RuleName, cPowerShell_RuleName, cFullSteamPath,

		TempBridgePath .. '\\' .. cPowerShell_UnlockFileName, TempBridgePath .. '\\' .. cPowerShell_UnlockFileName,
		cPowerShell_RuleName,

		TempBridgePath .. '\\' .. cPowerShell_ExitFileName, TempBridgePath .. '\\' .. cPowerShell_ExitFileName,
		cPowerShell_RuleName,

		cPowerShell_RuleName
	)

	if not Shell32 then 
		print("[-] Something went wrong")
		return false
	end

	local PowerShellScriptFULL = '-ExecutionPolicy Bypass -Command "' .. PowerShellScriptRAW .. '"'

	if DEBUG_STATUS == true then
		PowerShellScriptFULL = '-NoExit ' .. PowerShellScriptFULL
		print("Powershell script:" .. PowerShellScriptFULL)
	else
		PowerShellScriptFULL = '-WindowStyle Hidden ' .. PowerShellScriptFULL
	end

	local bResult, hInstance = pcall(function()
		return Shell32.ShellExecuteA(nil,
				 		"runas",
						"powershell.exe",
						PowerShellScriptFULL,
						nil,
						SW_POWERSHELL)
	end)

	if bResult and tonumber(ffi.cast("intptr_t", hInstance)) > 32 then
		print("[+] Lua should work successfully")
	else
		print("[-] Please relaunch Lua with admin rights")
		return false
	end

	return true
end
-------------- / Function_2 \ --------------
local function GetSteamPath()
	if not Advapi32 then
		cFullSteamPath = cBackupSteamPath
	end
	
	local hKeySteam = ffi.new("void*[1]")
	
	local bResult, lpStatus = pcall(function()
		return Advapi32.RegOpenKeyExA(HKEY_CURRENT_USER,
					      HKEY_STEAM_SUB_PATH,
					      0,
					      KEY_QUERY_VALUE,
					      hKeySteam)
	end)
	
	if bResult and lpStatus == ERROR_SUCCESS then
		local lpData 		= ffi.new("unsigned char[1024]")
		local lpDataSize 	= ffi.new("unsigned long[1]", 1024)

		bResult, lpStatus = pcall(function()
			return Advapi32.RegQueryValueExA(hKeySteam[0],
							 cSteamExeRegName,
							 nil,
							 nil,
							 lpData,
							 lpDataSize)
		end)

		if bResult and lpStatus == ERROR_SUCCESS then
			cFullSteamPath = ffi.string(lpData)
			cFullSteamPath = cFullSteamPath:gsub("/", "\\")
		else
			cFullSteamPath = cBackupSteamPath
		end

		pcall(function()
			return Advapi32.RegCloseKey(hKeySteam[0])
		end)
	else
		cFullSteamPath = cBackupSteamPath
	end
end
-------------- / Function_3 \ --------------
local function CreateActionFile(FileName)
	if not Kernel32 then
		print("[-] Something went wrong")
		return false
	end

	local bResult, hActionFile = pcall(function()
			return Kernel32.CreateFileA(TempBridgePath .. '\\' .. FileName, GENERIC_ALL, 0, nil, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nil)
		end)

	if bResult and hActionFile ~= INVALID_HANDLE_VALUE then
		pcall(function()
			return Kernel32.CloseHandle(hActionFile)
		end)
	else
		print("[-] Failed to create action file")
		return false
	end

	return true
end

-------------- / Function_4 \ --------------
local bPowerShellWasInit = false
local function BlockSteamOutConnection()
	if bPowerShellWasInit == false then
		GetSteamPath()
		InitPowerShellScript()
		bPowerShellWasInit = true
	end

	if CreateActionFile(cPowerShell_BlockFileName) then
		ReconnectBypassStatus_Text_Ref:SetText(cReconnectBypassStatus_Text_Active .. "\n ")
		bReconnectBypassStatusEnabled = true
		ResetReconnectTimer("enabled")
	end
end
-------------- / Function_5 \ --------------
local function UnlockSteamOutConnection()
	if bPowerShellWasInit == false then
		GetSteamPath()
		InitPowerShellScript()
		bPowerShellWasInit = true
	end

	if CreateActionFile(cPowerShell_UnlockFileName) then
		ReconnectBypassStatus_Text_Ref:SetText(cReconnectBypassStatus_Text_Disabled .. "\n ")
		bReconnectBypassStatusEnabled = false
		StopReconnectTimer()
	end
end
-------------- / Function_6 \ --------------
local cCurrentVersion = "v1.7.2"

local function CheckForUpdates()
	http.Get("https://raw.githubusercontent.com/0neLucky0neee/Aimware_Luas/refs/heads/main/Reconnect%20Bypass/Assets/version.txt", function(cExpectedVesion)
		print("[Reconnect Bypass] Your lua version is: " .. cCurrentVersion)

		if cExpectedVesion == nil then
			print("[Reconnect Bypass] Unable to receive the latest version")
			return
		end
	
		if string.find(cExpectedVesion, cCurrentVersion) == nil then
			print("[Reconnect Bypass] New version is out, get it on github.com/0neLucky0neee/Aimware_Luas")
		end
	end
	)
end

--------------  / Callback \ --------------

ReconnectBypass_Window_Ref 			= gui.Window("var_reconnect_bypass_window_0", "Reconnect Bypass", 220, 90, 500, 270)

ReconnectBypass_Menu_GroupBox_Ref 		= gui.Groupbox(ReconnectBypass_Window_Ref, "Controller", 20, 15, 150, 80)
ReconnectBypass_Enable_Button_Ref 		= gui.Button(ReconnectBypass_Menu_GroupBox_Ref, "Enable", BlockSteamOutConnection)
ReconnectBypass_Disable_Button_Ref 		= gui.Button(ReconnectBypass_Menu_GroupBox_Ref, "Disable", UnlockSteamOutConnection)

ReconnectBypassStatus_GroupBox_Ref 		= gui.Groupbox(ReconnectBypass_Window_Ref, "Status Information", 20, (15 + 80) + 15 + 20, 150, 100)
ReconnectBypassStatus_Text_Ref 			= gui.Text(ReconnectBypassStatus_GroupBox_Ref, cReconnectBypassStatus_Text_Unknown .. "\n ")
ReconnectBypassTimer_Text_Ref 			= gui.Text(ReconnectBypassStatus_GroupBox_Ref, "Timer: Disabled")

ReconnectBypassInfo_GroupBox_Ref 		= gui.Groupbox(ReconnectBypass_Window_Ref, "When should I turn it on?", (150 + 20) + 20, 15, 295, ((15 + 80) + 15 + 20) + 80)
ReconnectBypassInfo_Text_Ref 			= gui.Text(ReconnectBypassInfo_GroupBox_Ref, cReconnectBypassInfo_Text)

ReconnectBypass_Window_Ref:SetOpenKey(gui.GetValue("adv.menukey"))

--------------  / Callback \ --------------
callbacks.Register("Draw", function()
	local ok_server, server_ip = pcall(engine.GetServerIP)
	-- If AIMWARE cannot report the server for this frame, keep the previous
	-- state. Treating a temporary API error as a disconnect can create false logs.
	if ok_server == false then return end
	local bInMatch = ok_server and server_ip ~= nil and server_ip ~= ""

	-- Remember a real connected -> disconnected transition without printing it.
	if bReconnectBypassStatusEnabled == true and bWasInMatch == true and bInMatch == false then
		bWaitingForReconnect = true
	end

	-- Only a connection made after the disconnect above starts the 90-second timer.
	if bReconnectBypassStatusEnabled == true and bInMatch == true
		and bWasInMatch == false and bWaitingForReconnect == true then
		StartReconnectCountdown()
	end
	bWasInMatch = bInMatch

	if bTimerRunning == false or ReconnectBypassTimer_Text_Ref == nil then return end

	local elapsed = GetSafeTime() - cTimerStartedAt
	if elapsed < 0 then
		cTimerStartedAt = GetSafeTime()
		cLastTimerDisplaySecond = -1
		elapsed = 0
	end

	if cTimerMode == "initial_elapsed" then
		local elapsed_seconds = math.max(0, math.floor(elapsed))
		if elapsed_seconds ~= cLastTimerDisplaySecond then
			cLastTimerDisplaySecond = elapsed_seconds
			ReconnectBypassTimer_Text_Ref:SetText(string.format(
				"Elapsed: %02d:%02d", math.floor(elapsed_seconds / 60), elapsed_seconds % 60
			))
		end

		local start_at = math.max(1, tonumber(INITIAL_LOG_START_SECONDS) or 120)
		local interval = math.max(1, tonumber(INITIAL_LOG_INTERVAL_SECONDS) or 10)
		if elapsed_seconds >= start_at then
			local log_step = math.floor((elapsed_seconds - start_at) / interval)
			if cLastInitialLogStep < 0 then
				print("[Reconnect Bypass] Initial timer has passed 2 minutes")
				cLastInitialLogStep = 0
			end
			if log_step > cLastInitialLogStep then
				local logged_elapsed = start_at + (log_step * interval)
				print(string.format("[Reconnect Bypass] Initial elapsed: %d seconds", logged_elapsed))
				cLastInitialLogStep = log_step
			end
		end
	else
		local duration = math.max(1, tonumber(RECONNECT_COUNTDOWN_SECONDS) or 90)
		local remaining = math.max(0, math.ceil(duration - elapsed))
		if remaining ~= cLastTimerDisplaySecond then
			cLastTimerDisplaySecond = remaining
			ReconnectBypassTimer_Text_Ref:SetText(string.format(
				"Remaining: %02d:%02d", math.floor(remaining / 60), remaining % 60
			))
		end

		local warning_points = { 30, 20, 10, 5, 4, 3, 2, 1 }
		for i = 1, #warning_points do
			local point = warning_points[i]
			if cLastCountdownRemaining > point and remaining <= point then
				print(string.format("[Reconnect Bypass] %d seconds remaining", point))
			end
		end
		cLastCountdownRemaining = remaining
	end
end)

callbacks.Register("Unload", function() 
	CreateActionFile(cPowerShell_ExitFileName) 
end)
----------------  / Main \ ----------------
CheckForUpdates()
