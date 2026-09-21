@echo off
chcp 65001 >nul
title Cài Đặt 1-Click: Background Engine (DEKA Productions)

echo ======================================================================
echo          CÀI ĐẶT 1-CLICK: BACKGROUND ENGINE CHO VMIX & OBS
echo                       DEKA Productions - Production Build
echo ======================================================================
echo.

set "SETUP_EXE=%~dp0release\BackgroundEngine-Setup.exe"

if exist "%SETUP_EXE%" (
    echo [1/2] Đã tìm thấy bộ cài đặt: BackgroundEngine-Setup.exe
    echo [2/2] Đang khởi chạy trình cài đặt 1-Click...
    echo.
    echo * Ứng dụng sẽ tự động được cài đặt vào máy.
    echo * Biểu tượng Desktop và Start Menu sẽ được tự động tạo.
    echo.
    start "" "%SETUP_EXE%"
    goto :done
)

echo [!] Chưa tìm thấy file cài trong thư mục release.
echo [*] Đang tự động build bộ cài đặt 1-Click từ mã nguồn...
echo.

call npm run build
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Lỗi biên dịch dự án! Vui lòng kiểm tra lại.
    pause
    exit /b 1
)

call npm run dist
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Lỗi đóng gói bộ cài đặt! Vui lòng kiểm tra lại.
    pause
    exit /b 1
)

if exist "%SETUP_EXE%" (
    echo.
    echo [*] Đóng gói thành công! Đang khởi chạy bộ cài đặt 1-Click...
    start "" "%SETUP_EXE%"
) else (
    echo [ERROR] Không tìm thấy file %SETUP_EXE% sau khi build.
    pause
    exit /b 1
)

:done
echo.
echo ======================================================================
echo Cài đặt hoàn tất! Bạn có thể đóng cửa sổ này.
echo ======================================================================
timeout /t 5 >nul
