//============================================================================
// Emerson Arcadia 2001 para placas de la familia MiST
// (MiST, SiDi, Calypso y Poseidon)
//
// Top comun a todas las placas. La placa se elige con una macro en su .qsf:
//   MIST, SIDI, POSEIDON; sin ninguna de ellas, Calypso.
// Port original a Poseidon: turri21. Referencia: turri21/Arcadia_Senhor.
//============================================================================

`ifdef SIDI
`define UN_SOLO_LED
`define RELOJ_27
`endif
`ifdef MIST
`define UN_SOLO_LED
`define RELOJ_27
`endif
`ifdef POSEIDON
`define UN_SOLO_LED
`endif

module arcadia_top
(
`ifdef RELOJ_27
    input         CLOCK_27,
`elsif POSEIDON
    input         CLOCK_50,
`else
    input         CLK12M,
`endif

`ifdef UN_SOLO_LED
    output        LED,          // activo a nivel bajo, como en MiST
`else
    output  [7:0] LED,
`endif

    output [VGA_BITS-1:0] VGA_R,
    output [VGA_BITS-1:0] VGA_G,
    output [VGA_BITS-1:0] VGA_B,
    output        VGA_HS,
    output        VGA_VS,

    input         SPI_SCK,
    inout         SPI_DO,
    input         SPI_DI,
    input         SPI_SS2,       // data_io
    input         SPI_SS3,       // OSD
`ifndef NO_DIRECT_UPLOAD
    input         SPI_SS4,       // direct upload
`endif
    input         CONF_DATA0     // user_io

`ifdef I2S_AUDIO
   ,output        I2S_BCK,
    output        I2S_LRCK,
    output        I2S_DATA
`endif
`ifdef DELTASIGMA_AUDIO
   ,output        AUDIO_L,
    output        AUDIO_R
`endif
);

`ifdef VGA_8BIT
localparam VGA_BITS = 8;
`elsif RELOJ_27
localparam VGA_BITS = 6;      // MiST y SiDi: 6 bits por color
`elsif POSEIDON
localparam VGA_BITS = 6;      // Poseidon tambien
`else
localparam VGA_BITS = 4;      // Calypso
`endif

`ifdef RELOJ_27
wire clk_entrada = CLOCK_27;
`elsif POSEIDON
wire clk_entrada = CLOCK_50;
`else
wire clk_entrada = CLK12M;
`endif

`ifdef BIG_OSD
localparam bit BIG_OSD = 1;
`define SEP "-;",
`else
localparam bit BIG_OSD = 0;
`define SEP
`endif

`include "build_id.v"
parameter CONF_STR = {
    "ARCADIA;;",
	 `SEP
    "F,BIN,Load Cartridge;",
    `SEP
    "OBC,CPU Speed,100%,75%,50%,25%;",
    "O2,Reverse Left/Right,Off,On;",
    "OA,Reverse Up/Down,Off,On;",
    "O3,Auto-Center,On,Off;",
    "O4,Swap Joystick XY,Off,On;",
    "O5,D-Pad Analog Emulation,Off,On;",
	 "O8,Swap Controllers,Off,On;",
    "O67,Scanlines,Off,25%,50%,75%;",
    "O9,Pause Core on OSD,Off,On;",
    "T0,Reset;",
	 `SEP
    "V,",`BUILD_VERSION,"-",`BUILD_DATE
};

// ---------------------------------------------------------------------------
// Clocking
// Arcadia NTSC UVI pixel clock is 3.579545 MHz. The core runs at 8x that rate:
// 28.63636 MHz. Cada placa tiene su pll.v:
//   MiST/SiDi (27 MHz) x35/33, Calypso (12 MHz) x105/44, Poseidon (50 MHz).
// ---------------------------------------------------------------------------
// NOTA: se elimina el antiguo multiplexor combinacional c0/c1 (opcion "PAL").
// Conmutar clk_sys con un LUT desde un bit de status generado en el propio
// clk_sys provoca glitches de reloj, y ademas el UVI tiene np='0' fijo, por lo
// que "PAL" solo aceleraba el core un 24 % sin cambiar la temporizacion.
wire clk_sys;
wire pll_locked;

