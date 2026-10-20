param([switch]$Native, [string]$Python = 'python')
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
    moon build --target js --release
    if ($LASTEXITCODE -ne 0) { throw 'JavaScript CLI build failed' }
    & $Python -X utf8 scripts/interop.py
    if ($LASTEXITCODE -ne 0) { throw 'Interoperability failed' }
    & $Python -X utf8 scripts/compatibility_cases.py --download-official
    if ($LASTEXITCODE -ne 0) { throw 'Cross-encoding compatibility failed' }
    & $Python -X utf8 scripts/review_regressions.py
    if ($LASTEXITCODE -ne 0) { throw 'Independent precision regressions failed' }
    & $Python -X utf8 scripts/verify_consumer.py
    if ($LASTEXITCODE -ne 0) { throw 'External public API consumer failed' }
    $codeMetrics = & $Python -X utf8 scripts/count_code.py
    if ($LASTEXITCODE -ne 0) { throw 'Code count failed' }
    $codeMetrics | Set-Content -LiteralPath 'artifacts\code-count.json' -Encoding utf8
    ($codeMetrics -join "`n" | ConvertFrom-Json).totals | Format-Table
    moon package --list | Set-Content -LiteralPath 'artifacts\package-manifest.txt' -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw 'Source package file listing failed' }
    moon package
    if ($LASTEXITCODE -ne 0) { throw 'Source packaging failed' }
    & $Python -X utf8 scripts/check_package.py
    if ($LASTEXITCODE -ne 0) { throw 'Source archive integrity check failed' }
} finally {
    $env:MOON_HOME = $savedMoonHome
    $env:PATH = $savedPath
    Pop-Location
}
