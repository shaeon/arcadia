// ---------------------------------------------------------------------------
// Sincronismos estandar para la salida de video del Arcadia.
//
// El SC2637 del core usa como sincronismos sus senales internas:
//   HSync = hpos 201..226 (26 px, 7,3 us) y el video empieza 2,2 us despues
//   VSync = VRST, lineas 242..261 (20 lineas), sin ningun porche vertical
// ambos a nivel alto. Asi la salida no se parece a ningun modo estandar: a
// 15 kHz la imagen temblaba y a 31 kHz el monitor tiene que adivinar el modo
// (VSync de 40 lineas sin porche, polaridad +/+).
//
// Este modulo los regenera a partir de la temporizacion del core, a nivel
// BAJO (como la mayoria de cores MiST), con dos juegos de tiempos:
//
//   vga=0 (15 kHz, sin scandoubler):
//     HSync hpos 197..213 (17 px = 4,75 us), porches 1,4 / 5,6 us
//     VSync 3 lineas (vpos 245..247), porches 3 / 14 lineas
//
//   vga=1 (31 kHz; el scandoubler divide entre 2 los tiempos horizontales
//          y multiplica por 2 las lineas):
//     HSync hpos 196..218 (23 px) -> 3,2 us en VGA (640x480: 3,8 us)
//     porches 4 / 16 px           -> 0,56 / 2,2 us (640x480: 0,64 / 1,9 us)
//     VSync 1 linea (vpos 247)    -> 2 lineas en VGA (640x480: 2)
//     porches 5 / 14 lineas       -> 10 / 28 lineas (640x480: 10 / 33)
//
// Los flancos de VSync coinciden con el inicio de HSync. Las cuentas de pixel
// incluyen el desplazamiento de 8 px del video en el top.
// ---------------------------------------------------------------------------
module arcadia_sync
(
    input      clk,      // clk_sys (8 relojes por pixel Arcadia)
    input      vga,      // 1 = salida a 31 kHz (scandoubler activo)
    input      hs_in,    // HSync del core (activo alto, termina en hpos 0)
    input      vs_in,    // VSync/VRST del core (activo alto, lineas 242..261)
    output reg hs_n = 1'b1,
    output reg vs_n = 1'b1
);

wire [10:0] hs_start = vga ? 11'd1568 : 11'd1576;   // hpos 196 / 197
wire [10:0] hs_end   = vga ? 11'd1752 : 11'd1712;   // hpos 219 / 214
wire  [4:0] vs_first = vga ? 5'd6 : 5'd4;           // vpos 247 / 245
wire  [4:0] vs_last  = vga ? 5'd6 : 5'd6;           // vpos 247 / 247

reg [10:0] hc = 11'd0;   // relojes desde el inicio de linea (hpos 0)
reg  [4:0] vc = 5'd0;    // vpos - 241 durante el VBlank, 0 en zona activa
reg        hs_d = 1'b0;

always @(posedge clk) begin
    hs_d <= hs_in;
    hc   <= hc + 11'd1;

    if (hs_d & ~hs_in) begin           // inicio de linea
        hc <= 11'd0;
        if (!vs_in)            vc <= 5'd0;
        else if (vc != 5'd31)  vc <= vc + 5'd1;
    end

    if (hc == hs_start) begin
        hs_n <= 1'b0;
        vs_n <= ~((vc >= vs_first) && (vc <= vs_last));
    end
    if (hc == hs_end) hs_n <= 1'b1;
end

endmodule
