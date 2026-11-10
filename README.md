# nuphy-air60-v2-tools

macOS command-line tools for recovering and customizing a NuPhy Air60 V2 keyboard without the Windows-only NuPhy Console.

## Tools

| Binary | Purpose |
|---|---|
| `bin/ble-scan` | Lists BLE advertisers for 15 s (name, RSSI, CoreBluetooth UUID, service UUIDs). |
| `bin/nrf-dfu <dir>` | Flashes the nRF52 RF firmware over BLE using the Nordic Secure DFU protocol. `<dir>` holds the extracted `app.dat` and `app.bin` of `NUPHY_RF_OTA_Vx.x.x.zip`. Every 4 KiB object is verified with CRC32. |
| `bin/via-raw <hex bytes…>` | Sends one 32-byte VIA raw-HID report over USB and prints the response. |
| `bin/ddc get\|set <vcp> [value]` | Reads or writes a DDC/CI VCP feature on external displays (Apple Silicon). |
| `bin/input-source` | Lists, enables, selects, or disables macOS input sources. |
| `scripts/dvorak-ime.sh` | Puts Dvorak in the firmware and makes a Ctrl tap toggle the Japanese IME. |
| `bin/kvm-switch` | Switches the display input when the keyboard connects to or leaves this Mac over Bluetooth. |
| `bin/snap` | Caps-tap cursor pad with element snapping (F13). |
| `scripts/caps-mouse.sh` | Maps Caps + arrows to mouse movement, Caps + Space to left click, and Caps + Del to right click (dynamic keymap layer 7). |

## Build

```sh
make            # requires Xcode Command Line Tools
```

