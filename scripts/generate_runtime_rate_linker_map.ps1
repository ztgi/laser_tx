param(
    [string]$Workspace = "",
    [string]$Compiler = "D:\Vitis\2022.2\gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = Join-Path $repo "reports\runtime_rate_vitis"
}

$debugDir = Join-Path $Workspace "bringup\Debug"
$elf = Join-Path $debugDir "bringup.elf"
$map = Join-Path $debugDir "bringup.map"
$tempElf = Join-Path $debugDir "bringup.map_only.elf"
$linkerScript = Join-Path $Workspace "bringup\src\lscript.ld"
$bspLib = Join-Path $Workspace "runtime_rate_artifact_platform\export\runtime_rate_artifact_platform\sw\runtime_rate_artifact_platform\standalone_ps7_cortexa9_0\bsplib\lib"
$objectsFile = Join-Path $debugDir "objects.mk"
$subdirFile = Join-Path $debugDir "src\subdir.mk"

foreach ($path in @($Compiler, $elf, $linkerScript, $objectsFile, $subdirFile, $bspLib)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required map input is missing: $path"
    }
}

$objectsText = Get-Content -LiteralPath $objectsFile -Raw
if ($objectsText -notmatch '(?m)^USER_OBJS\s*:=\s*$') {
    throw "Managed USER_OBJS is not empty"
}

$subdirText = Get-Content -LiteralPath $subdirFile -Raw
$objectMatches = [regex]::Matches($subdirText, '(?m)^\./src/[^\s\\]+\.o')
$objects = @($objectMatches | ForEach-Object {
    Get-Item -LiteralPath (Join-Path $debugDir $_.Value)
})
if ($objects.Count -ne 16) {
    throw "Expected 16 managed objects, found $($objects.Count)"
}

$arguments = @(
    "-mcpu=cortex-a9",
    "-mfpu=vfpv3",
    "-mfloat-abi=hard",
    "-Wl,-build-id=none",
    "-specs=Xilinx.spec",
    "-Wl,-T",
    "-Wl,$linkerScript",
    "-L$bspLib",
    "-Wl,-Map=$map",
    "-o",
    $tempElf
)
$arguments += $objects.FullName
$arguments += @(
    "-Wl,--start-group,-lxil,-lgcc,-lc,--end-group",
    "-Wl,--start-group,-lxil,-llwip4,-lgcc,-lc,--end-group"
)

Push-Location $debugDir
try {
    & $Compiler @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Map-only relink failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$managedHash = (Get-FileHash -LiteralPath $elf -Algorithm SHA256).Hash
$mapOnlyHash = (Get-FileHash -LiteralPath $tempElf -Algorithm SHA256).Hash
if ($managedHash -ne $mapOnlyHash) {
    throw "Map-only relink changed ELF content: managed=$managedHash map_only=$mapOnlyHash"
}

Remove-Item -LiteralPath $tempElf -Force
Write-Output "RUNTIME_RATE_LINKER_MAP=PASS"
Write-Output "managed_objects=$($objects.Count)"
Write-Output "user_objs=EMPTY"
Write-Output "elf_sha256=$managedHash"
Write-Output "map=$map"
