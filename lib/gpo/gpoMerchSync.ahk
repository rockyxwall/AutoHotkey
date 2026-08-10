#Requires AutoHotkey v2.0

; ═══════════════════════════════════════════════════════════════════════════
; GPO MERCH SYNC
; ─────────────────────────────────────────────────────────────────────────
; Automates GPO private server joining on Virtual Desktop #3 before stock
; refresh, alerts on Merchant spawn, and manages stock checking lifecycle.
; Configurable via config.json.
; ═══════════════════════════════════════════════════════════════════════════
class GPOMerchSync {
    ; ── Settings ────────────────────────────────────────────────────────────
    static PROCESS         := "RobloxPlayerBeta.exe"
    static SCRIPT_DIR {
        get {
            SplitPath A_LineFile, , &dir
            return dir
        }
    }
    static CONFIG_PATH => GPOMerchSync.SCRIPT_DIR "\config.json"
    static ASSET_DIR   => GPOMerchSync.SCRIPT_DIR "\img\"

    ; ── State ───────────────────────────────────────────────────────────────
    static running         := false
    static inCycle         := false
    static currentDesktop  := 1
    static targetRefresh   := 0

    ; Dynamic configuration loaded from config.json
    static psCode                       := "Jk2JKTAKCf"
    static placeId                      := "1730877806"
    static afkDesktop                   := 3
    static homeDesktop                  := 1
    static alarmLead                    := 15
    static afkTimeout                   := 300
    static calibratedTs                 := 0
    static confidence                   := 50

    ; Timing & Schedule Config
    static joinLeadSeconds              := 810    ; 13m 30s before stock refresh
    static stockRefreshInterval         := 1800   ; 30 mins
    static merchantSpawnDelay           := 210    ; 3m 30s after join

    ; Workflow Delays (ms / sec)
    static afkDesktopDelayMs            := 500
    static robloxWaitTimeoutSecs        := 20
    static robloxFocusDelayMs           := 1000
    static mainScreenClickIntervalMs    := 400
    static mainScreenPostDelayMs        := 1000
    static psButtonDelayMs              := 1500
    static psBoxDelayMs                 := 500
    static pasteCodeDelayMs             := 300
    static enterKeyDelayMs              := 2500
    static regularButtonDelayMs         := 2000

    ; Assets & Sound
    static mainScreenImage              := "main_screen.png"
    static alarmBeepCount               := 4

    ; Coordinate map
    static coordInitialClick            := {x: 1886, y: 1050}
    static coordPsBtn                   := {x: 1650, y: 714}
    static coordPsBox                   := {x: 962, y: 695}
    static coordRegBtn                  := {x: 752, y: 581}
    static coordSeaBtn                  := {x: 815, y: 589}

    ; ── Called by router ────────────────────────────────────────────────────
    static Toggle() {
        GPOMerchSync.running := !GPOMerchSync.running
        if GPOMerchSync.running {
            GPOMerchSync.LoadConfig()
            GPORefreshHUD.Start()
            SetTimer ObjBindMethod(GPOMerchSync, "_Loop"), 1000
        } else {
            SetTimer ObjBindMethod(GPOMerchSync, "_Loop"), 0
            GPOMerchSync.inCycle := false
            GPORefreshHUD.Stop()
        }
    }

    ; ── Hotkey Calibration Entry Point ───────────────────────────────────────
    static CalibrateTimestamp() {
        GPORefreshHUD.Calibrate()
        GPOMerchSync.LoadConfig()
    }

    ; ── Cycle Lifecycle Control ─────────────────────────────────────────────
    static FinishCycle() {
        GPOMerchSync.inCycle := false
        GPOMerchSync.ForceKillRoblox()
        GPOMerchSync.SwitchDesktop(GPOMerchSync.homeDesktop)
    }

