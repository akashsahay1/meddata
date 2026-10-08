param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$appRoot = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $appRoot 'pubspec.yaml'
$pubspec = Get-Content -LiteralPath $pubspecPath -Raw
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)')
if (-not $versionMatch.Success) {
    throw "Could not read a semantic app version from $pubspecPath."
}
$appVersion = $versionMatch.Groups[1].Value

$releaseDir = Join-Path $appRoot 'build\windows\x64\runner\Release'
$appExecutable = Join-Path $releaseDir 'Meddata.exe'
if (-not $SkipBuild) {
    Push-Location $appRoot
    try {
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter Windows release build failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

if (-not (Test-Path -LiteralPath $appExecutable)) {
    throw "Windows release files were not found at $releaseDir. Build the app first or omit -SkipBuild."
}

$compiler = $env:INNO_SETUP_COMPILER
if (-not $compiler) {
    $compilerCommand = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($compilerCommand) {
        $compiler = $compilerCommand.Source
    }
}
if (-not $compiler) {
    $compilerCandidates = @()
    foreach ($version in @('7', '6')) {
        foreach ($programFiles in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if ($programFiles) {
                $compilerCandidates += Join-Path $programFiles "Inno Setup $version\ISCC.exe"
            }
        }
    }
    foreach ($candidate in $compilerCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            $compiler = $candidate
            break
        }
    }
}
if (-not $compiler -or -not (Test-Path -LiteralPath $compiler)) {
    throw 'Inno Setup 7 or 6 was not found. Install it, or set INNO_SETUP_COMPILER to the full path of ISCC.exe.'
}

$installerSpec = Join-Path $appRoot 'windows\installer\meddata.iss'
& $compiler "/DAppVersion=$appVersion" $installerSpec
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup failed with exit code $LASTEXITCODE."
}

$installer = Join-Path $appRoot "build\installer\Meddata-Setup-$appVersion.exe"
Write-Output "Installer created: $installer"
