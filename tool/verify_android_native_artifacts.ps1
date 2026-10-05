[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$ArtifactPath,

    [Alias('ExpectedAbis')]
    [ValidateSet('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64')]
    [string[]]$ExpectedAbi = @('armeabi-v7a', 'arm64-v8a', 'x86_64'),

    [string]$ApkSetPath,
    [string]$AndroidSdkPath,
    [string]$AndroidNdkPath,
    [string]$LlvmReadElfPath,
    [string]$ZipAlignPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
$script:ResolvedLlvmReadElf = $null
$script:ResolvedZipAlign = $null
$script:MinimumLoadAlignment = [uint64]0x4000
$script:IsWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$script:IsMacOSHost = -not $script:IsWindowsHost -and
    (Test-Path -LiteralPath '/System/Library/CoreServices/SystemVersion.plist')

$script:AbiSpecifications = @{
    'armeabi-v7a' = @{ Class = 1; Machine = 40; Name = 'ARM' }
    'arm64-v8a'   = @{ Class = 2; Machine = 183; Name = 'AArch64' }
    'x86'         = @{ Class = 1; Machine = 3; Name = 'Intel 80386' }
    'x86_64'      = @{ Class = 2; Machine = 62; Name = 'AMD x86-64' }
}

$script:RequiredDuneExports = @(
    'DuneStart',
    'DuneSetNetworkInterfaces',
    'DuneHttpStart',
    'DuneHttpBind',
    'DuneHttpAccept',
    'DuneHttpCloseBinding',
    'DuneTcpDialFd',
    'DuneTcpListenFd',
    'DuneTlsListenFd',
    'DuneTcpAcceptFd',
    'DuneTcpCloseFdListener',
    'DuneUdpBindFd',
    'DuneReactorCreate',
    'DuneReactorClose',
    'DuneReactorWake',
    'DuneReactorRegister',
    'DuneReactorUpdate',
    'DuneReactorUnregister',
    'DuneReactorWait',
    'DuneWhoIs',
    'DuneTlsDomains',
    'DuneDiagPing',
    'DuneDiagMetrics',
    'DuneDiagDERPMap',
    'DuneDiagCheckUpdate',
    'DuneHasState',
    'DuneLogout',
    'DuneStop',
    'DuneStatus',
    'DunePeers',
    'DunePrefsGet',
    'DunePrefsUpdate',
    'DuneExitNodeSuggest',
    'DuneExitNodeUseAuto',
    'DuneServeForward',
    'DuneServeClear',
    'DuneFree',
    'DuneSetLogLevel',
    'DuneInitDartAPI',
    'DuneSetDartPort',
    'DuneStartWatch',
    'DuneStopWatch'
)

function Throw-VerificationFailure {
    param([Parameter(Mandatory = $true)][string]$Message)

    throw [System.InvalidOperationException]::new($Message)
}

function Resolve-InputFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$AllowedExtensions,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Throw-VerificationFailure "$Description does not exist or is not a file: $Path"
    }

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $extension = [System.IO.Path]::GetExtension($resolved).ToLowerInvariant()
    if ($AllowedExtensions -notcontains $extension) {
        Throw-VerificationFailure (
            "$Description must use one of these extensions: " +
            "$($AllowedExtensions -join ', '). Received: $resolved"
        )
    }

    return $resolved
}

function Add-UniquePathCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Candidates,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$Seen,
        [AllowNull()][string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path.Trim())
    } catch {
        return
    }

    if ($Seen.Add($fullPath)) {
        $Candidates.Add($fullPath)
    }
}

