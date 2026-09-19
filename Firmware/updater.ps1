$ErrorActionPreference = "Stop"

$ScriptVersion = "1.0"

$RepoUrl = "https://github.com/MyRetroStore/6522-Tester"
$RepoApiLatest = "https://api.github.com/repos/MyRetroStore/6522-Tester/releases/latest"
$RawVersionUrl = "https://raw.githubusercontent.com/MyRetroStore/6522-Tester/updater/main/version"

$WebsiteUrl = "https://myretrostore.co.uk"

$ReadTimeoutSeconds = 5

# Arduino Mega 2560 USB identifiers
$ArduinoVIDPID = "VID_2341&PID_0042"
$ArduinoVID = "VID_2341"

# AVRDUDE settings
$Mcu = "atmega2560"
$Programmer = "wiring"
$Baud = 115200

# Local folders/files
$AvrdudeDir = Join-Path $PSScriptRoot "avrdude"
$AvrdudeExe = Join-Path $AvrdudeDir "avrdude.exe"
$AvrdudeConf = Join-Path $AvrdudeDir "avrdude.conf"

$FirmwareFile = Join-Path $PSScriptRoot "firmware.hex"

# Temporary download locations
$TempRoot = Join-Path $env:TEMP "Mega2560Updater"

function Write-Info {
    param([string]$Message)

    Write-Host "[INFO] " -ForegroundColor Cyan -NoNewline
    Write-Host $Message
}

