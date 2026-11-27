@echo off
setlocal
cd /d "%~dp0"
if exist "DropToDel.exe" goto launch
set "fx=%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319"
if not exist "%fx%\csc.exe" set "fx=%SystemRoot%\Microsoft.NET\Framework\v4.0.30319"
if not exist "%fx%\csc.exe" goto fail
"%fx%\csc.exe" /nologo /target:winexe /platform:anycpu /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:"%fx%\Microsoft.VisualBasic.dll" /out:DropToDel.exe DropToDel.cs
if errorlevel 1 goto fail
:launch
start "" "%~dp0DropToDel.exe"
exit /b 0
:fail
echo Build failed. Windows .NET Framework 4.x and a writable folder are required.
pause
exit /b 1
