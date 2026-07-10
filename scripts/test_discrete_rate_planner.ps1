$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$srcDir = Join-Path $repoRoot 'vitis_bringup\bringup\src'
$testDir = Join-Path $repoRoot 'vitis_bringup\bringup\tests'
$outDir = Join-Path $env:TEMP 'laser_tx_rate_planner_test'
$exe = Join-Path $outDir 'test_gt_rate_plan.exe'

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
gcc -std=c99 -Wall -Wextra -Werror -DGT_RATE_PLAN_HOST_TEST `
    -I $srcDir `
    (Join-Path $srcDir 'gt_rate_plan.c') `
    (Join-Path $testDir 'test_gt_rate_plan.c') `
    -o $exe
& $exe