function Get-LocalAndroidSdkPath {
    $localProperties = Join-Path $script:RepositoryRoot 'android/local.properties'
    if (-not (Test-Path -LiteralPath $localProperties -PathType Leaf)) {
        return $null
    }

    foreach ($line in Get-Content -LiteralPath $localProperties) {
        if ($line -match '^\s*sdk\.dir\s*=\s*(?<value>.+?)\s*$') {
            return $Matches['value'].Replace('\\', '\').Replace('\:', ':')
        }
    }

    return $null
}

function Get-AndroidSdkCandidates {
    $candidates = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    Add-UniquePathCandidate $candidates $seen $AndroidSdkPath
    Add-UniquePathCandidate $candidates $seen ([Environment]::GetEnvironmentVariable('ANDROID_SDK_ROOT'))
    Add-UniquePathCandidate $candidates $seen ([Environment]::GetEnvironmentVariable('ANDROID_HOME'))
    Add-UniquePathCandidate $candidates $seen (Get-LocalAndroidSdkPath)

    return $candidates.ToArray()
}

function ConvertTo-VersionSortKey {
    param([Parameter(Mandatory = $true)][string]$Value)

    $numbers = @([regex]::Matches($Value, '\d+') | ForEach-Object {
        [uint64]::Parse($_.Value)
    })
    while ($numbers.Count -lt 5) {
        $numbers += [uint64]0
    }

    return (($numbers | Select-Object -First 5 | ForEach-Object {
        $_.ToString('D12')
    }) -join '.')
}

function Get-VersionDirectoriesDescending {
    param([Parameter(Mandatory = $true)][string]$Parent)

    if (-not (Test-Path -LiteralPath $Parent -PathType Container)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $Parent -Directory | Sort-Object -Property @{
        Expression = { ConvertTo-VersionSortKey $_.Name }
        Descending = $true
    })
}

function Resolve-ExplicitTool {
    param(
        [AllowNull()][string]$ExplicitPath,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return $null
    }

    if (Test-Path -LiteralPath $ExplicitPath -PathType Leaf) {
        $resolved = (Resolve-Path -LiteralPath $ExplicitPath).Path
        if ((Get-Item -LiteralPath $resolved).Length -eq 0) {
            Throw-VerificationFailure "$Description is empty: $resolved"
        }
        return $resolved
    }

    $command = Get-Command $ExplicitPath -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $command) {
        return $command.Source
    }

    Throw-VerificationFailure "$Description was explicitly configured but not found: $ExplicitPath"
}

function Resolve-LlvmReadElf {
    if ($null -ne $script:ResolvedLlvmReadElf) {
        return $script:ResolvedLlvmReadElf
    }

    $explicit = Resolve-ExplicitTool $LlvmReadElfPath 'llvm-readelf'
    if ($null -ne $explicit) {
        $script:ResolvedLlvmReadElf = $explicit
        return $explicit
    }

    foreach ($name in @('llvm-readelf', 'llvm-readelf.exe')) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $command) {
            $script:ResolvedLlvmReadElf = $command.Source
            return $command.Source
        }
    }

    $ndkCandidates = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    Add-UniquePathCandidate $ndkCandidates $seen $AndroidNdkPath
    Add-UniquePathCandidate $ndkCandidates $seen ([Environment]::GetEnvironmentVariable('ANDROID_NDK_HOME'))
    Add-UniquePathCandidate $ndkCandidates $seen ([Environment]::GetEnvironmentVariable('ANDROID_NDK_ROOT'))

    foreach ($sdk in Get-AndroidSdkCandidates) {
        foreach ($directory in Get-VersionDirectoriesDescending (Join-Path $sdk 'ndk')) {
            Add-UniquePathCandidate $ndkCandidates $seen $directory.FullName
        }
        Add-UniquePathCandidate $ndkCandidates $seen (Join-Path $sdk 'ndk-bundle')
    }

    $hostPrebuiltNames = if ($script:IsWindowsHost) {
        @('windows-x86_64')
    } elseif ($script:IsMacOSHost) {
        @('darwin-arm64', 'darwin-x86_64')
    } else {
        @('linux-x86_64')
    }
    $toolNames = if ($script:IsWindowsHost) { @('llvm-readelf.exe', 'llvm-readelf') } else { @('llvm-readelf') }

    foreach ($ndk in $ndkCandidates) {
        foreach ($prebuiltName in $hostPrebuiltNames) {
            foreach ($toolName in $toolNames) {
                $candidate = Join-Path $ndk "toolchains/llvm/prebuilt/$prebuiltName/bin/$toolName"
                if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and
                    (Get-Item -LiteralPath $candidate).Length -gt 0) {
                    $script:ResolvedLlvmReadElf = (Resolve-Path -LiteralPath $candidate).Path
                    return $script:ResolvedLlvmReadElf
                }
            }
        }
    }

    Throw-VerificationFailure (
        'llvm-readelf was not found. Install the Android NDK, set ANDROID_NDK_HOME, ' +
        'or pass -LlvmReadElfPath. Artifact validation cannot be inferred from an NDK version.'
    )
}

