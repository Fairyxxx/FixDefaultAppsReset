@echo off
title 默认应用重置终极修复工具 v2.0
chcp 65001 >nul

:: 检查管理员权限
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo 正在请求管理员权限...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File ".\FixDefaultApps_Ultimate.ps1"

if %errorLevel% neq 0 (
    echo.
    echo 脚本执行出错
    pause
)
