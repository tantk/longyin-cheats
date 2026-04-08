# Crash Recovery Script for LongYinLiZhiZhuan + Cheat Engine
# Detects crash → Relaunches game → CE with autoload → Beep when ready
# Manual: Click Connect in Multi-Tool

param(
    [string]$GameProcess = "LongYinLiZhiZhuan",
    [string]$SteamAppID = "3202030",
    [string]$CEPath = "C:\Program Files\Cheat Engine\cheatengine-x86_64.exe",
    [string]$CTPath = "C:\dev\longyin-cheats\dist\LongYinLiZhiZhuan.CT"
)

$ErrorActionPreference = "Continue"
$LogFile = "C:\dev\longyin-cheats\tools\crash_recovery.log"
$StatusFile = "C:\dev\longyin-cheats\tools\.game_status"
$AutoloadSrc = "C:\dev\longyin-cheats\tools\autoload_save.lua"
$AutoloadDest = "C:\Program Files\Cheat Engine\autorun\autoload_save.lua"

function Set-GameStatus($status) {
    Set-Content -Path $StatusFile -Value $status -NoNewline
}

function Install-AutoLoad {
    Copy-Item $AutoloadSrc $AutoloadDest -Force
    Write-Status "Autoload installed to CE autorun"
}

function Remove-AutoLoad {
    if (Test-Path $AutoloadDest) {
        Remove-Item $AutoloadDest -Force
        Write-Status "Autoload removed from CE autorun"
    }
}

# Clean up autoload on Ctrl+C
Register-EngineEvent PowerShell.Exiting -Action {
    if (Test-Path $AutoloadDest) { Remove-Item $AutoloadDest -Force }
}
# Also handle Ctrl+C via trap
trap {
    Remove-AutoLoad
    exit 0
}

function Write-Log($msg, $level = "INFO") {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$level] $msg"
    Add-Content -Path $LogFile -Value $line
    return $line
}
function Write-Status($msg) { Write-Host (Write-Log $msg "INFO") -ForegroundColor Cyan }
function Write-Alert($msg) { Write-Host (Write-Log $msg "ALERT") -ForegroundColor Yellow }

function Beep-Ready {
    [Console]::Beep(800, 200); [Console]::Beep(1000, 200); [Console]::Beep(1200, 300)
}