function Resolve-ZipAlign {
    if ($null -ne $script:ResolvedZipAlign) {
        return $script:ResolvedZipAlign
    }

    $explicit = Resolve-ExplicitTool $ZipAlignPath 'zipalign'
    if ($null -ne $explicit) {
        $script:ResolvedZipAlign = $explicit
        return $explicit
    }

    foreach ($name in @('zipalign', 'zipalign.exe')) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $command) {
            $script:ResolvedZipAlign = $command.Source
            return $command.Source
        }
    }

    $toolNames = if ($script:IsWindowsHost) { @('zipalign.exe', 'zipalign') } else { @('zipalign') }
    foreach ($sdk in Get-AndroidSdkCandidates) {
        foreach ($directory in Get-VersionDirectoriesDescending (Join-Path $sdk 'build-tools')) {
            foreach ($toolName in $toolNames) {
                $candidate = Join-Path $directory.FullName $toolName
                if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and
                    (Get-Item -LiteralPath $candidate).Length -gt 0) {
                    $script:ResolvedZipAlign = (Resolve-Path -LiteralPath $candidate).Path
                    return $script:ResolvedZipAlign
                }
            }
        }
    }

    Throw-VerificationFailure (
        'zipalign was not found. Install Android SDK Build Tools, set ANDROID_SDK_ROOT, ' +
        'or pass -ZipAlignPath. APK 16 KB ZIP alignment is a mandatory release gate.'
    )
}

