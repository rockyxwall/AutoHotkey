#Requires AutoHotkey v2.0

; ═══════════════════════════════════════════════════════════════════════════
; GPO MERCH SYNC
; ─────────────────────────────────────────────────────────────────────────
; Automates GPO private server joining on Virtual Desktop #3 before stock
; refresh (T-13m30s), alerts on Merchant spawn (Server Uptime 10:00),
; and manages stock checking lifecycle.
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
    static psCode          := "Jk2JKTAKCf"
    static placeId         := "1730877806"
    static afkDesktop      := 3
    static alarmLead       := 15
    static afkTimeout      := 300
    static calibratedTs    := 0
    static confidence      := 50

    ; Coordinate map
    static coordPsBtn      := {x: 1650, y: 714}
    static coordPsBox      := {x: 962, y: 695}
    static coordRegBtn     := {x: 752, y: 581}
    static coordSeaBtn     := {x: 815, y: 589}

    ; ── Called by router ────────────────────────────────────────────────────
    static Toggle() {
        GPOMerchSync.running := !GPOMerchSync.running
        if GPOMerchSync.running {
            GPOMerchSync.LoadConfig()
            SetTimer ObjBindMethod(GPOMerchSync, "_Loop"), 1000
            TrayTip "GPO Merch Sync Active", "Monitoring stock refresh schedule...", 1
        } else {
            SetTimer ObjBindMethod(GPOMerchSync, "_Loop"), 0
            GPOMerchSync.inCycle := false
            TrayTip "GPO Merch Sync Stopped", "Looper disabled.", 1
        }
    }

    ; ── Hotkey Calibration Entry Point ───────────────────────────────────────
    static CalibrateTimestamp() {
        ib := InputBox("Enter remaining time until Global Refresh (e.g. '14:30' or '15'):", "GPO Merchant Sync Calibration", "w350 h130")
        if (ib.Result != "OK" || ib.Value == "")
            return

        mins := 0
        secs := 0
        if InStr(ib.Value, ":") {
            parts := StrSplit(ib.Value, ":")
            mins := Integer(parts[1])
            secs := Integer(parts[2])
        } else {
            mins := Integer(ib.Value)
        }

        totalSecs := (mins * 60) + secs
        nowUnix := GPOMerchSync._GetUnixTime()
        GPOMerchSync.calibratedTs := nowUnix + totalSecs
        GPOMerchSync.SaveConfig()

        TrayTip "Calibration Saved", "Next Refresh set in " mins "m " secs "s.", 1
    }

    ; ── Cycle Lifecycle Control ─────────────────────────────────────────────
    static FinishCycle() {
        GPOMerchSync.inCycle := false
        GPOMerchSync.ForceKillRoblox()
        GPOMerchSync.SwitchDesktop(1)
        TrayTip "Cycle Finished", "Roblox closed. Returned to Desktop 1.", 1
    }

    static EmergencyStop() {
        GPOMerchSync.running := false
        GPOMerchSync.inCycle := false
        SetTimer ObjBindMethod(GPOMerchSync, "_Loop"), 0
        GPOMerchSync.ForceKillRoblox()
        GPOMerchSync.SwitchDesktop(1)
        TrayTip "EMERGENCY STOP", "GPO Merch Sync force stopped.", 1
    }

    ; ── Internal Loop ───────────────────────────────────────────────────────
    static _Loop() {
        if !GPOMerchSync.running
            return

        nowUnix := GPOMerchSync._GetUnixTime()

        ; Determine next refresh target
        if (GPOMerchSync.calibratedTs > nowUnix) {
            GPOMerchSync.targetRefresh := GPOMerchSync.calibratedTs
        } else {
            ; Auto top-of-hour alignment (every 30 mins)
            rem := Mod(nowUnix, 1800)
            GPOMerchSync.targetRefresh := nowUnix + (1800 - rem)
        }

        ; Launch 13m 30s (810s) before stock refresh
        joinTrigger := GPOMerchSync.targetRefresh - 810

        if (nowUnix >= joinTrigger && !GPOMerchSync.inCycle) {
            GPOMerchSync.inCycle := true
            GPOMerchSync._RunJoinWorkflow()
        }
    }

    ; ── Join Workflow ────────────────────────────────────────────────────────
    static _RunJoinWorkflow() {
        ; Switch to AFK Desktop
        GPOMerchSync.SwitchDesktop(GPOMerchSync.afkDesktop)
        Sleep 500

        ; Launch Roblox GPO
        Run "roblox://placeId=" GPOMerchSync.placeId

        ; Wait up to 20s for Roblox window to exist & focus/maximize it
        if (!GPOMerchSync._WaitForRoblox(20))
            return
        Sleep 1000

        ; Constantly click (1886, 1050) until main_screen.png appears (no timeout)
        TrayTip "Clicking (1886, 1050) until main_screen.png appears...", "GPO Sync", 1

        while (GPOMerchSync.running) {
            foundX := 0, foundY := 0
            if GPOMerchSync._FindImageOrSleep("main_screen.png", 200, &foundX, &foundY) {
                break
            }

            GPOMerchSync._ClickRoblox(1886, 1050)
            Sleep 400
        }

        if (!GPOMerchSync.running)
            return

        TrayTip "GPO Sync", "main_screen.png detected! Proceeding to main menu...", 1
        Sleep 1000

        ; Main Menu PS Button
        TrayTip "GPO Sync", "Clicking PS Button (" GPOMerchSync.coordPsBtn.x ", " GPOMerchSync.coordPsBtn.y ")...", 1
        GPOMerchSync._ClickRoblox(GPOMerchSync.coordPsBtn.x, GPOMerchSync.coordPsBtn.y)
        Sleep 1500

        ; PS Code Box
        TrayTip "GPO Sync", "Clicking PS Code Box (" GPOMerchSync.coordPsBox.x ", " GPOMerchSync.coordPsBox.y ")...", 1
        GPOMerchSync._ClickRoblox(GPOMerchSync.coordPsBox.x, GPOMerchSync.coordPsBox.y)
        Sleep 500

        ; Paste PS Code & Enter
        A_Clipboard := GPOMerchSync.psCode
        ClipWait 1
        Send "^v"
        Sleep 300
        Send "{Enter}"
        Sleep 2500

        ; Regular Button
        TrayTip "GPO Sync", "Clicking Regular Button (" GPOMerchSync.coordRegBtn.x ", " GPOMerchSync.coordRegBtn.y ")...", 1
        GPOMerchSync._ClickRoblox(GPOMerchSync.coordRegBtn.x, GPOMerchSync.coordRegBtn.y)
        Sleep 2000

        ; First Sea Button
        TrayTip "GPO Sync", "Clicking First Sea Button (" GPOMerchSync.coordSeaBtn.x ", " GPOMerchSync.coordSeaBtn.y ")...", 1
        GPOMerchSync._ClickRoblox(GPOMerchSync.coordSeaBtn.x, GPOMerchSync.coordSeaBtn.y)

        ; Return to Desktop 1 until Merchant spawn
        GPOMerchSync.SwitchDesktop(1)

        ; Schedule Alarm 3m 15s after join (Server Uptime ~9:45)
        leadDelayMs := max(1000, ((210 - GPOMerchSync.alarmLead) * 1000))
        SetTimer ObjBindMethod(GPOMerchSync, "_PlayAlarmCallback"), -leadDelayMs
    }

    static _PlayAlarmCallback() {
        if !GPOMerchSync.running
            return

        ; Beep notification
        Loop 4 {
            SoundBeep 1000, 300
            Sleep 100
            SoundBeep 1400, 300
            Sleep 100
        }

        TrayTip "🔔 GPO Merchant Active!", "Merchant spawned! Check Stock #1. Stock #2 in 3 mins.", 1
        GPOMerchSync.SwitchDesktop(GPOMerchSync.afkDesktop)
    }

    ; ── Helper Utilities ────────────────────────────────────────────────────
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
            TrayTip "GPO Merch Sync", "Detected & clicked image: " imageName, 1
            return true
        }

        ; 2. Fallback to static coordinates if image search timed out or file missing
        if (coordObj && coordObj.HasOwnProp("x") && coordObj.HasOwnProp("y") && coordObj.x > 0 && coordObj.y > 0) {
            if !GPOMerchSync.running
                return false
            MouseMove coordObj.x, coordObj.y
            Sleep 150
            Click coordObj.x, coordObj.y
            TrayTip "GPO Merch Sync Warning", "Image '" imageName "' not found. Used fallback coords: (" coordObj.x ", " coordObj.y ")", 1
            return true
        }

        TrayTip "GPO Merch Sync Error", "Failed to find image '" imageName "' or valid fallback coords.", 2
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
            Sleep 200
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
            Sleep 500
        }
        return false
    }

    static _ClickRoblox(x, y) {
        CoordMode "Mouse", "Screen"
        if !WinActive("ahk_exe " GPOMerchSync.PROCESS) {
            try WinActivate "ahk_exe " GPOMerchSync.PROCESS
            Sleep 100
        }

        ; Jiggle mouse slightly (x-2, y-2 then x, y) to force Roblox WM_MOUSEMOVE hover event
        MouseMove x - 2, y - 2
        Sleep 30
        MouseMove x, y
        Sleep 50

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
    }

    static ForceKillRoblox() {
        if ProcessExist(GPOMerchSync.PROCESS) {
            try ProcessClose(GPOMerchSync.PROCESS)
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

            if RegExMatch(content, 'i)"gpo_ps_code"\s*:\s*"([^"]+)"', &m)
                GPOMerchSync.psCode := m[1]
            if RegExMatch(content, 'i)"roblox_place_id"\s*:\s*"([^"]+)"', &m)
                GPOMerchSync.placeId := m[1]
            if RegExMatch(content, 'i)"afk_desktop_index"\s*:\s*(\d+)', &m)
                GPOMerchSync.afkDesktop := Integer(m[1])
            if RegExMatch(content, 'i)"merchant_alarm_lead_seconds"\s*:\s*(\d+)', &m)
                GPOMerchSync.alarmLead := Integer(m[1])
            if RegExMatch(content, 'i)"afk_timeout_seconds"\s*:\s*(\d+)', &m)
                GPOMerchSync.afkTimeout := Integer(m[1])
            if RegExMatch(content, 'i)"calibrated_refresh_timestamp"\s*:\s*([\d\.]+)', &m)
                GPOMerchSync.calibratedTs := Float(m[1])

            if RegExMatch(content, 'i)"ps_button"\s*:\s*\{\s*"x"\s*:\s*(\d+),\s*"y"\s*:\s*(\d+)', &m)
                GPOMerchSync.coordPsBtn := {x: Integer(m[1]), y: Integer(m[2])}
            if RegExMatch(content, 'i)"ps_box"\s*:\s*\{\s*"x"\s*:\s*(\d+),\s*"y"\s*:\s*(\d+)', &m)
                GPOMerchSync.coordPsBox := {x: Integer(m[1]), y: Integer(m[2])}
            if RegExMatch(content, 'i)"regular_button"\s*:\s*\{\s*"x"\s*:\s*(\d+),\s*"y"\s*:\s*(\d+)', &m)
                GPOMerchSync.coordRegBtn := {x: Integer(m[1]), y: Integer(m[2])}
            if RegExMatch(content, 'i)"first_sea_button"\s*:\s*\{\s*"x"\s*:\s*(\d+),\s*"y"\s*:\s*(\d+)', &m)
                GPOMerchSync.coordSeaBtn := {x: Integer(m[1]), y: Integer(m[2])}
        }
    }

    static SaveConfig() {
        jsonStr := '{\n'
            . '  "gpo_ps_code": "' GPOMerchSync.psCode '",\n'
            . '  "roblox_place_id": "' GPOMerchSync.placeId '",\n'
            . '  "afk_desktop_index": ' GPOMerchSync.afkDesktop ',\n'
            . '  "confidence": 0.7,\n'
            . '  "menu_timeout_seconds": 90,\n'
            . '  "merchant_alarm_lead_seconds": ' GPOMerchSync.alarmLead ',\n'
            . '  "afk_timeout_seconds": ' GPOMerchSync.afkTimeout ',\n'
            . '  "calibrated_refresh_timestamp": ' GPOMerchSync.calibratedTs ',\n'
            . '  "coords": {\n'
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
