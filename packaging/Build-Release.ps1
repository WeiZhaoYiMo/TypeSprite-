Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseRoot = Join-Path $projectRoot 'release'
$compilerCandidates = @(
    "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:SystemRoot\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)
$compiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $compiler) { throw 'Windows .NET Framework C# compiler was not found.' }

New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null
$outputPath = Join-Path $releaseRoot 'TypingPet.exe'
$launcherPath = Join-Path $PSScriptRoot 'Launcher.cs'
$scriptPath = Join-Path $projectRoot 'TypingPet.ps1'
$imagePath = Join-Path $projectRoot 'assets\pet.png'

$arguments = @(
    '/nologo',
    '/target:winexe',
    '/platform:anycpu',
    '/optimize+',
    "/out:$outputPath",
    '/reference:System.dll',
    '/reference:System.Windows.Forms.dll',
    "/resource:$scriptPath,TypingPet.ps1",
    "/resource:$imagePath,pet.png",
    $launcherPath
)

& $compiler $arguments
if ($LASTEXITCODE -ne 0) { throw "Compilation failed with exit code: $LASTEXITCODE" }
Write-Output $outputPath