function Invoke-NativeTool {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $outputLines = @(& $Executable @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } catch {
        Throw-VerificationFailure "Failed to start $Description with ${Executable}: $($_.Exception.Message)"
    } finally {
        $ErrorActionPreference = $previousPreference
    }

    $output = ($outputLines | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    if ($exitCode -ne 0) {
        $tail = ($output -split '\r?\n' | Select-Object -Last 30) -join [Environment]::NewLine
        Throw-VerificationFailure "$Description failed with exit code $exitCode.`n$tail"
    }

    return $output
}

function Get-ElfHeader {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Abi
    )

    $file = Get-Item -LiteralPath $Path
    if ($file.Length -eq 0) {
        Throw-VerificationFailure "Packaged libtailscale.so is empty for ABI ${Abi}: $Path"
    }
    if ($file.Length -lt 52) {
        Throw-VerificationFailure "ELF file is too small or truncated for ABI ${Abi}: $Path"
    }

    $stream = [System.IO.File]::OpenRead($Path)
    $reader = [System.IO.BinaryReader]::new($stream)
    try {
        $identifier = $reader.ReadBytes(16)
        if ($identifier.Length -ne 16 -or
            $identifier[0] -ne 0x7f -or
            $identifier[1] -ne 0x45 -or
            $identifier[2] -ne 0x4c -or
            $identifier[3] -ne 0x46) {
            Throw-VerificationFailure "Packaged libtailscale.so is not an ELF binary for ABI ${Abi}: $Path"
        }
        if ($identifier[5] -ne 1 -or $identifier[6] -ne 1) {
            Throw-VerificationFailure "ELF byte order or identifier version is invalid for ABI ${Abi}: $Path"
        }

        $specification = $script:AbiSpecifications[$Abi]
        if ($identifier[4] -ne $specification.Class) {
            Throw-VerificationFailure (
                "ELF class $($identifier[4]) does not match packaged ABI $Abi " +
                "(expected ELF$($specification.Class * 32)): $Path"
            )
        }

        $stream.Position = 16
        $type = $reader.ReadUInt16()
        $machine = $reader.ReadUInt16()
        $version = $reader.ReadUInt32()
        if ($identifier[4] -eq 2) {
            [void]$reader.ReadUInt64()
            $programHeaderOffset = $reader.ReadUInt64()
            [void]$reader.ReadUInt64()
        } else {
            [void]$reader.ReadUInt32()
            $programHeaderOffset = [uint64]$reader.ReadUInt32()
            [void]$reader.ReadUInt32()
        }
        [void]$reader.ReadUInt32()
        $elfHeaderSize = $reader.ReadUInt16()
        $programHeaderEntrySize = $reader.ReadUInt16()
        $programHeaderCount = $reader.ReadUInt16()

        if ($type -ne 3 -or $version -ne 1) {
            Throw-VerificationFailure "ELF is not a valid shared object for ABI ${Abi}: $Path"
        }
        if ($machine -ne $specification.Machine) {
            Throw-VerificationFailure (
                "ELF machine $machine does not match packaged ABI $Abi " +
                "(expected $($specification.Machine), $($specification.Name)): $Path"
            )
        }

        $minimumHeaderSize = if ($identifier[4] -eq 2) { 64 } else { 52 }
        $minimumProgramHeaderSize = if ($identifier[4] -eq 2) { 56 } else { 32 }
        $programHeaderEnd = [decimal]$programHeaderOffset +
            ([decimal]$programHeaderEntrySize * [decimal]$programHeaderCount)
        if ($elfHeaderSize -lt $minimumHeaderSize -or
            $programHeaderOffset -lt $minimumHeaderSize -or
            $programHeaderEntrySize -lt $minimumProgramHeaderSize -or
            $programHeaderCount -eq 0 -or
            $programHeaderEnd -gt [decimal]$file.Length) {
            Throw-VerificationFailure "ELF program header table is malformed or truncated for ABI ${Abi}: $Path"
        }

        return [pscustomobject]@{
            Class = $identifier[4]
            Machine = $machine
            MachineName = $specification.Name
        }
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Test-ElfLoadAlignment {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Abi
    )

    $readElf = Resolve-LlvmReadElf
    $output = Invoke-NativeTool $readElf @('--program-headers', '--wide', $Path) "llvm-readelf LOAD inspection for $Abi"
    $loadLines = @($output -split '\r?\n' | Where-Object { $_ -match '^\s*LOAD\s+' })
    if ($loadLines.Count -eq 0) {
        Throw-VerificationFailure "ELF has no parseable LOAD segments for ABI ${Abi}: $Path"
    }

    foreach ($line in $loadLines) {
        $alignmentMatch = [regex]::Match($line, '(?<alignment>0x[0-9a-fA-F]+)\s*$')
        if (-not $alignmentMatch.Success) {
            Throw-VerificationFailure "Could not parse LOAD alignment for ABI $Abi from llvm-readelf: $line"
        }

        $hex = $alignmentMatch.Groups['alignment'].Value.Substring(2)
        $alignment = [Convert]::ToUInt64($hex, 16)
        if ($alignment -lt $script:MinimumLoadAlignment) {
            Throw-VerificationFailure (
                "ELF LOAD alignment $($alignmentMatch.Groups['alignment'].Value) is below required " +
                "0x4000 for ABI ${Abi}: $Path"
            )
        }
        if (($alignment -band ($alignment - 1)) -ne 0) {
            Throw-VerificationFailure "ELF LOAD alignment is not a power of two for ABI ${Abi}: $line"
        }
    }
}

function Test-ElfExports {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Abi
    )

    $readElf = Resolve-LlvmReadElf
    $output = Invoke-NativeTool $readElf @('--dyn-syms', '--wide', $Path) "llvm-readelf export inspection for $Abi"
    $definedExports = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )

    foreach ($line in $output -split '\r?\n') {
        $match = [regex]::Match(
            $line,
            '^\s*\d+:\s+\S+\s+\d+\s+(?:FUNC|IFUNC|NOTYPE)\s+(?:GLOBAL|WEAK)\s+(?:DEFAULT|PROTECTED)\s+(?<index>\S+)\s+(?<name>\S+)\s*$'
        )
        if (-not $match.Success -or $match.Groups['index'].Value -eq 'UND') {
            continue
        }
        $name = $match.Groups['name'].Value.Split('@')[0]
        [void]$definedExports.Add($name)
    }

    $missing = @($script:RequiredDuneExports | Where-Object {
        -not $definedExports.Contains($_)
    })
    if ($missing.Count -gt 0) {
        Throw-VerificationFailure (
            "ELF is missing required defined Dune exports for ABI ${Abi}: " +
            "$($missing -join ', '). Artifact: $Path"
        )
    }
}

function Test-ElfArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Abi
    )

    $header = Get-ElfHeader $Path $Abi
    Test-ElfLoadAlignment $Path $Abi
    Test-ElfExports $Path $Abi
    Write-Host (
        "[PASS] $Abi libtailscale.so: ELF$($header.Class * 32), " +
        "$($header.MachineName), all LOAD alignments >= 0x4000, " +
        "$($script:RequiredDuneExports.Count) required exports"
    )
}