function Write-OK {
    param([string]$Message)

    Write-Host "[OK]   " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Warn {
    param([string]$Message)

    Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Fail {
    param([string]$Message)

    Write-Host "[ERROR]" -ForegroundColor Red -NoNewline
    Write-Host " $Message" -ForegroundColor Red
}

function Stop-Updater {
    param([string]$Message)

    Write-Fail $Message
    exit 1
}

function Convert-ToVersion {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $clean = $Value.Trim()

    # Remove leading v
    $clean = $clean -replace '^[vV]', ''

    # Extract numeric version
    $match = [regex]::Match(
        $clean,
        '\d+(?:\.\d+){0,3}'
    )

    if (-not $match.Success) {
        return $null
    }

    try {
        return [version]$match.Value
    }
    catch {
        return $null
    }
}

function Get-AvrdudeVersion {
    param(
        [string]$Exe
    )

    if (-not (Test-Path -LiteralPath $Exe)) {
        return $null
    }

    try {
        $output = & $Exe --version 2>&1 | Out-String

        $match = [regex]::Match(
            $output,
            '(?i)\b(?:avrdude(?:\s+version)?\s*)?(\d+\.\d+(?:\.\d+)?)\b'
        )

        if ($match.Success) {
            return Convert-ToVersion $match.Groups[1].Value
        }
    }
    catch {
        return $null
    }

    return $null
}

function Ensure-AvrdudeDirectory {

    if (-not (Test-Path -LiteralPath $AvrdudeDir)) {

        Write-Info "AVRDUDE folder does not exist."

        New-Item `
            -ItemType Directory `
            -Path $AvrdudeDir `
            -Force | Out-Null

        Write-OK "Created: $AvrdudeDir"
    }
    else {
        Write-OK "AVRDUDE folder exists: $AvrdudeDir"
    }
}

function Get-LatestAvrdudeRelease {

    $api = "https://api.github.com/repos/avrdudes/avrdude/releases/latest"

    try {

        $headers = @{
            "User-Agent" = "Mega2560Updater/$ScriptVersion"
            "Accept"     = "application/vnd.github+json"
        }

        return Invoke-RestMethod `
            -Uri $api `
            -Headers $headers `
            -Method Get `
            -TimeoutSec 20
    }
    catch {

        Write-Warn "Could not contact AVRDUDE GitHub release API."
        return $null
    }
}

function Install-LatestAvrdude {

    Write-Info "Checking latest AVRDUDE release..."

    $release = Get-LatestAvrdudeRelease

    if ($null -eq $release) {
        return $false
    }

    $tag = $release.tag_name

    if ([string]::IsNullOrWhiteSpace($tag)) {
        Write-Warn "AVRDUDE release tag was not found."
        return $false
    }

    Write-Info "Latest AVRDUDE release: $tag"

    # Find Windows x64 ZIP
    $asset = @(
        $release.assets |
        Where-Object {
            $_.name -match '(?i)^avrdude-v.*-windows-x64\.zip$'
        }
    ) | Select-Object -First 1

    if ($null -eq $asset) {
        Write-Warn "Windows x64 AVRDUDE package was not found."

        Write-Warn "Available AVRDUDE assets:"
        foreach ($a in $release.assets) {
            Write-Host "       $($a.name)"
        }

        return $false
    }

    Write-Info "AVRDUDE package: $($asset.name)"

    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item `
            -LiteralPath $TempRoot `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }

    New-Item `
        -ItemType Directory `
        -Path $TempRoot `
        -Force | Out-Null

    $zipFile = Join-Path $TempRoot $asset.name
    $extractDir = Join-Path $TempRoot "extract"
    $newInstallDir = Join-Path $TempRoot "new-avrdude"

    try {

        Write-Info "Downloading AVRDUDE..."

        $headers = @{
            "User-Agent" = "Mega2560Updater/$ScriptVersion"
            "Accept"     = "application/octet-stream"
        }

        Invoke-WebRequest `
            -Uri $asset.browser_download_url `
            -Headers $headers `
            -OutFile $zipFile `
            -UseBasicParsing `
            -TimeoutSec 60

        if (-not (Test-Path -LiteralPath $zipFile)) {
            throw "AVRDUDE ZIP download failed."
        }

        Write-OK "AVRDUDE downloaded."

        if ($asset.digest) {

            $expectedHash = $asset.digest

            if ($expectedHash -match '^sha256:(.+)$') {
                $expectedHash = $Matches[1]
            }

            Write-Info "Verifying AVRDUDE SHA256..."

            $actualHash = (
                Get-FileHash `
                    -LiteralPath $zipFile `
                    -Algorithm SHA256
            ).Hash

            if (
                $actualHash.ToLowerInvariant() `
                -ne $expectedHash.ToLowerInvariant()
            ) {
                throw "AVRDUDE SHA256 verification failed."
            }

            Write-OK "AVRDUDE SHA256 verified."
        }

        Write-Info "Extracting AVRDUDE..."

        New-Item `
            -ItemType Directory `
            -Path $extractDir `
            -Force | Out-Null

        Expand-Archive `
            -LiteralPath $zipFile `
            -DestinationPath $extractDir `
            -Force

        Write-Info "Searching extracted package for avrdude.exe..."

        $foundExe = Get-ChildItem `
            -LiteralPath $extractDir `
            -Filter "avrdude.exe" `
            -Recurse `
            -File |
            Select-Object -First 1

        if ($null -eq $foundExe) {

            Write-Warn "avrdude.exe was not found."

            Write-Warn "Contents of extracted package:"

            Get-ChildItem `
                -LiteralPath $extractDir `
                -Recurse `
                -File |
                Select-Object FullName |
                ForEach-Object {
                    Write-Host "       $($_.FullName)"
                }

            throw "avrdude.exe was not found in the downloaded package."
        }

        Write-OK "Found avrdude.exe:"
        Write-Host "       $($foundExe.FullName)"

        Write-Info "Searching for avrdude.conf..."

        $foundConf = Get-ChildItem `
            -LiteralPath $extractDir `
            -Filter "avrdude.conf" `
            -Recurse `
            -File |
            Select-Object -First 1

        if ($null -eq $foundConf) {
            throw "avrdude.conf was not found in the downloaded package."
        }

        Write-OK "Found avrdude.conf:"
        Write-Host "       $($foundConf.FullName)"

        $packageRoot = $foundExe.Directory.FullName

        Write-Info "AVRDUDE package directory:"
        Write-Host "       $packageRoot"

        New-Item `
            -ItemType Directory `
            -Path $newInstallDir `
            -Force | Out-Null

        Write-Info "Copying complete AVRDUDE package..."

        $packageItems = Get-ChildItem `
            -LiteralPath $packageRoot `
            -Force

        foreach ($item in $packageItems) {

            Copy-Item `
                -LiteralPath $item.FullName `
                -Destination $newInstallDir `
                -Recurse `
                -Force
        }

        $newExe = Join-Path $newInstallDir "avrdude.exe"

        if (-not (Test-Path -LiteralPath $newExe)) {

            Write-Warn "Temporary AVRDUDE installation contents:"

            Get-ChildItem `
                -LiteralPath $newInstallDir `
                -Recurse `
                -File |
                Select-Object FullName |
                ForEach-Object {
                    Write-Host "       $($_.FullName)"
                }

            throw "avrdude.exe was not copied to temporary installation."
        }

        Write-OK "Temporary AVRDUDE installation verified."

        Write-Info "Updating local AVRDUDE installation..."

        if (Test-Path -LiteralPath $AvrdudeDir) {

            $oldItems = Get-ChildItem `
                -LiteralPath $AvrdudeDir `
                -Force

            foreach ($item in $oldItems) {

                Remove-Item `
                    -LiteralPath $item.FullName `
                    -Recurse `
                    -Force `
                    -ErrorAction Stop
            }
        }
        else {

            New-Item `
                -ItemType Directory `
                -Path $AvrdudeDir `
                -Force | Out-Null
        }

        $finalItems = Get-ChildItem `
            -LiteralPath $newInstallDir `
            -Force

        foreach ($item in $finalItems) {

            Copy-Item `
                -LiteralPath $item.FullName `
                -Destination $AvrdudeDir `
                -Recurse `
                -Force
        }

        if (-not (Test-Path -LiteralPath $AvrdudeExe)) {
            throw "AVRDUDE installation completed but avrdude.exe is missing."
        }

        if (-not (Test-Path -LiteralPath $AvrdudeConf)) {
            throw "AVRDUDE installation completed but avrdude.conf is missing."
        }

        Write-OK "AVRDUDE installed successfully."
        Write-OK "Location: $AvrdudeDir"

        return $true
    }
    catch {

        Write-Warn "AVRDUDE installation failed: $($_.Exception.Message)"
        return $false
    }
    finally {

        if (Test-Path -LiteralPath $TempRoot) {

            Remove-Item `
                -LiteralPath $TempRoot `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }
}

function Get-LatestFirmwareRelease {

    Write-Info "Checking GitHub for latest firmware release..."

    try {

        $headers = @{
            "User-Agent" = "Mega2560Updater/$ScriptVersion"
            "Accept"     = "application/vnd.github+json"
        }

        $release = Invoke-RestMethod `
            -Uri $RepoApiLatest `
            -Headers $headers `
            -Method Get `
            -TimeoutSec 20

        if ($null -eq $release) {
            throw "Empty GitHub response."
        }

        return $release
    }
    catch {

        Write-Fail "Could not retrieve latest GitHub release."
        Write-Fail $_.Exception.Message

        return $null
    }
}


function Get-SafeFirmwareAsset {

    param(
        [Parameter(Mandatory)]
        $Release
    )

    $bootloaderAssets = @(
        $Release.assets |
        Where-Object {
            $_.name -match '(?i)bootloader' -and
            $_.name -match '(?i)\.hex$'
        }
    )

    $safeAssets = @(
        $Release.assets |
        Where-Object {
            $_.name -match '(?i)\.hex$' -and
            $_.name -notmatch '(?i)bootloader'
        }
    )

    if ($bootloaderAssets.Count -gt 0) {

        foreach ($asset in $bootloaderAssets) {
            Write-Warn "Ignoring bootloader HEX: $($asset.name)"
        }
    }

    if ($safeAssets.Count -eq 0) {

        if ($bootloaderAssets.Count -gt 0) {

            Write-Fail "The latest GitHub release contains only bootloader HEX files."
            Write-Fail "No application firmware was found."
        }
        else {

            Write-Fail "No .hex firmware asset was found in the latest GitHub release."
        }

        return $null
    }

    # Use first safe application HEX
    return $safeAssets[0]
}


function Test-SafeApplicationHex {

    param(
        [Parameter(Mandatory)]
        [string]$File
    )

    if (-not (Test-Path -LiteralPath $File)) {
        Write-Fail "HEX file does not exist: $File"
        return $false
    }

    $fileName = Split-Path $File -Leaf

    # ------------------------------------------------------------------------
    # Filename safety check
    # ------------------------------------------------------------------------

    if ($fileName -match '(?i)bootloader') {

        Write-Fail "SAFETY BLOCK: '$fileName' contains 'bootloader'."
        Write-Fail "This file will NOT be flashed."
        return $false
    }

    # ------------------------------------------------------------------------
    # Read HEX
    # ------------------------------------------------------------------------

    try {

        $lines = Get-Content -LiteralPath $File -ErrorAction Stop
    }
    catch {

        Write-Fail "Could not read HEX file."
        return $false
    }

    $extendedAddress = 0

    foreach ($lineRaw in $lines) {

        $line = $lineRaw.Trim()

        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if (-not $line.StartsWith(":")) {

            Write-Fail "Invalid Intel HEX line detected."
            return $false
        }

        # Minimum Intel HEX record length
        if ($line.Length -lt 11) {

            Write-Fail "Invalid Intel HEX record."
            return $false
        }

        try {

            $byteCount = [Convert]::ToInt32($line.Substring(1, 2), 16)
            $address = [Convert]::ToInt32($line.Substring(3, 4), 16)
            $recordType = [Convert]::ToInt32($line.Substring(7, 2), 16)

            # ----------------------------------------------------------------
            # Extended Linear Address record
            # ----------------------------------------------------------------

            if ($recordType -eq 4) {

                if ($byteCount -ne 2) {
                    Write-Fail "Invalid extended address record."
                    return $false
                }

                $extendedAddress =
                    [Convert]::ToInt32(
                        $line.Substring(9, 4),
                        16
                    ) -shl 16

                continue
            }

            # ----------------------------------------------------------------
            # Data record
            # ----------------------------------------------------------------

            if ($recordType -eq 0) {

                $absoluteAddress =
                    $extendedAddress + $address

                $endAddress =
                    $absoluteAddress + $byteCount - 1

                # Mega 2560 bootloader area begins at 0x3E000
                if ($absoluteAddress -ge 0x3E000 -or
                    $endAddress -ge 0x3E000) {

                    Write-Fail ""
                    Write-Fail "=============================================="
                    Write-Fail "SAFETY BLOCK"
                    Write-Fail "=============================================="
                    Write-Fail "HEX contains data in the Mega 2560"
                    Write-Fail "bootloader area."
                    Write-Fail ""
                    Write-Fail ("Start address: 0x{0:X}" -f $absoluteAddress)
                    Write-Fail ("End address:   0x{0:X}" -f $endAddress)
                    Write-Fail "Bootloader begins at: 0x3E000"
                    Write-Fail ""
                    Write-Fail "Flashing this file has been cancelled."
                    Write-Fail "=============================================="

                    return $false
                }
            }
        }
        catch {

            Write-Fail "Invalid Intel HEX record detected."
            return $false
        }
    }

    return $true
}

function Download-Firmware {

    param(
        [Parameter(Mandatory)]
        $Asset,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    $name = $Asset.name
    $url = $Asset.browser_download_url

    if ([string]::IsNullOrWhiteSpace($url)) {

        Write-Fail "GitHub firmware download URL is missing."
        return $false
    }

    # Absolute safety check
    if ($name -match '(?i)bootloader') {

        Write-Fail "SAFETY BLOCK: Refusing to download '$name'."
        return $false
    }

    Write-Info "Downloading firmware from GitHub..."

    $tempFile = "$Destination.download"

    try {

        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }

        Invoke-WebRequest `
            -Uri $url `
            -OutFile $tempFile `
            -UseBasicParsing `
            -TimeoutSec 60

        if (-not (Test-Path $tempFile)) {
            throw "Download did not create a file."
        }

        $size = (Get-Item $tempFile).Length

        if ($size -le 0) {
            throw "Downloaded firmware file is empty."
        }

        Write-OK "Firmware downloaded ($size bytes)."

        if (-not (Test-SafeApplicationHex -File $tempFile)) {

            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

            Write-Fail "Downloaded firmware failed safety validation."
            return $false
        }

        # Replace firmware.hex
        Move-Item `
            -LiteralPath $tempFile `
            -Destination $Destination `
            -Force

        Write-OK "Firmware saved as:"
        Write-Host "       $Destination"

        return $true
    }
    catch {

        Write-Fail "Firmware download failed."
        Write-Fail $_.Exception.Message

        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }

        return $false
    }
}

# ============================================================================
# DETECT ARDUINO MEGA 2560
# ============================================================================

function Find-ArduinoMega {

    Write-Info "Detecting Arduino Mega 2560..."

    try {

        $ports = Get-CimInstance Win32_SerialPort |
            Where-Object {
                $_.PNPDeviceID -match $ArduinoVIDPID
            }

        if ($ports.Count -eq 0) {

            # Fallback to VID only
            $ports = Get-CimInstance Win32_SerialPort |
                Where-Object {
                    $_.PNPDeviceID -match $ArduinoVID
                }
        }

        if ($null -eq $ports -or $ports.Count -eq 0) {
            return $null
        }

        return $ports | Select-Object -First 1
    }
    catch {

        Write-Warn "Could not query Windows serial devices."
        return $null
    }
}

# ============================================================================
# READ ARDUINO FIRMWARE VERSION
# ============================================================================
function Read-ArduinoVersion {

    param(
        [Parameter(Mandatory)]
        [string]$PortName,

        [int]$BaudRate = 115200,

        [int]$TimeoutSeconds = 5
    )

    $serial = $null

    try {
        $serial = New-Object System.IO.Ports.SerialPort

        $serial.PortName = $PortName
        $serial.BaudRate = $BaudRate
        $serial.DataBits = 8
        $serial.StopBits = [System.IO.Ports.StopBits]::One
        $serial.Parity = [System.IO.Ports.Parity]::None
        $serial.Handshake = [System.IO.Ports.Handshake]::None

        $serial.ReadTimeout = 1000
        $serial.WriteTimeout = 1000
        $serial.NewLine = "`n"

        $serial.Open()

        # Opening the Mega's USB serial port normally resets the board.
        Start-Sleep -Milliseconds 3000

        # Discard the boot banner and anything else generated during reset.
        try {
            $serial.DiscardInBuffer()
            $serial.DiscardOutBuffer()
        }
        catch {
        }

        Write-Info "Requesting firmware version..."

        $command = [System.Text.Encoding]::ASCII.GetBytes("version`n")
        $serial.Write($command, 0, $command.Length)

        $start = Get-Date

        while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {

            try {

                $line = $serial.ReadLine()

                if ([string]::IsNullOrWhiteSpace($line)) {
                    continue
                }

                $line = $line.Trim()

                $match = [regex]::Match(
                    $line,
                    '(?i)Firmware\s+Version\s*:\s*([0-9]+(?:\.[0-9]+)*)'
                )

                if ($match.Success) {
                    return $match.Groups[1].Value
                }

                $match = [regex]::Match(
                    $line,
                    '(?i)Version\s*:\s*([0-9]+(?:\.[0-9]+)*)'
                )

                if ($match.Success) {
                    return $match.Groups[1].Value
                }

                $match = [regex]::Match(
                    $line,
                    '^\s*([0-9]+\.[0-9]+(?:\.[0-9]+)?)\s*$'
                )

                if ($match.Success) {
                    return $match.Groups[1].Value
                }
            }
            catch [System.TimeoutException] {
            }
        }

        Write-Warn "No firmware version response received within $TimeoutSeconds seconds."
        return $null
    }
    catch {
        Write-Warn "Could not read firmware version from $PortName."
        Write-Warn $_.Exception.Message
        return $null
    }
    finally {

        if ($null -ne $serial) {

            try {
                if ($serial.IsOpen) {
                    $serial.Close()
                }
            }
            catch {
            }

            try {
                $serial.Dispose()
            }
            catch {
            }
        }
    }
}



# ============================================================================
# FLASH FIRMWARE
# ============================================================================
function Flash-Firmware {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Port,

        [Parameter(Mandatory = $true)]
        [string]$FirmwareFile
    )

    Write-Host "[INFO] Firmware path: $FirmwareFile" -ForegroundColor Cyan

    if ([string]::IsNullOrWhiteSpace($FirmwareFile)) {
        Write-Host "[ERROR] Firmware path is empty." -ForegroundColor Red
        return $false
    }

    if (-not (Test-Path -LiteralPath $FirmwareFile -PathType Leaf)) {
        Write-Host "[ERROR] Firmware file does not exist: $FirmwareFile" -ForegroundColor Red
        return $false
    }

    Write-Host "[INFO] Firmware file confirmed." -ForegroundColor Green

    # Use the AVRDUDE settings defined at the top of the script:
    # $Mcu
    # $Programmer
    # $Baud

    $avrdudeArgs = @(
        "-c", $Programmer
        "-p", $Mcu
        "-P", $Port
        "-b", $Baud
        "-D"
        "-U", "flash:w:${FirmwareFile}:i"
    )

    Write-Host ""

    try {
        & $AvrdudeExe @avrdudeArgs
        $exitCode = $LASTEXITCODE
    }
    catch {
        Write-Host "[ERROR] Could not start AVRDUDE: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    if ($exitCode -ne 0) {
        Write-Host "[ERROR] AVRDUDE failed with exit code $exitCode." -ForegroundColor Red
        return $false
    }

    Write-Host "[OK] Firmware flashed successfully." -ForegroundColor Green
    return $true
}

Clear-Host

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "     Firmware updater for 6522 Tester" -ForegroundColor Cyan
Write-Host "                 Version $ScriptVersion" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host $WebsiteUrl
Write-Host $RepoUrl
Write-Host ""

Ensure-AvrdudeDirectory

$installedAvrdudeVersion = Get-AvrdudeVersion -Exe $AvrdudeExe

if ($installedAvrdudeVersion) {

    Write-OK "Local AVRDUDE version: $installedAvrdudeVersion"
}
else {

    if (Test-Path $AvrdudeExe) {
        Write-Warn "AVRDUDE exists but its version could not be detected."
    }
    else {
        Write-Info "AVRDUDE is not installed."
    }
}

$avrdudeRelease = Get-LatestAvrdudeRelease

if ($null -ne $avrdudeRelease) {

    $latestAvrdudeVersion =
        Convert-ToVersion $avrdudeRelease.tag_name

    if ($latestAvrdudeVersion) {

        Write-Info "Latest AVRDUDE version: $latestAvrdudeVersion"

        $needsAvrdudeUpdate = $false

        if ($null -eq $installedAvrdudeVersion) {
            $needsAvrdudeUpdate = $true
        }
        elseif ($installedAvrdudeVersion -lt $latestAvrdudeVersion) {
            $needsAvrdudeUpdate = $true
        }

        if ($needsAvrdudeUpdate) {

            Write-Info "Installing/updating AVRDUDE..."

            if (-not (Install-LatestAvrdude)) {

                if (-not (Test-Path $AvrdudeExe)) {
                    Stop-Updater "AVRDUDE is required but could not be installed."
                }

                Write-Warn "Continuing with existing AVRDUDE."
            }
        }
        else {

            Write-OK "Local AVRDUDE is up to date."
        }
    }
}
else {

    if (-not (Test-Path $AvrdudeExe)) {
        Stop-Updater "No local AVRDUDE and GitHub could not be contacted."
    }

    Write-Warn "Could not check latest AVRDUDE. Using local copy."
}

# Re-check after possible installation
if (-not (Test-Path $AvrdudeExe)) {
    Stop-Updater "avrdude.exe is missing."
}

if (-not (Test-Path $AvrdudeConf)) {
    Stop-Updater "avrdude.conf is missing."
}

$installedAvrdudeVersion = Get-AvrdudeVersion -Exe $AvrdudeExe

if ($installedAvrdudeVersion) {
    Write-OK "AVRDUDE v$installedAvrdudeVersion"
}
else {
    Write-Warn "AVRDUDE version could not be parsed, but AVRDUDE is available."
}

Write-Host ""


$release = Get-LatestFirmwareRelease

if ($null -eq $release) {
    Stop-Updater "Cannot continue without GitHub firmware release information."
}

$releaseTag = $release.tag_name
$remoteVersion = Convert-ToVersion $releaseTag

if (-not $remoteVersion) {

    # Fallback to raw version file
    Write-Warn "Could not parse release version."

    try {

        $rawVersion = Invoke-RestMethod `
            -Uri $RawVersionUrl `
            -Method Get `
            -TimeoutSec 15

        $remoteVersion = Convert-ToVersion $rawVersion
    }
    catch {}
}

if (-not $remoteVersion) {
    Stop-Updater "Could not determine firmware version from GitHub."
}

Write-OK "Latest GitHub release: $releaseTag"

$firmwareAsset = Get-SafeFirmwareAsset -Release $release

if ($null -eq $firmwareAsset) {
    Stop-Updater "No firmware HEX was found."
}

if ($firmwareAsset.size) {
    Write-OK "Firmware size: $($firmwareAsset.size) bytes"
}

Write-Host ""

$arduino = Find-ArduinoMega

if ($null -eq $arduino) {

    Write-Fail "Arduino Mega 2560 was not detected."
    Write-Fail "Make sure the board is connected."

    Write-Host ""
    Write-Host "Detected serial devices:" -ForegroundColor Yellow

    Get-CimInstance Win32_SerialPort |
        Select-Object DeviceID, Name, PNPDeviceID |
        Format-Table -AutoSize

    exit 1
}

$port = $arduino.DeviceID

Write-OK "Arduino detected."
Write-OK "Port: $port"
Write-OK "Device: $($arduino.Name)"

Write-Host ""

$arduinoVersionText = Read-ArduinoVersion `
    -PortName $port `
    -BaudRate $Baud `
    -TimeoutSeconds $ReadTimeoutSeconds

if ([string]::IsNullOrWhiteSpace($arduinoVersionText)) {

    Write-Fail "Could not read firmware version from Arduino."
    Write-Fail "Make sure the firmware responds to:"
    Write-Host ""
    Write-Host '    version'
    Write-Host ""

    exit 1
}

$arduinoVersion = Convert-ToVersion $arduinoVersionText

if ($null -eq $arduinoVersion) {

    Write-Fail "Arduino returned an invalid version: $arduinoVersionText"
    exit 1
}

Write-OK "Arduino reports version: v$arduinoVersion"
Write-Host ""

if ($arduinoVersion -eq $remoteVersion) {

    Write-Host ""
    Write-Host "STATUS: Arduino is already up to date." -ForegroundColor Green
    Write-Host ""
    Write-Host "No firmware update is required."

    exit 0
}

if ($arduinoVersion -gt $remoteVersion) {

    Write-Host ""
    Write-Warn "The Arduino version is newer than the latest GitHub release."
    Write-Host ""
    Write-Host "Installed : v$arduinoVersion"
    Write-Host "GitHub    : v$remoteVersion"
    Write-Host ""

    $continue = Read-Host "Download/flash the GitHub version anyway? [y/N]"

    if ($continue -notmatch '^(y|yes)$') {
        Write-Info "Update cancelled."
        exit 0
    }
}
else {

    Write-Host ""
    Write-Host "STATUS: Firmware update available." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Installed : v$arduinoVersion"
    Write-Host "Available : v$remoteVersion"
}

Write-Host ""

if (-not (Download-Firmware `
    -Asset $firmwareAsset `
    -Destination $FirmwareFile)) {

    Stop-Updater "Firmware download failed."
}

Write-Host ""

Write-Host "The firmware will now be written to flash."
Write-Host ""

$confirm = Read-Host "Continue? [y/N]"

if ($confirm -notmatch '^(y|yes)$') {

    Write-Info "Firmware update cancelled."
    exit 0
}

Write-Host ""

if (-not (Flash-Firmware `
    -Port $port `
    -FirmwareFile $FirmwareFile)) {

    Stop-Updater "Firmware flashing failed."
}

Write-Host ""
Write-Info "Waiting for Arduino to restart..."

Start-Sleep -Seconds 2

Write-Info "Re-checking Arduino firmware version..."

$newArduinoVersionText = Read-ArduinoVersion `
    -PortName $port `
    -BaudRate $Baud `
    -TimeoutSeconds $ReadTimeoutSeconds

if ([string]::IsNullOrWhiteSpace($newArduinoVersionText)) {

    Write-Warn "Firmware flashed successfully, but the version could not be read after reboot."
    Write-Host ""
    Write-Host "Update operation completed."
    exit 0
}

$newArduinoVersion = Convert-ToVersion $newArduinoVersionText

Write-Host ""

if ($null -eq $newArduinoVersion) {

    Write-Warn "Arduino returned an unrecognised version: $newArduinoVersionText"
    exit 0
}

if ($newArduinoVersion -eq $remoteVersion) {

    Write-Host "             UPDATE SUCCESSFUL" -ForegroundColor Green
    Write-Host ""
    Write-Host "Arduino now reports: v$newArduinoVersion"
    Write-Host ""
}
else {

    Write-Host "        FLASH COMPLETED - VERSION DIFFERENT" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Expected : v$remoteVersion"
    Write-Host "Reported : v$newArduinoVersion"
    Write-Host ""
    Write-Warn "Please check the firmware's version reporting."
}

exit 0

