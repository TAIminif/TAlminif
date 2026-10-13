param([switch]$Native)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$isolatedRoot = Join-Path $projectRoot '.tools\moon-20261012'
$savedMoonHome = $env:MOON_HOME
$savedPath = $env:PATH
Push-Location -LiteralPath $projectRoot
try {
    if (Test-Path -LiteralPath (Join-Path $isolatedRoot 'bin\moon.exe')) {
        $env:MOON_HOME = $isolatedRoot
        $env:PATH = (Join-Path $isolatedRoot 'bin') + ';' + $env:PATH
    }
    moon version
    moon fmt --check
    if ($LASTEXITCODE -ne 0) { throw 'Formatting check failed' }
    moon check --deny-warn
    if ($LASTEXITCODE -ne 0) { throw 'Core check failed' }
    moon check --target js --deny-warn
    if ($LASTEXITCODE -ne 0) { throw 'JS check failed' }
    moon build
    if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
    foreach ($backend in @('wasm-gc', 'wasm', 'js')) {
        moon test --target $backend
        if ($LASTEXITCODE -ne 0) { throw "Tests failed: $backend" }
    }
    if ($Native) {
        moon test --target native
        if ($LASTEXITCODE -ne 0) { throw 'Native tests failed' }
    }
    moon run examples/memory
    if ($LASTEXITCODE -ne 0) { throw 'Example failed' }
    python -X utf8 scripts/interop.py
    if ($LASTEXITCODE -ne 0) { throw 'Interoperability failed' }
    $codeMetrics = python -X utf8 scripts/count_code.py
    if ($LASTEXITCODE -ne 0) { throw 'Code count failed' }
    $codeMetrics | Set-Content -LiteralPath 'artifacts\code-count.json' -Encoding utf8
    ($codeMetrics -join "`n" | ConvertFrom-Json).totals | Format-Table
} finally {
    $env:MOON_HOME = $savedMoonHome
    $env:PATH = $savedPath
    Pop-Location
}