function Copy-ZipEntryToFile {
    param(
        [Parameter(Mandatory = $true)][System.IO.Compression.ZipArchiveEntry]$Entry,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $parent = Split-Path -Parent $Destination
    [void][System.IO.Directory]::CreateDirectory($parent)
    $inputStream = $Entry.Open()
    $outputStream = [System.IO.File]::Create($Destination)
    try {
        $inputStream.CopyTo($outputStream)
    } finally {
        $outputStream.Dispose()
        $inputStream.Dispose()
    }

    if ((Get-Item -LiteralPath $Destination).Length -ne $Entry.Length) {
        Throw-VerificationFailure "ZIP entry extraction was truncated: $($Entry.FullName)"
    }
}

function Get-NativePayloadsFromArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('APK', 'AAB')][string]$Kind,
        [Parameter(Mandatory = $true)][string]$ExtractionRoot,
        [Parameter(Mandatory = $true)][string[]]$ExpectedAbis
    )

    $nativePattern = if ($Kind -eq 'APK') {
        '^lib/(?<abi>[^/]+)/[^/]+\.so$'
    } else {
        '^base/lib/(?<abi>[^/]+)/[^/]+\.so$'
    }
    $tailscalePattern = if ($Kind -eq 'APK') {
        '^lib/(?<abi>[^/]+)/libtailscale\.so$'
    } else {
        '^base/lib/(?<abi>[^/]+)/libtailscale\.so$'
    }
    $nativeRegex = [regex]::new($nativePattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
    $tailscaleRegex = [regex]::new($tailscalePattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    } catch {
        Throw-VerificationFailure "$Kind is not a readable ZIP archive: $Path. $($_.Exception.Message)"
    }

    try {
        $packagedAbis = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        $tailscaleEntries = @{}
        $unexpectedTailscalePaths = [System.Collections.Generic.List[string]]::new()

        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            $nativeMatch = $nativeRegex.Match($name)
            if ($nativeMatch.Success) {
                [void]$packagedAbis.Add($nativeMatch.Groups['abi'].Value)
            }

            $tailscaleMatch = $tailscaleRegex.Match($name)
            if ($tailscaleMatch.Success) {
                $abi = $tailscaleMatch.Groups['abi'].Value
                if (-not $tailscaleEntries.ContainsKey($abi)) {
                    $tailscaleEntries[$abi] = [System.Collections.Generic.List[object]]::new()
                }
                $tailscaleEntries[$abi].Add($entry)
            } elseif ($name.EndsWith('/libtailscale.so', [System.StringComparison]::Ordinal) -or
                $name -eq 'libtailscale.so') {
                $unexpectedTailscalePaths.Add($name)
            }
        }

        $packaged = @($packagedAbis | Sort-Object)
        Write-Host "[INFO] $Kind packaged ABIs: $(if ($packaged.Count -gt 0) { $packaged -join ', ' } else { '<none>' })"

        if ($unexpectedTailscalePaths.Count -gt 0) {
            Throw-VerificationFailure (
                "$Kind contains libtailscale.so outside the required native-library path: " +
                "$($unexpectedTailscalePaths -join ', ')"
            )
        }

        $unknown = @($packaged | Where-Object { -not $script:AbiSpecifications.ContainsKey($_) })
        if ($unknown.Count -gt 0) {
            Throw-VerificationFailure "$Kind contains unsupported Android ABI directories: $($unknown -join ', ')"
        }

        $missingPackaged = @($ExpectedAbis | Where-Object { -not $packagedAbis.Contains($_) })
        if ($missingPackaged.Count -gt 0) {
            Throw-VerificationFailure (
                "$Kind is missing expected packaged ABI(s): $($missingPackaged -join ', '). " +
                "Found: $(if ($packaged.Count -gt 0) { $packaged -join ', ' } else { '<none>' })"
            )
        }

        $unexpectedPackaged = @($packaged | Where-Object { $ExpectedAbis -notcontains $_ })
        if ($unexpectedPackaged.Count -gt 0) {
            Throw-VerificationFailure (
                "$Kind contains unexpected packaged ABI(s): $($unexpectedPackaged -join ', '). " +
                "Pass the exact intended list with -ExpectedAbi only if this is deliberate."
            )
        }

        $payloads = [System.Collections.Generic.List[object]]::new()
        foreach ($abi in $ExpectedAbis) {
            $entries = [System.Collections.Generic.List[object]]::new()
            if ($tailscaleEntries.ContainsKey($abi)) {
                $entries = $tailscaleEntries[$abi]
            }
            if ($entries.Count -eq 0) {
                Throw-VerificationFailure "$Kind is missing libtailscale.so for expected ABI: $abi"
            }
            if ($entries.Count -ne 1) {
                Throw-VerificationFailure (
                    "$Kind must contain exactly one libtailscale.so for ABI $abi; found $($entries.Count)."
                )
            }

            $entry = $entries[0]
            if ($entry.Length -eq 0) {
                Throw-VerificationFailure "$Kind contains an empty libtailscale.so for ABI $abi at $($entry.FullName)"
            }

            $destination = Join-Path $ExtractionRoot "$Kind/$abi/libtailscale.so"
            Copy-ZipEntryToFile $entry $destination
            $payloads.Add([pscustomobject]@{
                Abi = $abi
                Path = $destination
                ArchiveEntry = $entry.FullName
                Length = $entry.Length
            })
        }

        return $payloads.ToArray()
    } finally {
        $archive.Dispose()
    }
}

