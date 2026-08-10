#Requires AutoHotkey v2.0

; ═══════════════════════════════════════════════════════════════════════════
; GPO DIRECT JOIN TEST MODULE (SLOT 5)
; ─────────────────────────────────────────────────────────────────────────
; Triggers the server join workflow IMMEDIATELY without waiting for
; scheduled stock refresh timers. Use to test button clicks & desktop switch.
; ═══════════════════════════════════════════════════════════════════════════
class GPOTestJoin {
    ; ── Settings ────────────────────────────────────────────────────────────
    static PROCESS         := "RobloxPlayerBeta.exe"

    static SCRIPT_DIR {
        get {
            SplitPath A_LineFile, , &dir
            return dir
        }
    }
    static CONFIG_PATH => GPOTestJoin.SCRIPT_DIR "\config.json"
    static ASSET_DIR   => GPOTestJoin.SCRIPT_DIR "\img\"

    ; ── State ───────────────────────────────────────────────────────────────
    static running         := false
    static lastToggle      := 0

    ; Defaults from config.json
    static psCode          := "Jk2JKTAKCf"
    static placeId         := "1730877806"
    static afkDesktop      := 3
    static confidence      := 50

    static coordPsBtn      := {x: 1650, y: 714}
    static coordPsBox      := {x: 962, y: 695}
    static coordRegBtn     := {x: 752, y: 581}
    static coordSeaBtn     := {x: 815, y: 589}

    ; ── Called by router (Slot 5) ───────────────────────────────────────────
    static Toggle() {
        now := A_TickCount
        if (now - GPOTestJoin.lastToggle < 500)
            return
        GPOTestJoin.lastToggle := now

        GPOTestJoin.running := !GPOTestJoin.running
        if GPOTestJoin.running {
            GPOTestJoin.LoadConfig()
            SetTimer ObjBindMethod(GPOTestJoin, "_StartWorkflowAsync"), -10
        } else {
            SetTimer ObjBindMethod(GPOTestJoin, "_StartWorkflowAsync"), 0
        }
    }

    static Stop() {
        if GPOTestJoin.running {
            GPOTestJoin.running := false
            SetTimer ObjBindMethod(GPOTestJoin, "_StartWorkflowAsync"), 0
        }
    }

    ; ── Async Workflow Launcher ─────────────────────────────────────────────
    static _StartWorkflowAsync() {
        if (!GPOTestJoin.running)
            return
        GPOTestJoin.RunJoinWorkflow()
    }

    ; ── Direct Join Workflow ────────────────────────────────────────────────
    static RunJoinWorkflow() {
        CoordMode "Pixel", "Screen"
        CoordMode "Mouse", "Screen"

        ; Ensure any existing/stuck Roblox process is closed for a clean launch
        GPOTestJoin.ForceKillRoblox()

        ; Switch to AFK Desktop
        if (!GPOTestJoin.running)
            return
        GPOTestJoin.SwitchDesktop(GPOTestJoin.afkDesktop)
        if (!GPOTestJoin._SleepIfRunning(500))
            return

        ; Launch Roblox GPO
        if (!GPOTestJoin.running)
            return
        Run "roblox://placeId=" GPOTestJoin.placeId

        ; Wait up to 20s for Roblox window to exist & focus/maximize it
        if (!GPOTestJoin._WaitForRoblox(20))
            return
        if (!GPOTestJoin._SleepIfRunning(1000))
            return

        ; Constantly click (1886, 1050) until main_screen.png appears (no timeout)
        if (!GPOTestJoin.running)
            return

        while (GPOTestJoin.running) {
            foundX := 0, foundY := 0
            if GPOTestJoin._FindImageOrSleep("main_screen.png", 200, &foundX, &foundY) {
                break
            }

            GPOTestJoin._ClickRoblox(1886, 1050)

            if (!GPOTestJoin._SleepIfRunning(400))
                return
        }

        if (!GPOTestJoin.running)
            return

        if (!GPOTestJoin._SleepIfRunning(1000))
            return

        ; Main Menu PS Button
        if (!GPOTestJoin.running)
            return
        GPOTestJoin._ClickRoblox(GPOTestJoin.coordPsBtn.x, GPOTestJoin.coordPsBtn.y)
        if (!GPOTestJoin._SleepIfRunning(1500))
            return

        ; PS Code Box
        if (!GPOTestJoin.running)
            return
        GPOTestJoin._ClickRoblox(GPOTestJoin.coordPsBox.x, GPOTestJoin.coordPsBox.y)
        if (!GPOTestJoin._SleepIfRunning(500))
            return

        ; Paste PS Code & Enter
        if (!GPOTestJoin.running)
            return
        A_Clipboard := GPOTestJoin.psCode
        ClipWait 1
        if (!GPOTestJoin.running)
            return
        Send "^v"
        if (!GPOTestJoin._SleepIfRunning(300))
            return
        Send "{Enter}"
        if (!GPOTestJoin._SleepIfRunning(2500))
            return

        ; Regular Button
        if (!GPOTestJoin.running)
            return
        GPOTestJoin._ClickRoblox(GPOTestJoin.coordRegBtn.x, GPOTestJoin.coordRegBtn.y)
        if (!GPOTestJoin._SleepIfRunning(2000))
            return

        ; First Sea Button
        if (!GPOTestJoin.running)
            return
        GPOTestJoin._ClickRoblox(GPOTestJoin.coordSeaBtn.x, GPOTestJoin.coordSeaBtn.y)

        if (GPOTestJoin.running) {
            GPOTestJoin.running := false
        }
    }

