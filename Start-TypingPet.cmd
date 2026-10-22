@echo off
setlocal
where pwsh.exe >nul 2>nul
if %errorlevel%==0 (
    start "TypingPet" pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0TypingPet.ps1"
) else (
    set "TYPING_PET_ROOT=%~dp0"
    start "TypingPet" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -Command "$code=[IO.File]::ReadAllText((Join-Path $env:TYPING_PET_ROOT 'TypingPet.ps1'),[Text.Encoding]::UTF8); & ([ScriptBlock]::Create($code))"
)

