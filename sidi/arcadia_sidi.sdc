create_clock -name CLOCK_27 -period 37.037 [get_ports {CLOCK_27}]
create_clock -name SPI_SCK -period 41.666 -waveform { 20.8 41.666 } [get_ports {SPI_SCK}]

derive_pll_clocks
derive_clock_uncertainty

# SPI (user_io / data_io / OSD) es asincrono respecto al reloj del sistema
set_clock_groups -asynchronous -group [get_clocks {SPI_SCK}] -group [get_clocks {*pll1|clk[*]}]
