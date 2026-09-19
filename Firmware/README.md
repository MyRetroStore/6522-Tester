# 6522 Tester Firmware Updater

Firmware updater for the **6522 Tester** running on an **Arduino Mega 2560**.

The updater checks the firmware installed on the tester against the latest release on GitHub and can download, flash, and verify the update automatically.

## Features

* Automatic Arduino Mega 2560 detection
* Firmware version checking
* GitHub release checking
* Automatic firmware download
* Firmware flashing with `avrdude`
* Flash verification
* Post-update version verification
* Linux and Windows support

## Platforms

| Platform | Updater    |
| -------- | ---------- |
| Linux    | Bash       |
| Windows  | PowerShell |

## Linux

### Requirements

* `curl`
* `jq`
* `avrdude`

Install dependencies on Debian/Ubuntu:

```bash
sudo apt install curl avrdude jq
```

Run the updater:

```bash
chmod +x updater.sh
./updater.sh
```

## Windows

### Requirements

* Windows 10/11
* Arduino IDE installed
* PowerShell

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\updater.ps1
```

## Firmware Releases

Firmware is distributed through the GitHub releases:

https://github.com/MyRetroStore/6522-Tester/releases

The updater automatically checks for the latest release and optionally downloads and installs it. 

## Project

**6522 Tester**

https://github.com/MyRetroStore/6522-Tester

**MyRetroStore**

https://myretrostore.co.uk