    ; ── Helper Utilities ────────────────────────────────────────────────────
    static _SleepIfRunning(ms) {
        elapsed := 0
        while (elapsed < ms) {
            if (!GPOTestJoin.running)
                return false
            step := Min(50, ms - elapsed)
            Sleep step
            elapsed += step
        }
        return GPOTestJoin.running
    }

    static _FindImageOrSleep(imageName, timeoutMs, &foundX := 0, &foundY := 0) {
        imgPath := GPOTestJoin.ASSET_DIR imageName
        if !FileExist(imgPath)
            return false

        CoordMode "Pixel", "Screen"
        startTick := A_TickCount
        while (GPOTestJoin.running && (A_TickCount - startTick < timeoutMs)) {
            try {
                if ImageSearch(&foundX, &foundY, 0, 0, A_ScreenWidth, A_ScreenHeight, "*" GPOTestJoin.confidence " " imgPath) {
                    return true
                }
            } catch {
                ; Ignore search errors during transition
            }
            if (!GPOTestJoin._SleepIfRunning(150))
                return false
        }
        return false
    }

    static _WaitForRoblox(timeoutSecs := 20) {
        startTick := A_TickCount
        while (GPOTestJoin.running && (A_TickCount - startTick < timeoutSecs * 1000)) {
            if WinExist("ahk_exe " GPOTestJoin.PROCESS) {
                try {
                    WinActivate "ahk_exe " GPOTestJoin.PROCESS
                    WinMaximize "ahk_exe " GPOTestJoin.PROCESS
                    return true
                } catch {
                    ; Handle temporary activation glitches during launcher/splash window transitions
                }
            }
            if (!GPOTestJoin._SleepIfRunning(500))
                return false
        }
        return false
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
        if ProcessExist(GPOTestJoin.PROCESS) {
            try ProcessClose(GPOTestJoin.PROCESS)
            Sleep 500
        }
    }

    static _ClickRoblox(x, y, radius := 5) {
        CoordMode "Mouse", "Screen"
        if !WinActive("ahk_exe " GPOTestJoin.PROCESS) {
            try WinActivate "ahk_exe " GPOTestJoin.PROCESS
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

    static LoadConfig() {
        if !FileExist(GPOTestJoin.CONFIG_PATH)
            return

        try {
            content := FileRead(GPOTestJoin.CONFIG_PATH)

            if RegExMatch(content, 'i)"gpo_ps_code"\s*:\s*"([^"]+)"', &m)
                GPOTestJoin.psCode := m[1]
            if RegExMatch(content, 'i)"roblox_place_id"\s*:\s*"([^"]+)"', &m)
                GPOTestJoin.placeId := m[1]
            if RegExMatch(content, 'i)"afk_desktop_index"\s*:\s*(\d+)', &m)
                GPOTestJoin.afkDesktop := Integer(m[1])
            if RegExMatch(content, 'i)"confidence"\s*:\s*([\d\.]+)', &m) {
                confVal := Float(m[1])
                GPOTestJoin.confidence := (confVal <= 1.0) ? Integer(confVal * 255) : Integer(confVal)
            }

            if RegExMatch(content, 'i)"ps_button"\s*:\s*\{\s*"x"\s*:\s*(\d+),\s*"y"\s*:\s*(\d+)', &m)
                GPOTestJoin.coordPsBtn := {x: Integer(m[1]), y: Integer(m[2])}
            if RegExMatch(content, 'i)"ps_box"\s*:\s*\{\s*"x"\s*:\s*(\d+),\s*"y"\s*:\s*(\d+)', &m)
                GPOTestJoin.coordPsBox := {x: Integer(m[1]), y: Integer(m[2])}
            if RegExMatch(content, 'i)"regular_button"\s*:\s*\{\s*"x"\s*:\s*(\d+),\s*"y"\s*:\s*(\d+)', &m)
                GPOTestJoin.coordRegBtn := {x: Integer(m[1]), y: Integer(m[2])}
            if RegExMatch(content, 'i)"first_sea_button"\s*:\s*\{\s*"x"\s*:\s*(\d+),\s*"y"\s*:\s*(\d+)', &m)
                GPOTestJoin.coordSeaBtn := {x: Integer(m[1]), y: Integer(m[2])}
        }
    }
}

; ═══════════════════════════════════════════════════════════════════════════
; SLOT 6 CONTROL HOTKEYS
; ═══════════════════════════════════════════════════════════════════════════

Numpad6 & NumpadSub::
NumpadRight & NumpadSub::
{
    GPOTestJoin.Toggle()
}
