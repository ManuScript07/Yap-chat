param(
  [ValidateSet('seed','panel','run','verify','status','cleanup')][string]$Action = 'status',
  [string]$Device,
  [switch]$DebugBuild
)
$ErrorActionPreference = 'Stop'
$labRoot = Split-Path $PSScriptRoot -Parent
Push-Location $labRoot
try {
  $nodeCommand = (Get-Command node -ErrorAction Stop).Source
  $labScript = Join-Path $labRoot 'tools/pagination_lab/main.mjs'
  if ($Action -eq 'run') {
    & $nodeCommand $labScript prepare
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось подготовить локальную сессию' }
    $flutterCommand = (Get-Command flutter -ErrorAction Stop).Source
    $adbCommand = Get-Command adb -ErrorAction SilentlyContinue
    if (-not $adbCommand) {
      $sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { $null }
      if (-not $sdkRoot) {
        $sdkLine = Get-Content (Join-Path $labRoot 'android/local.properties') -ErrorAction SilentlyContinue | Where-Object { $_ -match '^sdk\.dir=' } | Select-Object -First 1
        $sdkRoot = if ($sdkLine) { $sdkLine.Substring(8).Replace('\:',':').Replace('\\','\') } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
      }
      $adbPath = Join-Path $sdkRoot 'platform-tools/adb.exe'
    } else { $adbPath = $adbCommand.Source }
    if (-not $Device) {
      $available = @(& $adbPath devices -l | Where-Object { $_ -match '^\S+\s+device(?:\s|$)' } | ForEach-Object { ($_ -split '\s+')[0] })
      $physical = @($available | Where-Object { $_ -notlike 'emulator-*' })
      if ($physical.Count -eq 1) { $Device = $physical[0] }
      elseif ($available.Count -eq 1) { $Device = $available[0] }
      else { throw 'Не удалось однозначно выбрать устройство. Укажите -Device из adb devices.' }
    }
    Write-Host "Тестовое устройство: $Device"
    $deviceArgs = if ($Device) { @('-s', $Device) } else { @() }
    & $adbPath @deviceArgs reverse tcp:54321 tcp:54321
    if ($LASTEXITCODE -ne 0) { throw 'USB-проброс не установлен. Укажите -Device из adb devices.' }
    $mode = if ($DebugBuild) { '--debug' } else { '--profile' }
    $flutterArgs = @('run',$mode,'--dart-define-from-file=.local/pagination-lab/manual/launch.json')
    if ($Device) { $flutterArgs += @('-d',$Device) }
    & $flutterCommand @flutterArgs
  } else {
    $command = if ($Action -eq 'panel') { 'serve' } else { $Action }
    & $nodeCommand $labScript $command
  }
  if ($LASTEXITCODE -ne 0) { throw "Команда завершилась с кодом $LASTEXITCODE" }
} finally { Pop-Location }
