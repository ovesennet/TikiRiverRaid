# build.ps1 - Build TIKI RIVER RAID with z88dk
#
# Usage:
#   .\build.ps1              Build tikirr.com
#   .\build.ps1 -Clean       Clean build outputs first
#   .\build.ps1 -Verbose     Show full compiler output

param(
    [switch]$Clean,
    [switch]$Verbose
)

# === Configuration ===
$ProjectRoot = $PSScriptRoot
$SrcDir      = "$ProjectRoot\src\c"
$BuildDir    = "$ProjectRoot\build"
$OutputName  = "tikirr"

# Ensure z88dk environment
if (-not $env:ZCCCFG) {
    $env:ZCCCFG = "C:\z88dk\lib\config"
}
if ($env:PATH -notlike "*z88dk*") {
    $env:PATH = "C:\z88dk\bin;$env:PATH"
}

# Verify zcc is available
$zcc = Get-Command zcc.exe -ErrorAction SilentlyContinue
if (-not $zcc) {
    Write-Host "ERROR: zcc not found. Is z88dk installed at C:\z88dk?" -ForegroundColor Red
    exit 1
}

# Create build dir
if (-not (Test-Path $BuildDir)) {
    New-Item -ItemType Directory -Path $BuildDir | Out-Null
}

# Clean
if ($Clean) {
    Write-Host "Cleaning build directory..." -ForegroundColor Yellow
    Remove-Item "$BuildDir\*" -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=== TIKI RIVER RAID Build ===" -ForegroundColor Cyan
Write-Host ""

# -- Full game build --
Write-Host "Building tikirr..." -ForegroundColor White

# Collect C source files
$cFiles = @(
    "$SrcDir\main.c",
    "$SrcDir\video.c",
    "$SrcDir\input.c",
    "$SrcDir\river.c"
)

# Assembly source files
$asmDir = "$ProjectRoot\src\asm"
$asmFiles = @(
    "$asmDir\screen.asm",
    "$asmDir\keyboard.asm"
)

# Verify all source files exist
$allFiles = $cFiles + $asmFiles
foreach ($f in $allFiles) {
    if (-not (Test-Path $f)) {
        Write-Host "  ERROR: Source file not found: $f" -ForegroundColor Red
        exit 1
    }
}

$sourceList = ($allFiles | ForEach-Object { "`"$_`"" }) -join " "

# Build command:
#   +cpm                    Target CP/M
#   -subtype=tiki100_400k   Tiki-100 400K disk format (also links -ltiki100)
#   -startup=0              Minimal CRT startup
#   -clib=default           Default C library
#   -compiler=sccz80        Use sccz80 compiler (more forgiving; use sdcc for optimized builds)
#   -create-app             Generate .dsk disk image too
#   -m                      Generate map file
#   -s                      Generate symbol file
#   -I                      Include path for our headers

$cmd = "zcc +cpm -subtype=tiki100_400k -startup=0 -clib=default -compiler=sccz80 -Cz--container=raw -I`"$SrcDir`" -o `"$BuildDir\$OutputName`" $sourceList -create-app -m -s"

Write-Host "  $cmd" -ForegroundColor DarkGray

$result = Invoke-Expression "$cmd 2>&1" | Out-String
if ($Verbose -or $LASTEXITCODE -ne 0) { Write-Host $result }

if (Test-Path "$BuildDir\$OutputName.com") {
    $sz = (Get-Item "$BuildDir\$OutputName.com").Length
    Write-Host "  OK: $OutputName.com ($sz bytes)" -ForegroundColor Green
    
    # Rename .img to .dsk (raw container produces .img)
    if (Test-Path "$BuildDir\$OutputName.img") {
        Move-Item "$BuildDir\$OutputName.img" "$BuildDir\$OutputName.dsk" -Force
        $dsz = (Get-Item "$BuildDir\$OutputName.dsk").Length
        Write-Host "  OK: $OutputName.dsk ($([math]::Round($dsz/1024))K raw disk image)" -ForegroundColor Green
    }
    
    if (Test-Path "$BuildDir\$OutputName.map") {
        Write-Host "  Map: $BuildDir\$OutputName.map" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  FAILED - .com not produced" -ForegroundColor Red
    if (-not $Verbose) { Write-Host $result }
    exit 1
}

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
