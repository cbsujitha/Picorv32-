@echo off
REM ==============================================================================
REM run_demo.bat -- One-Click Live Demo for PicoRV32 + Sobel Accelerator SoC
REM ==============================================================================
echo ==============================================================================
echo  RUNNING LIVE PICORV32 + SOBEL DEMO ON BOOLEAN BOARD (COM9)
echo ==============================================================================
powershell.exe -ExecutionPolicy Bypass -File "%~dp0host\Send-SobelImage.ps1" -Port COM9 -InputBin "%~dp0host\custom_input_64x64.bin" -OutputBmp "%~dp0host\custom_sobel_output.bmp"
echo.
echo Opening the resulting Sobel Edge image...
start "" "%~dp0host\custom_sobel_output.bmp"
pause