    static EmergencyStop() {
        GPOMerchSync.running := false
        GPOMerchSync.inCycle := false
        SetTimer ObjBindMethod(GPOMerchSync, "_Loop"), 0
        GPORefreshHUD.Stop()
        GPOMerchSync.ForceKillRoblox()
        GPOMerchSync.SwitchDesktop(GPOMerchSync.homeDesktop)
    }

    ; ── Internal Loop ───────────────────────────────────────────────────────
    static _Loop() {
        if !GPOMerchSync.running
            return

        nowUnix := GPOMerchSync._GetUnixTime()
        interval := GPOMerchSync.stockRefreshInterval

        ; Determine next refresh target (recurs every stockRefreshInterval seconds)
        if (GPOMerchSync.calibratedTs > 0) {
            diff := GPOMerchSync.calibratedTs - nowUnix
            if (diff <= 0) {
                cyclesPassed := Floor(Abs(diff) / interval) + 1
                GPOMerchSync.targetRefresh := GPOMerchSync.calibratedTs + (cyclesPassed * interval)
            } else {
                GPOMerchSync.targetRefresh := GPOMerchSync.calibratedTs
            }
        } else {
            ; Auto top-of-hour alignment
            rem := Mod(nowUnix, interval)
            GPOMerchSync.targetRefresh := nowUnix + (interval - rem)
        }

        ; Launch join workflow joinLeadSeconds before stock refresh
        joinTrigger := GPOMerchSync.targetRefresh - GPOMerchSync.joinLeadSeconds

        if (nowUnix >= joinTrigger && !GPOMerchSync.inCycle) {
            GPOMerchSync.inCycle := true
            GPOMerchSync._RunJoinWorkflow()
        }
    }

    ; ── Join Workflow ────────────────────────────────────────────────────────
    static _RunJoinWorkflow() {
        CoordMode "Pixel", "Screen"
        CoordMode "Mouse", "Screen"

        ; Ensure any existing/stuck Roblox process is closed for a clean launch
        GPOMerchSync.ForceKillRoblox()

        ; Switch to AFK Desktop
        if (!GPOMerchSync.running)
            return
        GPOMerchSync.SwitchDesktop(GPOMerchSync.afkDesktop)
        if (!GPOMerchSync._SleepIfRunning(GPOMerchSync.afkDesktopDelayMs))
            return

        ; Launch Roblox GPO
        if (!GPOMerchSync.running)
            return
        Run "roblox://placeId=" GPOMerchSync.placeId

        ; Wait up to robloxWaitTimeoutSecs for Roblox window to exist & focus/maximize it
        if (!GPOMerchSync._WaitForRoblox(GPOMerchSync.robloxWaitTimeoutSecs))
            return
        if (!GPOMerchSync._SleepIfRunning(GPOMerchSync.robloxFocusDelayMs))
            return

        ; Constantly click initial_click coords until mainScreenImage appears (no timeout)
        if (!GPOMerchSync.running)
            return

        while (GPOMerchSync.running) {
            foundX := 0, foundY := 0
            if GPOMerchSync._FindImageOrSleep(GPOMerchSync.mainScreenImage, 200, &foundX, &foundY) {
                break
            }

            GPOMerchSync._ClickRoblox(GPOMerchSync.coordInitialClick.x, GPOMerchSync.coordInitialClick.y)

            if (!GPOMerchSync._SleepIfRunning(GPOMerchSync.mainScreenClickIntervalMs))
                return
        }

        if (!GPOMerchSync.running)
            return

        if (!GPOMerchSync._SleepIfRunning(GPOMerchSync.mainScreenPostDelayMs))
            return

        ; Main Menu PS Button
        if (!GPOMerchSync.running)
            return
        GPOMerchSync._ClickRoblox(GPOMerchSync.coordPsBtn.x, GPOMerchSync.coordPsBtn.y)
        if (!GPOMerchSync._SleepIfRunning(GPOMerchSync.psButtonDelayMs))
            return

        ; PS Code Box
        if (!GPOMerchSync.running)
            return
        GPOMerchSync._ClickRoblox(GPOMerchSync.coordPsBox.x, GPOMerchSync.coordPsBox.y)
        if (!GPOMerchSync._SleepIfRunning(GPOMerchSync.psBoxDelayMs))
            return

        ; Paste PS Code & Enter
        if (!GPOMerchSync.running)
            return
        A_Clipboard := GPOMerchSync.psCode
        ClipWait 1
        if (!GPOMerchSync.running)
            return
        Send "^v"
        if (!GPOMerchSync._SleepIfRunning(GPOMerchSync.pasteCodeDelayMs))
            return
        Send "{Enter}"
        if (!GPOMerchSync._SleepIfRunning(GPOMerchSync.enterKeyDelayMs))
            return

        ; Regular Button
        if (!GPOMerchSync.running)
            return
        GPOMerchSync._ClickRoblox(GPOMerchSync.coordRegBtn.x, GPOMerchSync.coordRegBtn.y)
        if (!GPOMerchSync._SleepIfRunning(GPOMerchSync.regularButtonDelayMs))
            return

        ; First Sea Button
        if (!GPOMerchSync.running)
            return
        GPOMerchSync._ClickRoblox(GPOMerchSync.coordSeaBtn.x, GPOMerchSync.coordSeaBtn.y)

        ; Return to home desktop until Merchant spawn
        if (!GPOMerchSync.running)
            return
        GPOMerchSync.SwitchDesktop(GPOMerchSync.homeDesktop)

        ; Schedule Alarm
        leadDelayMs := max(1000, ((GPOMerchSync.merchantSpawnDelay - GPOMerchSync.alarmLead) * 1000))
        SetTimer ObjBindMethod(GPOMerchSync, "_PlayAlarmCallback"), -leadDelayMs
    }

