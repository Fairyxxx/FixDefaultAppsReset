<#
.SYNOPSIS
    Windows 默认应用重置终极修复工具 v3.0（集成 SetUserFTA）
.DESCRIPTION
    支持浏览器、压缩软件、视频播放器三类默认应用设置
    使用 SetUserFTA 正确计算哈希，配合策略锁定防止重置
#>

# 检查管理员权限
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "⚠️  请以管理员身份运行！" -ForegroundColor Yellow
    pause
    exit 1
}

chcp 65001 | Out-Null
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$setuserftaPath = Join-Path $scriptDir "SetUserFTA.exe"
$backupDir = Join-Path $scriptDir "备份"

if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
}

# ==================== 工具下载 ====================
function Download-SetUserFTA {
    if (Test-Path $setuserftaPath) {
        Write-Host "✅ SetUserFTA 已就绪" -ForegroundColor Green
        return $true
    }
    
    Write-Host "`n📥 正在下载 SetUserFTA 工具..." -ForegroundColor Cyan
    
    $downloadUrls = @(
        "https://kolbi.cz/SetUserFTA.zip"
    )
    
    $zipPath = Join-Path $scriptDir "SetUserFTA.zip"
    $downloadSuccess = $false
    
    foreach ($url in $downloadUrls) {
        try {
            Write-Host "   尝试下载源: $url" -ForegroundColor Gray
            
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "Mozilla/5.0")
            
            $progressEvent = Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -Action {
                $percent = $eventArgs.ProgressPercentage
                $received = [math]::Round($eventArgs.BytesReceived / 1KB, 1)
                $total = [math]::Round($eventArgs.TotalBytesToReceive / 1KB, 1)
                Write-Progress -Activity "下载中" -Status "$percent% ($received KB / $total KB)" -PercentComplete $percent
            }
            
            $completedEvent = Register-ObjectEvent -InputObject $webClient -EventName DownloadFileCompleted -Action {
                Write-Progress -Activity "下载中" -Completed
            }
            
            $webClient.DownloadFileAsync([Uri]$url, $zipPath)
            
            while ($webClient.IsBusy) {
                Start-Sleep -Milliseconds 100
            }
            
            Unregister-Event -SourceIdentifier $progressEvent.Name -ErrorAction SilentlyContinue
            Unregister-Event -SourceIdentifier $completedEvent.Name -ErrorAction SilentlyContinue
            $webClient.Dispose()
            
            # 检查文件是否有效
            if (Test-Path $zipPath -and (Get-Item $zipPath).Length -gt 1000) {
                $downloadSuccess = $true
                break
            }
        }
        catch {
            Write-Progress -Activity "下载中" -Completed
            Write-Host "   该源下载失败，尝试下一个..." -ForegroundColor DarkGray
        }
    }
    
    if ($downloadSuccess) {
        Write-Host "`n📦 正在解压..." -ForegroundColor Cyan
        Expand-Archive -Path $zipPath -DestinationPath $scriptDir -Force
        Remove-Item $zipPath -Force
        
        if (Test-Path $setuserftaPath) {
            Write-Host "✅ 下载完成" -ForegroundColor Green
            return $true
        }
    }
    
    # 所有源都失败，给出手动下载指引
    Write-Host "`n❌ 自动下载失败" -ForegroundColor Red
    Write-Host ""
    Write-Host "📝 请手动下载：" -ForegroundColor Yellow
    Write-Host "   地址1（官网）: https://kolbi.cz/SetUserFTA.zip" -ForegroundColor White
    Write-Host "   地址2（蓝奏云）: https://wwtv.lanzouv.com/io1qA2n4uhpc" -ForegroundColor White
    Write-Host ""
    Write-Host "   解压后把 SetUserFTA.exe 放到以下目录，再重新运行脚本：" -ForegroundColor Yellow
    Write-Host "   $scriptDir" -ForegroundColor Cyan
    Write-Host ""
    
    return $false
}

