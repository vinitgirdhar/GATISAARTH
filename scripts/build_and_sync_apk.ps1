# PowerShell script to build Flutter release APK and sync to apks folder and landing page
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
Set-Location $repoRoot

Write-Host "=== 1. Building Flutter Release APK ===" -ForegroundColor Cyan
Set-Location "$repoRoot\frontend"
flutter build apk --release
Set-Location $repoRoot

Write-Host "=== 2. Synchronizing APK to apks/ and landing page ===" -ForegroundColor Cyan
node tools/sync_apk.js
