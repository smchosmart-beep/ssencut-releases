# 쎈Cut Windows 실기 시험 (GitHub Actions windows-latest)
# 게시된 릴리스(wintest/args.txt의 태그, 없으면 latest)에서 전체 설치본·작은 업데이트를 받아:
#  1) Microsoft Defender 검사(설치 파일 2개)  2) 전체 설치 무인(/S) → 파일·레지스트리·바로 가기
#  3) 실행 → 실행기·Edge 편집 창(제목 "쎈Cut <버전>") 확인·화면 캡처
#  4) 쎈Cut이 열린 채로 작은 업데이트 --silent-update → 편집 창 닫기(앱의 [다시 시작해서 적용]과 같은 순서) → 교체·다시 열림 확인
#  5) 설치 폴더 Defender 검사  6) 제거 무인 → 지워졌는지  7) Defender 감지 기록
param([string]$Out = "$PWD/wintest-out")
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$log = Join-Path $Out 'log.txt'; $results = [ordered]@{}; $fails = 0
function Log($m) { $line = "[$(Get-Date -Format HH:mm:ss)] $m"; Write-Host $line; Add-Content -Path $log -Value $line -Encoding utf8 }
function Check($name, [bool]$ok, $detail = '') { $script:results[$name] = @{ ok = $ok; detail = "$detail" }; if (-not $ok) { $script:fails++ }; Log ("{0} {1} {2}" -f ($(if ($ok) { 'PASS' } else { 'FAIL' })), $name, $detail) }
function Shot($name) {
  try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds; $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
    $bmp.Save((Join-Path $Out "$name.png")); $g.Dispose(); $bmp.Dispose(); Log "화면 캡처 $name.png"
  } catch { Log "화면 캡처 실패: $_" }
}
function EditorWindows { Get-Process msedge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like '*쎈Cut*' } }
function Launchers { $p = Join-Path $env:LOCALAPPDATA 'SsenCut\SsenCut.exe'; Get-Process SsenCut -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -eq $p } catch { $false } } }
function WaitFor([scriptblock]$cond, [int]$sec) { $t = 0; while ($t -lt $sec * 2) { if (& $cond) { return $true }; Start-Sleep -Milliseconds 500; $t++ }; return $false }
function Scan($path, $name) {
  $mp = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
  if (-not (Test-Path $mp)) { Log "MpCmdRun 없음"; return }
  $o = & $mp -Scan -ScanType 3 -File $path -DisableRemediation 2>&1 | Out-String; $code = $LASTEXITCODE
  Add-Content -Path (Join-Path $Out 'defender-scan.txt') -Value "== $name ($path) exit=$code`n$o" -Encoding utf8
  Check "Defender 검사: $name" ($code -eq 0) "exit=$code $((($o -split "`n") | Where-Object { $_ -match 'threat|Threat|found' }) -join ' / ')"
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$tag = if (Test-Path (Join-Path $here 'args.txt')) { (Get-Content (Join-Path $here 'args.txt') -Raw).Trim() } else { '' }
$repo = 'smchosmart-beep/ssencut-releases'
$manUrl = if ($tag) { "https://github.com/$repo/releases/download/$tag/ssencut-update.json" } else { "https://github.com/$repo/releases/latest/download/ssencut-update.json" }
Log "Windows: $((Get-CimInstance Win32_OperatingSystem).Caption) $([Environment]::OSVersion.Version)  매니페스트: $manUrl"
$raw = Invoke-RestMethod $manUrl; $m = $raw.signed | ConvertFrom-Json; $V = $m.version
Log "버전 $V  small $($m.small.size)B  full $($m.full.size)B"
$dl = Join-Path $env:RUNNER_TEMP 'ssencut-dl'; New-Item -ItemType Directory -Force -Path $dl | Out-Null
$full = Join-Path $dl ($m.full.url -split '/')[-1]; $small = Join-Path $dl ($m.small.url -split '/')[-1]
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest $m.full.url -OutFile $full; Invoke-WebRequest $m.small.url -OutFile $small
Check '전체 설치본 받기·SHA-256' ((Get-FileHash $full -Algorithm SHA256).Hash.ToLower() -eq $m.full.sha256) $full
Check '작은 업데이트 받기·SHA-256' ((Get-FileHash $small -Algorithm SHA256).Hash.ToLower() -eq $m.small.sha256) $small

# 1) Defender
try {
  $st = Get-MpComputerStatus; Log "Defender: AMService=$($st.AMServiceEnabled) 실시간=$($st.RealTimeProtectionEnabled) 서명=$($st.AntivirusSignatureVersion) ($($st.AntivirusSignatureLastUpdated))"
  $pref = Get-MpPreference; Log "클라우드 보호(MAPS)=$($pref.MAPSReporting) 샘플 제출=$($pref.SubmitSamplesConsent)"
  try { Update-MpSignature -ErrorAction Stop; Log "Defender 서명 업데이트 후: $((Get-MpComputerStatus).AntivirusSignatureVersion)" } catch { Log "서명 업데이트 실패: $_" }
} catch { Log "Defender 상태 확인 실패: $_" }
Scan $full '전체 설치본'; Scan $small '작은 업데이트'

# 2) 전체 설치(무인)
$inst = Join-Path $env:LOCALAPPDATA 'SsenCut'; $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\SsenCut'
$p = Start-Process $full -ArgumentList '/S' -PassThru -Wait
Check '전체 설치 종료 코드 0' ($p.ExitCode -eq 0) "exit=$($p.ExitCode)"
$need = @('SsenCut.exe', 'Uninstall.exe', 'README-KO.txt', 'app\index.html', 'app\assets.js', 'app\update-ui.js', 'engine\ssen-mr.exe', 'engine\ssen-align.exe', 'engine\manifest.txt', 'engine\omniasr-ctc-300m-int8.onnx', 'licenses')
$missing = $need | Where-Object { -not (Test-Path (Join-Path $inst $_)) }
Check '설치 파일' (-not $missing) ("없음: " + ($missing -join ', '))
$exeSize = (Get-Item (Join-Path $inst 'SsenCut.exe')).Length; Check '실행기는 작은 exe(앱을 품지 않음)' ($exeSize -lt 1MB) "$exeSize B"
$reg = Get-ItemProperty $key -ErrorAction SilentlyContinue
Check '앱 목록 등록' ($reg -and $reg.DisplayVersion -eq $V -and $reg.Publisher -eq 'Ssen Tools') "$($reg.DisplayName) $($reg.DisplayVersion) $($reg.Publisher) $($reg.EstimatedSize)KB"
$desk = [Environment]::GetFolderPath('Desktop'); $progs = [Environment]::GetFolderPath('Programs')
Check '바로 가기(바탕화면·시작 메뉴)' ((Test-Path (Join-Path $desk '쎈Cut.lnk')) -and (Test-Path (Join-Path $progs '쎈Cut.lnk')))
try { $it = (New-Object -ComObject Shell.Application).NameSpace($desk).ParseName('쎈Cut.lnk'); $lnk = $it.GetLink; Check '바로 가기 대상' ($lnk.Path -eq (Join-Path $inst 'SsenCut.exe')) "$($lnk.Path) / 작업 폴더 $($lnk.WorkingDirectory)" } catch { Log "바로 가기 읽기 실패: $_" }
Get-ChildItem $inst -Recurse -File | Measure-Object Length -Sum | ForEach-Object { Log "설치 폴더 $($_.Count)개 파일, $([math]::Round($_.Sum/1MB))MB" }

# 3) 실행
Start-Process (Join-Path $inst 'SsenCut.exe') -WorkingDirectory $inst
$ok = WaitFor { (Launchers) -and (EditorWindows) } 40
$w = EditorWindows | Select-Object -First 1
Check '실행: 실행기 + Edge 편집 창' $ok "창 제목: $($w.MainWindowTitle)"
Check '창 제목에 버전' ($w -and $w.MainWindowTitle -like "*쎈Cut $V*") "$($w.MainWindowTitle)"
Check 'edge-path.txt' (Test-Path (Join-Path $inst 'edge-path.txt')) "$(Get-Content (Join-Path $inst 'edge-path.txt') -ErrorAction SilentlyContinue)"
Start-Sleep 5; Shot '1-editor'
Start-Sleep 15  # 시작 15초 뒤 업데이트 확인(같은 버전이면 알림 없음)
Shot '2-after-update-check'
$settings = Join-Path $inst 'update-settings.json'
Log "update-settings.json: $(Get-Content $settings -Raw -ErrorAction SilentlyContinue)"

# 4) 작은 업데이트(쎈Cut이 연 것처럼 --silent-update) → 편집 창 닫기 → 교체·다시 열림
$before = (Launchers | Select-Object -First 1).Id
$up = Start-Process $small -ArgumentList '--silent-update' -PassThru
Start-Sleep 2
Check '작은 업데이트가 쎈Cut이 닫히길 기다림' (-not $up.HasExited) ''
EditorWindows | ForEach-Object { [void]$_.CloseMainWindow() }
$done = WaitFor { $up.HasExited } 90
Check '작은 업데이트 끝남·종료 코드 0' ($done -and $up.ExitCode -eq 0) "exit=$($up.ExitCode)"
$re = WaitFor { (Launchers | Where-Object { $_.Id -ne $before }) -and (EditorWindows) } 40
Check '업데이트 뒤 쎈Cut 다시 열림' $re "$((EditorWindows | Select-Object -First 1).MainWindowTitle)"
$left = @('app.new', 'app.old', 'SsenCut.exe.new', 'SsenCut.exe.bak', 'payload-version.txt') | Where-Object { Test-Path (Join-Path $inst $_) }
Check '임시 파일 정리' (-not $left) ($left -join ', ')
Check '업데이트 뒤 앱 파일' ((Test-Path (Join-Path $inst 'app\index.html')) -and (Test-Path (Join-Path $inst 'app\assets.js'))) ''
Start-Sleep 3; Shot '3-after-small-update'

# 5) 설치 폴더 검사
Scan $inst '설치 폴더'

# 6) 제거
EditorWindows | ForEach-Object { [void]$_.CloseMainWindow() }
[void](WaitFor { -not (Launchers) } 20)
$u = Start-Process (Join-Path $inst 'Uninstall.exe') -ArgumentList '/S' -PassThru -Wait
$gone = WaitFor { -not (Test-Path (Join-Path $inst 'app')) -and -not (Test-Path (Join-Path $inst 'SsenCut.exe')) } 60
Check '제거: 앱·엔진·실행기 지움' ($gone -and -not (Test-Path (Join-Path $inst 'engine'))) "남은 것: $((Get-ChildItem $inst -ErrorAction SilentlyContinue).Name -join ', ')"
Check '제거: 앱 목록·바로 가기' (-not (Test-Path $key) -and -not (Test-Path (Join-Path $desk '쎈Cut.lnk'))) ''

# 7) Defender 감지 기록
try { $det = Get-MpThreatDetection -ErrorAction Stop; $det | Format-List * | Out-String | Set-Content (Join-Path $Out 'defender-detections.txt') -Encoding utf8
  Check 'Defender 감지 기록 없음' (-not ($det | Where-Object { $_.Resources -match 'SsenCut|ssencut|ssen-' })) "$(@($det).Count)건(전체)" } catch { Log "감지 기록 없음/확인 불가: $_"; $results['Defender 감지 기록 없음'] = @{ ok = $true; detail = 'none' } }

$results | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $Out 'results.json') -Encoding utf8
Log ("결과: 실패 {0}건 / {1}개" -f $fails, $results.Count)
exit 0