function Test-NativePayloads {
    param([Parameter(Mandatory = $true)][object[]]$Payloads)

    foreach ($payload in $Payloads) {
        Test-ElfArtifact $payload.Path $payload.Abi
    }
}

function Test-ApkZipAlignment {
    param([Parameter(Mandatory = $true)][string]$Path)

    $zipAlign = Resolve-ZipAlign
    [void](Invoke-NativeTool $zipAlign @('-c', '-P', '16', '-v', '4', $Path) 'zipalign 16 KB APK verification')
    Write-Host "[PASS] APK ZIP alignment: zipalign -c -P 16 -v 4"
}

function Test-AndroidArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('APK', 'AAB')][string]$Kind,
        [Parameter(Mandatory = $true)][string]$ExtractionRoot,
        [Parameter(Mandatory = $true)][string[]]$ExpectedAbis
    )

    $payloads = @(Get-NativePayloadsFromArchive $Path $Kind $ExtractionRoot $ExpectedAbis)
    Test-NativePayloads $payloads
    if ($Kind -eq 'APK') {
        Test-ApkZipAlignment $Path
    }
    return $payloads
}

function Test-UniversalApkSet {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExtractionRoot,
        [Parameter(Mandatory = $true)][string[]]$ExpectedAbis
    )

    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    } catch {
        Throw-VerificationFailure "APK set is not a readable ZIP archive: $Path. $($_.Exception.Message)"
    }

    try {
        $universalEntries = @($archive.Entries | Where-Object {
            $_.FullName.Replace('\', '/') -match '(^|/)universal\.apk$'
        })
        if ($universalEntries.Count -eq 0) {
            Throw-VerificationFailure (
                'APK set does not contain universal.apk. Generate it with bundletool ' +
                '`build-apks --mode=universal`, then pass the resulting .apks file.'
            )
        }
        if ($universalEntries.Count -ne 1) {
            Throw-VerificationFailure "APK set contains multiple universal.apk entries; found $($universalEntries.Count)."
        }
        if ($universalEntries[0].Length -eq 0) {
            Throw-VerificationFailure 'APK set contains an empty universal.apk.'
        }

        $universalApk = Join-Path $ExtractionRoot 'apk-set/universal.apk'
        Copy-ZipEntryToFile $universalEntries[0] $universalApk
    } finally {
        $archive.Dispose()
    }

    Write-Host "[INFO] Inspecting bundletool universal APK: $Path"
    return @(Test-AndroidArchive $universalApk 'APK' (Join-Path $ExtractionRoot 'apk-set-payloads') $ExpectedAbis)
}