    static _PlayAlarmCallback() {
        if !GPOMerchSync.running
            return

        ; Beep notification
        Loop GPOMerchSync.alarmBeepCount {
            SoundBeep 1000, 300
            Sleep 100
            SoundBeep 1400, 300
            Sleep 100
        }

        GPOMerchSync.SwitchDesktop(GPOMerchSync.afkDesktop)
    }

    ; ── Helper Utilities ────────────────────────────────────────────────────
    static _SleepIfRunning(ms) {
        elapsed := 0
        while (elapsed < ms) {
            if (!GPOMerchSync.running)
                return false
            step := Min(50, ms - elapsed)
            Sleep step
            elapsed += step
        }
        return GPOMerchSync.running
    }

    static _ClickCoordsOrImage(coordObj, imageName, timeoutMs := 5000) {
        if !GPOMerchSync.running
            return false

        CoordMode "Pixel", "Screen"
        CoordMode "Mouse", "Screen"

        ; 1. Try ImageSearch FIRST (poll up to timeoutMs)
        foundX := 0
        foundY := 0
        if (imageName != "" && GPOMerchSync._FindImageOrSleep(imageName, timeoutMs, &foundX, &foundY)) {
            if !GPOMerchSync.running
                return false
            MouseMove foundX, foundY
            Sleep 150
            Click foundX, foundY
            return true
        }

        ; 2. Fallback to static coordinates if image search timed out or file missing
        if (coordObj && coordObj.HasOwnProp("x") && coordObj.HasOwnProp("y") && coordObj.x > 0 && coordObj.y > 0) {
            if !GPOMerchSync.running
                return false
            MouseMove coordObj.x, coordObj.y
            Sleep 150
            Click coordObj.x, coordObj.y
            return true
        }

        return false
    }

    static _FindImageOrSleep(imageName, timeoutMs, &foundX := 0, &foundY := 0) {
        imgPath := GPOMerchSync.ASSET_DIR imageName
        if !FileExist(imgPath)
            return false

        CoordMode "Pixel", "Screen"
        startTick := A_TickCount
        while (GPOMerchSync.running && (A_TickCount - startTick < timeoutMs)) {
            try {
                if ImageSearch(&foundX, &foundY, 0, 0, A_ScreenWidth, A_ScreenHeight, "*" GPOMerchSync.confidence " " imgPath) {
                    return true
                }
            } catch {
                ; Ignore search errors during transition
            }
            if (!GPOMerchSync._SleepIfRunning(150))
                return false
        }
        return false
    }

