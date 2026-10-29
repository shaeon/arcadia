// ---------------------------------------------------------------------------
// Sincronismos estandar para la salida de 15 kHz (sin scandoubler).
//
// El SC2637 del core usa como sincronismos sus senales internas:
//   HSync = hpos 201..226 -> 26 px = 7,3 us, y el video empieza 2,2 us despues
//   VSync = VRST, lineas 242..261 -> 20 lineas, sin porche posterior
// Eso funciona tras el scandoubler, pero a 15 kHz muchos monitores/TV no
// enganchan bien (la imagen tiembla). Aqui se regeneran a partir de la
// temporizacion del core:
//   HSync: hpos 197..213 (17 px = 4,75 us), porche anterior 1,4 us y posterior
//          5,6 us contando el desplazamiento de 8 px del top-level
//   VSync: 3 lineas (vpos 245..247), 3 lineas de porche anterior y 14 de
//          porche posterior dentro del VBlank original
// Ambas a nivel alto, igual que las originales (mist_video las combina por XOR).
// ---------------------------------------------------------------------------
module arcadia_sync15
(
    input      clk,      // clk_sys (8 relojes por pixel Arcadia)
    input      hs_in,    // HSync del core (activo alto, termina en hpos 0)
    input      vs_in,    // VSync/VRST del core (activo alto, lineas 242..261)
    output reg hs_out = 1'b0,
    output reg vs_out = 1'b0
);

localparam [10:0] HS_START = 11'd197 * 11'd8;   // 1576
localparam [10:0] HS_END   = 11'd214 * 11'd8;   // 1712
localparam  [4:0] VS_FIRST = 5'd4;              // vpos 245
localparam  [4:0] VS_LAST  = 5'd6;              // vpos 247

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

    if (hc == HS_START) begin
        hs_out <= 1'b1;
        vs_out <= (vc >= VS_FIRST) && (vc <= VS_LAST);  // flancos de VSync alineados con el de HSync
    end
    if (hc == HS_END) hs_out <= 1'b0;
end

endmodule
