@echo off
rem Entry point for cmd.exe: msi-diff old.msi new.msi -MarkdownReport diff.md
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Compare-Msi.ps1" %*
exit /b %ERRORLEVEL%
