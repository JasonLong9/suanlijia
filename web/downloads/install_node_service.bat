@echo on
echo [DEBUG] Script started (v5).
pause

setlocal
set "BASE_DIR=%~dp0"
cd /d "%BASE_DIR%"

echo [DEBUG] Checking administrative privileges...
fsutil dirty query %systemdrive% >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
  echo.
  echo [ERROR] Administrative privileges required.
  echo [ERROR] Please right-click this script and select "Run as administrator".
  echo.
  pause
  exit /b 1
)

echo [DEBUG] Checking files...
if not exist "SLC.exe" (
  echo [ERROR] SLC.exe not found in: %BASE_DIR%
  pause
  exit /b 1
)

if not exist "service.bat" (
  echo [ERROR] service.bat not found in: %BASE_DIR%
  pause
  exit /b 1
)

set "CPP_REGION=hk"
set "CPP_GPU_TIER=tier_7"
set "CPP_HEARTBEAT_SECONDS=10"
set "CPP_REBOOT_ON_RELEASE=true"
set "CPP_REBOOT_DELAY_SECONDS=3"

echo.
echo === SLC Node Config ===
set /p CPP_DEVICE_ID=Device ID (e.g. hk-gpu-001): 
set /p CPP_DEVICE_SECRET=Device Secret: 
set /p CPP_REGION=Region [%CPP_REGION%]: 
set /p CPP_GPU_TIER=GPU Tier [%CPP_GPU_TIER%]: 

if "%CPP_DEVICE_ID%"=="" (
  echo [ERROR] Device ID is required.
  pause
  exit /b 1
)
if "%CPP_DEVICE_SECRET%"=="" (
  echo [ERROR] Device Secret is required.
  pause
  exit /b 1
)
if "%CPP_REGION%"=="" set "CPP_REGION=hk"
if "%CPP_GPU_TIER%"=="" set "CPP_GPU_TIER=tier_7"

echo [DEBUG] ProgramData is: "%ProgramData%"
set "CFG_DIR=C:\ProgramData\SLC"
set "CFG_FILE=%CFG_DIR%\node.json"

echo [DEBUG] Generating PowerShell script to write config...
set "PS_SCRIPT=%TEMP%\create_slc_config.ps1"

(
  echo $path = "%CFG_DIR%"
  echo $file = "%CFG_FILE%"
  echo if ^(!^(Test-Path $path^)^) { New-Item -ItemType Directory -Force -Path $path }
  echo $json = @'
  echo {
  echo   "enabled": true,
  echo   "device_id": "%CPP_DEVICE_ID%",
  echo   "device_secret": "%CPP_DEVICE_SECRET%",
  echo   "region": "%CPP_REGION%",
  echo   "gpu_tier": "%CPP_GPU_TIER%",
  echo   "heartbeat_seconds": %CPP_HEARTBEAT_SECONDS%,
  echo   "agent_version": "0.1.0",
  echo   "reboot_on_release": %CPP_REBOOT_ON_RELEASE%,
  echo   "reboot_delay_seconds": %CPP_REBOOT_DELAY_SECONDS%
  echo }
  echo '@
  echo Set-Content -Path $file -Value $json -Encoding UTF8
  echo Write-Host "[PS] Config written to $file"
) > "%PS_SCRIPT%"

echo [DEBUG] Executing PowerShell script...
powershell -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
if not "%ERRORLEVEL%"=="0" (
  echo [ERROR] PowerShell script failed.
  pause
  exit /b 1
)

del "%PS_SCRIPT%"

if not exist "%CFG_FILE%" (
  echo [ERROR] Config file was NOT created!
  pause
  exit /b 1
)
echo [DEBUG] Config file created successfully.
type "%CFG_FILE%"
echo.
pause

echo.
echo === Install Windows Service ===
call "%BASE_DIR%service.bat"
if not "%ERRORLEVEL%"=="0" (
  echo [ERROR] Failed to install/start service.
  pause
  exit /b 1
)

echo.
echo [OK] Installed.
echo.
pause
exit /b 0