If `swiftc` complains about the Xcode license, use the Command Line Tools toolchain:

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools make
```

## Recovering Bluetooth pairing

The keyboard can keep advertising yet ignore connection requests from a new host. Updating the RF firmware resolved this.

1. Download `NUPHY_RF_OTA_V2.1.5.zip` from <https://nuphy.com/pages/qmk-firmwares> and verify its SHA-1 against that page.
2. `unzip NUPHY_RF_OTA_V2.1.5.zip -d rf && bin/nrf-dfu rf`
3. Connect USB-C, set the mode switch to wired, and press `Fn + [`. The RF chip resets to factory settings and advertises as `DfuTarg`; the tool connects and flashes it.
4. Power-cycle the keyboard, switch to Bluetooth, and hold `Fn + Q` for 3–5 s to pair.

## Dvorak in firmware and Ctrl-tap IME toggle

```sh
make && scripts/dvorak-ime.sh   # keyboard on USB, switch on wired
```

- Writes Dvorak to the Mac (0) and Windows (3) base layers, so every host and IME gets Dvorak. Set the OS layout to US/ABC (QWERTY).
- Ctrl is a mod-tap: hold for Ctrl, tap to toggle the IME. Mac sends F18, which the script binds to "Select the previous input source"; Windows sends LANG2 (VK_KANJI).
- On macOS the script selects ABC and removes the Dvorak layout.
- `bin/input-source list|enable|select|disable <id>` manages macOS input sources.

## Rear Mac/Win switch selects the host (custom firmware)

`firmware/` patches the stock NuPhy source (`UPSTREAM_COMMIT`) so that the rear Mac/Win switch also selects the Bluetooth slot: Mac → BT1, Win → BT2. Holding Esc at power-on still enters the bootloader but no longer wipes the VIA keymap (stock QMK bootmagic erases EEPROM). It also answers a VIA custom-value query (`08 00 01` → `[link_mode, ble_channel, sys_sw_state]`). `kvm-switch` uses that query to tell wired mode from a charging cable in Bluetooth mode.

```sh
firmware/build.sh            # needs arm-none-eabi-gcc on PATH
# then flash nuphy_air60_v2_ansi_kvm.bin as in "Updating the QMK firmware"
```

This firmware is unofficial. To go back, flash the official binary the same way.

## Updating the QMK (main MCU) firmware on Apple Silicon

The VIA bootloader-jump command is disabled, so enter the STM32 DFU bootloader by hand.

1. Download `QMK_firmware_nuphy_air60_v2_ansi_v2.1.5.bin` from <https://nuphy.com/pages/qmk-firmwares> and verify its SHA-1.
2. `dfu-util` from the QMK Toolbox app is x86_64 only; install Rosetta 2 (`softwareupdate --install-rosetta`) or use a native build.
3. Set the switch to wired, unplug, hold `Esc`, plug in, and release.
4. `dfu-util -a 0 -d 0483:df11 -s 0x08000000:leave -D QMK_firmware_nuphy_air60_v2_ansi_v2.1.5.bin`

Flashing resets the dynamic keymap; run `scripts/caps-mouse.sh` again afterwards.

## Key combinations (from nuphy-src/qmk_firmware)

| Combination | Action |
|---|---|
| `Fn + Q/W/E` | Switch to BT slot 1/2/3 (hold 3–5 s to pair; needs the mode switch on Bluetooth) |
| `Fn + R` | 2.4 GHz dongle |
| `Fn + [` (hold ~3 s) | Factory reset: clears BT bonds and EEPROM; in wired mode the RF chip enters DFU |
| `Fn + ]` | Toggle keyboard sleep |
| `Fn + \` | Show battery level |
| `Fn + 1/2` | Display brightness down/up (Mac layer) |

## Caps-mouse layer

```sh
make && scripts/caps-mouse.sh   # keyboard connected by USB, switch on wired
```

The script aborts without writing if layer 0 does not match the stock layout (`Fn = MO(1)`, `Caps = KC_CAPS`). The mapping is stored in EEPROM and survives Bluetooth mode; a factory reset removes it. Caps Lock is no longer available on the base layers.

### Caps pad

Tap Caps (`LT(7, F13)`) to start the pad; hold Caps for the mouse layer.

- The screen shows each letter key's label on its target element; nothing else is drawn.
- A letter key snaps the cursor to an element in that key's direction from the middle of the letter block. Keys near the middle go to neighboring elements, and edge keys go to far ones. The top row goes up and the bottom row goes down. Holding a key keeps stepping element by element.
- Space/Enter click, Shift+key moves and clicks, and Esc or another Caps tap exits.
- With the kvm firmware, the letter block glows dim white while the pad runs, and the key being pressed lights up.

| Hold Caps + | Action |
|---|---|
| arrows | mouse move |
| Space / Del | left / right click |

Needs Accessibility permission for the `snap` binary. `bin/snap count` prints how many elements it sees; `bin/snap show-pad` shows the pad for 3 s.

## Display input follows the keyboard (`kvm-switch`)

`Fn + Q/W/E` is handled inside the keyboard firmware, so no key event reaches the host. `kvm-switch` instead watches the keyboard's Bluetooth LE HID connection and sets the display input over DDC/CI (VCP `0x60`):

- the keyboard connects to this Mac → switch the display to this Mac's input;
- the keyboard leaves this Mac (after a 3 s debounce) → optionally switch to the other host's input.

Example: Mac A on HDMI1 uses BT slot 1, Mac B on HDMI2 uses BT slot 2.

```sh
make
scripts/install-kvm-switch.sh 17 18   # on Mac A (HDMI1): pair with Fn + Q
scripts/install-kvm-switch.sh 18 17   # on Mac B (HDMI2): pair with Fn + W
```

If the other host cannot run `kvm-switch`, the disconnect rule on the Mac still switches the display away; switching back happens when the keyboard reconnects to the Mac.

Input codes for DELL monitors: HDMI1 = 17, HDMI2 = 18, DP = 15, USB-C = 27. Check yours with `bin/ddc get 60` (the low byte of `current`).

Caveats:

- The keyboard drops its Bluetooth link when it sleeps, which looks like a slot switch. Disable keyboard sleep with `Fn + ]` if the disconnect rule fires unexpectedly.
- A wired (USB) connection to this Mac counts as connected, so flipping the switch to wired does not switch the display away.
- DDC/CI must be enabled in the monitor menu.
- Logs: `~/Library/Logs/kvm-switch.log`. Uninstall: `launchctl bootout gui/$(id -u)/dev.nuphy.kvm-switch`.

## Limitations

- The VIA `eeprom_reset` command (`0x0A`) is not supported by the stock firmware; use `Fn + [`.
- Firmware binaries are not redistributed here.

## License

MIT. See [LICENSE](LICENSE).
