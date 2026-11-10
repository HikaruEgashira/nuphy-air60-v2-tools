# nuphy-air60-v2-tools

macOS command-line tools for recovering and customizing a NuPhy Air60 V2 keyboard without the Windows-only NuPhy Console.

## Tools

| Binary | Purpose |
|---|---|
| `bin/ble-scan` | Lists BLE advertisers for 15 s (name, RSSI, CoreBluetooth UUID, service UUIDs). |
| `bin/nrf-dfu <dir>` | Flashes the nRF52 RF firmware over BLE using the Nordic Secure DFU protocol. `<dir>` holds the extracted `app.dat` and `app.bin` of `NUPHY_RF_OTA_Vx.x.x.zip`. Every 4 KiB object is verified with CRC32. |
| `bin/via-raw <hex bytes…>` | Sends one 32-byte VIA raw-HID report over USB and prints the response. |
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
4. Power-cycle the keyboard, switch to Bluetooth, and hold `Fn + 1` for 3–5 s to pair.

## Key combinations (from nuphy-src/qmk_firmware)

| Combination | Action |
|---|---|
| `Fn + -` (hold ~3 s) | Factory reset: clears BT bonds and EEPROM |
| `Fn + [` (wired mode) | RF factory reset / enter DFU |
| `Fn + 1/2/3` (hold) | Pair BT slot 1/2/3 |

## Caps-mouse layer

```sh
make && scripts/caps-mouse.sh   # keyboard connected by USB, switch on wired
```

The script aborts without writing if layer 0 does not match the stock layout (`Fn = MO(1)`, `Caps = KC_CAPS`). The mapping is stored in EEPROM and survives Bluetooth mode; a factory reset removes it. Caps Lock is no longer available on the base layers.

## Limitations

- The VIA `eeprom_reset` command (`0x0A`) is not supported by the stock firmware; use `Fn + -`.
- Firmware binaries are not redistributed here.

## License

MIT. See [LICENSE](LICENSE).
