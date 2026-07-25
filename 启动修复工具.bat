@echo off
title 默认应用重置修复工具
chcp 65001 >nul

:: 检查是否为管理员权限
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo 正在请求管理员权限...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: 切换到脚本所在目录
cd /d "%~dp0"

:: 运行PowerShell脚本
powershell -ExecutionPolicy Bypass -File ".\FixDefaultAppsReset.ps1"

if %errorLevel% neq 0 (
    echo.
    echo 脚本执行出错，请检查是否有杀毒软件拦截
    pause
)