    static _WaitForRoblox(timeoutSecs := 20) {
        startTick := A_TickCount
        while (GPOMerchSync.running && (A_TickCount - startTick < timeoutSecs * 1000)) {
            if WinExist("ahk_exe " GPOMerchSync.PROCESS) {
                try {
                    WinActivate "ahk_exe " GPOMerchSync.PROCESS
                    WinMaximize "ahk_exe " GPOMerchSync.PROCESS
                    return true
                } catch {
                    ; Handle temporary activation glitches during launcher/splash window transitions
                }
            }
            if (!GPOMerchSync._SleepIfRunning(500))
                return false
        }
        return false
    }

    static _ClickRoblox(x, y, radius := 5) {
        CoordMode "Mouse", "Screen"
        if !WinActive("ahk_exe " GPOMerchSync.PROCESS) {
            try WinActivate "ahk_exe " GPOMerchSync.PROCESS
            Sleep 100
        }

        ; Randomize position within 5px radius to force Windows & Roblox to register fresh WM_MOUSEMOVE on every click
        offsetX := Random(-radius, radius)
        offsetY := Random(-radius, radius)
        targetX := x + offsetX
        targetY := y + offsetY

        MouseMove targetX, targetY
        Sleep 40

        ; Hold click down for 50ms so Roblox engine registers the press
        Click "Down"
        Sleep 50
        Click "Up"
    }

    static SwitchDesktop(targetDesktop) {
        if (targetDesktop < 1)
            targetDesktop := 1

        ; Windows virtual desktop switching is relative (Win+Ctrl+Left/Right).
        ; Rewind to Desktop 1 first by sending Win+Ctrl+Left 6 times (Windows clamps at Desktop 1).
        Loop 6 {
            Send "{LWin down}{LCtrl down}{Left}{LWin up}{LCtrl up}"
            Sleep 80
        }
        Sleep 150

        ; Navigate Right from Desktop 1 to targetDesktop
        Loop targetDesktop - 1 {
            Send "{LWin down}{LCtrl down}{Right}{LWin up}{LCtrl up}"
            Sleep 150
        }
        Sleep 250

        ; Release modifier keys to avoid stuck modifier keys when executing Run
        Send "{LWin up}{LCtrl up}{Alt up}{Shift up}"
    }

    static ForceKillRoblox() {
        if ProcessExist(GPOMerchSync.PROCESS) {
            try ProcessClose(GPOMerchSync.PROCESS)
            Sleep 500
        }
    }

    static _GetUnixTime() {
        return DateDiff(A_NowUTC, "19700101000000", "Seconds")
    }

