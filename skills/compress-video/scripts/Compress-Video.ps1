# Compress-Video.ps1 — ffmpeg two-pass 壓縮，預設目標 10 MB
param(
    [Parameter(Mandatory)][string]$InputPath,
    [string]$OutputPath = "",
    [double]$TargetMB = 10.0,
    [int]$AudioKbps = 128
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 確認輸入檔
$InputPath = (Resolve-Path $InputPath).Path
if (-not (Test-Path $InputPath)) { Write-Error "找不到輸入檔：$InputPath"; exit 1 }

# 決定輸出路徑
if (-not $OutputPath) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
    $ext  = [System.IO.Path]::GetExtension($InputPath)
    $dir  = [System.IO.Path]::GetDirectoryName($InputPath)
    $OutputPath = Join-Path $dir "${base}_compressed${ext}"
}

# 源檔已在目標大小以下 → 不需壓縮
$origSize = (Get-Item $InputPath).Length
$origMB   = [math]::Round($origSize / 1MB, 2)
if ($origSize -le $TargetMB * 1024 * 1024) {
    Write-Host "  原始 ${origMB} MB 已低於目標 ${TargetMB} MB，不需壓縮。"
    exit 0
}
Write-Host "  原始     : ${origMB} MB（目標 ${TargetMB} MB）"

# 確認 ffmpeg / ffprobe 可用
foreach ($cmd in @('ffmpeg','ffprobe')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "$cmd 不在 PATH。請先安裝：winget install Gyan.FFmpeg"
        exit 1
    }
}

# 取得影片時長（秒）
$durationStr = & ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $InputPath 2>$null
if ($durationStr -and $durationStr.Trim() -match '^\d') {
    $durationSec = [double]$durationStr.Trim()
} else {
    # fallback: parse ffmpeg -i stderr
    $info = & ffmpeg -i $InputPath 2>&1 | Out-String
    if ($info -match 'Duration:\s+(\d+):(\d+):([\d.]+)') {
        $durationSec = [int]$Matches[1]*3600 + [int]$Matches[2]*60 + [double]$Matches[3]
    } else {
        Write-Error "無法取得影片時長"; exit 1
    }
}
Write-Host "  時長     : $([math]::Round($durationSec, 1)) 秒"

# 計算目標 video bitrate（留 2% buffer 防容器 overhead 超標）
# target_bits = TargetMB * 0.98 * 1024 * 1024 * 8
# video_kbps  = (target_bits / duration_sec / 1000) - AudioKbps
$targetBits = $TargetMB * 0.98 * 1024 * 1024 * 8
$totalKbps  = $targetBits / $durationSec / 1000
$videoKbps  = [int]($totalKbps - $AudioKbps)

if ($videoKbps -le 0) {
    Write-Error "影片時長 $([math]::Round($durationSec))s 過長，純音訊碼率已超過 ${TargetMB}MB 上限，無法壓縮"
    exit 1
}
Write-Host "  目標碼率 : $([math]::Round($totalKbps,1)) kbps（視訊 ${videoKbps}k + 音訊 ${AudioKbps}k）"

# Two-pass encode
$passLog = Join-Path ([System.IO.Path]::GetTempPath()) "ffmpeg2pass-$(Get-Random)"

try {
    Write-Host "  Pass 1..."
    & ffmpeg -y -i $InputPath -c:v libx264 -b:v "${videoKbps}k" -pass 1 -passlogfile $passLog -an -f null NUL 2>&1 |
        Where-Object { $_ -match 'frame=' } | Select-Object -Last 1

    Write-Host "  Pass 2..."
    & ffmpeg -y -i $InputPath -c:v libx264 -b:v "${videoKbps}k" -pass 2 -passlogfile $passLog `
        -c:a aac -b:a "${AudioKbps}k" $OutputPath 2>&1 |
        Where-Object { $_ -match 'frame=' } | Select-Object -Last 1
} finally {
    Remove-Item "${passLog}-0.log*" -ErrorAction SilentlyContinue
}

# 回報
$origMB = [math]::Round($origSize / 1MB, 2)
$outMB  = [math]::Round((Get-Item $OutputPath).Length / 1MB, 2)
Write-Host ""
Write-Host "  原始     : ${origMB} MB"
Write-Host "  壓縮後   : ${outMB} MB"
Write-Host "  輸出     : $OutputPath"

if ($outMB -gt $TargetMB) {
    Write-Warning "結果 ${outMB} MB 仍超過目標 ${TargetMB} MB（影片過長或 libx264 最低碼率限制）"
    Write-Warning "建議降解析度後重壓，例如在 ffmpeg 加上 -vf scale=1280:-2"
} else {
    Write-Host "  [OK] 已壓縮至 ${TargetMB} MB 以下"
}
