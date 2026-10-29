# Emerson Arcadia 2001 for MiST-family FPGA boards

[*Leer en español*](README_es.md)

An FPGA implementation of the **Emerson Arcadia 2001** (1982) game console, with its Signetics 2650 CPU and 2637 UVI video/sound chip, for the **MiST**, **SiDi**, **Calypso** and **Poseidon** boards.

The core itself is **Grabulosaure's** MiSTer Arcadia core. The **port to Poseidon was done by Turri ([@turri21](https://github.com/turri21))**, based on his port to Senhor: [turri21/Arcadia_Senhor](https://github.com/turri21/Arcadia_Senhor), which is the reference for this repository.

Our contribution is small: we fixed the OSD and the video syncs of the Poseidon port, then the block graphics, the controller mapping and the OSD colour, and arranged the project so the same sources build for the other MiST-family boards.

## Board status

| Board | FPGA | Clock | Video | Audio | Status |
|---|---|---|---|---|---|
| Poseidon | Cyclone IV GX EP4CGX150 | 50 MHz | 6-bit VGA | I2S | Tested on hardware |
| MiST | Cyclone III EP3C25 | 27 MHz | 6-bit VGA | Sigma-delta | Not yet tested |
| SiDi | Cyclone IV E EP4CE22 | 27 MHz | 6-bit VGA | Sigma-delta | Not yet tested |
| Calypso | Cyclone 10 LP 10CL025 | 12 MHz | 4-bit VGA | I2S | Not yet tested |

The core needs no SDRAM: the cartridge (up to 16 KiB) and the video RAM live in FPGA block RAM.

## What we changed

**OSD.** The Poseidon port still used the OSD's automatic pixel-clock detection with `ce_divider=1`. On VGA this squeezed the OSD to about a third of the screen width, and its size changed between 15 kHz and 31 kHz. Now `mist_video` uses a fixed pixel enable (`OSD_AUTO_CE=0`) with `ce_divider=3` (clk_sys/4), so every line has 368 active samples at both frequencies and the 256-pixel OSD is centred, with the same proportions, in both modes. The `osd_enable` output is now connected, so "Pause Core on OSD" works, and the core's HBlank/VBlank are registered like its syncs.

**Video syncs.** The 2637 core uses its internal signals as syncs, active high: a 7.3 µs HSync with a 2.2 µs back porch, and the 20-line vertical reset (VRST) as VSync, with no vertical porch at all. At 15 kHz the picture shook, and at 31 kHz the scandoubler turned that into a 40-line VSync with no back porch and +/+ polarity, which a monitor cannot match to any standard mode. `rtl/arcadia_sync.v` now generates standard, active-low syncs, with 15 kHz timings when the scandoubler is off and timings that become close to 640×480 after it:

| | Before (15 kHz) | Now (15 kHz) | Before (31 kHz) | Now (31 kHz) | 640×480 |
|---|---|---|---|---|---|
| HSync | 7.26 µs | 4.75 µs | 3.63 µs | 3.21 µs | 3.81 µs |
| Front / back porch | 2.51 / 2.23 µs | 1.47 / 5.80 µs | 1.26 / 1.12 µs | 0.56 / 2.23 µs | 0.64 / 1.91 µs |
| VSync | 20 lines | 3 lines | 40 lines | 2 lines | 2 lines |
| Vertical front / back porch | 0 / 0 | 3 / 14 | 0 / 0 | 10 / 28 | 10 / 33 |
| Polarity | +/+ | −/− | +/+ | −/− | −/− |

**Clock and timing.** The old "Video output NTSC/PAL" option switched the system clock between two PLL outputs through a logic multiplexer, which can glitch the clock; and since the 2637 core has PAL mode tied off, "PAL" only ran the console 24 % faster. It has been removed. The `.sdc` files now constrain `SPI_SCK` and declare it asynchronous to the system clock.