# ==================== 应用检测 ====================
function Get-InstalledApps {
    param([string]$category)
    
    $apps = @()
    $appPaths = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths"
    $appPaths32 = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths"
    
    switch ($category) {
        "browser" {
            $definitions = @(
                @{ Name = "Chrome"; Exe = "chrome.exe"; ProgId = "ChromeHTML" },
                @{ Name = "Edge"; Exe = "msedge.exe"; ProgId = "MSEdgeHTM" },
                @{ Name = "Firefox"; Exe = "firefox.exe"; ProgId = "FirefoxURL-308046B0AF4A39CB" }
            )
        }
        "archive" {
            $definitions = @(
                @{ Name = "WinRAR"; Exe = "WinRAR.exe"; ProgId = "WinRAR" },
                @{ Name = "7-Zip"; Exe = "7zFM.exe"; ProgId = "7-Zip" },
                @{ Name = "Bandizip"; Exe = "Bandizip.exe"; ProgId = "Bandizip" }
            )
        }
        "video" {
            $definitions = @(
                @{ Name = "PotPlayer"; Exe = "PotPlayerMini64.exe"; ProgId = "PotPlayer" },
                @{ Name = "VLC"; Exe = "vlc.exe"; ProgId = "VLC" },
                @{ Name = "MPC-HC"; Exe = "mpc-hc64.exe"; ProgId = "mpc-hc" }
            )
        }
    }
    
    foreach ($def in $definitions) {
        $found = $false
        if (Test-Path "$appPaths\$($def.Exe)") { $found = $true }
        elseif (Test-Path "$appPaths32\$($def.Exe)") { $found = $true }
        
        # 也检查常见安装目录
        if (-not $found) {
            $commonPaths = @(
                "$env:ProgramFiles\$($def.Name)\$($def.Exe)",
                "${env:ProgramFiles(x86)}\$($def.Name)\$($def.Exe)",
                "$env:ProgramFiles\$($def.Name)\$($def.Name).exe"
            )
            foreach ($p in $commonPaths) {
                if (Test-Path $p) { $found = $true; break }
            }
        }
        
        if ($found) {
            $apps += @{ Name = $def.Name; ProgId = $def.ProgId }
        }
    }
    
    return $apps
}

# ==================== 设置函数 ====================
function Set-Associations {
    param(
        [string]$ProgId,
        [string[]]$Extensions,
        [string]$CategoryName
    )
    
    Write-Host "`n🔧 正在设置默认$CategoryName..." -ForegroundColor Cyan
    $success = 0
    
    foreach ($ext in $Extensions) {
        $result = & $setuserftaPath $ext $ProgId 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   ✓ $ext" -ForegroundColor Gray
            $success++
        }
    }
    
    Write-Host "✅ $CategoryName设置完成（$success 个关联）" -ForegroundColor Green
}

function Set-DefaultBrowser {
    param([string]$ProgId)
    $exts = @("http", "https", ".htm", ".html", ".pdf")
    Set-Associations -ProgId $ProgId -Extensions $exts -CategoryName "浏览器"
}

function Set-DefaultArchiver {
    param([string]$ProgId)
    $exts = @(".zip", ".rar", ".7z", ".tar", ".gz", ".bz2", ".xz", ".iso", ".cab")
    Set-Associations -ProgId $ProgId -Extensions $exts -CategoryName "压缩软件"
}

function Set-DefaultVideoPlayer {
    param([string]$ProgId)
    $exts = @(".mp4", ".mkv", ".avi", ".mov", ".flv", ".wmv", ".webm", ".m4v", ".mpg", ".mpeg")
    Set-Associations -ProgId $ProgId -Extensions $exts -CategoryName "视频播放器"
}

