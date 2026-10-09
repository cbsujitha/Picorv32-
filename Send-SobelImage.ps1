<#
================================================================================
Send-SobelImage.ps1
PowerShell host interface for the PicoRV32 + Sobel SoC on RealDigital Boolean Board.
Runs natively on Windows without requiring Python or pip packages.
================================================================================
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Port,

    [Parameter(Mandatory=$false)]
    [string]$InputBin,

    [Parameter(Mandatory=$false)]
    [string]$OutputBmp
)

if (-not $InputBin) {
    $InputBin = Join-Path $PSScriptRoot "test_input_64x64.bin"
}
if (-not $OutputBmp) {
    $OutputBmp = Join-Path $PSScriptRoot "sobel_fpga_output.bmp"
}

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host " PicoRV32 + Sobel Accelerator PowerShell Host Interface" -ForegroundColor Cyan
Write-Host " RealDigital Boolean Board (Spartan-7 XC7S50)" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

# 1. Check COM Port
if (-not $Port) {
    $ports = [System.IO.Ports.SerialPort]::GetPortNames()
    if ($ports.Count -eq 0) {
        Write-Error "No serial COM ports detected. Please connect the Boolean Board USB cable."
        return
    }
    Write-Host "Available COM ports: $($ports -join ', ')"
    $Port = $ports[0]
    Write-Host "Defaulting to: $Port" -ForegroundColor Yellow
}

# 2. Check Input File
if (-not (Test-Path $InputBin)) {
    Write-Error "Input file not found: $InputBin"
    return
}

$inputBytes = [System.IO.File]::ReadAllBytes($InputBin)
if ($inputBytes.Length -ne 4096) {
    Write-Error "Input image must be exactly 4096 bytes (64x64). Got $($inputBytes.Length) bytes."
    return
}

Write-Host "[OK] Loaded input image: $InputBin ($($inputBytes.Length) bytes)" -ForegroundColor Green

# 3. Open Serial Port
Write-Host "[INFO] Connecting to $Port at 115200 baud..." -ForegroundColor Gray
$sp = New-Object System.IO.Ports.SerialPort
$sp.PortName = $Port
$sp.BaudRate = 115200
$sp.Parity = [System.IO.Ports.Parity]::None
$sp.DataBits = 8
$sp.StopBits = [System.IO.Ports.StopBits]::One
$sp.ReadTimeout = 8000
$sp.WriteTimeout = 8000
$sp.DtrEnable = $false
$sp.RtsEnable = $false

try {
    $sp.Open()
    Start-Sleep -Milliseconds 200
    $sp.DiscardInBuffer()
    $sp.DiscardOutBuffer()

    # 4. Transmit 4096 Bytes to PicoRV32
    Write-Host "[TX] Streaming 4096 bytes to Boolean Board..." -ForegroundColor Yellow
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $sp.Write($inputBytes, 0, $inputBytes.Length)
    $sw.Stop()
    Write-Host "[TX] Completed in $($sw.ElapsedMilliseconds) ms." -ForegroundColor Green

    # 5. Receive 4096 Edge Bytes from PicoRV32
    Write-Host "[RX] Receiving 4096 edge pixels from SoC..." -ForegroundColor Yellow
    $rxBytes = New-Object byte[] 4096
    $totalRead = 0
    $sw.Restart()

    while ($totalRead -lt 4096) {
        $count = $sp.Read($rxBytes, $totalRead, 4096 - $totalRead)
        if ($count -eq 0) { break }
        $totalRead += $count
        $pct = [math]::Round(($totalRead / 4096) * 100, 1)
        Write-Progress -Activity "Receiving Sobel Output from FPGA" -Status "$totalRead / 4096 bytes ($pct%)" -PercentComplete $pct
    }
    $sw.Stop()
    Write-Progress -Activity "Receiving Sobel Output from FPGA" -Completed

    if ($totalRead -ne 4096) {
        Write-Error "Timeout! Expected 4096 bytes but received $totalRead bytes."
        return
    }

    Write-Host "[RX] Completed in $($sw.ElapsedMilliseconds) ms ($totalRead bytes received)." -ForegroundColor Green

    # Save raw binary output
    $outBin = [System.IO.Path]::ChangeExtension($OutputBmp, ".bin")
    [System.IO.File]::WriteAllBytes($outBin, $rxBytes)

    # 6. Generate 8-bit BMP file
    $width = 64
    $height = 64
    $rowStride = 64
    $imageSize = $rowStride * $height
    $paletteSize = 256 * 4
    $headerSize = 14 + 40 + $paletteSize
    $fileSize = $headerSize + $imageSize

    $bmpStream = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter $bmpStream

    # BITMAPFILEHEADER (14 bytes)
    $bw.Write([byte]0x42) # 'B'
    $bw.Write([byte]0x4D) # 'M'
    $bw.Write([uint32]$fileSize)
    $bw.Write([uint16]0)
    $bw.Write([uint16]0)
    $bw.Write([uint32]$headerSize)

    # BITMAPINFOHEADER (40 bytes)
    $bw.Write([uint32]40)
    $bw.Write([int32]$width)
    $bw.Write([int32]$height)
    $bw.Write([uint16]1)      # planes
    $bw.Write([uint16]8)      # 8 bits per pixel
    $bw.Write([uint32]0)      # uncompressed BI_RGB
    $bw.Write([uint32]$imageSize)
    $bw.Write([int32]2835)
    $bw.Write([int32]2835)
    $bw.Write([uint32]256)
    $bw.Write([uint32]256)

    # Grayscale Palette (256 entries * 4 bytes: B, G, R, 0)
    for ($i = 0; $i -lt 256; $i++) {
        $bw.Write([byte]$i)
        $bw.Write([byte]$i)
        $bw.Write([byte]$i)
        $bw.Write([byte]0)
    }

    # Bottom-to-top pixel rows
    for ($y = $height - 1; $y -ge 0; $y--) {
        $rowOffset = $y * $width
        for ($x = 0; $x -lt $width; $x++) {
            $bw.Write($rxBytes[$rowOffset + $x])
        }
    }

    $bw.Flush()
    [System.IO.File]::WriteAllBytes($OutputBmp, $bmpStream.ToArray())
    $bw.Close()
    $bmpStream.Close()

    Write-Host "[OK] Output BMP saved to: $OutputBmp" -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host " SUCCESS: Sobel Edge Detection completed on Boolean Board!" -ForegroundColor Green
    Write-Host "======================================================================" -ForegroundColor Green
}
catch {
    Write-Error "Communication error: $_"
}
finally {
    if ($sp -and $sp.IsOpen) {
        $sp.Close()
    }
}
