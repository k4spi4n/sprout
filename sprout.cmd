@echo off
rem Wrapper so sprout.ps1 runs even when the PowerShell execution policy blocks scripts.
rem Usage: sprout [start|stop|status]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sprout.ps1" %*
