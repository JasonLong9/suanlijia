@echo off
echo ========================================
echo SLC Node Silent Installer
echo ========================================
echo.

setlocal
set "BASE_DIR=%~dp0"
cd /d "%BASE_DIR%"

REM Check for admin privileges
fsutil dirty query %systemdrive% >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
  echo [ERROR] Administrative privileges required.
  echo [ERROR] Please right-click this script and select "Run as administrator".
  echo.
  timeout /t 3 /nobreak >nul
  exit /b 1
)

REM Check required files
if not exist "SLC.exe" (
  echo [ERROR] SLC.exe not found in: %BASE_DIR%
  timeout /t 3 /nobreak >nul
  exit /b 1
)

if not exist "service.bat" (
  echo [ERROR] service.bat not found in: %BASE_DIR%
  timeout /t 3 /nobreak >nul
  exit /b 1
)

echo [INFO] Detecting system information...
echo.

REM Get computer name
set "HOSTNAME=%COMPUTERNAME%"
echo [DETECTED] Computer Name: %HOSTNAME%

REM Get public IP address
echo [INFO] Fetching public IP address...
for /f "delims=" %%i in ('curl -s https://api.ipify.org') do set PUBLIC_IP=%%i
REM Try PowerShell fallback (no curl needed)
if "%PUBLIC_IP%"=="" (
  for /f "delims=" %%i in ('powershell -Command "(Invoke-WebRequest -Uri 'https://api.ipify.org' -UseBasicParsing -TimeoutSec 5).Content" 2^>nul') do set PUBLIC_IP=%%i
)
if "%PUBLIC_IP%"=="" (
  echo [WARNING] Failed to detect public IP. Using localhost.
  set "PUBLIC_IP=127.0.0.1"
)
echo [DETECTED] Public IP: %PUBLIC_IP%

REM Auto-generate device_id from hostname
set "CPP_DEVICE_ID=%HOSTNAME%"
echo [GENERATED] Device ID: %CPP_DEVICE_ID%

REM Auto-generate device_secret (using hostname + timestamp hash)
for /f "tokens=1-4 delims=:.," %%a in ("%time%") do (
  set /a "TIMESTAMP_HASH=%%a*3600+%%b*60+%%c"
)
set "CPP_DEVICE_SECRET=%HOSTNAME%_%TIMESTAMP_HASH%"
echo [GENERATED] Device Secret: %CPP_DEVICE_SECRET%

REM Default settings
set "CPP_REGION=hk"
set "CPP_GPU_TIER=tier_7"
set "CPP_HEARTBEAT_SECONDS=10"
set "CPP_REBOOT_ON_RELEASE=true"
set "CPP_REBOOT_DELAY_SECONDS=3"

REM Try to detect region from IP geolocation
echo [INFO] Detecting region from IP...
for /f "delims=" %%i in ('curl -s "https://ipapi.co/%PUBLIC_IP%/country_code/"') do set COUNTRY_CODE=%%i
if "%COUNTRY_CODE%"=="CN" (
  set "CPP_REGION=cn"
  echo [DETECTED] Region: China (cn)
) else if "%COUNTRY_CODE%"=="HK" (
  set "CPP_REGION=hk"
  echo [DETECTED] Region: Hong Kong (hk)
) else if "%COUNTRY_CODE%"=="US" (
  set "CPP_REGION=us"
  echo [DETECTED] Region: United States (us)
) else if "%COUNTRY_CODE%"=="SG" (
  set "CPP_REGION=sg"
  echo [DETECTED] Region: Singapore (sg)
) else if "%COUNTRY_CODE%"=="JP" (
  set "CPP_REGION=jp"
  echo [DETECTED] Region: Japan (jp)
) else (
  echo [INFO] Unknown country code '%COUNTRY_CODE%', using default region: hk
)

REM Detect city from IP geolocation
echo [INFO] Detecting city from IP...
for /f "tokens=*" %%i in ('powershell -Command "(Invoke-WebRequest -Uri http://ip-api.com/json/%PUBLIC_IP% -UseBasicParsing).Content | ConvertFrom-Json | Select-Object -ExpandProperty city"') do set "CPP_CITY=%%i"
REM Try ipinfo.io (more reliable)
if "%CPP_CITY%"=="" (
  for /f "delims=" %%i in ('curl -s --connect-timeout 5 "https://ipinfo.io/%PUBLIC_IP%/city" 2^>nul') do set "CPP_CITY=%%i"
)
if "%CPP_CITY%"=="" (
  echo [WARNING] Failed to detect city.
  set "CPP_CITY=unknown"
) else (
  echo [DETECTED] City: %CPP_CITY%
)

echo.
echo ========================================
echo Configuration Summary
echo ========================================
echo Device ID:       %CPP_DEVICE_ID%
echo Device Secret:   %CPP_DEVICE_SECRET%
echo Region:          %CPP_REGION%
echo GPU Tier:        %CPP_GPU_TIER%
echo Public IP:       %PUBLIC_IP%
echo ========================================
echo.

REM Write configuration file using PowerShell
set "CFG_DIR=C:\ProgramData\SLC"
set "CFG_FILE=%CFG_DIR%\node.json"
set "PS_SCRIPT=%TEMP%\create_slc_config_silent.ps1"

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
  echo   "agent_version": "0.10.1",
  echo   "city": "%CPP_CITY%",
  echo   "reboot_on_release": %CPP_REBOOT_ON_RELEASE%,
  echo   "reboot_delay_seconds": %CPP_REBOOT_DELAY_SECONDS%,
  echo   "public_ip": "%PUBLIC_IP%",
  echo   "hostname": "%HOSTNAME%",
  echo   "api_url": "http://8.210.183.180:18080"
  echo }
  echo '@
  echo Set-Content -Path $file -Value $json -Encoding UTF8
  echo Write-Host "[PS] Config written to $file"
) > "%PS_SCRIPT%"

echo [INFO] Writing configuration file...
powershell -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
if not "%ERRORLEVEL%"=="0" (
  echo [ERROR] Failed to write configuration file.
  timeout /t 3 /nobreak >nul
  exit /b 1
)

del "%PS_SCRIPT%"

if not exist "%CFG_FILE%" (
  echo [ERROR] Config file was NOT created!
  timeout /t 3 /nobreak >nul
  exit /b 1
)

echo [OK] Configuration file created: %CFG_FILE%
echo.

echo [INFO] Installing Windows Service...
call "%BASE_DIR%service.bat"
if not "%ERRORLEVEL%"=="0" (
  echo [ERROR] Failed to install/start service.
  timeout /t 3 /nobreak >nul
  exit /b 1
)

echo.
echo ========================================
echo Installation Complete!
echo ========================================
echo Service Name:     slcsvc
echo Display Name:     SLC Node Service
echo Config File:      %CFG_FILE%
echo ========================================
echo.
echo The SLC Node service is now running in the background.
echo You can check its status in Windows Services (services.msc).
echo.
echo This window will close in 3 seconds...
timeout /t 3 /nobreak >nul
exit /b 0
