# 로그챌린지 웹(PWA) 빌드 → keywordream_web/keepup 사이트의 /app/ 으로 복사한다.
#
#   실행:  powershell -ExecutionPolicy Bypass -File tool\build_web.ps1
#   배포:  cd E:\app\keywordream_web\keepup ; npm run deploy
#
# 결과 주소: https://log.keywordream.com/app/
#
# 참고: 앱 아이콘을 바꿨다면 먼저 `dart run tool/gen_web_icons.dart` 를 돌린다.

$ErrorActionPreference = 'Stop'

$appRoot  = Split-Path -Parent $PSScriptRoot
$siteApp  = 'E:\app\keywordream_web\keepup\public\app'
$baseHref = '/app/'

Write-Host "▶ Flutter 웹 빌드 (base-href $baseHref)" -ForegroundColor Cyan
Push-Location $appRoot
try {
    flutter build web --release --base-href $baseHref --no-wasm-dry-run
    if ($LASTEXITCODE -ne 0) { throw "flutter build web 실패 (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}

$buildWeb = Join-Path $appRoot 'build\web'

# dart2js(JS) 빌드는 canvaskit만 쓴다 — wasm 전용/실험용 런타임과 디버그 심볼은 뺀다(약 21MB 절약)
Write-Host "▶ 안 쓰는 런타임 파일 정리" -ForegroundColor Cyan
$prune = @(
    'canvaskit\skwasm.js', 'canvaskit\skwasm.wasm', 'canvaskit\skwasm.js.symbols',
    'canvaskit\skwasm_heavy.js', 'canvaskit\skwasm_heavy.wasm', 'canvaskit\skwasm_heavy.js.symbols',
    'canvaskit\wimp.js', 'canvaskit\wimp.wasm', 'canvaskit\wimp.js.symbols',
    'canvaskit\canvaskit.js.symbols', 'canvaskit\chromium\canvaskit.js.symbols',
    'canvaskit\experimental_webparagraph'
)
foreach ($p in $prune) {
    $full = Join-Path $buildWeb $p
    if (Test-Path $full) { Remove-Item $full -Recurse -Force }
}

Write-Host "▶ $siteApp 로 복사" -ForegroundColor Cyan
if (Test-Path $siteApp) { Remove-Item $siteApp -Recurse -Force }
New-Item -ItemType Directory -Path $siteApp -Force | Out-Null
Copy-Item (Join-Path $buildWeb '*') $siteApp -Recurse -Force

$mb = [math]::Round((Get-ChildItem $siteApp -Recurse -File | Measure-Object Length -Sum).Sum / 1MB, 1)
Write-Host "√ 완료 — $siteApp ($mb MB)" -ForegroundColor Green
Write-Host "  다음: cd E:\app\keywordream_web\keepup ; npm run deploy" -ForegroundColor Green