pll pll(
    .inclk0(clk_entrada),
    .c0(clk_sys),      // 28,636 MHz (8 x 3,579545 MHz)
    .locked(pll_locked)
);
  

// ---------------------------------------------------------------------------
// MiST user I/O
// ---------------------------------------------------------------------------
wire [63:0] status;
wire  [1:0] buttons;
wire        scandoubler_disable;
wire        ypbpr;
wire        no_csync;

wire [31:0] joystick_0;
wire [31:0] joystick_1;
wire [31:0] joystick_analog_0;
wire [31:0] joystick_analog_1;

wire        key_strobe;
wire        key_pressed;
wire        key_extended;
wire  [7:0] key_code;

//wire [10:0] conf_str_addr;
//reg   [7:0] conf_str_char;

//always @(posedge clk_sys) begin
//    conf_str_char <= CONF_STR[(($size(CONF_STR)>>3) - conf_str_addr - 1)<<3 +:8];
//end

// BIG_OSD feature bit = 13. No SD-image service is needed by Arcadia.
user_io #(.STRLEN($size(CONF_STR)>>3), .SD_IMAGES(1), .PS2DIV(500), .FEATURES(32'h0 | (BIG_OSD << 13))) user_io
(
    .clk_sys(clk_sys),
    .clk_sd(clk_sys),

    .SPI_SS_IO(CONF_DATA0),
    .SPI_CLK(SPI_SCK),
    .SPI_MOSI(SPI_DI),
    .SPI_MISO(SPI_DO),
	 
	 .conf_str(CONF_STR),

//    .conf_addr(conf_str_addr),
//    .conf_chr(conf_str_char),

    .status(status),
    .buttons(buttons),
    .scandoubler_disable(scandoubler_disable),
    .ypbpr(ypbpr),
    .no_csync(no_csync),

    .joystick_0(joystick_0),
    .joystick_1(joystick_1),
    .joystick_analog_0(joystick_analog_0),
    .joystick_analog_1(joystick_analog_1),

    .key_strobe(key_strobe),
    .key_pressed(key_pressed),
    .key_extended(key_extended),
    .key_code(key_code),

    .sd_conf(1'b0),
    .sd_sdhc(1'b1),
    .sd_lba(32'd0),
    .sd_rd(1'b0),
    .sd_wr(1'b0),
    .sd_din(8'd0),

    .ps2_kbd_clk_i(1'b1),
    .ps2_kbd_data_i(1'b1),
    .ps2_mouse_clk_i(1'b1),
    .ps2_mouse_data_i(1'b1),
    .kbd_out_data(8'd0),
    .kbd_out_strobe(1'b0),
    .leds(8'd0),
    .i2c_din(8'd0),
    .i2c_ack(1'b0),
    .i2c_end(1'b0),
    .serial_data(8'd0),
    .serial_strobe(1'b0)
);

// ---------------------------------------------------------------------------
// Cartridge download
// Arcadia cartridges are kept in the core's internal 16 KiB cartridge RAM.
// ---------------------------------------------------------------------------
wire        ioctl_download;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire  [7:0] ioctl_index;

data_io data_io(
    .clk_sys(clk_sys),
    .SPI_SCK(SPI_SCK),
    .SPI_SS2(SPI_SS2),

`ifdef NO_DIRECT_UPLOAD
    .SPI_SS4(1'b1),
`else
    .SPI_SS4(SPI_SS4),
`endif

    .SPI_DI(SPI_DI),
    .SPI_DO(SPI_DO),
    .ioctl_download(ioctl_download),
    .ioctl_index(ioctl_index),
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout)
);


`ifdef UN_SOLO_LED
assign LED = ~ioctl_download;
`else
assign LED = {7'd0, ioctl_download};
`endif

// ---------------------------------------------------------------------------
// Keyboard -> Arcadia keypad / panel mapping
// MiST user_io already emits make/break PS/2 set-2 events, so there is no need
// for the MiSTer ps2_key toggle bridge used by the HPS top-level.
// ---------------------------------------------------------------------------
reg [9:0] kb1_keys = 10'd0;
reg [9:0] kb2_keys = 10'd0;
reg kb1_enter = 1'b0, kb1_clear = 1'b0;
reg kb2_enter = 1'b0, kb2_clear = 1'b0;
reg kb_start  = 1'b0, kb_select = 1'b0, kb_option = 1'b0;

always @(posedge clk_sys) begin
    if (key_strobe && !key_extended) begin
        case (key_code)
            8'h16: kb1_keys[1] <= key_pressed;
            8'h1E: kb1_keys[2] <= key_pressed;
            8'h26: kb1_keys[3] <= key_pressed;
            8'h15: kb1_keys[4] <= key_pressed;
            8'h1D: kb1_keys[5] <= key_pressed;
            8'h24: kb1_keys[6] <= key_pressed;
            8'h1C: kb1_keys[7] <= key_pressed;
            8'h1B: kb1_keys[8] <= key_pressed;
            8'h23: kb1_keys[9] <= key_pressed;
            8'h1A: kb1_clear   <= key_pressed;
            8'h22: kb1_keys[0] <= key_pressed;
            8'h21: kb1_enter   <= key_pressed;
            8'h29: kb_start    <= key_pressed; // Space
            8'h05: kb_select   <= key_pressed; // F1
            8'h06: kb_option   <= key_pressed; // F2

            8'h3E: kb2_keys[1] <= key_pressed;
            8'h46: kb2_keys[2] <= key_pressed;
            8'h45: kb2_keys[3] <= key_pressed;
            8'h43: kb2_keys[4] <= key_pressed;
            8'h44: kb2_keys[5] <= key_pressed;
            8'h4D: kb2_keys[6] <= key_pressed;
            8'h42: kb2_keys[7] <= key_pressed;
            8'h4B: kb2_keys[8] <= key_pressed;
            8'h4C: kb2_keys[9] <= key_pressed;
            8'h41: kb2_clear   <= key_pressed;
            8'h49: kb2_keys[0] <= key_pressed;
            8'h4A: kb2_enter   <= key_pressed;
            default: ;
        endcase
    end
end

wire [31:0] joy0_combined;
wire [31:0] joy1_combined;

// ---------------------------------------------------------------------------
// Standard MiST gamepad -> Arcadia controller mapping.
//
// user_io uses the standard layout:
//   [0] R [1] L [2] D [3] U [4] A [5] B [6] SELECT [7] START
//   [8] X [9] Y [10] L [11] R [12] L2 [13] R2 [14] L3 [15] R3
//
// Arcadia's internal controller image is different: bits 4..8 are START,
// SELECT, OPTION, ENTER and CLEAR, while 9..18 are keypad 0..9 and 19/20
// are the two physical fire switches (both wired to keypad 2 on Emerson).
// Keep the translation here so the VHDL core sees a real Arcadia controller
// instead of depending on the physical gamepad's arbitrary button numbering.
//
// Default gamepad layout:
//   D-pad          = joystick
//   A + B          = FIRE / keypad 2
//   X              = OPTION
//   Y              = ENTER
//   SELECT         = SELECT
//   START          = START
//   L              = CLEAR
//   R              = keypad 0
//   L2/R2/L3/R3    = keypad 1/3/4/6
//   Right analog   = keypad 1..4/6..9 (8 directions, centre = none)
// ---------------------------------------------------------------------------
wire [7:0] p1_ra_x = joystick_analog_0[31:24];
wire [7:0] p1_ra_y = joystick_analog_0[23:16];
wire [7:0] p2_ra_x = joystick_analog_1[31:24];
wire [7:0] p2_ra_y = joystick_analog_1[23:16];

wire p1_ra_left  = ($signed(p1_ra_x) < -8'sd64);
wire p1_ra_right = ($signed(p1_ra_x) >  8'sd64);
wire p1_ra_up    = ($signed(p1_ra_y) < -8'sd64);
wire p1_ra_down  = ($signed(p1_ra_y) >  8'sd64);
wire p2_ra_left  = ($signed(p2_ra_x) < -8'sd64);
wire p2_ra_right = ($signed(p2_ra_x) >  8'sd64);
wire p2_ra_up    = ($signed(p2_ra_y) < -8'sd64);
wire p2_ra_down  = ($signed(p2_ra_y) >  8'sd64);

assign joy0_combined[3:0] = joystick_0[3:0];
assign joy0_combined[4]   = joystick_0[7]  | kb_start;   // START
assign joy0_combined[5]   = joystick_0[6]  | kb_select;  // SELECT
assign joy0_combined[6]   = joystick_0[8]  | kb_option;  // OPTION (X)
assign joy0_combined[7]   = joystick_0[9]  | kb1_enter;   // ENTER (Y)
assign joy0_combined[8]   = joystick_0[10] | kb1_clear;   // CLEAR (L)
assign joy0_combined[9]   = joystick_0[11] | kb1_keys[0]; // 0
assign joy0_combined[10]  = joystick_0[12] | kb1_keys[1] | (p1_ra_down  & p1_ra_left); // 1
assign joy0_combined[11]  = joystick_0[5]  | kb1_keys[2] | (p1_ra_down  & ~p1_ra_left & ~p1_ra_right); // 2 / FIRE
assign joy0_combined[12]  = joystick_0[13] | kb1_keys[3] | (p1_ra_down  &  p1_ra_right);               // 3
assign joy0_combined[13]  = joystick_0[14] | kb1_keys[4] | (p1_ra_left  & ~p1_ra_up & ~p1_ra_down);    // 4
assign joy0_combined[14]  = kb1_keys[5]; // 5 (centre / keyboard only)
assign joy0_combined[15]  = joystick_0[15] | kb1_keys[6] | (p1_ra_right & ~p1_ra_up & ~p1_ra_down); // 6
assign joy0_combined[16]  = kb1_keys[7] | (p1_ra_up    & ~p1_ra_left & ~p1_ra_right);                  // 7
assign joy0_combined[17] = kb1_keys[8] | (p1_ra_up    & ~p1_ra_left & ~p1_ra_right);                    // 8
assign joy0_combined[18] = kb1_keys[9] | (p1_ra_up    &  p1_ra_right);                                     // 9
assign joy0_combined[19] = joystick_0[4] | joystick_0[5] | kb1_keys[2]; // FIRE 1
assign joy0_combined[20] = joystick_0[4] | joystick_0[5] | kb1_keys[2]; // FIRE 2
assign joy0_combined[31:21] = joystick_0[31:21];

assign joy1_combined[3:0] = joystick_1[3:0];
assign joy1_combined[4]   = joystick_1[7];  // START
assign joy1_combined[5]   = joystick_1[6];  // SELECT
assign joy1_combined[6]   = joystick_1[8];  // OPTION (X)
assign joy1_combined[7]   = joystick_1[9] | kb2_enter; // ENTER (Y)
assign joy1_combined[8]   = joystick_1[10] | kb2_clear; // CLEAR (L)
assign joy1_combined[9]   = joystick_1[11] | kb2_keys[0]; // 0
assign joy1_combined[10]  = joystick_1[12] | kb2_keys[1] | (p2_ra_down  &  p2_ra_left);
assign joy1_combined[11]  = joystick_1[5]  | kb2_keys[2] | (p2_ra_down  & ~p2_ra_left & ~p2_ra_right);
assign joy1_combined[12]  = joystick_1[13] | kb2_keys[3] | (p2_ra_down  &  p2_ra_right);
assign joy1_combined[13]  = joystick_1[14] | kb2_keys[4] | (p2_ra_left  & ~p2_ra_up & ~p2_ra_down);
assign joy1_combined[14]  = kb2_keys[5]; // 5
assign joy1_combined[15]  = joystick_1[15] | kb2_keys[6] | (p2_ra_right & ~p2_ra_up & ~p2_ra_down); // 6
assign joy1_combined[16]  = kb2_keys[7] | (p2_ra_up    & ~p2_ra_left & ~p2_ra_right);
assign joy1_combined[17]  = kb2_keys[8] | (p2_ra_up    & ~p2_ra_left & ~p2_ra_right);
assign joy1_combined[18]  = kb2_keys[9] | (p2_ra_up    &  p2_ra_right);
assign joy1_combined[19]  = joystick_1[4] | joystick_1[5] | kb2_keys[2];
assign joy1_combined[20]  = joystick_1[4] | joystick_1[5] | kb2_keys[2];
assign joy1_combined[31:21] = joystick_1[31:21];

// ---------------------------------------------------------------------------
// D-pad -> analog ramp emulation (same behaviour as release top-level)
// ---------------------------------------------------------------------------
localparam [16:0] RAMP_PRE = 17'd131071;

reg [16:0] p1_ramp_cnt = 17'd0;
reg [16:0] p2_ramp_cnt = 17'd0;
reg  [7:0] p1_analog_x = 8'h00, p1_analog_y = 8'h00;
reg  [7:0] p2_analog_x = 8'h00, p2_analog_y = 8'h00;
reg  [3:0] p1_dpad_d = 4'd0, p2_dpad_d = 4'd0;

wire [3:0] p1_dpad = joy0_combined[3:0];
wire [3:0] p2_dpad = joy1_combined[3:0];
wire [15:0] analog_0_core = status[5] ? {p1_analog_x,p1_analog_y} : joystick_analog_0[15:0];
wire [15:0] analog_1_core = status[5] ? {p2_analog_x,p2_analog_y} : joystick_analog_1[15:0];

always @(posedge clk_sys) begin
    p1_dpad_d <= p1_dpad;
    if (p1_dpad != 4'd0 && p1_dpad_d == 4'd0)
        p1_ramp_cnt <= RAMP_PRE;
    else if (p1_ramp_cnt == RAMP_PRE) begin
        p1_ramp_cnt <= 17'd0;
        // MiST joystick bits: [0]=RIGHT, [1]=LEFT, [2]=DOWN, [3]=UP.
        // Right/Left drive analog X; Down/Up drive analog Y.
        if (p1_dpad[0] && !p1_dpad[1]) begin
            if (p1_analog_x[7] == 1'b0 && p1_analog_x != 8'h7F) p1_analog_x <= p1_analog_x + 8'd1;
            else if (p1_analog_x[7] == 1'b1) p1_analog_x <= p1_analog_x + 8'd1;
        end else if (p1_dpad[1] && !p1_dpad[0]) begin
            if (p1_analog_x[7] == 1'b1 && p1_analog_x != 8'h80) p1_analog_x <= p1_analog_x - 8'd1;
            else if (p1_analog_x[7] == 1'b0) p1_analog_x <= p1_analog_x - 8'd1;
        end else if (!status[3]) begin
            if (p1_analog_x[7] == 1'b0 && p1_analog_x != 8'h00) p1_analog_x <= p1_analog_x - 8'd1;
            else if (p1_analog_x[7] == 1'b1 && p1_analog_x != 8'h00) p1_analog_x <= p1_analog_x + 8'd1;
        end

        if (p1_dpad[2] && !p1_dpad[3]) begin
            if (p1_analog_y[7] == 1'b0 && p1_analog_y != 8'h7F) p1_analog_y <= p1_analog_y + 8'd1;
            else if (p1_analog_y[7] == 1'b1) p1_analog_y <= p1_analog_y + 8'd1;
        end else if (p1_dpad[3] && !p1_dpad[2]) begin
            if (p1_analog_y[7] == 1'b1 && p1_analog_y != 8'h80) p1_analog_y <= p1_analog_y - 8'd1;
            else if (p1_analog_y[7] == 1'b0) p1_analog_y <= p1_analog_y - 8'd1;
        end else if (!status[3]) begin
            if (p1_analog_y[7] == 1'b0 && p1_analog_y != 8'h00) p1_analog_y <= p1_analog_y - 8'd1;
            else if (p1_analog_y[7] == 1'b1 && p1_analog_y != 8'h00) p1_analog_y <= p1_analog_y + 8'd1;
        end
    end else p1_ramp_cnt <= p1_ramp_cnt + 17'd1;

    p2_dpad_d <= p2_dpad;
    if (p2_dpad != 4'd0 && p2_dpad_d == 4'd0)
        p2_ramp_cnt <= RAMP_PRE;
    else if (p2_ramp_cnt == RAMP_PRE) begin
        p2_ramp_cnt <= 17'd0;
        if (p2_dpad[0] && !p2_dpad[1]) begin
            if (p2_analog_x[7] == 1'b0 && p2_analog_x != 8'h7F) p2_analog_x <= p2_analog_x + 8'd1;
            else if (p2_analog_x[7] == 1'b1) p2_analog_x <= p2_analog_x + 8'd1;
        end else if (p2_dpad[1] && !p2_dpad[0]) begin
            if (p2_analog_x[7] == 1'b1 && p2_analog_x != 8'h80) p2_analog_x <= p2_analog_x - 8'd1;
            else if (p2_analog_x[7] == 1'b0) p2_analog_x <= p2_analog_x - 8'd1;
        end else if (!status[3]) begin
            if (p2_analog_x[7] == 1'b0 && p2_analog_x != 8'h00) p2_analog_x <= p2_analog_x - 8'd1;
            else if (p2_analog_x[7] == 1'b1 && p2_analog_x != 8'h00) p2_analog_x <= p2_analog_x + 8'd1;
        end

        if (p2_dpad[2] && !p2_dpad[3]) begin
            if (p2_analog_y[7] == 1'b0 && p2_analog_y != 8'h7F) p2_analog_y <= p2_analog_y + 8'd1;
            else if (p2_analog_y[7] == 1'b1) p2_analog_y <= p2_analog_y + 8'd1;
        end else if (p2_dpad[3] && !p2_dpad[2]) begin
            if (p2_analog_y[7] == 1'b1 && p2_analog_y != 8'h80) p2_analog_y <= p2_analog_y - 8'd1;
            else if (p2_analog_y[7] == 1'b0) p2_analog_y <= p2_analog_y - 8'd1;
        end else if (!status[3]) begin
            if (p2_analog_y[7] == 1'b0 && p2_analog_y != 8'h00) p2_analog_y <= p2_analog_y - 8'd1;
            else if (p2_analog_y[7] == 1'b1 && p2_analog_y != 8'h00) p2_analog_y <= p2_analog_y + 8'd1;
        end
    end else p2_ramp_cnt <= p2_ramp_cnt + 17'd1;

    if (!pll_locked || status[0] || buttons[1]) begin
        p1_analog_x <= 8'h00;
        p1_analog_y <= 8'h00;
        p1_ramp_cnt <= 17'd0;
        p1_dpad_d   <= 4'd0;
        p2_analog_x <= 8'h00;
        p2_analog_y <= 8'h00;
        p2_ramp_cnt <= 17'd0;
        p2_dpad_d   <= 4'd0;
    end
end

// ---------------------------------------------------------------------------
// Arcadia core
// ---------------------------------------------------------------------------
wire reset = ~pll_locked | status[0] | buttons[1];

wire [7:0] core_r, core_g, core_b;
wire       core_hs, core_vs, core_de, core_hbl, core_vbl;
wire       core_clk_video;
wire       core_ce_pixel;
wire [7:0] sound;
wire       ioctl_wait_unused;
wire       osd_enable;

// Only menu index zero is an Arcadia cartridge.
//wire cart_download = ioctl_download && (ioctl_index[5:0] == 6'd0);
//wire cart_wr       = ioctl_wr       && (ioctl_index[5:0] == 6'd0);

arcadia_core core
(
    .clk(clk_sys),
    .OSD_STATUS(osd_enable),
    .pause_osd(status[9]),
    .reset(reset),

    .swapxy(status[4]),
    .swap_controllers(status[8]),
    .reverse_lr(status[2]),
    .reverse_ud(status[10]),
    .cpu_speed(status[12:11]),

    .clk_video(core_clk_video),
    .ce_pixel(core_ce_pixel),
    .vga_r(core_r),
    .vga_g(core_g),
    .vga_b(core_b),
    .vga_hs(core_hs),
    .vga_vs(core_vs),
    .vga_de(core_de),
    .vga_hbl(core_hbl),
    .vga_vbl(core_vbl),

    .sound(sound),

    .ps2_key(11'd0),
    .joystick_0(joy0_combined),
    .joystick_1(joy1_combined),
    .joystick_analog_0(analog_0_core),
    .joystick_analog_1(analog_1_core),
    .dpad_analog_en(status[5]),

    .ioctl_download(ioctl_download),
    .ioctl_index(ioctl_index),
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr[24:0]),
    .ioctl_dout(ioctl_dout),
    .ioctl_wait(ioctl_wait_unused)
);

// ---------------------------------------------------------------------------
// MiST video / OSD / scan doubler
// The Arcadia core clock is 8x its pixel rate, therefore ce_divider=7 gives
// one input pixel every eight clk_sys clocks.
//
// Poseidon horizontal centering: the native SC2637 timing has the active
// 184-pixel window beginning immediately after HSync.  Move the COMPLETE
// active video window (RGB + HBlank) to the right while leaving HSync and the
// line timing relationship untouched.  This is important for the MiST
// scandoubler, which measures its framing from HSync and HBlank together.
// ---------------------------------------------------------------------------
localparam integer VIDEO_SHIFT_PIXELS = 8;
localparam integer VIDEO_SHIFT_CYCLES = VIDEO_SHIFT_PIXELS * 8;

reg [7:0] r_shift [0:VIDEO_SHIFT_CYCLES-1];
reg [7:0] g_shift [0:VIDEO_SHIFT_CYCLES-1];
reg [7:0] b_shift [0:VIDEO_SHIFT_CYCLES-1];
reg       hb_shift[0:VIDEO_SHIFT_CYCLES-1];
integer video_shift_i;

always @(posedge clk_sys) begin
    if (reset) begin
        for (video_shift_i = 0; video_shift_i < VIDEO_SHIFT_CYCLES; video_shift_i = video_shift_i + 1) begin
            r_shift[video_shift_i]  <= 8'd0;
            g_shift[video_shift_i]  <= 8'd0;
            b_shift[video_shift_i]  <= 8'd0;
            hb_shift[video_shift_i] <= 1'b1;
        end
    end else begin
        r_shift[0]  <= core_r;
        g_shift[0]  <= core_g;
        b_shift[0]  <= core_b;
        hb_shift[0] <= core_hbl;
        for (video_shift_i = 1; video_shift_i < VIDEO_SHIFT_CYCLES; video_shift_i = video_shift_i + 1) begin
            r_shift[video_shift_i]  <= r_shift[video_shift_i-1];
            g_shift[video_shift_i]  <= g_shift[video_shift_i-1];
            b_shift[video_shift_i]  <= b_shift[video_shift_i-1];
            hb_shift[video_shift_i] <= hb_shift[video_shift_i-1];
        end
    end
end

wire [7:0] video_r_shifted = r_shift[VIDEO_SHIFT_CYCLES-1];
wire [7:0] video_g_shifted = g_shift[VIDEO_SHIFT_CYCLES-1];
wire [7:0] video_b_shifted = b_shift[VIDEO_SHIFT_CYCLES-1];
wire       video_hb_shifted = hb_shift[VIDEO_SHIFT_CYCLES-1];

// OSD: pixel-enable fijo (OSD_AUTO_CE=0) y ce_divider=3 (clk_sys/4).
// La linea se muestrea a 368 puntos (2 por pixel Arcadia) tanto a 15 kHz
// (pe_in) como a 31 kHz (ce_x2), y el OSD de 256 px queda centrado con la
// misma proporcion en ambos modos. Con ce_divider=7 solo habria 184 puntos a
// 15 kHz y el OSD (256) no cabria; con el detector automatico y
// ce_divider=1 el OSD salia comprimido a ~1/3 del ancho en VGA.
// Sincronismos estandar para 15 kHz; a 31 kHz se mantienen los originales,
// que el scandoubler ya convierte correctamente.
wire hs_15k, vs_15k;
arcadia_sync15 sync15
(
    .clk(clk_sys),
    .hs_in(core_hs),
    .vs_in(core_vs),
    .hs_out(hs_15k),
    .vs_out(vs_15k)
);

wire video_hs = scandoubler_disable ? hs_15k : core_hs;
wire video_vs = scandoubler_disable ? vs_15k : core_vs;

mist_video #(.COLOR_DEPTH(8),
   .SD_HCNT_WIDTH(11),
	.OUT_COLOR_DEPTH(VGA_BITS),
	.USE_BLANKS(1'b1),
	.OSD_AUTO_CE(1'b0),
	.BIG_OSD(BIG_OSD))
mist_video (
    .clk_sys(clk_sys),
    .SPI_SCK(SPI_SCK),
    .SPI_SS3(SPI_SS3),
    .SPI_DI(SPI_DI),

    .scanlines(status[7:6]),
    .ce_divider(3'd3),
    .scandoubler_disable(scandoubler_disable),
    .no_csync(no_csync),
    .ypbpr(ypbpr),
    .rotate(2'b00),
    .blend(1'b0),

    .R(video_r_shifted),
    .G(video_g_shifted),
    .B(video_b_shifted),
    .HBlank(video_hb_shifted),
    .VBlank(core_vbl),
    .HSync(video_hs),
    .VSync(video_vs),

    .osd_enable(osd_enable),
    .VGA_R(VGA_R),
    .VGA_G(VGA_G),
    .VGA_B(VGA_B),
    .VGA_HS(VGA_HS),
    .VGA_VS(VGA_VS)
);

// ---------------------------------------------------------------------------
// Audio. sound[] es PCM de 8 bits con signo.
// ---------------------------------------------------------------------------
wire [15:0] audio_sample = {sound,8'h00};

`ifdef I2S_AUDIO
i2s #(.AUDIO_DW(16), .I2S_Freq(48000)) audio_i2s
(
    .reset(reset),
    .clk(clk_sys),
    .clk_rate(32'd28636364),
    .sclk(I2S_BCK),
    .lrclk(I2S_LRCK),
    .sdata(I2S_DATA),
    .left_chan(audio_sample),
    .right_chan(audio_sample)
);
`endif

`ifdef DELTASIGMA_AUDIO
// El modulador de dac.vhd quiere la muestra SIN signo: se pasa a binario
// desplazado invirtiendo el bit de signo (silencio = media escala).
wire [15:0] audio_unsigned = {~audio_sample[15], audio_sample[14:0]};

dac #(.C_bits(16)) dac_l
(
    .clk_i(clk_sys),
    .res_n_i(1'b1),
    .dac_i(audio_unsigned),
    .dac_o(AUDIO_L)
);

dac #(.C_bits(16)) dac_r
(
    .clk_i(clk_sys),
    .res_n_i(1'b1),
    .dac_i(audio_unsigned),
    .dac_o(AUDIO_R)
);
`endif

endmodule
