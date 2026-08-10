#Requires AutoHotkey v2.0

; ═══════════════════════════════════════════════════════════════════════════
; GPO REFRESH HUD & CALIBRATOR MODULE
; ─────────────────────────────────────────────────────────────────────────
; Live countdown HUD overlay for GPO stock refresh schedule & interactive
; timestamp calibration saved directly to config.json.
; ═══════════════════════════════════════════════════════════════════════════
class GPORefreshHUD {
    ; ── Settings ────────────────────────────────────────────────────────────
    static SCRIPT_DIR {
        get {
            SplitPath A_LineFile, , &dir
            return dir
        }
    }
    static CONFIG_PATH => GPORefreshHUD.SCRIPT_DIR "\config.json"

    ; ── State ───────────────────────────────────────────────────────────────
    static running         := false
    static calibratedTs    := 0
    static hudGui          := ""
    static hudTxt          := ""
    static lastToggle      := 0

    ; ── Called to toggle HUD overlay ────────────────────────────────────────
    static Toggle() {
        now := A_TickCount
        if (now - GPORefreshHUD.lastToggle < 500)
            return
        GPORefreshHUD.lastToggle := now

        GPORefreshHUD.running := !GPORefreshHUD.running
        if GPORefreshHUD.running {
            GPORefreshHUD.LoadConfig()
            SetTimer ObjBindMethod(GPORefreshHUD, "_UpdateLoop"), 1000
            GPORefreshHUD._UpdateLoop()
        } else {
            SetTimer ObjBindMethod(GPORefreshHUD, "_UpdateLoop"), 0
            GPORefreshHUD.HideHUD()
        }
    }

    ; ── Interactive Calibration Entry Point ─────────────────────────────────
    static Calibrate() {
        ib := InputBox("Look at the GPO in-game timer and enter remaining time until refresh`n(e.g. '14:30' or '15'):", "GPO Refresh Calibration", "w380 h150")
        if (ib.Result != "OK" || ib.Value == "")
            return

        mins := 0
        secs := 0
        val := Trim(ib.Value)
        if InStr(val, ":") {
            parts := StrSplit(val, ":")
            mins := Integer(parts[1])
            secs := Integer(parts[2])
        } else {
            valFloat := Float(val)
            mins := Floor(valFloat)
            secs := Round((valFloat - mins) * 60)
        }

        totalSecs := (mins * 60) + secs
        nowUnix := GPORefreshHUD._GetUnixTime()
        GPORefreshHUD.calibratedTs := nowUnix + totalSecs
        GPORefreshHUD.SaveConfig()

        if (!GPORefreshHUD.running) {
            GPORefreshHUD.Toggle()
        } else {
            GPORefreshHUD._UpdateLoop()
        }
    }

    ; ── Live HUD Update Loop ────────────────────────────────────────────────
    static _UpdateLoop() {
        if (!GPORefreshHUD.running)
            return

        nowUnix := GPORefreshHUD._GetUnixTime()

        if (GPORefreshHUD.calibratedTs <= 0) {
            GPORefreshHUD.ShowHUD("Next Refresh: Uncalibrated")
            return
        }

        ; Calculate next refresh target (GPO refreshes recur every 30 mins / 1800s)
        diff := GPORefreshHUD.calibratedTs - nowUnix
        if (diff <= 0) {
            cyclesPassed := Floor(Abs(diff) / 1800) + 1
            targetTs := GPORefreshHUD.calibratedTs + (cyclesPassed * 1800)
            remSecs := targetTs - nowUnix
        } else {
            remSecs := diff
        }

        remMins := Floor(remSecs / 60)
        remSecsMod := Mod(remSecs, 60)
        formattedTime := Format("{:02d}:{:02d}", remMins, remSecsMod)

        GPORefreshHUD.ShowHUD("Next Refresh: " formattedTime)
    }

    ; ── Clickthrough Live HUD Overlay (Screen 0, 1079) ──────────────────────
    static ShowHUD(text) {
        if (!GPORefreshHUD.hudGui) {
            ; +AlwaysOnTop: stay visible over game
            ; -Caption: no title bar
            ; +ToolWindow: hide taskbar icon
            ; +E0x20: WS_EX_TRANSPARENT makes GUI 100% clickthrough
            GPORefreshHUD.hudGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
            GPORefreshHUD.hudGui.BackColor := "0d0d11"
            GPORefreshHUD.hudGui.SetFont("s10 c0x00FF88 Bold", "Segoe UI")
            GPORefreshHUD.hudTxt := GPORefreshHUD.hudGui.Add("Text", "w250 h24 Left", text)
            WinSetTransColor "0d0d11 220", GPORefreshHUD.hudGui
        } else {
            GPORefreshHUD.hudTxt.Value := text
        }
        ; Position HUD overlay at Screen (0, 1079) without stealing focus
        GPORefreshHUD.hudGui.Show("x0 y1055 NoActivate")
    }

    static HideHUD() {
        if (GPORefreshHUD.hudGui) {
            GPORefreshHUD.hudGui.Hide()
        }
    }

    static _GetUnixTime() {
        return DateDiff(A_NowUTC, "19700101000000", "Seconds")
    }

    ; ── Load / Save Config ──────────────────────────────────────────────────
    static LoadConfig() {
        if !FileExist(GPORefreshHUD.CONFIG_PATH)
            return

        try {
            content := FileRead(GPORefreshHUD.CONFIG_PATH)
            if RegExMatch(content, 'i)"calibrated_refresh_timestamp"\s*:\s*([\d\.]+)', &m)
                GPORefreshHUD.calibratedTs := Float(m[1])
        }
    }

    static SaveConfig() {
        if !FileExist(GPORefreshHUD.CONFIG_PATH)
            return

        try {
            content := FileRead(GPORefreshHUD.CONFIG_PATH)
            if RegExMatch(content, 'i)"calibrated_refresh_timestamp"\s*:\s*[\d\.]+') {
                newContent := RegExReplace(content, 'i)"calibrated_refresh_timestamp"\s*:\s*[\d\.]+', '"calibrated_refresh_timestamp": ' GPORefreshHUD.calibratedTs)
                FileDelete GPORefreshHUD.CONFIG_PATH
                FileAppend newContent, GPORefreshHUD.CONFIG_PATH
            }
        }
    }
}

; ═══════════════════════════════════════════════════════════════════════════
; HOTKEYS FOR REFRESH HUD & CALIBRATION
; ═══════════════════════════════════════════════════════════════════════════

; Numpad6 + Plus to open calibration prompt
Numpad6 & NumpadAdd::
NumpadRight & NumpadAdd::
{
    GPORefreshHUD.Calibrate()
}

; Numpad6 + Minus to toggle live HUD overlay on/off
Numpad6 & NumpadSub::
NumpadRight & NumpadSub::
{
    GPORefreshHUD.Toggle()
}
