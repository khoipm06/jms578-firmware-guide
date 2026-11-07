# JMicron JMS578 Firmware Update & Performance Guide
### Fixing Linux UAS Stability, Disconnects, and Drive Standby (With Emergency BootROM Hardware Recovery)

A battle-tested field manual for updating, configuring, and optimizing **JMicron JMS578** USB 3.0 to SATA bridge enclosures on Linux. Written to help developers, homelabbers, and storage enthusiasts navigate real-world firmware traps, configure valid NVRAM parameters, verify kernel UAS driver bindings, and recover bricked controllers via hardware BootROM.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Firmware: Hardkernel v173.01.00.02](https://img.shields.io/badge/Firmware-Hardkernel_v173.01.00.02-success.svg)](firmware/)
[![Tested on Linux: 6.x / 7.x](https://img.shields.io/badge/Kernel-Linux_6.x_%2F_7.x-orange.svg)](https://kernel.org)

---

## Table of Contents
1. [The Problem: Why Update JMS578 Firmware?](#1-the-problem-why-update-jms578-firmware)
2. [Hardware Architecture & Mental Model](#2-hardware-architecture--mental-model)
3. [Firmware Selection: What to Flash & What to Avoid](#3-firmware-selection-what-to-flash--what-to-avoid)
4. [The NVRAM Decoupling Principle (Can ODD Firmware Be Used?)](#4-the-nvram-decoupling-principle-can-odd-firmware-be-used)
5. [Tool Setup: Building `jms578flash` with PUYA Support](#5-tool-setup-building-jms578flash-with-puya-support)
6. [Step 1: Backing Up Factory Firmware](#6-step-1-backing-up-factory-firmware)
7. [Step 2: Step-by-Step Firmware Flashing Procedure](#7-step-2-step-by-step-firmware-flashing-procedure)
8. [Step 3: Enabling & Verifying SuperSpeed UAS on Linux](#8-step-3-enabling--verifying-superspeed-uas-on-linux)
9. [Critical Caveats & Lessons Learned](#9-critical-caveats--lessons-learned)
10. [Emergency Disaster Recovery: Hardware Unbricking (The Jig)](#10-emergency-disaster-recovery-hardware-unbricking-the-jig)
11. [Digital Forensics: Recovering Lost Factory ROM from Raw SPI Logs](#11-digital-forensics-recovering-lost-factory-rom-from-raw-spi-logs)
12. [Acknowledgements](#12-acknowledgements)

---

## 1. The Problem: Why Update JMS578 Firmware?

The JMicron JMS578 is one of the most widely deployed USB 3.0 to SATA 6 Gb/s bridge controllers, found in external drive enclosures from XDISK, Sabrent, Orico, and single-board computers like ODROID-HC1/HC2.

However, factory OEM firmwares (predominantly 2016–2017 revisions like `32.02`) suffer from three major shortcomings under Linux:

1. **UAS Bus Deadlock / Blacklist**: Older firmware revisions trigger bus lockups under command queuing. The Linux kernel marks these older revisions with `US_FL_IGNORE_UAS`, forcing fallback to slower Bulk-Only Transport (BOT).
2. **Infinite Drive Spin (No Standby)**: Many OEM enclosures ship with the standby timer disabled (`Timer = 0`). Mechanical disks spin at full speed 24/7, generating excessive heat and shortening drive lifespan.
3. **Random Bus Resets Under Heavy I/O**: High queue depth operations (e.g. `zfs scrub`, multi-stream transfers, or database writes) cause controller crashes on stock firmware.

Updating to **Hardkernel `v173.01.00.02`** resolves these defects: it enables native, stable **USB Attached SCSI (UAS)**, full **SMART pass-through** (`smartctl -a /dev/sdX`), and an automatic **10-minute drive spin-down timer**.

---

## 2. Hardware Architecture & Mental Model

```mermaid
graph LR
    Host["Host Computer<br/>(Linux / xHCI)"] -- "USB 3.0 (5 Gbps SuperSpeed)" --> JMS578["JMicron JMS578 Controller<br/>(8051 MCU + RAM + ROM)"]
    JMS578 -- "SPI Bus (4-Wire)" --> SPIFlash["SPI NOR Flash (SOIC-8, 256 KB)<br/>PUYA P25D21 / Winbond<br/>[48 KB Code + 512 B NVRAM]"]
    JMS578 -- "SATA III (6 Gbps)" --> Drive["SATA Storage Drive<br/>(Mechanical HDD / SSD)"]
```

- **JMS578 Bridge Controller**: Contains an 8051 microcontroller running at 30–60 MHz. It has **no onboard writable flash memory**. All persistent configuration is loaded from the external SPI flash at boot.
- **SPI NOR Flash (SOIC-8)**: The sole non-volatile memory on the PCB. It stores 48 KB of 8051 executable binary code and a 512-byte NVRAM configuration block.
- **Firmware Binary Layout (`.bin`, 50,688 bytes)**:

```mermaid
flowchart TD
    subgraph BinFile["Firmware Image (*.bin, 50,688 Bytes)"]
        direction TB
        CodeBlock["8051 Machine Code<br/>(Offset 0x0000 - 0xC3FF, 48 KB)"]
        NVRAMBlock["NVRAM Configuration Block<br/>(Offset 0xC400 - 0xC5FF, 512 Bytes)"]
    end

    subgraph NVRAMBreakdown["NVRAM Breakdown"]
        direction TB
        USBDesc["0x000 - 0x05F: USB Descriptors (VID/PID, Vendor Strings, Serial)"]
        HDBlock["0x0E0 - 0x0EF: Disk Class Config (0x0E7: 0xC3 HDD vs 0xC6 ODD)"]
        BCBlock["0x0F0 - 0x0FF: Board Config (GPIO Power FET Polarity, Standby Timer)"]
    end

    NVRAMBlock --> USBDesc
    NVRAMBlock --> HDBlock
    NVRAMBlock --> BCBlock
```

---

## 3. Firmware Selection: What to Flash & What to Avoid

| Firmware Image | Disk Mode (`0x0E7`) | GPIO Config | Standby Timer | Linux UAS Stability | Verdict |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Hardkernel ODROID (`v173.01.00.02`)** | **`0xC3` (HDD)** | **`0x38 0xC1`** | **10 Minutes (`600s`)** | **Optimal (UAS + SMART)** | **RECOMMENDED** |
| **Factory OEM Dump (`32.02`)** | `0x43` (HDD) | `0x30 0xC0` | Disabled (`0s`) | Blacklisted (`usb-storage`) | Keep as emergency backup |
| **JMicron STD ODD (`v00.04.01.04`)** | `0xC6` (ODD) | `0x28 0xC9` | 10 Minutes (`600s`) | Deadlock (Tray Poll Loop) | **DO NOT FLASH (Bricks Board)** |

### Why Hardkernel `v173.01.00.02` is the Gold Standard:
Originally developed for the ODROID-HC1/HC2 Linux NAS platforms, this build fixes xHCI command queueing timeouts, enables clean ATA pass-through for `smartctl`, and handles drive standby without bus resets.

---

## 4. The NVRAM Decoupling Principle (Can ODD Firmware Be Used?)

> [!NOTE]
> The 8051 machine code inside `JMS578_STD_v00.04.01.04_Self Power + ODD.bin` is **NOT corrupt**. The crash is caused exclusively by the **ODD NVRAM block** bundled at the tail of the file.

```mermaid
flowchart LR
    ODD_CODE["v00.04.01.04 Code<br/>(48 KB Code Block)"] --> MERGER["Binary Merger"]
    HDD_NVRAM["Standard Storage NVRAM<br/>(Byte 0x0E7 = 0xC3/0x43, GPIO = 0x38/0x30)"] --> MERGER
    MERGER --> SAFE_BIN["Safe Storage Firmware<br/>(Runs on standard drive enclosures)"]
```

If you ever need features from the `00.04.01.04` codebase, do not flash the `.bin` as-is. Instead, alter byte `0xC4E7` from `0xC6` to `0xC3` (or append the 512-byte NVRAM from the Hardkernel image).

---

## 5. Tool Setup: Building `jms578flash` with PUYA Support

Many modern enclosures use **PUYA Semiconductor P25D21 / P25Q20** NOR flash chips (`JEDEC ID: 0x85441285`). Upstream `jms578flash` lacks this ID and terminates with:
```
unsupported flash type: 85441285
```

This repository includes a git submodule for upstream `jms578flash`, a patch file [`tools/puya_flash_support.patch`](tools/puya_flash_support.patch), and an automated containerized build script:

```bash
# Clone the repository with submodules
git clone --recursive https://github.com/khoipm06/jms578-firmware-guide.git
cd jms578-firmware-guide

# Build the patched static binary (uses Podman, Docker, or native Go)
./tools/build.sh
```

The script automatically initializes the submodule, applies the PUYA patch, and builds a static 64-bit ELF binary at `tools/jms578flash_x86_64`.

---

## 6. Step 1: Backing Up Factory Firmware

**Always dump your existing firmware before flashing anything:**

```bash
# 1. Identify your enclosure block device (e.g. /dev/sda)
lsblk

# 2. Extract current SPI flash content
sudo tools/jms578flash_x86_64 -dev /dev/sda -extract -firmware backup_original.bin
```

---

## 7. Step 2: Step-by-Step Firmware Flashing Procedure

Once the device is recognized (e.g. at `/dev/sda`):

### Option A: Flash the Recommended Hardkernel Firmware
```bash
sudo tools/jms578flash_x86_64 \
  -dev /dev/sda \
  -flash \
  -firmware firmware/JMS578-Hardkenel-Release-v173.01.00.02-20190306.bin \
  -hook=false \
  -unsafe
```

### Option B: Restore Original Factory Firmware (Rollback)
```bash
sudo tools/jms578flash_x86_64 \
  -dev /dev/sda \
  -flash \
  -firmware firmware/factory_restoration.bin \
  -hook=false \
  -unsafe
```

### Explanation of Mandatory Flags:
- `-dev /dev/sda`: SCSI block device node for the enclosure.
- `-flash`: Enables write/reflash mode on the SPI flash.
- `-firmware <file>`: Target firmware binary path.
- `-hook=false`: Writes 100% clean vendor machine code, preventing the insertion of external ASM hooks.
- `-unsafe`: Disengages the safety interlock to allow raw sector erase (`0x60`) and page write (`0x02`) commands.
- **NEVER pass `-mods ClearNVRAM`**: Preserves the valid NVRAM configuration table (GPIO assignments, LED mapping, and the 10-minute standby timer).

### Post-Flash Hard Power Cycle:
1. Run `sync` in your terminal to flush filesystem caches.
2. Unplug the USB cable $\to$ Unplug the 12V DC power barrel jack.
3. Wait **5 seconds** for power capacitors to fully discharge.
4. Plug in the 12V DC power barrel jack $\to$ Reconnect the USB cable so the controller loads the new configuration.

---

## 8. Step 3: Enabling & Verifying SuperSpeed UAS on Linux

### Linux Kernel Driver Behavior:
By default, the Linux kernel sets quirk `0x1800000` (`US_FL_IGNORE_UAS`) for VID:PID `152d:0578` devices running legacy 2016-era firmwares due to command queuing lockups.

With **Hardkernel `v173.01.00.02`** flashed, controller stability is resolved. On modern Linux kernels (5.x, 6.x, 7.x), the kernel automatically binds `152d:0578` directly to `Driver=uas` without requiring any manual quirks.

> [!NOTE]
> In Linux kernel source code (`drivers/usb/storage/usb.c`), the quirk character `u` corresponds to `US_FL_IGNORE_UAS` (bypasses the UAS driver and forces `usb-storage`). Do not configure `quirks=152d:0578:u` in `/etc/modprobe.d/`. If an erroneous file exists, remove it:
> ```bash
> sudo rm -f /etc/modprobe.d/jms578*.conf
> ```

### Verifying UAS Status:
Check the USB driver tree:
```bash
lsusb -t
```
Under your USB 3.0 root hub, the mass storage interface will report:
```
|__ Port 001: Dev 002, If 0, Class=Mass Storage, Driver=uas, 5000M
```

Or run the included diagnostic script:
```bash
./scripts/check_uas.sh
```

---

## 9. Critical Caveats & Lessons Learned

1. **Never Hot-Plug 3.5" Hard Drives into a Powered Board**: The instant inrush current when a mechanical spindle motor spins up is very high. Hot-plugging causes a severe voltage drop on the 12V/5V rails, resetting the microcontroller or causing voltage spikes that can destroy the power MOSFET or the SATA PHY. **Always seat the drive into the SATA port before connecting 12V DC power.**
2. **Always Check the ODD Flag Before Flashing**: Inside any firmware `.bin` image, check the byte at offset `0xC4E7`. If `bit 2 = 1` (such as `0xC6`), the image is compiled for an Optical Disc Drive (CD/DVD). Flashing this to a hard drive enclosure causes an immediate BootROM deadlock because the chip halts waiting for tray and laser GPIO responses.
3. **Never Use Unpowered USB Hubs During Recovery**: Initial BootROM enumeration is sensitive to bus latency and voltage dips. Flashing through cheap hubs frequently causes USB timeout errors (`error -71` / `error -110`). Always plug the USB cable directly into a motherboard port.
4. **Always Back Up the Original NVRAM**: Different enclosure manufacturers wire the drive activity LED and the power MOSFET gate to different GPIO pins on the JMS578. Keeping an intact backup of your factory NVRAM ensures you can restore correct pin assignments for your specific enclosure hardware.

---

## 10. Emergency Disaster Recovery: Hardware Unbricking (The Jig)

If your board is completely frozen (two solid LEDs, zero USB enumeration, no `/dev/sdX`), the 8051 microcontroller is stuck in an execution loop. You must force the chip into its internal **ROM Bootloader** by disabling external SPI flash reads during power-up.

### SOIC-8 Flash Pinout & Bridge Target

```mermaid
graph TD
    subgraph SOIC8["SOIC-8 Flash Pinout (Top View)"]
        direction LR
        subgraph LeftPins["Left Side (Pins 1 - 4)"]
            direction TB
            P1["Pin 1: CE# (Chip Enable)"]
            P2["Pin 2: MISO (Data Out) ⚡ BRIDGE"]
            P3["Pin 3: WP# (Write Protect)"]
            P4["Pin 4: GND (Ground) ⚡ BRIDGE"]
        end
        subgraph RightPins["Right Side (Pins 5 - 8)"]
            direction TB
            P8["Pin 8: VCC (3.3V Power)"]
            P7["Pin 7: HOLD#"]
            P6["Pin 6: SCK (Clock)"]
            P5["Pin 5: MOSI (Data In)"]
        end
    end
    P2 <-->|"Bridge with tweezers (1-2s)"| P4
    style P2 fill:#ff7043,stroke:#333,stroke-width:2px,color:#fff
    style P4 fill:#ff7043,stroke:#333,stroke-width:2px,color:#fff
```

### The Unbrick Sequence:

```mermaid
sequenceDiagram
    autonumber
    actor Tech as Engineer / User
    participant Board as JMS578 PCB + SATA Port
    participant SPI as SPI Flash (SOIC-8)
    participant Host as Linux Host Machine

    Tech->>Board: 1. Plug SATA drive firmly into SATA connector
    Tech->>Host: 2. Connect USB cable directly to PC motherboard port
    Tech->>SPI: 3. Bridge Pin 2 (MISO) to Pin 4 (GND) with tweezers
    Tech->>Board: 4. Insert 12V DC power barrel plug
    Note over SPI: Hold tweezers bridge for 1 to 2 seconds
    Tech->>SPI: 5. Release tweezers
    Board->>Host: 6. BootROM initializes, enumerating /dev/sdX
```

### Step-by-Step Jig Execution:
1. Disconnect DC power and USB cable.
2. **Attach a SATA drive** to the board's SATA port (mandatory for SCSI enumeration).
3. Connect USB cable directly to the PC (avoid unpowered hubs).
4. Use fine-tipped tweezers to short **Pin 2 (MISO)** to **Pin 4 (GND)** (or Pin 5 to Pin 6).
5. While holding the short, plug in the 12V DC power jack.
6. Hold for **1 to 2 seconds**, then release the tweezers immediately.
7. The Activity LED will turn off; the host computer will enumerate the device under BootROM.
8. Re-flash the safe Hardkernel firmware using the standard flashing command in [Step 2](#7-step-2-step-by-step-firmware-flashing-procedure).

---

## 11. Digital Forensics: Recovering Lost Factory ROM from Raw SPI Logs

If an enclosure is bricked before an explicit backup was saved, forensic reconstruction is possible if terminal logs captured raw SPI transactions:

```mermaid
flowchart LR
    RawLog["Raw Terminal Logs<br/>(4,225 SPI Access Lines)"] --> Parser["Regex Parser & Offset Sorter"]
    Parser --> Blk0["Block 0 Header (0x0E00)"]
    Parser --> Blk1["Block 1 Boot Header (0x0000)"]
    Parser --> Code["8051 Machine Code (0x1000 - 0xC3FF)"]
    Parser --> NVRAM["Factory NVRAM (0xD000)"]
    Blk0 & Blk1 & Code & NVRAM --> Assembler["CRC-32 Assembler"]
    Assembler --> RestoredROM["100% Exact Factory Image<br/>(factory_restoration.bin)"]
```

During our investigation, 4,225 SPI read transactions (`0x03` opcode) were parsed, aligned into respective blocks, and validated against JMicron's CRC-32 polynomial algorithm, yielding a 100% byte-accurate factory image: [`firmware/factory_restoration.bin`](firmware/factory_restoration.bin).

---

## 12. Acknowledgements

- **[BertoldVdb](https://github.com/BertoldVdb)**: Creator of [`jms578flash`](https://github.com/BertoldVdb/jms578flash), the essential open-source Go tool for flashing JMS578 devices over raw SCSI pass-through.
- **[Hardkernel / ODROID Community](https://wiki.odroid.com/odroid-xu4/software/jms578_fw_update)**: For their collaboration with JMicron to produce and maintain the rock-solid `v173.01.00.02` firmware build for Linux storage platforms.
- **[Ralimtek (Ben V. Brown)](https://ralimtek.com/posts/2021/jms578/)**: For pioneering documentation on the SPI flash MISO pin-shorting BootROM recovery technique.
- **JMicron Technology Corporation**: For the JMS578 controller architecture.