function Stop-CE {
    $ce = Get-Process -Name "cheatengine*" -ErrorAction SilentlyContinue
    if ($ce) {
        Write-Status "Killing CE..."
        $ce | Stop-Process -Force
        # Poll until dead (no hardcoded sleep)
        for ($i = 0; $i -lt 20; $i++) {
            if (-not (Get-Process -Name "cheatengine*" -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Milliseconds 250
        }
    }
}

function Wait-ForGame {
    Write-Status "Waiting for game process..."
    for ($i = 0; $i -lt 60; $i++) {
        $proc = Get-Process -Name $GameProcess -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Status "Game process found (PID: $($proc.Id))"
            return $true
        }
        Start-Sleep -Seconds 1
    }
    Write-Alert "Game did not start within 60s"
    return $false
}

function Wait-ForGameWindow {
    # Poll until game window has a title (= past splash screen, at main menu)
    # Also spam Escape to skip intro/splash
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class KeySender {
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

        [StructLayout(LayoutKind.Sequential)]
        public struct INPUT {
            public uint type;
            public INPUTUNION u;
        }
        [StructLayout(LayoutKind.Explicit)]
        public struct INPUTUNION {
            [FieldOffset(0)] public KEYBDINPUT ki;
        }
        [StructLayout(LayoutKind.Sequential)]
        public struct KEYBDINPUT {
            public ushort wVk;
            public ushort wScan;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        public static void SendEscape(IntPtr hWnd) {
            SetForegroundWindow(hWnd);
            INPUT[] inputs = new INPUT[2];
            // Key down - scan code 0x01 = Escape
            inputs[0].type = 1;
            inputs[0].u.ki.wVk = 0x1B;
            inputs[0].u.ki.wScan = 0x01;
            inputs[0].u.ki.dwFlags = 0x0008; // KEYEVENTF_SCANCODE
            // Key up
            inputs[1].type = 1;
            inputs[1].u.ki.wVk = 0x1B;
            inputs[1].u.ki.wScan = 0x01;
            inputs[1].u.ki.dwFlags = 0x0008 | 0x0002; // SCANCODE | KEYUP
            SendInput(2, inputs, System.Runtime.InteropServices.Marshal.SizeOf(typeof(INPUT)));
        }
    }
"@

    Write-Status "Waiting for main menu..."
    $windowReady = $false
    for ($i = 0; $i -lt 60; $i++) {
        $proc = Get-Process -Name $GameProcess -ErrorAction SilentlyContinue
        if ($proc) {
            $hwnd = $proc.MainWindowHandle
            if ($hwnd -ne [IntPtr]::Zero) {
                # Spam Escape to skip intro movie
                [KeySender]::SendEscape($hwnd)
            }
            if (-not $windowReady -and $proc.MainWindowTitle -ne "") {
                $windowReady = $true
                Write-Status "Window detected (${i}s) - sending Escape for 5 more seconds..."
            }
            if ($windowReady -and $i -ge 5) {
                Write-Status "Main menu ready"
                return $true
            }
        }
        Start-Sleep -Seconds 1
    }
    Write-Alert "Window not ready after 60s"
    return $false
}

function Setup-AutoLoad { Install-AutoLoad }

function Cleanup-AutoLoad {
    Remove-AutoLoad
}

function Wait-ForSaveLoaded {
    $marker = "C:\dev\longyin-cheats\tools\.autoload_done"
    Write-Status "Waiting for save to load..."
    for ($i = 0; $i -lt 60; $i++) {
        # Check if game crashed during load
        if (-not (Get-Process -Name $GameProcess -ErrorAction SilentlyContinue)) {
            Write-Alert "Game crashed during autoload!"
            if (Test-Path $marker) { Remove-Item $marker -Force }
            return $false
        }
        if (Test-Path $marker) {
            Remove-Item $marker -Force
            Write-Status "Save loaded! (marker found)"
            return $true
        }
        Start-Sleep -Seconds 1
    }
    Write-Status "Autoload wait timed out (60s)"
    return $false
}

function Do-Recovery {
    Stop-CE

    Write-Status "Launching game via Steam..."
    Start-Process "steam://rungameid/$SteamAppID"

    if (-not (Wait-ForGame)) { return }

    # Copy autoload script FIRST, then launch CE
    # CE runs autorun/*.lua on startup — script must be there before CE starts
    Setup-AutoLoad
    Start-Sleep -Milliseconds 500
    Write-Status "Launching CE with CT (parallel with game startup)..."
    Start-Process -FilePath $CEPath -ArgumentList "`"$CTPath`""

    # Wait for autoload to complete (Lua script writes marker file when done)
    if (-not (Wait-ForSaveLoaded)) {
        Write-Alert "Save load failed - will retry on next crash detection"
        Cleanup-AutoLoad
        return
    }
    Cleanup-AutoLoad

    Beep-Ready
    Write-Alert ">>> READY: Click Connect in Multi-Tool <<<"
}

# ============================================================
# Main
# ============================================================

Write-Host ""
Write-Host "=== LongYinLiZhiZhuan Crash Recovery ===" -ForegroundColor Green
Write-Host "Log: $LogFile" -ForegroundColor Green
Write-Host "Ctrl+C to stop" -ForegroundColor Green
Write-Host ""
Write-Log "=== Monitor started ===" "START"

# Clean up stale autoload from previous interrupted session
Remove-AutoLoad

$gameProc = Get-Process -Name $GameProcess -ErrorAction SilentlyContinue
if (-not $gameProc) {
    Set-GameStatus "RECOVERING"
    Write-Alert "Game not running. Recovering..."
    Do-Recovery
}
else {
    Set-GameStatus "RUNNING"
    Write-Status "Game running (PID: $($gameProc.Id))"
}

while ($true) {
    Start-Sleep -Seconds 2
    if (-not (Get-Process -Name $GameProcess -ErrorAction SilentlyContinue)) {
        Set-GameStatus "CRASHED"
        Write-Alert "!!! CRASH DETECTED !!!"
        Start-Sleep -Seconds 2  # brief pause for crash dialogs
        Get-Process -Name $GameProcess -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Set-GameStatus "RECOVERING"
        Do-Recovery
        Set-GameStatus "RUNNING"
    }
}