    ; ── Dynamic Config Parser / Writer ───────────────────────────────────────
    static LoadConfig() {
        if !FileExist(GPOMerchSync.CONFIG_PATH)
            return

        try {
            content := FileRead(GPOMerchSync.CONFIG_PATH)

            ; ── Helper: extract a named section block from JSON ───────────────
            ; Returns the raw text between "sectionName": { ... }
            _Section(src, sectionName) {
                pattern := 'i)"' sectionName '"\s*:\s*\{'
                pos := RegExMatch(src, pattern)
                if (!pos)
                    return ""
                ; Walk forward past the opening brace to find matching close brace
                start := pos + StrLen(RegExMatch(src, pattern, &mm) ? mm[0] : 0)
                depth := 1
                i := start
                while (i <= StrLen(src) && depth > 0) {
                    ch := SubStr(src, i, 1)
                    if (ch = "{")
                        depth++
                    else if (ch = "}")
                        depth--
                    i++
                }
                return SubStr(src, start, i - start - 1)
            }

            ; ── Extract each section ──────────────────────────────────────────
            server   := _Section(content, "server")
            desktops := _Section(content, "desktops")
            schedule := _Section(content, "schedule")
            delays   := _Section(content, "delays")
            assets   := _Section(content, "assets_and_detection")
            coords   := _Section(content, "coords")

            ; ── server ───────────────────────────────────────────────────────
            if RegExMatch(server, 'i)"gpo_ps_code"\s*:\s*"([^"]+)"', &m)
                GPOMerchSync.psCode := m[1]
            if RegExMatch(server, 'i)"roblox_place_id"\s*:\s*"([^"]+)"', &m)
                GPOMerchSync.placeId := m[1]

            ; ── desktops ─────────────────────────────────────────────────────
            if RegExMatch(desktops, 'i)"afk_desktop_index"\s*:\s*(\d+)', &m)
                GPOMerchSync.afkDesktop := Integer(m[1])
            if RegExMatch(desktops, 'i)"home_desktop_index"\s*:\s*(\d+)', &m)
                GPOMerchSync.homeDesktop := Integer(m[1])

            ; ── schedule ─────────────────────────────────────────────────────
            if RegExMatch(schedule, 'i)"stock_refresh_interval_seconds"\s*:\s*(\d+)', &m)
                GPOMerchSync.stockRefreshInterval := Integer(m[1])
            if RegExMatch(schedule, 'i)"join_lead_seconds"\s*:\s*(\d+)', &m)
                GPOMerchSync.joinLeadSeconds := Integer(m[1])
            if RegExMatch(schedule, 'i)"merchant_spawn_delay_seconds"\s*:\s*(\d+)', &m)
                GPOMerchSync.merchantSpawnDelay := Integer(m[1])
            if RegExMatch(schedule, 'i)"merchant_alarm_lead_seconds"\s*:\s*(\d+)', &m)
                GPOMerchSync.alarmLead := Integer(m[1])
            if RegExMatch(schedule, 'i)"afk_timeout_seconds"\s*:\s*(\d+)', &m)
                GPOMerchSync.afkTimeout := Integer(m[1])
            if RegExMatch(schedule, 'i)"calibrated_refresh_timestamp"\s*:\s*([\d\.]+)', &m)
                GPOMerchSync.calibratedTs := Float(m[1])

            ; ── delays ───────────────────────────────────────────────────────
            if RegExMatch(delays, 'i)"afk_desktop_delay_ms"\s*:\s*(\d+)', &m)
                GPOMerchSync.afkDesktopDelayMs := Integer(m[1])
            if RegExMatch(delays, 'i)"roblox_wait_timeout_seconds"\s*:\s*(\d+)', &m)
                GPOMerchSync.robloxWaitTimeoutSecs := Integer(m[1])
            if RegExMatch(delays, 'i)"roblox_focus_delay_ms"\s*:\s*(\d+)', &m)
                GPOMerchSync.robloxFocusDelayMs := Integer(m[1])
            if RegExMatch(delays, 'i)"main_screen_click_interval_ms"\s*:\s*(\d+)', &m)
                GPOMerchSync.mainScreenClickIntervalMs := Integer(m[1])
            if RegExMatch(delays, 'i)"main_screen_post_delay_ms"\s*:\s*(\d+)', &m)
                GPOMerchSync.mainScreenPostDelayMs := Integer(m[1])
            if RegExMatch(delays, 'i)"ps_button_delay_ms"\s*:\s*(\d+)', &m)
                GPOMerchSync.psButtonDelayMs := Integer(m[1])
            if RegExMatch(delays, 'i)"ps_box_delay_ms"\s*:\s*(\d+)', &m)
                GPOMerchSync.psBoxDelayMs := Integer(m[1])
            if RegExMatch(delays, 'i)"paste_code_delay_ms"\s*:\s*(\d+)', &m)
                GPOMerchSync.pasteCodeDelayMs := Integer(m[1])
            if RegExMatch(delays, 'i)"enter_key_delay_ms"\s*:\s*(\d+)', &m)
                GPOMerchSync.enterKeyDelayMs := Integer(m[1])
            if RegExMatch(delays, 'i)"regular_button_delay_ms"\s*:\s*(\d+)', &m)
                GPOMerchSync.regularButtonDelayMs := Integer(m[1])

            ; ── assets_and_detection ─────────────────────────────────────────
            if RegExMatch(assets, 'i)"confidence"\s*:\s*([\d\.]+)', &m) {
                confVal := Float(m[1])
                GPOMerchSync.confidence := (confVal <= 1.0) ? Integer(confVal * 255) : Integer(confVal)
            }
            if RegExMatch(assets, 'i)"main_screen_image"\s*:\s*"([^"]+)"', &m)
                GPOMerchSync.mainScreenImage := m[1]
            if RegExMatch(assets, 'i)"alarm_beep_count"\s*:\s*(\d+)', &m)
                GPOMerchSync.alarmBeepCount := Integer(m[1])

            ; ── coords ───────────────────────────────────────────────────────
            if RegExMatch(coords, 'i)"initial_click"\s*:\s*\{\s*"x"\s*:\s*(\d+),\s*"y"\s*:\s*(\d+)', &m)
                GPOMerchSync.coordInitialClick := {x: Integer(m[1]), y: Integer(m[2])}
            if RegExMatch(coords, 'i)"ps_button"\s*:\s*\{\s*"x"\s*:\s*(\d+),\s*"y"\s*:\s*(\d+)', &m)
                GPOMerchSync.coordPsBtn := {x: Integer(m[1]), y: Integer(m[2])}
            if RegExMatch(coords, 'i)"ps_box"\s*:\s*\{\s*"x"\s*:\s*(\d+),\s*"y"\s*:\s*(\d+)', &m)
                GPOMerchSync.coordPsBox := {x: Integer(m[1]), y: Integer(m[2])}
            if RegExMatch(coords, 'i)"regular_button"\s*:\s*\{\s*"x"\s*:\s*(\d+),\s*"y"\s*:\s*(\d+)', &m)
                GPOMerchSync.coordRegBtn := {x: Integer(m[1]), y: Integer(m[2])}
            if RegExMatch(coords, 'i)"first_sea_button"\s*:\s*\{\s*"x"\s*:\s*(\d+),\s*"y"\s*:\s*(\d+)', &m)
                GPOMerchSync.coordSeaBtn := {x: Integer(m[1]), y: Integer(m[2])}
        }
    }