# ==================== 防重置策略 ====================
function Enable-NoResetPolicy {
    Write-Host "`n🔒 正在启用防重置策略..." -ForegroundColor Cyan
    
    # NoOpenWith 策略 - 阻止系统强制重置
    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
    if (-not (Test-Path $policyPath)) {
        New-Item -Path $policyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $policyPath -Name "NoOpenWith" -Value 1 -Type DWord -Force
    Write-Host "   ✓ NoOpenWith 策略（阻止系统重置）" -ForegroundColor Gray
    
    # 禁用 Edge 强制接管
    $edgePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main"
    if (-not (Test-Path $edgePolicy)) {
        New-Item -Path $edgePolicy -Force | Out-Null
    }
    Set-ItemProperty -Path $edgePolicy -Name "PreventFirstRunDefaultBrowserPrompt" -Value 1 -Type DWord -Force
    Write-Host "   ✓ 禁用Edge默认浏览器提示" -ForegroundColor Gray
    
    # 禁用应用体验计划任务
    $taskPaths = @(
        "\Microsoft\Windows\Application Experience\"
    )
    $disabled = 0
    foreach ($path in $taskPaths) {
        try {
            Get-ScheduledTask -TaskPath $path -ErrorAction Stop | Where-Object { $_.State -ne 'Disabled' } | ForEach-Object {
                Disable-ScheduledTask -TaskPath $path -TaskName $_.TaskName -ErrorAction SilentlyContinue | Out-Null
                $disabled++
            }
        } catch {}
    }
    Write-Host "   ✓ 禁用应用体验任务（$disabled 个）" -ForegroundColor Gray
    
    Write-Host "✅ 防重置策略已全部启用" -ForegroundColor Green
}

# ==================== 辅助功能 ====================
function Clear-CorruptedUserChoice {
    Write-Host "`n🧹 正在清理损坏的 UserChoice 项..." -ForegroundColor Cyan
    
    $fileExtsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts"
    $count = 0
    
    Get-ChildItem $fileExtsPath | ForEach-Object {
        $userChoice = Join-Path $_.PSPath "UserChoice"
        if (Test-Path $userChoice) {
            try {
                Remove-Item $userChoice -Recurse -Force -ErrorAction Stop
                $count++
            } catch {}
        }
    }
    
    Write-Host "✅ 已清理 $count 个损坏项" -ForegroundColor Green
}

function Get-CurrentAssociations {
    Write-Host "`n📋 当前文件关联（常见类型）：" -ForegroundColor Cyan
    $output = & $setuserftaPath get 2>&1
    
    $commonExts = @(".pdf", ".zip", ".rar", ".7z", ".mp4", ".mkv", ".avi", ".html", "http", "https")
    $lines = $output -split "`n"
    
    foreach ($line in $lines) {
        foreach ($ext in $commonExts) {
            if ($line -like "$ext *") {
                Write-Host "   $line" -ForegroundColor Gray
                break
            }
        }
    }
}

function Export-Associations {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $exportFile = Join-Path $backupDir "默认应用配置_$timestamp.txt"
    & $setuserftaPath get | Out-File $exportFile -Encoding UTF8
    Write-Host "`n✅ 配置已备份到: $exportFile" -ForegroundColor Green
}

function Select-App {
    param([string]$Category, [string]$CategoryName)
    
    $apps = Get-InstalledApps -category $Category
    if ($apps.Count -eq 0) {
        Write-Host "`n❌ 未检测到已安装的$CategoryName" -ForegroundColor Red
        return $null
    }
    
    Write-Host "`n检测到的$CategoryName：" -ForegroundColor Cyan
    for ($i = 0; $i -lt $apps.Count; $i++) {
        Write-Host "  $($i+1). $($apps[$i].Name)" -ForegroundColor White
    }
    
    $sel = Read-Host "选择编号"
    $idx = [int]$sel - 1
    
    if ($idx -ge 0 -and $idx -lt $apps.Count) {
        return $apps[$idx]
    }
    return $null
}

# ==================== 菜单 ====================
function Show-Menu {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   默认应用重置 终极修复工具 v3.0" -ForegroundColor Cyan
    Write-Host "   浏览器 / 压缩 / 视频 全支持" -ForegroundColor DarkCyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "【一键修复】" -ForegroundColor Yellow
    Write-Host "  1. 全部修复：浏览器+压缩+视频 + 防重置锁定" -ForegroundColor Green
    Write-Host ""
    Write-Host "【单独设置】" -ForegroundColor Yellow
    Write-Host "  2. 设置默认浏览器" -ForegroundColor White
    Write-Host "  3. 设置默认压缩软件" -ForegroundColor White
    Write-Host "  4. 设置默认视频播放器" -ForegroundColor White
    Write-Host "  5. 仅启用防重置策略（不改关联）" -ForegroundColor White
    Write-Host ""
    Write-Host "【工具】" -ForegroundColor Yellow
    Write-Host "  6. 查看当前文件关联" -ForegroundColor White
    Write-Host "  7. 清理损坏的注册表项" -ForegroundColor White
    Write-Host "  8. 备份当前配置" -ForegroundColor White
    Write-Host "  9. 重新下载 SetUserFTA" -ForegroundColor White
    Write-Host ""
    Write-Host "  0. 退出" -ForegroundColor Red
    Write-Host ""
}

# ==================== 主程序 ====================
$toolReady = Download-SetUserFTA

do {
    Show-Menu
    $sel = Read-Host "请选择"
    
    switch ($sel) {
        "1" {
            # 一键全部修复
            if (-not $toolReady) { Write-Host "❌ 工具未就绪" -ForegroundColor Red; break }
            
            Clear-CorruptedUserChoice
            
            # 浏览器
            $browser = Select-App -Category "browser" -CategoryName "浏览器"
            if ($browser) { Set-DefaultBrowser -ProgId $browser.ProgId }
            
            # 压缩
            $archiver = Select-App -Category "archive" -CategoryName "压缩软件"
            if ($archiver) { Set-DefaultArchiver -ProgId $archiver.ProgId }
            
            # 视频
            $video = Select-App -Category "video" -CategoryName "视频播放器"
            if ($video) { Set-DefaultVideoPlayer -ProgId $video.ProgId }
            
            Enable-NoResetPolicy
            
            Write-Host "`n🎉 全部修复完成！建议重启电脑验证效果" -ForegroundColor Green
        }
        "2" {
            if (-not $toolReady) { Write-Host "❌ 工具未就绪" -ForegroundColor Red; break }
            $app = Select-App -Category "browser" -CategoryName "浏览器"
            if ($app) {
                Clear-CorruptedUserChoice
                Set-DefaultBrowser -ProgId $app.ProgId
                Enable-NoResetPolicy
                Write-Host "`n✅ 完成！建议重启验证" -ForegroundColor Green
            }
        }
        "3" {
            if (-not $toolReady) { Write-Host "❌ 工具未就绪" -ForegroundColor Red; break }
            $app = Select-App -Category "archive" -CategoryName "压缩软件"
            if ($app) {
                Clear-CorruptedUserChoice
                Set-DefaultArchiver -ProgId $app.ProgId
                Enable-NoResetPolicy
                Write-Host "`n✅ 完成！建议重启验证" -ForegroundColor Green
            }
        }
        "4" {
            if (-not $toolReady) { Write-Host "❌ 工具未就绪" -ForegroundColor Red; break }
            $app = Select-App -Category "video" -CategoryName "视频播放器"
            if ($app) {
                Clear-CorruptedUserChoice
                Set-DefaultVideoPlayer -ProgId $app.ProgId
                Enable-NoResetPolicy
                Write-Host "`n✅ 完成！建议重启验证" -ForegroundColor Green
            }
        }
        "5" { Enable-NoResetPolicy }
        "6" { if ($toolReady) { Get-CurrentAssociations } }
        "7" { Clear-CorruptedUserChoice }
        "8" { if ($toolReady) { Export-Associations } }
        "9" {
            if (Test-Path $setuserftaPath) { Remove-Item $setuserftaPath -Force }
            $toolReady = Download-SetUserFTA
        }
        "0" { break }
        default { Write-Host "无效选项" -ForegroundColor Red }
    }
    
    if ($sel -ne "0") {
        Write-Host "`n"
        pause
    }
} while ($sel -ne "0")

# ==================== 退出清理 ====================
Write-Host "`n🧹 正在清理临时文件..." -ForegroundColor Cyan

# 清理 SetUserFTA 相关文件
$cleanupFiles = @(
    "SetUserFTA.exe",
    "SetUserFTA.zip",
    "SetUserFTA.pdf",
    "readme.txt"
)

foreach ($file in $cleanupFiles) {
    $filePath = Join-Path $scriptDir $file
    if (Test-Path $filePath) {
        Remove-Item $filePath -Force -ErrorAction SilentlyContinue
        Write-Host "   已删除: $file" -ForegroundColor Gray
    }
}

Write-Host "✅ 清理完成" -ForegroundColor Green
Write-Host "`n👋 再见！" -ForegroundColor Cyan
Start-Sleep -Seconds 1
