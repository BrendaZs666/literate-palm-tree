#requires -version 5.1
<#
    一键把「萨克斯社」网页上传到 GitHub 仓库并等待 Pages 部署完成
    仓库：BrendaZs666/literate-palm-tree   分支：main

    使用方法（二选一）：
      1) 右键本文件 → “使用 PowerShell 运行”
      2) 在本文件夹地址栏输入 powershell 回车，然后执行：
         powershell -ExecutionPolicy Bypass -File ".\一键上传到GitHub.ps1"

    需要先准备：一个 GitHub 个人访问令牌（classic，勾选 repo 权限）
      GitHub → 右上头像 → Settings → Developer settings
        → Personal access tokens → Tokens (classic)
        → Generate new token (classic) → 勾选 repo → Generate → 复制 ghp_ 开头的一串

    注意：本机需要能访问 github.com（开着代理/加速器再运行）。
#>

$ErrorActionPreference = 'Stop'
$Owner  = 'BrendaZs666'
$Repo   = 'literate-palm-tree'
$Branch = 'main'
$Api    = "https://api.github.com/repos/$Owner/$Repo"

# 要上传的文件（当前脚本所在目录下的这些文件）
$Files = @(
    'zhao-0124-work2.html',
    'club_intro.html',
    'music.mp3',
    'video.mp4',
    'sax-club.jpg',
    'sax-band.jpg',
    '.nojekyll'
)

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ''
Write-Host '=== 萨克斯社网页 · 一键上传 ===' -ForegroundColor Cyan
Write-Host "仓库：$Owner/$Repo  分支：$Branch"
Write-Host ''

# ---------- 1. 取令牌 ----------
$Token = Read-Host '请粘贴 GitHub 令牌（输入时不显示），回车确认'
$Token = $Token.Trim()
if ([string]::IsNullOrWhiteSpace($Token)) { Write-Host '没有输入令牌，已退出。' -ForegroundColor Red; exit 1 }

$Headers = @{
    Authorization          = "Bearer $Token"
    Accept                 = 'application/vnd.github+json'
    'User-Agent'           = 'sax-club-uploader'
    'X-GitHub-Api-Version' = '2022-11-28'
}

# ---------- 2. 验证令牌 ----------
try {
    $me = Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers $Headers -TimeoutSec 30
    Write-Host "已登录：$($me.login)" -ForegroundColor Green
} catch {
    Write-Host '令牌无效或网络不通：' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor DarkRed
    Write-Host '请检查：①令牌是否复制完整 ②是否开着代理/加速器 ③令牌是否勾了 repo 权限' -ForegroundColor Yellow
    exit 1
}

# ---------- 3. 逐个上传 ----------
function Send-File([string]$Path) {
    $name = Split-Path $Path -Leaf
    $enc  = [uri]::EscapeDataString($name)
    $url  = "${Api}/contents/$enc"

    $sha = $null
    try {
        $info = Invoke-RestMethod -Uri "$url`?ref=$Branch" -Headers $Headers -TimeoutSec 30
        $sha  = $info.sha
    } catch {
        $sha = $null   # 文件还不存在
    }

    $bytes  = [System.IO.File]::ReadAllBytes((Join-Path $Root $Path))
    $b64    = [Convert]::ToBase64String($bytes)
    $action = if ($sha) { '更新' } else { '新增' }

    $body = @{
        message = "upload $name"
        content = $b64
        branch  = $Branch
    }
    if ($sha) { $body.sha = $sha }

    $json = $body | ConvertTo-Json -Compress
    $res  = Invoke-RestMethod -Uri $url -Method Put -Headers $Headers -Body ([Text.Encoding]::UTF8.GetBytes($json)) -ContentType 'application/json' -TimeoutSec 300
    Write-Host ("  [{0}] {1}  ({2:N1} KB)" -f $action, $name, ($bytes.Length / 1KB)) -ForegroundColor Green
}

foreach ($f in $Files) {
    if (-not (Test-Path (Join-Path $Root $f))) {
        Write-Host "  [跳过] $f 不存在" -ForegroundColor Yellow
        continue
    }
    Send-File $f
}

# ---------- 4. 等待 Pages 部署 ----------
Write-Host ''
Write-Host '文件已提交，正在等待 GitHub Pages 重新部署……' -ForegroundColor Cyan

$deadline = (Get-Date).AddMinutes(12)
$lastId   = $null
$done     = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 10
    try {
        $runs = Invoke-RestMethod -Uri "${Api}/actions/runs?branch=$Branch&per_page=1" -Headers $Headers -TimeoutSec 30
        $run  = $runs.workflow_runs[0]
        if (-not $run) { Write-Host '  还没有出现构建记录，继续等……'; continue }
        if ($run.id -ne $lastId) {
            $lastId = $run.id
            Write-Host ("  最新构建 #{0}：{1}" -f $run.run_number, $run.status)
        }
        if ($run.status -eq 'completed') {
            Write-Host ''
            if ($run.conclusion -eq 'success') {
                Write-Host '部署成功！' -ForegroundColor Green
                Write-Host "页面地址：https://$($Owner.ToLower()).github.io/$Repo/zhao-0124-work2.html" -ForegroundColor Cyan
                Write-Host "介绍页：  https://$($Owner.ToLower()).github.io/$Repo/club_intro.html" -ForegroundColor Cyan
            } else {
                Write-Host "部署失败（$($run.conclusion)）。" -ForegroundColor Red
                Write-Host "请打开日志查看原因：$($run.html_url)" -ForegroundColor Yellow
                Write-Host '常见处理：到 Actions 页面点 “Re-run all jobs” 再试一次。' -ForegroundColor Yellow
            }
            $done = $true
            break
        }
        Write-Host ("  正在进行：{0}" -f $run.status)
    } catch {
        Write-Host "  查询构建状态出错：$($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

if (-not $done) {
    Write-Host ''
    Write-Host '等待超时，请手动到 Actions 页面查看：' -ForegroundColor Yellow
    Write-Host "https://github.com/$Owner/$Repo/actions" -ForegroundColor Yellow
}

Write-Host ''
Read-Host '按回车键关闭窗口'