    static SaveConfig() {
        jsonStr := '{\n'
            . '  "_title": "GPO Merchant Sync & Auto-Join Configuration",\n'
            . '  "_version": "2.0.0",\n\n'
            . '  "server": {\n'
            . '    "_comment": "Roblox Server & Private Server Connection Settings",\n'
            . '    "gpo_ps_code": "' GPOMerchSync.psCode '",\n'
            . '    "roblox_place_id": "' GPOMerchSync.placeId '"\n'
            . '  },\n\n'
            . '  "desktops": {\n'
            . '    "_comment": "Windows Virtual Desktop Indices (1-based index)",\n'
            . '    "afk_desktop_index": ' GPOMerchSync.afkDesktop ',\n'
            . '    "home_desktop_index": ' GPOMerchSync.homeDesktop '\n'
            . '  },\n\n'
            . '  "schedule": {\n'
            . '    "_comment": "Stock Refresh & Merchant Spawn Schedule Settings (Seconds)",\n'
            . '    "stock_refresh_interval_seconds": ' GPOMerchSync.stockRefreshInterval ',\n'
            . '    "join_lead_seconds": ' GPOMerchSync.joinLeadSeconds ',\n'
            . '    "merchant_spawn_delay_seconds": ' GPOMerchSync.merchantSpawnDelay ',\n'
            . '    "merchant_alarm_lead_seconds": ' GPOMerchSync.alarmLead ',\n'
            . '    "afk_timeout_seconds": ' GPOMerchSync.afkTimeout ',\n'
            . '    "calibrated_refresh_timestamp": ' GPOMerchSync.calibratedTs '\n'
            . '  },\n\n'
            . '  "delays": {\n'
            . '    "_comment": "Workflow Step Micro-Delays & Timeouts",\n'
            . '    "afk_desktop_delay_ms": ' GPOMerchSync.afkDesktopDelayMs ',\n'
            . '    "roblox_wait_timeout_seconds": ' GPOMerchSync.robloxWaitTimeoutSecs ',\n'
            . '    "roblox_focus_delay_ms": ' GPOMerchSync.robloxFocusDelayMs ',\n'
            . '    "main_screen_click_interval_ms": ' GPOMerchSync.mainScreenClickIntervalMs ',\n'
            . '    "main_screen_post_delay_ms": ' GPOMerchSync.mainScreenPostDelayMs ',\n'
            . '    "ps_button_delay_ms": ' GPOMerchSync.psButtonDelayMs ',\n'
            . '    "ps_box_delay_ms": ' GPOMerchSync.psBoxDelayMs ',\n'
            . '    "paste_code_delay_ms": ' GPOMerchSync.pasteCodeDelayMs ',\n'
            . '    "enter_key_delay_ms": ' GPOMerchSync.enterKeyDelayMs ',\n'
            . '    "regular_button_delay_ms": ' GPOMerchSync.regularButtonDelayMs '\n'
            . '  },\n\n'
            . '  "assets_and_detection": {\n'
            . '    "_comment": "Image Recognition & Audio Alert Settings",\n'
            . '    "confidence": 0.7,\n'
            . '    "main_screen_image": "' GPOMerchSync.mainScreenImage '",\n'
            . '    "alarm_beep_count": ' GPOMerchSync.alarmBeepCount '\n'
            . '  },\n\n'
            . '  "coords": {\n'
            . '    "_comment": "Screen Click Coordinates (1920x1080 Screen Relative)",\n'
            . '    "initial_click": { "x": ' GPOMerchSync.coordInitialClick.x ', "y": ' GPOMerchSync.coordInitialClick.y ' },\n'
            . '    "ps_button": { "x": ' GPOMerchSync.coordPsBtn.x ', "y": ' GPOMerchSync.coordPsBtn.y ' },\n'
            . '    "ps_box": { "x": ' GPOMerchSync.coordPsBox.x ', "y": ' GPOMerchSync.coordPsBox.y ' },\n'
            . '    "regular_button": { "x": ' GPOMerchSync.coordRegBtn.x ', "y": ' GPOMerchSync.coordRegBtn.y ' },\n'
            . '    "first_sea_button": { "x": ' GPOMerchSync.coordSeaBtn.x ', "y": ' GPOMerchSync.coordSeaBtn.y ' }\n'
            . '  }\n'
            . '}\n'

        if FileExist(GPOMerchSync.CONFIG_PATH)
            FileDelete GPOMerchSync.CONFIG_PATH
        FileAppend jsonStr, GPOMerchSync.CONFIG_PATH
    }
}

; ═══════════════════════════════════════════════════════════════════════════
; SLOT CONTROL & GLOBAL CYCLE HOTKEYS
; ═══════════════════════════════════════════════════════════════════════════

; Slot 4 Control: Numpad4 + Plus to calibrate stock refresh timestamp
Numpad4 & NumpadAdd::
NumpadLeft & NumpadAdd::
{
    GPOMerchSync.CalibrateTimestamp()
}

; Slot 4 Control: Numpad4 + Minus to toggle looper on/off
Numpad4 & NumpadSub::
NumpadLeft & NumpadSub::
{
    GPOMerchSync.Toggle()
}

; Active Cycle Hotkeys
#HotIf GPOMerchSync.running
F8::
{
    GPOMerchSync.FinishCycle()
}

F6::
{
    GPOMerchSync.EmergencyStop()
}
#HotIf
