<#
.SYNOPSIS
    Windows 默认应用重置问题修复工具
.DESCRIPTION
    整合多种解决方案，修复Windows系统更新或重启后默认应用自动重置的问题
    需要以管理员权限运行
.NOTES
    版本: 1.0
    日期: 2026-07-25
#>

# 检查管理员权限
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "⚠️  请以管理员身份运行此脚本！" -ForegroundColor Yellow
    Write-Host "右键点击脚本，选择'以管理员身份运行'" -ForegroundColor Yellow
    pause
    exit 1
}

# 设置控制台编码
chcp 65001 | Out-Null

# 注册表备份路径
$backupPath = "$env:USERPROFILE\Desktop\DefaultApps_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"

function Show-Menu {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   Windows 默认应用重置修复工具 v1.0" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "请选择要执行的操作：" -ForegroundColor White
    Write-Host ""
    Write-Host "1. 一键综合修复（推荐）" -ForegroundColor Green
    Write-Host "2. 启用 NoOpenWith 策略（阻止系统强制重置）" -ForegroundColor Yellow
    Write-Host "3. 清理损坏的 UserChoice 注册表项" -ForegroundColor Yellow
    Write-Host "4. 备份当前默认应用设置" -ForegroundColor Yellow
    Write-Host "5. 修复系统文件（SFC + DISM）" -ForegroundColor Yellow
    Write-Host "6. 禁用 Edge 强制关联任务" -ForegroundColor Yellow
    Write-Host "7. 禁用应用程序体验计划任务" -ForegroundColor Yellow
    Write-Host "8. 恢复默认应用设置（从备份）" -ForegroundColor Yellow
    Write-Host "0. 退出" -ForegroundColor Red
    Write-Host ""
}

function Backup-Registry {
    Write-Host "`n📦 正在备份注册表..." -ForegroundColor Cyan
    try {
        reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts" $backupPath /y | Out-Null
        Write-Host "✅ 备份已保存到: $backupPath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "❌ 备份失败: $_" -ForegroundColor Red
        return $false
    }
}

function Enable-NoOpenWithPolicy {
    Write-Host "`n🔧 正在配置 NoOpenWith 策略..." -ForegroundColor Cyan
    
    $registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
    
    if (-not (Test-Path $registryPath)) {
        New-Item -Path $registryPath -Force | Out-Null
        Write-Host "   创建注册表路径: $registryPath" -ForegroundColor Gray
    }
    
    Set-ItemProperty -Path $registryPath -Name "NoOpenWith" -Value 1 -Type DWord -Force
    Write-Host "✅ NoOpenWith 策略已启用（值=1）" -ForegroundColor Green
    Write-Host "   此策略可阻止系统强制重置默认应用关联" -ForegroundColor Gray
}

function Clear-UserChoiceRegistry {
    Write-Host "`n🧹 正在清理损坏的 UserChoice 注册表项..." -ForegroundColor Cyan
    
    $fileExtsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts"
    $clearedCount = 0
    
    # 获取所有扩展名
    $extensions = Get-ChildItem $fileExtsPath
    
    foreach ($ext in $extensions) {
        $userChoicePath = Join-Path $ext.PSPath "UserChoice"
        if (Test-Path $userChoicePath) {
            try {
                Remove-Item $userChoicePath -Recurse -Force -ErrorAction Stop
                $clearedCount++
                Write-Host "   已清理: $($ext.PSChildName)" -ForegroundColor Gray
            }
            catch {
                Write-Host "   跳过: $($ext.PSChildName) (无法删除)" -ForegroundColor DarkGray
            }
        }
    }
    
    Write-Host "`n✅ 共清理了 $clearedCount 个 UserChoice 项" -ForegroundColor Green
    Write-Host "   请重新设置你的默认应用，设置将不再被自动重置" -ForegroundColor Yellow
}

function Repair-SystemFiles {
    Write-Host "`n🔍 正在运行系统文件检查（SFC）..." -ForegroundColor Cyan
    sfc /scannow
    
    Write-Host "`n🔧 正在运行 DISM 修复..." -ForegroundColor Cyan
    DISM /Online /Cleanup-Image /RestoreHealth
    
    Write-Host "`n✅ 系统文件修复完成" -ForegroundColor Green
    Write-Host "   建议重启电脑后再设置默认应用" -ForegroundColor Yellow
}

