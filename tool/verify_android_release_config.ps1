[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

function Read-RequiredFile([string]$RelativePath) {
    $path = Join-Path $ProjectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required release file is missing: $RelativePath"
    }
    return Get-Content -LiteralPath $path -Raw
}

function Assert-Contains([string]$Content, [string]$Pattern, [string]$Description) {
    if ($Content -notmatch $Pattern) {
        throw "Release configuration check failed: $Description"
    }
}

$manifest = Read-RequiredFile 'android/app/src/main/AndroidManifest.xml'
$styles = Read-RequiredFile 'android/app/src/main/res/values/styles.xml'
$styles31 = Read-RequiredFile 'android/app/src/main/res/values-v31/styles.xml'
$launchBackground = Read-RequiredFile 'android/app/src/main/res/drawable/launch_background.xml'
$buildGradle = Read-RequiredFile 'android/app/build.gradle'
$gitignore = Read-RequiredFile '.gitignore'

Assert-Contains $manifest 'android:allowBackup\s*=\s*"false"' 'Android backup must be disabled.'
Assert-Contains $manifest 'android\.permission\.USE_BIOMETRIC' 'Biometric permission must be declared.'
Assert-Contains $manifest 'android:icon\s*=\s*"@mipmap/ic_launcher"' 'Adaptive launcher icon must be configured.'
Assert-Contains $manifest 'android:roundIcon\s*=\s*"@mipmap/ic_launcher_round"' 'Round adaptive launcher icon must be configured.'

Assert-Contains $styles 'name="LaunchTheme"\s+parent="@android:style/Theme\.Black\.NoTitleBar"' 'LaunchTheme must be dark and titleless.'
Assert-Contains $styles 'android:windowBackground">@drawable/launch_background' 'LaunchTheme must use the dark launch drawable.'
Assert-Contains $styles31 'name="LaunchTheme"\s+parent="@android:style/Theme\.Black\.NoTitleBar"' 'Android 12+ LaunchTheme must remain dark and titleless.'
Assert-Contains $launchBackground 'launch_background_color' 'Launch drawable must use the black launch color.'

Assert-Contains $buildGradle 'release\s*\{[\s\S]*?signingConfig\s+signingConfigs\.release' 'Release builds must use the external release signing configuration.'
Assert-Contains $buildGradle 'minifyEnabled\s+true' 'Release minification must remain enabled.'
Assert-Contains $buildGradle 'shrinkResources\s+true' 'Release resource shrinking must remain enabled.'
Assert-Contains $gitignore '(?m)^key\.properties$' 'Signing properties must be ignored.'
Assert-Contains $gitignore '(?m)\*\*/\*\.(jks|keystore)$' 'Keystore files must be ignored.'

foreach ($icon in @(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml')) {
    $iconContent = Read-RequiredFile $icon
    Assert-Contains $iconContent '<adaptive-icon' "$icon must use an adaptive icon."
    Assert-Contains $iconContent 'ic_launcher_background' "$icon must use the OLED background color."
    Assert-Contains $iconContent 'ic_launcher_foreground' "$icon must use the centered foreground asset."
}

Write-Output 'Android release configuration checks passed.'
