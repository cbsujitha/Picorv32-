@echo off
REM ============================================================================
REM program_board.bat -- Flash PicoRV32 + Sobel SoC Bitstream to Boolean Board
REM ============================================================================
echo Connecting to RealDigital Boolean Board (Spartan-7)...
"D:\2025.2\Vivado\bin\vivado.bat" -mode batch -nojournal -nolog -source "%~dp0program_board.tcl"
pause