function Compare-NativePayloads {
    param(
        [Parameter(Mandatory = $true)][object[]]$BundlePayloads,
        [Parameter(Mandatory = $true)][object[]]$ApkPayloads
    )

    foreach ($bundlePayload in $BundlePayloads) {
        $apkPayload = @($ApkPayloads | Where-Object { $_.Abi -eq $bundlePayload.Abi })
        if ($apkPayload.Count -ne 1) {
            Throw-VerificationFailure "Could not correlate AAB and universal APK payload for ABI $($bundlePayload.Abi)."
        }

        $bundleHash = (Get-FileHash -LiteralPath $bundlePayload.Path -Algorithm SHA256).Hash
        $apkHash = (Get-FileHash -LiteralPath $apkPayload[0].Path -Algorithm SHA256).Hash
        if ($bundleHash -ne $apkHash) {
            Throw-VerificationFailure (
                "Universal APK libtailscale.so does not match the inspected AAB for ABI " +
                "$($bundlePayload.Abi). Regenerate the APK set from this exact AAB."
            )
        }
    }

    Write-Host '[PASS] Universal APK native payloads match the AAB byte-for-byte'
}

function Remove-VerificationTempDirectory {
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
        [System.IO.Path]::GetFileName($resolved) -notlike 'tether-native-verify-*') {
        Throw-VerificationFailure "Refusing to remove unexpected temporary path: $resolved"
    }

    [System.IO.Directory]::Delete($resolved, $true)
}

$temporaryRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) ('tether-native-verify-' + [guid]::NewGuid().ToString('N'))

try {
    $resolvedArtifact = Resolve-InputFile $ArtifactPath @('.apk', '.aab', '.apks') 'Android artifact'
    $expectedUnique = @($ExpectedAbi | Select-Object -Unique)
    if ($expectedUnique.Count -ne $ExpectedAbi.Count) {
        Throw-VerificationFailure 'Expected ABI list contains duplicates.'
    }
    if ($expectedUnique.Count -eq 0) {
        Throw-VerificationFailure 'At least one expected ABI is required.'
    }

    [void][System.IO.Directory]::CreateDirectory($temporaryRoot)
    $extension = [System.IO.Path]::GetExtension($resolvedArtifact).ToLowerInvariant()
    Write-Host "[INFO] Artifact: $resolvedArtifact"
    Write-Host "[INFO] Expected ABIs: $($expectedUnique -join ', ')"

    switch ($extension) {
        '.apk' {
            if (-not [string]::IsNullOrWhiteSpace($ApkSetPath)) {
                Throw-VerificationFailure '-ApkSetPath is only valid when -ArtifactPath points to an AAB.'
            }
            [void](Test-AndroidArchive $resolvedArtifact 'APK' (Join-Path $temporaryRoot 'apk') $expectedUnique)
        }
        '.apks' {
            if (-not [string]::IsNullOrWhiteSpace($ApkSetPath)) {
                Throw-VerificationFailure '-ApkSetPath is only valid when -ArtifactPath points to an AAB.'
            }
            [void](Test-UniversalApkSet $resolvedArtifact (Join-Path $temporaryRoot 'apks') $expectedUnique)
        }
        '.aab' {
            $bundlePayloads = @(Test-AndroidArchive $resolvedArtifact 'AAB' (Join-Path $temporaryRoot 'aab') $expectedUnique)
            if ([string]::IsNullOrWhiteSpace($ApkSetPath)) {
                Throw-VerificationFailure (
                    'AAB payload inspection passed, but the installable APK alignment gate is incomplete. ' +
                    'Generate a bundletool APK set with `build-apks --mode=universal` and rerun with ' +
                    '`-ApkSetPath <path-to.apks>`. See docs/RELEASE_CHECKLIST.md.'
                )
            }
            $resolvedApkSet = Resolve-InputFile $ApkSetPath @('.apks') 'Bundletool APK set'
            $apkPayloads = @(Test-UniversalApkSet $resolvedApkSet (Join-Path $temporaryRoot 'aab-apks') $expectedUnique)
            Compare-NativePayloads $bundlePayloads $apkPayloads
        }
    }

    Write-Host "[PASS] Android native artifact release gate completed: $resolvedArtifact"
    exit 0
} catch {
    Write-Error "[FAIL] $($_.Exception.Message)"
    exit 1
} finally {
    try {
        Remove-VerificationTempDirectory $temporaryRoot
    } catch {
        Write-Warning "Temporary verification cleanup failed: $($_.Exception.Message)"
    }
}
