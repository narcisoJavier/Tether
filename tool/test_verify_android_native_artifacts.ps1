[CmdletBinding()]
param(
    [string]$LlvmReadElfPath,
    [string]$ZipAlignPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$verifier = Join-Path $PSScriptRoot 'verify_android_native_artifacts.ps1'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$powerShell = (Get-Process -Id $PID).Path
$temporaryRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) ('tether-native-verifier-test-' + [guid]::NewGuid().ToString('N'))

function New-SyntheticElf64 {
    param(
        [Parameter(Mandatory = $true)][uint16]$Machine,
        [Parameter(Mandatory = $true)][uint64]$LoadAlignment
    )

    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([byte[]]@(
            0x7f, 0x45, 0x4c, 0x46,
            0x02, 0x01, 0x01, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00
        ))
        $writer.Write([uint16]3)
        $writer.Write($Machine)
        $writer.Write([uint32]1)
        $writer.Write([uint64]0)
        $writer.Write([uint64]64)
        $writer.Write([uint64]0)
        $writer.Write([uint32]0)
        $writer.Write([uint16]64)
        $writer.Write([uint16]56)
        $writer.Write([uint16]1)
        $writer.Write([uint16]64)
        $writer.Write([uint16]0)
        $writer.Write([uint16]0)

        $writer.Write([uint32]1)
        $writer.Write([uint32]5)
        $writer.Write([uint64]0)
        $writer.Write([uint64]0)
        $writer.Write([uint64]0)
        $writer.Write([uint64]120)
        $writer.Write([uint64]120)
        $writer.Write($LoadAlignment)
        $writer.Flush()
        return $stream.ToArray()
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Add-ZipBytes {
    param(
        [Parameter(Mandatory = $true)][System.IO.Compression.ZipArchive]$Archive,
        [Parameter(Mandatory = $true)][string]$EntryName,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Content
    )

    $entry = $Archive.CreateEntry(
        $EntryName,
        [System.IO.Compression.CompressionLevel]::NoCompression
    )
    $stream = $entry.Open()
    try {
        if ($Content.Length -gt 0) {
            $stream.Write($Content, 0, $Content.Length)
        }
    } finally {
        $stream.Dispose()
    }
}

function New-FixtureApk {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowNull()][AllowEmptyCollection()][byte[]]$TailscaleContent,
        [switch]$OmitTailscale
    )

    $archive = [System.IO.Compression.ZipFile]::Open(
        $Path,
        [System.IO.Compression.ZipArchiveMode]::Create
    )
    try {
        Add-ZipBytes $archive 'AndroidManifest.xml' ([byte[]]@(1, 2, 3, 4))
        Add-ZipBytes $archive 'lib/arm64-v8a/libapp.so' ([byte[]]@(1, 2, 3, 4))
        if (-not $OmitTailscale) {
            Add-ZipBytes $archive 'lib/arm64-v8a/libtailscale.so' $TailscaleContent
        }
    } finally {
        $archive.Dispose()
    }
}

function Invoke-ExpectedFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedMessage,
        [switch]$UseDefaultAbis
    )

    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-File',
        $verifier,
        '-ArtifactPath',
        $Path
    )
    if (-not $UseDefaultAbis) {
        $arguments += @('-ExpectedAbi', 'arm64-v8a')
    }
    if (-not [string]::IsNullOrWhiteSpace($LlvmReadElfPath)) {
        $arguments += @('-LlvmReadElfPath', $LlvmReadElfPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($ZipAlignPath)) {
        $arguments += @('-ZipAlignPath', $ZipAlignPath)
    }

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $outputLines = @(& $powerShell @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    $output = ($outputLines | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine

    if ($exitCode -eq 0) {
        throw "Fixture '$Name' unexpectedly passed.`n$output"
    }
    if ($output -notmatch $ExpectedMessage) {
        throw (
            "Fixture '$Name' failed for the wrong reason; expected /$ExpectedMessage/.`n" +
            $output
        )
    }
    Write-Host "[PASS] $Name rejected"
}

function Remove-TestTempDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    $resolved = [System.IO.Path]::GetFullPath($Path)
    if (-not $resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetFileName($resolved) -notlike 'tether-native-verifier-test-*') {
        throw "Refusing to remove unexpected test path: $resolved"
    }
    [System.IO.Directory]::Delete($resolved, $true)
}

try {
    if (-not (Test-Path -LiteralPath $verifier -PathType Leaf)) {
        throw "Verifier not found: $verifier"
    }
    [void][System.IO.Directory]::CreateDirectory($temporaryRoot)

    $missing = Join-Path $temporaryRoot 'missing.apk'
    New-FixtureApk $missing $null -OmitTailscale
    Invoke-ExpectedFailure 'missing library' $missing 'missing libtailscale\.so'

    $empty = Join-Path $temporaryRoot 'empty.apk'
    New-FixtureApk $empty ([byte[]]@())
    Invoke-ExpectedFailure 'zero-byte library' $empty 'empty libtailscale\.so'

    $notElf = Join-Path $temporaryRoot 'not-elf.apk'
    New-FixtureApk $notElf ([System.Text.Encoding]::ASCII.GetBytes(
        'not an ELF binary; this payload is deliberately longer than an ELF32 header'
    ))
    Invoke-ExpectedFailure 'non-ELF library' $notElf 'not an ELF binary'

    $validHeader = New-SyntheticElf64 183 0x4000
    $malformed = Join-Path $temporaryRoot 'malformed.apk'
    New-FixtureApk $malformed ([byte[]]$validHeader[0..31])
    Invoke-ExpectedFailure 'malformed ELF library' $malformed 'too small or truncated'

    $wrongAbi = Join-Path $temporaryRoot 'wrong-abi.apk'
    New-FixtureApk $wrongAbi (New-SyntheticElf64 62 0x4000)
    Invoke-ExpectedFailure 'wrong ABI library' $wrongAbi 'ELF machine 62 does not match packaged ABI arm64-v8a'

    $misaligned = Join-Path $temporaryRoot 'misaligned.apk'
    New-FixtureApk $misaligned (New-SyntheticElf64 183 0x1000)
    Invoke-ExpectedFailure '4 KB LOAD alignment' $misaligned 'LOAD alignment 0x1000 is below required 0x4000'

    $missingExports = Join-Path $temporaryRoot 'missing-exports.apk'
    New-FixtureApk $missingExports (New-SyntheticElf64 183 0x4000)
    Invoke-ExpectedFailure 'missing Dune exports' $missingExports 'missing required defined Dune exports'

    $seededRelease = Join-Path $repositoryRoot 'release/Tether-v0.6.1.apk'
    if (Test-Path -LiteralPath $seededRelease -PathType Leaf) {
        Invoke-ExpectedFailure 'seeded release APK' $seededRelease 'empty libtailscale\.so' -UseDefaultAbis
    } else {
        Write-Host '[SKIP] Seeded release APK is not present in this checkout'
    }

    Write-Host '[PASS] Native artifact verifier negative-path self-test completed'
    exit 0
} catch {
    Write-Error "[FAIL] $($_.Exception.Message)"
    exit 1
} finally {
    try {
        Remove-TestTempDirectory $temporaryRoot
    } catch {
        Write-Warning "Self-test cleanup failed: $($_.Exception.Message)"
    }
}
