[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'verify_android_release_config.ps1'

& $script
if (-not $?) {
    throw "Expected Android release configuration preflight to pass."
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tether-release-config-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    Copy-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'android') $tempRoot -Recurse
    Copy-Item (Join-Path (Split-Path -Parent $PSScriptRoot) '.gitignore') $tempRoot
    $manifestPath = Join-Path $tempRoot 'android/app/src/main/AndroidManifest.xml'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw
    $manifest.Replace('android:allowBackup="false"', 'android:allowBackup="true"') |
        Set-Content -LiteralPath $manifestPath -NoNewline

    $failed = $false
    try {
        & $script -ProjectRoot $tempRoot
    } catch {
        $failed = $true
    }
    if (-not $failed) {
        throw 'Expected a tampered backup setting to fail the preflight.'
    }
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

Write-Output 'Android release configuration preflight self-test passed.'