**Block graphics and controllers.** The block-graphics control codes `$C0`/`$40` had been restricted to the first column of each line; they work again in any column, as in MAME and in the original core (this fixes the katakana title of Mobile Soldier Gundam). The D-pad directions now match the analog stick and MAME (right and down give high values), the MiST analog X/Y bytes are read in the right order, "Reverse Left/Right" and "Reverse Up/Down" act on the axes they name, and the right stick's up-left diagonal gives keypad 7 instead of 8. Player 1's joystick is read at $19FF and its keypad at $1900, as in MAME; the per-game table of the Poseidon port still swaps both to the other controller for the games that need it.

**OSD text.** The OSD uses the standard MiST modules, with `OSD_COLOR` set to 1: a blue window instead of the default red, which made the text look pinkish. As in every MiST core, the OSD window is semi-transparent and the text keeps the low bits of the video underneath, so it can shift slightly in tone over very bright or saturated backgrounds.

All of this was checked in simulation (Icarus Verilog) with the exact 2637 timing and the real `mist_video`, and on a Poseidon.

## Controls

Gamepad (players 1 and 2):

| Gamepad | Arcadia |
|---|---|
| D-pad | Joystick |
| A / B | Fire (keypad 2) |
| X | Option |
| Y | Enter |
| Select / Start | Select / Start |
| L / R | Clear / Keypad 0 |
| L2 / R2 | Keypad 1 / Keypad 3 |
| L3 / R3 | Keypad 4 / Keypad 6 |
| Right analog stick | Keypad 1-2-3-4-6-7-8-9 in 8 directions |

Keyboard:

| | Player 1 | Player 2 |
|---|---|---|
| Keypad 1 2 3 | `1` `2` `3` | `8` `9` `0` |
| Keypad 4 5 6 | `Q` `W` `E` | `I` `O` `P` |
| Keypad 7 8 9 | `A` `S` `D` | `K` `L` `;` |
| Clear / 0 / Enter | `Z` `X` `C` | `,` `.` `/` |

`Space` is Start, `F1` Select and `F2` Option.

Cartridges are loaded from the OSD as `.BIN` files. The machine is NTSC only.

## Building

Open the project for your board (`mist/`, `sidi/`, `calypso/` or `poseidon/`) in Quartus and compile. `files.qip` lists the sources shared by all boards; each board folder has its own `.qsf` (pins and macros), PLL and `.sdc`. The board is selected with a Verilog macro (`MIST`, `SIDI`, `POSEIDON`; none for Calypso).

`common/mist-modules` is a git submodule ([teiram/mist-modules](https://github.com/teiram/mist-modules)). After cloning:

```
git submodule update --init
```

## Credits

- **Arcadia core** (Signetics 2650 CPU and 2637 UVI): **Grabulosaure** (TEMLIB), from the original MiSTer core.
- **Port to Senhor and Poseidon**: **Turri ([@turri21](https://github.com/turri21))** — [Arcadia_Senhor](https://github.com/turri21/Arcadia_Senhor) is the reference for this repository.
- **MiST modules** (`user_io`, `data_io`, `mist_video`, OSD, scandoubler and related): Till Harbaum, Gyorgy Szombathelyi (gyurco) and the MiST community.
- Board projects (pins and settings) for MiST, SiDi and Calypso taken from [shaeon/newbrain](https://github.com/shaeon/newbrain).
- OSD, video sync and controller fixes, and multi-board arrangement: Shaeon (Carlos Palmero).

## AI assistance and resources

The OSD, video sync and controller fixes and the multi-board arrangement were developed with the assistance of Claude (Anthropic), used for analysis, simulation and documentation. Access to Claude was provided by Advanced Computer Trading, S.L. (actsl.com). Testing on real hardware and final review were carried out by Shaeon (Carlos Palmero).

## License

The Arcadia core is distributed under the **GNU General Public License version 2**, as in [Arcadia_Senhor](https://github.com/turri21/Arcadia_Senhor); see [LICENSE](LICENSE). Third-party files, such as the MiST modules, keep their own copyright notices and licenses.

## Disclaimer

This project is provided **"as is", without warranty of any kind**, express or implied. In no event shall the authors or contributors be liable for any claim, damages or other liability arising from the use of this software, of the hardware it runs on, or of any connected equipment. Use it at your own risk.

Arcadia 2001 is a trademark of its respective owners. This project is not affiliated with or endorsed by them.
