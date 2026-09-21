@echo off
title DEKA Source Detector — Deep Protocol Analyzer
echo =======================================================
echo   KHOI CHAY TRINH PHAT HIEN NGUON (SOURCE DETECTOR)
echo =======================================================
echo.
cd /d "%~dp0"
echo Dang khoi chay DEKA Source Detector Standalone...
npm run detector
if %ERRORLEVEL% neq 0 (
    echo.
    echo [THONG BAO] Dang bien dich lai bo ma nguon...
    npm run build:ts
    npm run build:copy
    npm run detector
)