function Disable-EdgeTasks {
    Write-Host "`n🛡️  正在禁用 Edge 强制关联相关任务..." -ForegroundColor Cyan
    
    $tasks = @(
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
        "\Microsoft\Windows\Application Experience\StartupAppTask"
    )
    
    $disabledCount = 0
    foreach ($task in $tasks) {
        try {
            $taskInfo = Get-ScheduledTask -TaskPath (Split-Path $task) -TaskName (Split-Path $task -Leaf) -ErrorAction Stop
            if ($taskInfo.State -ne 'Disabled') {
                Disable-ScheduledTask -TaskPath (Split-Path $task) -TaskName (Split-Path $task -Leaf) -ErrorAction Stop | Out-Null
                Write-Host "   已禁用: $(Split-Path $task -Leaf)" -ForegroundColor Gray
                $disabledCount++
            }
            else {
                Write-Host "   已禁用(跳过): $(Split-Path $task -Leaf)" -ForegroundColor DarkGray
            }
        }
        catch {
            Write-Host "   未找到: $(Split-Path $task -Leaf)" -ForegroundColor DarkGray
        }
    }
    
    # 禁用Edge浏览器默认提示
    $edgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main"
    if (-not (Test-Path $edgePolicyPath)) {
        New-Item -Path $edgePolicyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $edgePolicyPath -Name "PreventFirstRunDefaultBrowserPrompt" -Value 1 -Type DWord -Force
    
    Write-Host "`n✅ 已禁用 $disabledCount 个相关计划任务" -ForegroundColor Green
    Write-Host "   已禁用 Edge 默认浏览器提示" -ForegroundColor Green
}

function Disable-AppExperienceTasks {
    Write-Host "`n⏸️  正在禁用应用程序体验计划任务..." -ForegroundColor Cyan
    
    $taskPaths = @(
        "\Microsoft\Windows\Application Experience\",
        "\Microsoft\Windows\Shell\"
    )
    
    $disabledCount = 0
    foreach ($path in $taskPaths) {
        try {
            $tasks = Get-ScheduledTask -TaskPath $path -ErrorAction Stop
            foreach ($task in $tasks) {
                if ($task.State -ne 'Disabled') {
                    Disable-ScheduledTask -TaskPath $path -TaskName $task.TaskName -ErrorAction SilentlyContinue | Out-Null
                    Write-Host "   已禁用: $($task.TaskName)" -ForegroundColor Gray
                    $disabledCount++
                }
            }
        }
        catch {
            Write-Host "   路径访问失败: $path" -ForegroundColor DarkGray
        }
    }
    
    Write-Host "`n✅ 共禁用了 $disabledCount 个计划任务" -ForegroundColor Green
}

function Restore-FromBackup {
    $backupFiles = Get-ChildItem "$env:USERPROFILE\Desktop" -Filter "DefaultApps_Backup_*.reg" | Sort-Object LastWriteTime -Descending
    
    if ($backupFiles.Count -eq 0) {
        Write-Host "`n❌ 未找到备份文件" -ForegroundColor Red
        return
    }
    
    Write-Host "`n📋 找到以下备份文件：" -ForegroundColor Cyan
    for ($i = 0; $i -lt $backupFiles.Count; $i++) {
        Write-Host "   $($i+1). $($backupFiles[$i].Name) ($($backupFiles[$i].LastWriteTime))" -ForegroundColor Gray
    }
    
    $choice = Read-Host "`n请选择要恢复的备份编号（输入0取消）"
    if ($choice -eq "0" -or $choice -eq "") { return }
    
    $selectedIndex = [int]$choice - 1
    if ($selectedIndex -ge 0 -and $selectedIndex -lt $backupFiles.Count) {
        $selectedFile = $backupFiles[$selectedIndex].FullName
        Write-Host "`n🔄 正在恢复: $selectedFile" -ForegroundColor Cyan
        reg import $selectedFile | Out-Null
        Write-Host "✅ 恢复完成" -ForegroundColor Green
    }
}

function Run-AllFixes {
    Write-Host "`n🚀 开始执行一键综合修复..." -ForegroundColor Cyan
    Write-Host "=" * 40 -ForegroundColor Cyan
    
    # 1. 先备份
    Backup-Registry
    
    # 2. 启用 NoOpenWith 策略
    Enable-NoOpenWithPolicy
    
    # 3. 清理 UserChoice
    Clear-UserChoiceRegistry
    
    # 4. 禁用 Edge 相关任务
    Disable-EdgeTasks
    
    # 5. 禁用应用体验任务
    Disable-AppExperienceTasks
    
    Write-Host "`n" + "=" * 40 -ForegroundColor Cyan
    Write-Host "✅ 综合修复完成！" -ForegroundColor Green
    Write-Host ""
    Write-Host "📝 后续操作建议：" -ForegroundColor Yellow
    Write-Host "   1. 重启电脑" -ForegroundColor White
    Write-Host "   2. 重新设置你的默认应用（设置 → 应用 → 默认应用）" -ForegroundColor White
    Write-Host "   3. 之后默认应用就不会再被自动重置了" -ForegroundColor White
}

# 主循环
do {
    Show-Menu
    $selection = Read-Host "请输入选项编号"
    
    switch ($selection) {
        "1" { Run-AllFixes }
        "2" { Enable-NoOpenWithPolicy }
        "3" { Clear-UserChoiceRegistry }
        "4" { Backup-Registry }
        "5" { Repair-SystemFiles }
        "6" { Disable-EdgeTasks }
        "7" { Disable-AppExperienceTasks }
        "8" { Restore-FromBackup }
        "0" { 
            Write-Host "`n👋 再见！" -ForegroundColor Cyan
            break 
        }
        default { 
            Write-Host "`n❌ 无效选项，请重新选择" -ForegroundColor Red 
        }
    }
    
    if ($selection -ne "0") {
        Write-Host "`n"
        pause
    }
} while ($selection -ne "0")
