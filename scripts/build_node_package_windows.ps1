param(
  [Parameter(Mandatory = $false)]
  [string]$ApiBaseUrl = "http://8.210.183.180:8080",

  [Parameter(Mandatory = $false)]
  [string]$OutputZip = "CloudPlayPlusNode-win64.zip"
)

$ErrorActionPreference = "Stop"

function Ensure-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Missing command: $name"
  }
}

Ensure-Command "flutter"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host ("Repo: " + $repoRoot)
Write-Host ("CPP_API_BASE_URL=" + $ApiBaseUrl)

flutter pub get
flutter build windows --release --dart-define=("CPP_API_BASE_URL=" + $ApiBaseUrl)

$releaseDirCandidates = @(
  (Join-Path $repoRoot "build\\windows\\x64\\runner\\Release"),
  (Join-Path $repoRoot "build\\windows\\runner\\Release")
)

$releaseDir = $null
foreach ($c in $releaseDirCandidates) {
  if (Test-Path $c) {
    $releaseDir = $c
    break
  }
}

if (-not $releaseDir) {
  throw ("Release folder not found. Tried: " + ($releaseDirCandidates -join ", "))
}

$required = @(
  "cloudplayplus.exe",
  "CloudPlayPlusSvc.exe",
  "install_node_service.bat",
  "service.bat"
)
foreach ($f in $required) {
  $p = Join-Path $releaseDir $f
  if (-not (Test-Path $p)) {
    throw ("Missing required file in Release folder: " + $p)
  }
}

if (Test-Path $OutputZip) {
  Remove-Item -Force $OutputZip
}

Compress-Archive -Path (Join-Path $releaseDir "*") -DestinationPath $OutputZip -Force
Write-Host ("OK: " + (Resolve-Path $OutputZip))

