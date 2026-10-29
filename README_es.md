# Emerson Arcadia 2001 para placas FPGA de la familia MiST

[*Read in English*](README.md)

Implementación en FPGA de la consola **Emerson Arcadia 2001** (1982), con su CPU Signetics 2650 y su chip de vídeo y sonido 2637 UVI, para las placas **MiST**, **SiDi**, **Calypso** y **Poseidon**.

El core es el de **Grabulosaure** para MiSTer. El **port a Poseidon lo hizo Turri ([@turri21](https://github.com/turri21))**, a partir de su port a Senhor: [turri21/Arcadia_Senhor](https://github.com/turri21/Arcadia_Senhor), que es la referencia de este repositorio.

Nuestra aportación es pequeña: arreglamos el OSD y los sincronismos de vídeo del port de Poseidon, después los gráficos de bloques, el mapeo de mandos y el color del OSD, y organizamos el proyecto para que los mismos fuentes compilen en las demás placas de la familia MiST.

## Estado por placa

| Placa | FPGA | Reloj | Vídeo | Audio | Estado |
|---|---|---|---|---|---|
| Poseidon | Cyclone IV GX EP4CGX150 | 50 MHz | VGA 6 bits | I2S | Probado en hardware |
| MiST | Cyclone III EP3C25 | 27 MHz | VGA 6 bits | Sigma-delta | Sin probar todavía |
| SiDi | Cyclone IV E EP4CE22 | 27 MHz | VGA 6 bits | Sigma-delta | Sin probar todavía |
| Calypso | Cyclone 10 LP 10CL025 | 12 MHz | VGA 4 bits | I2S | Sin probar todavía |

El core no necesita SDRAM: el cartucho (hasta 16 KiB) y la RAM de vídeo van en la memoria interna de la FPGA.

## Qué hemos cambiado

**OSD.** El port de Poseidon seguía usando la detección automática del reloj de píxel del OSD con `ce_divider=1`. En VGA eso dejaba el OSD comprimido a un tercio del ancho de la pantalla, y su tamaño cambiaba entre 15 kHz y 31 kHz. Ahora `mist_video` usa un pixel enable fijo (`OSD_AUTO_CE=0`) con `ce_divider=3` (clk_sys/4): cada línea tiene 368 muestras activas en las dos frecuencias y el OSD de 256 píxeles queda centrado, con las mismas proporciones, en ambos modos. La salida `osd_enable` ya está conectada, así que "Pause Core on OSD" funciona, y el HBlank/VBlank del core se registran igual que sus sincronismos.

**Sincronismos de vídeo.** El core del 2637 usa como sincronismos sus señales internas, a nivel alto: un HSync de 7,3 µs con 2,2 µs de porche posterior, y como VSync el reset vertical (VRST) de 20 líneas, sin ningún porche vertical. A 15 kHz la imagen temblaba, y a 31 kHz el scandoubler lo convertía en un VSync de 40 líneas sin porche posterior y polaridad +/+, que un monitor no puede asociar a ningún modo estándar. `rtl/arcadia_sync.v` genera ahora sincronismos estándar a nivel bajo, con tiempos de 15 kHz cuando el scandoubler está desactivado y con tiempos que tras él quedan muy cerca de 640×480:

| | Antes (15 kHz) | Ahora (15 kHz) | Antes (31 kHz) | Ahora (31 kHz) | 640×480 |
|---|---|---|---|---|---|
| HSync | 7,26 µs | 4,75 µs | 3,63 µs | 3,21 µs | 3,81 µs |
| Porche anterior / posterior | 2,51 / 2,23 µs | 1,47 / 5,80 µs | 1,26 / 1,12 µs | 0,56 / 2,23 µs | 0,64 / 1,91 µs |
| VSync | 20 líneas | 3 líneas | 40 líneas | 2 líneas | 2 líneas |
| Porche vertical anterior / posterior | 0 / 0 | 3 / 14 | 0 / 0 | 10 / 28 | 10 / 33 |
| Polaridad | +/+ | −/− | +/+ | −/− | −/− |

**Reloj y temporización.** La antigua opción "Video output NTSC/PAL" conmutaba el reloj del sistema entre dos salidas del PLL con un multiplexor lógico, lo que puede producir glitches de reloj; y como el core del 2637 tiene el modo PAL desactivado, "PAL" solo hacía ir la consola un 24 % más rápida. Se ha quitado. Los `.sdc` restringen ahora `SPI_SCK` y lo declaran asíncrono respecto al reloj del sistema.

**Gráficos de bloques y mandos.** Los códigos de control de gráficos de bloques `$C0`/`$40` se habían limitado a la primera columna de cada línea; vuelven a funcionar en cualquier columna, como en MAME y en el core original (esto arregla el título en katakana de Mobile Soldier Gundam). Las direcciones de la cruceta coinciden ya con las del stick analógico y con MAME (derecha y abajo dan valores altos), los bytes X/Y del analógico de MiST se leen en el orden correcto, "Reverse Left/Right" y "Reverse Up/Down" actúan sobre el eje que indican, y la diagonal arriba-izquierda del stick derecho da la tecla 7 en vez de la 8. El joystick del jugador 1 se lee en $19FF y su teclado en $1900, como en MAME; la tabla por juego del port de Poseidon sigue pasando los dos al otro mando en los juegos que lo necesitan.

**Texto del OSD.** El OSD usa los módulos MiST estándar, con `OSD_COLOR` a 1: ventana azul en lugar de la roja por defecto, que hacía que el texto pareciera rosado. Como en todos los cores MiST, la ventana del OSD es semitransparente y el texto conserva los bits bajos del vídeo de debajo, así que puede variar ligeramente de tono sobre fondos muy claros o saturados.

Todo esto se ha comprobado en simulación (Icarus Verilog), con la temporización exacta del 2637 y el `mist_video` real, y en una Poseidon.

## Controles

Mando (jugadores 1 y 2):

| Mando | Arcadia |
|---|---|
| Cruceta | Joystick |
| A / B | Disparo (tecla 2) |
| X | Option |
| Y | Enter |
| Select / Start | Select / Start |
| L / R | Clear / Tecla 0 |
| L2 / R2 | Tecla 1 / Tecla 3 |
| L3 / R3 | Tecla 4 / Tecla 6 |
| Stick analógico derecho | Teclas 1-2-3-4-6-7-8-9 en 8 direcciones |

Teclado:

| | Jugador 1 | Jugador 2 |
|---|---|---|
| Teclas 1 2 3 | `1` `2` `3` | `8` `9` `0` |
| Teclas 4 5 6 | `Q` `W` `E` | `I` `O` `P` |
| Teclas 7 8 9 | `A` `S` `D` | `K` `L` `Ñ` |
| Clear / 0 / Enter | `Z` `X` `C` | `,` `.` `-` |

`Espacio` es Start, `F1` Select y `F2` Option. (Las teclas del jugador 2 están indicadas en un teclado español; son las mismas posiciones que `;` y `/` en uno inglés.)

Los cartuchos se cargan desde el OSD como ficheros `.BIN`. La máquina es solo NTSC.

## Compilación

Abre en Quartus el proyecto de tu placa (`mist/`, `sidi/`, `calypso/` o `poseidon/`) y compila. `files.qip` lista los fuentes comunes a todas las placas; cada carpeta de placa tiene su `.qsf` (pines y macros), su PLL y su `.sdc`. La placa se elige con una macro de Verilog (`MIST`, `SIDI`, `POSEIDON`; ninguna para Calypso).

`common/mist-modules` es un submódulo de git ([teiram/mist-modules](https://github.com/teiram/mist-modules)). Después de clonar:

```
git submodule update --init
```

## Créditos

- **Core Arcadia** (CPU Signetics 2650 y UVI 2637): **Grabulosaure** (TEMLIB), del core original de MiSTer.
- **Port a Senhor y a Poseidon**: **Turri ([@turri21](https://github.com/turri21))** — [Arcadia_Senhor](https://github.com/turri21/Arcadia_Senhor) es la referencia de este repositorio.
- **Módulos MiST** (`user_io`, `data_io`, `mist_video`, OSD, scandoubler y relacionados): Till Harbaum, Gyorgy Szombathelyi (gyurco) y la comunidad MiST.
- Proyectos de placa (pines y ajustes) de MiST, SiDi y Calypso tomados de [shaeon/newbrain](https://github.com/shaeon/newbrain).
- Arreglos del OSD, de los sincronismos de vídeo y de los mandos, y organización multiplaca: Shaeon (Carlos Palmero).

## Asistencia de IA y recursos

Los arreglos del OSD, de los sincronismos de vídeo y de los mandos y la organización multiplaca se desarrollaron con la ayuda de Claude (Anthropic), usado para análisis, simulación y documentación. El acceso a Claude lo proporcionó Advanced Computer Trading, S.L. (actsl.com). Las pruebas en hardware real y la revisión final las hizo Shaeon (Carlos Palmero).

## Licencia

El core Arcadia se distribuye bajo la **Licencia Pública General de GNU, versión 2**, como en [Arcadia_Senhor](https://github.com/turri21/Arcadia_Senhor); ver [LICENSE](LICENSE). Los ficheros de terceros, como los módulos MiST, conservan sus propios avisos de copyright y licencias.

## Aviso

Este proyecto se ofrece **"tal cual", sin garantía de ningún tipo**, expresa o implícita. En ningún caso los autores o colaboradores serán responsables de reclamaciones, daños u otras responsabilidades derivadas del uso de este software, del hardware en el que se ejecute o de cualquier equipo conectado. Úsalo bajo tu propia responsabilidad.

Arcadia 2001 es una marca de sus respectivos propietarios. Este proyecto no está afiliado ni respaldado por ellos.
