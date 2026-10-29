--------------------------------------------------------------------------------
-- Signetics 2637 UVI Universal Video Interface
--------------------------------------------------------------------------------
-- Original core: DO 10/2018
-- Arcadia preservation/reconstruction release: 09/2026
--
-- Release model includes the validated character row buffer, SC2637 colour and
-- collision corrections, DMA-row M/HSHIFT sampling, SC2637/2650 PAUSE handling,
-- and the tall-character CPU-visible DMA-status phase correction.
--------------------------------------------------------------------------------

--  00 .. CF  : RAM screen
--  D0 .. EF  : RAM user
--  F0        : /O1.VC
--  F1        :  O1.HC
--  F2        : /O2.VC
--  F3        :  O2.HC
--  F4        : /O3.VC
--  F5        :  O3.HC
--  F6        : /O4.VC
--  F7        :  O4.HC
--  F8        : ?
--  F9        : ?
--  FA        : ?
--  FB        : ?
--  FC        : V offset
--  FD        : Sound pitch / Color mode
--  FE        : Delay chars / random noise / sound ena / loudness
--  FF        : DMA row
-- 100 .. 17F : ?
-- 180 .. 187 : O1. font
-- 188 .. 18F : O2. font
-- 190 .. 197 : O3. font
-- 198 .. 19F : O4. font
-- 1A0 .. 1A7 : O5. font
-- 1A8 .. 1AF : O6. font
-- 1B0 .. 1B7 : O7. font
-- 1B8 .. 1BF : O8. font
-- 1C0 .. 1F7 : ?
-- 1F8        : Colour / refresh mode / graphic mode /
-- 1F9        : Colour characters / pot / charsize
-- 1FA        : Obj 3-4 colour
-- 1FB        : Obj 1-2 colour
-- 1FC        : Collision detect : chars
-- 1FD        : Collision detect : inter-objets
-- 1FE        : POT 2/4
-- 1FF        : POT 1/2

--       A         D
-- 0 : Text     
-- 1 :            Data
-- 2 : Charmap
-- 3 : Obj1map    Charsymbol
-- 4 : Obj2map    Charsymbol
-- 5 : Obj3map    Charsymbol
-- 6 : Obj4map    Charsymbol
-- 7 :            Charsymbol


-- 1800 .. 18FF : RAM

-- 1900 .. 197F : Buttons
-- 1980 .. 19FF : Regs
-- 1A00 .. 1AFF : RAM
-- 1B00 .. 1BFF : Mirror 1900 .. 19FF
--
-- 
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;

ENTITY sgs2637 IS
  PORT (
    ad   : IN  uv15;      -- Address bus
    
    dw   : IN  uv8;       -- Data write
    dr   : OUT uv8;       -- Data read
    
    req  : IN  std_logic;
    ack  : OUT std_logic;
    wr   : IN  std_logic;
    tick : IN  std_logic;
    
    vid_argb : OUT uv4;         -- I | R | G | B
    vid_de   : OUT std_logic;
    vid_hblank : OUT std_logic;
    vid_vblank : OUT std_logic;
    vid_hsyn : OUT std_logic;
    vid_vsyn : OUT std_logic;
    vid_ce   : OUT std_logic;
    vrst     : OUT std_logic;

    -- SC2637 character DMA bus ownership.  Asserted for the single scanline
    -- occupied by each DMA 15,0..13 transfer so the 2650 can honour PAUSE.
    dma_pause : OUT std_logic;

    sound    : OUT uv8;

    pot1     : IN uv8;
    pot2     : IN uv8;
    pot3     : IN uv8;
    pot4     : IN uv8;

    np       : IN std_logic; -- 0=NTSC 60Hz, 1=PAL 50Hz
    
    reset    : IN std_logic;
    clk      : IN std_logic; -- 8x Pixel clock
    reset_na : IN std_logic
    );
END ENTITY sgs2637;

ARCHITECTURE rtl OF sgs2637 IS
  SUBTYPE uint9 IS natural RANGE 0 TO 511;
  
  -- 64 chars * 8 lines  = 512
  CONSTANT CHARS : arr_uv8(0 TO 511) := (
      x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",  -- ' '
      x"01",x"02",x"04",x"08",x"10",x"20",x"40",x"80",  -- /
      x"80",x"40",x"20",x"10",x"08",x"04",x"02",x"01",  -- \
      x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",  -- #
      -- SC2637 built-in line/corner glyphs ($04..$0B) use two-pixel strokes.
      x"FF",x"FF",x"00",x"00",x"00",x"00",x"00",x"00",  -- $04 top line
      x"03",x"03",x"03",x"03",x"03",x"03",x"03",x"03",  -- $05 right line
      x"00",x"00",x"00",x"00",x"00",x"00",x"FF",x"FF",  -- $06 bottom line
      x"C0",x"C0",x"C0",x"C0",x"C0",x"C0",x"C0",x"C0",  -- $07 left line
      x"FF",x"FF",x"03",x"03",x"03",x"03",x"03",x"03",  -- $08 top+right
      x"FF",x"FF",x"C0",x"C0",x"C0",x"C0",x"C0",x"C0",  -- $09 top+left
      x"C0",x"C0",x"C0",x"C0",x"C0",x"C0",x"FF",x"FF",  -- $0A left+bottom
      x"03",x"03",x"03",x"03",x"03",x"03",x"FF",x"FF",  -- $0B right+bottom
      x"01",x"03",x"07",x"0F",x"1F",x"3F",x"7F",x"FF",  -- /
      x"80",x"C0",x"E0",x"F0",x"F8",x"FC",x"FE",x"FF",  -- \
      x"FF",x"FE",x"FC",x"F8",x"F0",x"E0",x"C0",x"80",  -- /
      x"FF",x"7F",x"3F",x"1F",x"0F",x"07",x"03",x"01",  -- \
      x"00",x"1C",x"22",x"26",x"2A",x"32",x"22",x"1C",  -- 0
      x"00",x"08",x"18",x"08",x"08",x"08",x"08",x"1C",  -- 1
      x"00",x"1C",x"22",x"02",x"0C",x"10",x"20",x"3E",  -- 2
      x"00",x"3E",x"02",x"04",x"0C",x"02",x"22",x"1C",  -- 3
      x"00",x"04",x"0C",x"14",x"24",x"3E",x"04",x"04",  -- 4
      x"00",x"3E",x"20",x"3C",x"02",x"02",x"22",x"1C",  -- 5
      x"00",x"0C",x"10",x"20",x"3C",x"22",x"22",x"1C",  -- 6
      x"00",x"7C",x"02",x"04",x"08",x"10",x"10",x"10",  -- 7
      x"00",x"1C",x"22",x"22",x"1C",x"22",x"22",x"1C",  -- 8
      x"00",x"1C",x"22",x"22",x"3E",x"02",x"04",x"18",  -- 9
      x"00",x"08",x"14",x"22",x"22",x"3E",x"22",x"22",  -- A
      x"00",x"3C",x"22",x"22",x"3C",x"22",x"22",x"3C",  -- B
      x"00",x"1C",x"22",x"20",x"20",x"20",x"22",x"1C",  -- C
      x"00",x"3C",x"22",x"22",x"22",x"22",x"22",x"3C",  -- D
      x"00",x"3E",x"20",x"20",x"3C",x"20",x"20",x"3E",  -- E
      x"00",x"3E",x"20",x"20",x"38",x"20",x"20",x"20",  -- F
      x"00",x"1E",x"20",x"20",x"20",x"26",x"22",x"1E",  -- G
      x"00",x"22",x"22",x"22",x"3E",x"22",x"22",x"22",  -- H
      x"00",x"1C",x"08",x"08",x"08",x"08",x"08",x"1C",  -- I
      x"00",x"02",x"02",x"02",x"02",x"02",x"22",x"1C",  -- J
      x"00",x"22",x"24",x"28",x"30",x"28",x"24",x"22",  -- K
      x"00",x"20",x"20",x"20",x"20",x"20",x"20",x"3E",  -- L
      x"00",x"22",x"36",x"2A",x"2A",x"22",x"22",x"22",  -- M
      x"00",x"22",x"22",x"32",x"2A",x"26",x"22",x"22",  -- N
      x"00",x"1C",x"22",x"22",x"22",x"22",x"22",x"1C",  -- O
      x"00",x"3C",x"22",x"22",x"3C",x"20",x"20",x"20",  -- P
      x"00",x"1C",x"22",x"22",x"22",x"2A",x"24",x"1A",  -- Q
      x"00",x"3C",x"22",x"22",x"3C",x"28",x"24",x"22",  -- R
      x"00",x"1C",x"22",x"20",x"1C",x"02",x"22",x"1C",  -- S
      x"00",x"3E",x"08",x"08",x"08",x"08",x"08",x"08",  -- T
      x"00",x"22",x"22",x"22",x"22",x"22",x"22",x"1C",  -- U
      x"00",x"22",x"22",x"22",x"22",x"22",x"14",x"08",  -- V
      x"00",x"22",x"22",x"22",x"2A",x"2A",x"36",x"22",  -- W
      x"00",x"22",x"22",x"14",x"08",x"14",x"22",x"22",  -- X
      x"00",x"22",x"22",x"14",x"08",x"08",x"08",x"08",  -- Y
      x"00",x"3E",x"02",x"04",x"08",x"10",x"20",x"3E",  -- Z
      x"00",x"00",x"00",x"00",x"00",x"00",x"0C",x"0C",  -- .
      x"00",x"00",x"00",x"00",x"00",x"08",x"08",x"10",  -- ,
      x"00",x"00",x"08",x"08",x"3E",x"08",x"08",x"00",  -- +
      x"00",x"08",x"1E",x"28",x"1C",x"0A",x"3C",x"08",  -- $
      x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",  -- User char
      x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",  -- User char
      x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",  -- User char
      x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",  -- User char
      x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",  -- User char
      x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",  -- User char
      x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",  -- User char
      x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00"); -- User char
  
  SIGNAL wreq : std_logic;
  SIGNAL ram : arr_uv8(0 TO 1023);
  ATTRIBUTE ramstyle : string;
  ATTRIBUTE ramstyle OF ram : SIGNAL IS "no_rw_check";

  SIGNAL adi : uv12;
  SIGNAL ram_ad : uv10;
  SIGNAL ram_dr,rom_dr,ch : uv8;
  SIGNAL dr_reg,dr_mem : uv8;
  SIGNAL drreg_sel : std_logic;
  SIGNAL rom_ad : uv9;
  
  -- UVI-active object coordinates. The SC2637 samples all four objects'
  -- coordinate registers at DMA 15; CPU writes therefore go to staging
  -- latches and become visible together at the next field boundary.
  SIGNAL o1_hc,o1_vc,o2_hc,o2_vc : uv8; -- F0..F3 active
  SIGNAL o3_hc,o3_vc,o4_hc,o4_vc : uv8; -- F4..F7 active
  SIGNAL o1_hc_wr,o1_vc_wr,o2_hc_wr,o2_vc_wr : uv8;
  SIGNAL o3_hc_wr,o3_vc_wr,o4_hc_wr,o4_vc_wr : uv8;
  SIGNAL voffset : uv8;  -- FC
  SIGNAL r_0fd  : uv8; -- FD
  ALIAS  r_freq : uv7 IS r_0fd(6 DOWNTO 0); -- Sound Frequency
  ALIAS  r_cm   : std_logic IS r_0fd(7); -- CPU-visible/live color mode
  -- The SC2637 accesses external RAM address 253 ($FD) for every character
  -- DMA. Hold the M bit for the complete character row, just as HSHIFT is
  -- held row-wide. Keep r_freq live so display timing does not alter sound.
  SIGNAL r_cm_row : std_logic := '0';
  
  SIGNAL r_0fe  : uv8; -- FE
  ALIAS hshift  : uv3 IS r_0fe(7 DOWNTO 5); -- Character shift register
  -- Horizontal character delay is captured at the start of each DMA row.
  SIGNAL hshift_row : uv3 := (OTHERS => '0');
  -- Registered horizontal origin shared by fetch, clipping and pixel phase.
  SIGNAL row_origin : natural range 0 to 255 := 43;
  SIGNAL hshift_zero_pending : std_logic := '0';

  ALIAS r_rng   : std_logic IS r_0fe(4); -- Random noise
  ALIAS r_sen   : std_logic IS r_0fe(3); -- Sound enable
  ALIAS r_loud  : uv3 IS r_0fe(2 DOWNTO 0); -- Sound loudness
  SIGNAL dmarow : uv4; -- FF -- renderer/internal DMA row
  -- CPU-visible DMA status. Small-character mode follows the renderer DMA row;
  -- tall-character mode uses the measured 11-scanline status phase offset.
  SIGNAL dmarow_cpu : uv4 := to_unsigned(15,4);
  CONSTANT TALL_DMA_STATUS_VPHASE : natural := 11;
  -- Physical SC2637 DMA owns the processor bus for one complete TV line.
  -- This is intentionally separate from the CPU-visible DMA-row register.
  SIGNAL dma_pause_i : std_logic := '0';
  SIGNAL r_1f8 : uv8;
  ALIAS r_gmode : std_logic IS r_1f8(7);     -- Graphic mode
  ALIAS r_ref : std_logic IS r_1f8(6);    -- Resolution vert.
  ALIAS r_acc : uv3 IS r_1f8(5 DOWNTO 3); -- Alternate Character Colour (Cc')
  ALIAS r_asc : uv3 IS r_1f8(2 DOWNTO 0); -- Alternate Screen Colour (Cs')
  SIGNAL r_1f9 : uv8;
  ALIAS r_cc : uv3 IS r_1f9(5 DOWNTO 3); -- Character Colour
  ALIAS r_sc : uv3 IS r_1f9(2 DOWNTO 0); -- Screen Colour
  ALIAS r_pmux  : std_logic IS r_1f9(6); -- Pot mux
  ALIAS r_csize : std_logic IS r_1f9(7); -- Character Size
  SIGNAL r_1fa,r_1fb : uv8;
  ALIAS o1_size : std_logic IS r_1fb(7); -- Object 1 size
  ALIAS o2_size : std_logic IS r_1fb(6); -- Object 2 size
  ALIAS o3_size : std_logic IS r_1fa(7); -- Object 3 size
  ALIAS o4_size : std_logic IS r_1fa(6); -- Object 4 size
  ALIAS o1_col : uv3 IS r_1fb(5 DOWNTO 3); -- Object 1 colour
  ALIAS o2_col : uv3 IS r_1fb(2 DOWNTO 0); -- Object 2 colour
  ALIAS o3_col : uv3 IS r_1fa(5 DOWNTO 3); -- Object 3 colour
  ALIAS o4_col : uv3 IS r_1fa(2 DOWNTO 0); -- Object 4 colour
  SIGNAL ccoll : uv4; -- Character collision, active low
  SIGNAL ocoll : uv6; -- Object collision, active low
  SIGNAL pot24, pot13 : uv8;

  -- The real SC2637 fetches one 16-character row during the row DMA and
  -- retains those character bytes while the remaining rasters of that row
  -- are displayed. This row buffer models that documented retention behavior.
  TYPE rowbuf_t IS ARRAY (0 TO 15) OF uv8;
  SIGNAL rowbuf : rowbuf_t;
  SIGNAL char_code_mux : uv8;

  SIGNAL o1_hit,o2_hit,o3_hit,o4_hit,bg_hit : std_logic;
  SIGNAL o12_coll,o13_coll,o23_coll,o14_coll,o34_coll,o24_coll : std_logic;
  SIGNAL o1c_coll,o2c_coll,o3c_coll,o4c_coll : std_logic;

  SIGNAL col_grb : uv3;
  -- SC2637 object colours are wired-ORed when objects overlap.
  SIGNAL obj_grb_acc : uv3 := (OTHERS => '0');
  SIGNAL obj_any     : std_logic := '0';
  -- SC2637 character-video horizontal origin.
  -- Character video begins at UVI clock 23 plus the per-row HSHIFT.
  -- Objects retain their independently validated origin HC - 20.
  CONSTANT HOFFSET : natural := 23;

  -- SC2637 object horizontal coordinates are not in the same origin as the
  -- cropped Arcadia picture.  With the 2621/2622 timing, the visible raster
  -- begins at UVI count 49 while the object coordinate domain carries a
  -- 20-clock pre-display offset.  Express object X in this renderer's
  -- left-edge-relative hpos domain by subtracting that offset.
  --
  -- This is a chip/timing rule, not a Black Jack special case.
  CONSTANT OBJ_X_ORIGIN : natural := 20;
  CONSTANT OBJ_X_LAST   : natural := 227;

  SIGNAL cyc : uint3;
  SIGNAL vrle,vrle_pre,hrle,hrle_pre,hpulse : std_logic;
  SIGNAL hpos,hlen,hsync,hdisp : uint9;
  SIGNAL vpos,vlen,vsync,vdisp : uint9;

  SIGNAL gmode : std_logic;
  
  ------------------------------------------------
  -- Preservation sound rebuild: the old ad-hoc Sono process has been
  -- replaced by a self-contained SC2637 sound block.
  SIGNAL sound_chip : unsigned(7 DOWNTO 0);
  
  ------------------------------------------------
  -- Read object/character
  FUNCTION objadrs(
    vpos : uint9; -- Spot vertical   position
    vc   : uv8; -- Vertical   coordinate object
    size : std_logic; -- Object size
    no   : uint2) RETURN unsigned IS
    VARIABLE ivc : natural := to_integer(vc);
  BEGIN
    IF size='0' THEN -- 16 lines
      RETURN to_unsigned(384 + no*8 + (((vpos-ivc)/2) MOD 8), 10);
    ELSE -- 8 lines
      RETURN to_unsigned(384 + no*8 + (((vpos-ivc) ) MOD 8), 10);
    END IF;
  END FUNCTION objadrs;

  ------------------------------------------------
  FUNCTION objbit(
    hpos : uint9; -- Spot horizontal position
    hc   : uv8 ) RETURN natural IS -- Horizontal coordinate object
    VARIABLE a : uint3;
    VARIABLE ihc : integer := to_integer(hc) - OBJ_X_ORIGIN;
  BEGIN
    -- objhit() rejects coordinates before the visible object origin; keep
    -- the bit selector harmless when called for one of those coordinates.
    IF ihc < 0 THEN
      RETURN 0;
    ELSE
      a:=(hpos-ihc) MOD 8;
      RETURN 7-a;
    END IF;
  END FUNCTION;
  
  ------------------------------------------------
  FUNCTION objhit(
    hpos : uint9; -- Spot horizontal position
    vpos : uint9; -- Spot vertical   position
    hc   : uv8; -- Horizontal coordinate object
    vc   : uv8; -- Vertical   coordinate object
    size : std_logic) RETURN boolean IS -- Object size
    VARIABLE ivc : uint8 := to_integer(vc);
    VARIABLE ihc : integer := to_integer(hc) - OBJ_X_ORIGIN;
  BEGIN
    -- Convert the SC2637 object coordinate into the renderer's visible-X
    -- domain.  Coordinates before the object origin or beyond the chip
    -- displayable range do not produce pixels.
    IF to_integer(hc) < OBJ_X_ORIGIN OR to_integer(hc) > OBJ_X_LAST THEN
      RETURN false;
    ELSIF size='1' THEN -- Small
      RETURN vpos>=ivc AND (vpos-ivc)<8 AND hpos>=ihc AND (hpos-ihc)<8;
    ELSE -- High
      RETURN vpos>=ivc AND (vpos-ivc)<16 AND hpos>=ihc AND (hpos-ihc)<8;
    END IF;
  END FUNCTION;

  ------------------------------------------------
  -- True on the first physical raster of a character row. Small characters
  -- are 8 rasters high; enlarged characters repeat each font raster twice
  -- across a 16-raster character row.
  FUNCTION first_char_raster(
    vpos    : uint9;
    voffset : uv8;
    csize   : std_logic) RETURN boolean IS
    VARIABLE ivoff : natural := to_integer(voffset);
  BEGIN
    IF vpos < ivoff THEN
      RETURN false;
    ELSIF csize='1' THEN
      RETURN ((vpos-ivoff) MOD 8)=0;
    ELSE
      RETURN ((vpos-ivoff) MOD 16)=0;
    END IF;
  END FUNCTION;

  ------------------------------------------------
  FUNCTION pix(g : std_logic; -- 0=Text 1=Graph
               h : uint3;  -- Horizontal offset
               v : uint1;  -- Vertical   offset
               d : uv8;    -- Character font
               c : uv8) RETURN boolean IS -- Character code (for graphics)
  BEGIN
    IF g='0' THEN
      RETURN d(7-h)='1';
    ELSE
      -- Documented SC2637 block-graphics mapping is exactly:
      --   22211100
      --   22211100
      --   22211100
      --   22211100
      --   55544433
      --   55544433
      --   55544433
      --   55544433
      -- i.e. horizontal widths 3 + 3 + 2, matching the documented mapping.
      IF    v=0 AND h<3 THEN  RETURN c(2)='1';
      ELSIF v=1 AND h<3 THEN  RETURN c(5)='1';
      ELSIF v=0 AND h<6 THEN  RETURN c(1)='1';
      ELSIF v=1 AND h<6 THEN  RETURN c(4)='1';
      ELSIF v=0         THEN  RETURN c(0)='1';
      ELSE                    RETURN c(3)='1';
      END IF;
    END IF;
  END FUNCTION;
  
  ------------------------------------------------

BEGIN
  
  ack<='1';

  dma_pause <= dma_pause_i;

  wreq<=wr AND req AND tick;
  -- Normalise the Arcadia mirror aliases to the native 1 KiB 2637 window.
  -- $xB00-$xBFF is an alias of $x900-$x9FF; the surrounding 1 KiB blocks
  -- repeat at $x000/$x400/$x800/$xC00 within each odd 4 KiB CPU page.
  adi <= "000" & ad(8 DOWNTO 0) WHEN ad(9 DOWNTO 8)="11" ELSE
         "00"  & ad(9 DOWNTO 0);

  dr<=dr_reg WHEN drreg_sel='1' ELSE dr_mem;
  
  Regs:PROCESS(clk,reset_na) IS
  BEGIN
    IF reset_na='0' THEN
      -- Collision status is inactive (all ones) until the first hit.
      ccoll<=(OTHERS => '1');
      ocoll<=(OTHERS => '1');
      
    ELSIF rising_edge(clk) THEN
      --------------------------------------------
      -- RAM
      dr_mem<=ram(to_integer(adi(9 DOWNTO 0)));

      IF wreq='1' THEN
        ram(to_integer(adi(9 DOWNTO 0)))<=dw;
      END IF;
      
      --------------------------------------------
      -- Registers
      drreg_sel<='0';
      dr_reg<=x"00";
      
      CASE adi IS
        WHEN x"0F0" =>  IF wreq='1' THEN o1_vc_wr<=(NOT dw) + 1; END IF;
        WHEN x"0F1" =>  IF wreq='1' THEN o1_hc_wr<=dw; END IF;
        WHEN x"0F2" =>  IF wreq='1' THEN o2_vc_wr<=(NOT dw) + 1; END IF;
        WHEN x"0F3" =>  IF wreq='1' THEN o2_hc_wr<=dw; END IF;
        WHEN x"0F4" =>  IF wreq='1' THEN o3_vc_wr<=(NOT dw) + 1; END IF;
        WHEN x"0F5" =>  IF wreq='1' THEN o3_hc_wr<=dw; END IF;
        WHEN x"0F6" =>  IF wreq='1' THEN o4_vc_wr<=(NOT dw) + 1; END IF;
        WHEN x"0F7" =>  IF wreq='1' THEN o4_hc_wr<=dw; END IF;
        WHEN x"0FC" =>  IF wreq='1' THEN voffset<=NOT dw; END IF;
        WHEN x"0FD" =>  IF wreq='1' THEN r_0fd<=dw; END IF;
        WHEN x"0FE" =>  IF wreq='1' THEN r_0fe<=dw; END IF;
        WHEN x"0FF" =>
          IF r_csize='1' THEN
            dr_reg <= "1111" & dmarow;
          ELSE
            dr_reg <= "1111" & dmarow_cpu;
          END IF;
          drreg_sel<='1';
        WHEN x"1F8" =>  IF wreq='1' THEN r_1f8<=dw; END IF;
        WHEN x"1F9" =>  IF wreq='1' THEN r_1f9<=dw; END IF;
        WHEN x"1FA" =>  IF wreq='1' THEN r_1fa<=dw; END IF;
        WHEN x"1FB" =>  IF wreq='1' THEN r_1fb<=dw; END IF;
        WHEN x"1FC" =>  dr_reg<="1111" & ccoll; drreg_sel<='1'; -- Coll bg
        WHEN x"1FD" =>  dr_reg<="11" & ocoll;   drreg_sel<='1'; -- Coll obj
        WHEN x"1FE" =>  dr_reg<=pot24; drreg_sel<='1'; -- POT24
        WHEN x"1FF" =>  dr_reg<=pot13; drreg_sel<='1'; -- POT13
        WHEN OTHERS =>  NULL;
      END CASE;

      --------------------------------------------
      -- SC2637 object coordinate sampling.
      -- The UVI accesses the horizontal/vertical coordinates of all four
      -- objects at DMA 15. Keep CPU-programmed values separate from the
      -- raster-active values and take one coherent snapshot at the
      -- trailing edge of VRST (DMA-15 -> active-field boundary).
      IF vrle_pre='1' AND vrle='0' THEN
        o1_vc <= o1_vc_wr; o1_hc <= o1_hc_wr;
        o2_vc <= o2_vc_wr; o2_hc <= o2_hc_wr;
        o3_vc <= o3_vc_wr; o3_hc <= o3_hc_wr;
        o4_vc <= o4_vc_wr; o4_hc <= o4_hc_wr;
      END IF;

      --------------------------------------------
      -- Collisions.  The SC2637 status latches are active low.  A read returns
      -- the pre-clear value on this clock edge, then immediately rearms the
      -- complete status register; trailing VRST also rearms it.
      IF (vrle_pre='1' AND vrle='0') OR
         (adi=x"1FC" AND req='1' AND tick='1' AND wr='0') THEN
        ccoll<=(OTHERS => '1');
      ELSE
        ccoll<=ccoll AND NOT (o4c_coll & o3c_coll & o2c_coll & o1c_coll);
      END IF;
      
      IF (vrle_pre='1' AND vrle='0') OR
         (adi=x"1FD" AND req='1' AND tick='1' AND wr='0') THEN
        ocoll<=(OTHERS => '1');
      ELSE
        ocoll<=ocoll AND NOT (o34_coll & o24_coll & o23_coll &
                              o14_coll & o13_coll & o12_coll);
      END IF;
      
      --------------------------------------------
      -- POT MUX
      -- Paddle A/D registers are valid only during vertical reset.
      -- Outside VRST the real 2637 returns $FF.
      IF vrle='1' THEN
        pot13<=mux(r_pmux,pot3,pot1);
        pot24<=mux(r_pmux,pot4,pot2);
      ELSE
        pot13<=x"FF";
        pot24<=x"FF";
      END IF;
      
      --------------------------------------------
    END IF;
    
  END PROCESS Regs;

  ------------------------------------------------------------------------------
  -- Memory address mux
  MadMux:PROCESS(ram_dr,rowbuf,vpos,voffset,hpos,row_origin,r_csize,r_ref,dmarow,
                 o1_size,o2_size,o3_size,o4_size,
                 o1_vc,o2_vc,o3_vc,o4_vc,cyc) IS
    VARIABLE col_i       : natural RANGE 0 TO 15;
    VARIABLE raster_i    : natural RANGE 0 TO 15;
    VARIABLE text_addr_i : natural RANGE 0 TO 1023;
    VARIABLE active_cell : boolean;
    VARIABLE char_code_v : uv8;
  BEGIN
    char_code_v   := x"00";
    char_code_mux <= x"00";
    rom_ad         <= (OTHERS => '0');
    ram_ad         <= (OTHERS => '0');

    active_cell := hpos>=row_origin AND hpos<row_origin+16*8 AND
                   vpos>=to_integer(voffset) AND
                   to_integer(dmarow)<=12;

    IF active_cell THEN
      col_i := (hpos-row_origin)/8;

      -- On the first raster the external character byte is fetched; for all
      -- later rasters use the SC2637 row-buffer copy.
      IF first_char_raster(vpos,voffset,r_csize) AND
         ((hpos-row_origin) MOD 8)=0 THEN
        char_code_v := ram_dr;
      ELSE
        char_code_v := rowbuf(col_i);
      END IF;
      char_code_mux <= char_code_v;

      IF r_csize='1' THEN
        raster_i := (vpos-to_integer(voffset)) MOD 8;
      ELSE
        raster_i := ((vpos-to_integer(voffset))/2) MOD 8;
      END IF;

      -- Built-in character ROM and UDG lookup both use the buffered code.
      rom_ad <= (char_code_v(5 DOWNTO 0) & "000") + raster_i;

      IF r_csize='1' AND r_ref='1' AND
         vpos>=to_integer(voffset)+13*8 THEN
        text_addr_i := 512 + col_i + to_integer(dmarow)*16;
      ELSE
        text_addr_i := col_i + to_integer(dmarow)*16;
      END IF;
    END IF;

    CASE cyc IS
      WHEN 1 | 7 | 0 => -- External character-code fetch
        IF active_cell THEN
          ram_ad <= to_unsigned(text_addr_i,10);
        END IF;

      WHEN 2 => -- Read user character shape
        IF active_cell THEN
          ram_ad <= to_unsigned(384 + to_integer(char_code_v(2 DOWNTO 0))*8 +
                                raster_i,10);
        END IF;

      WHEN 3 => -- Read object 1 shape
        ram_ad <=objadrs(vpos,o1_vc,o1_size,0);

      WHEN 4 =>
        ram_ad <=objadrs(vpos,o2_vc,o2_size,1);

      WHEN 5 =>
        ram_ad <=objadrs(vpos,o3_vc,o3_size,2);

      WHEN 6 =>
        ram_ad <=objadrs(vpos,o4_vc,o4_size,3);

    END CASE;

  END PROCESS MadMux;

  ------------------------------------------------------------------------------
  
  rom_dr<=CHARS(to_integer(rom_ad)) WHEN rising_edge (clk);
 
  Madar:PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      ram_dr<=ram(to_integer(ram_ad));
    END IF;
  END PROCESS Madar;
  
  ------------------------------------------------------------------------------

  Vid:PROCESS (clk,reset_na) IS
    VARIABLE h,m : boolean;
    VARIABLE i : natural RANGE 0 TO 7;
    VARIABLE dm_v : uv8;
    VARIABLE next_v : natural RANGE 0 TO 311;
    VARIABLE next_dma : uv4;
    VARIABLE dma_status_v : natural;
  BEGIN
    IF reset_na='0' THEN
      dma_pause_i <= '0';
    ELSIF rising_edge(clk) THEN
      --------------------------------------------
      -- 2622 NTSC and 2621 PAL both use exactly 227 pixel clocks per line.
      -- Counters are zero based, hence terminal counts 226 / 261 / 311.
      -- VRST (and therefore the 2650 SENSE input) lasts 20 NTSC lines or
      -- 43 PAL lines, as on the real USG.
      hlen <=226;
      hsync<=200;
      hdisp<=184;
      IF np='0' THEN
        -- 262 total lines: 242 active + 20 vertical-reset lines.
        vlen <=261;
        vdisp<=242;
        vsync<=241;
      ELSE
        -- 312 total lines: 269 active + 43 vertical-reset lines.
        vlen <=311;
        vdisp<=269;
        vsync<=268;
      END IF;
      
      --------------------------------------------
      -- Collisions pulses
      o12_coll<='0';
      o23_coll<='0';
      o34_coll<='0';
      o13_coll<='0';
      o14_coll<='0';
      o24_coll<='0';
      o1c_coll<='0';
      o2c_coll<='0';
      o3c_coll<='0';
      o4c_coll<='0';
      
      hpulse<='0';

      --------------------------------------------
      cyc<=(cyc+1) MOD 8;
      
      CASE cyc IS
        WHEN 0 => -- Clear
          IF hpos<hlen THEN
            -- Capture horizontal delay at the first raster of a character row.
            IF hpos=0 THEN
              -- Keep the 8-raster character status stream aligned with the
              -- renderer. For 16-raster characters, phase only the CPU-visible
              -- DMA status; internal fetch/render timing remains unchanged.
              IF r_csize='0' THEN
                IF vpos < TALL_DMA_STATUS_VPHASE THEN
                  dmarow_cpu <= to_unsigned(15,4);
                ELSE
                  dma_status_v := vpos - TALL_DMA_STATUS_VPHASE;
                  IF dma_status_v < to_integer(voffset) THEN
                    dmarow_cpu <= to_unsigned(15,4);
                  ELSIF dma_status_v < to_integer(voffset)+16*13 THEN
                    dmarow_cpu <= to_unsigned((dma_status_v-to_integer(voffset))/16,4);
                  ELSE
                    dmarow_cpu <= to_unsigned(13,4);
                  END IF;
                END IF;
              END IF;

              IF r_csize='1' THEN
                IF vpos<to_integer(voffset) THEN
                  next_dma := to_unsigned(15,4);
                ELSIF vpos<to_integer(voffset)+8*13 THEN
                  next_dma := to_unsigned((vpos-to_integer(voffset))/8,4);
                ELSIF vpos<to_integer(voffset)+8*13*2 AND r_ref='1' THEN
                  next_dma := to_unsigned((vpos-to_integer(voffset))/8-13,4);
                ELSE
                  next_dma := to_unsigned(13,4);
                END IF;
              ELSE
                IF vpos<to_integer(voffset) THEN
                  next_dma := to_unsigned(15,4);
                ELSIF vpos<to_integer(voffset)+16*13 THEN
                  next_dma := to_unsigned((vpos-to_integer(voffset))/16,4);
                ELSE
                  next_dma := to_unsigned(13,4);
                END IF;
              END IF;

              IF next_dma /= dmarow THEN
                -- The SC2637 asserts PAUSE and owns the 2650 bus for
                -- one TV scanline for each DMA number 15,0..13.  DMA 14 does
                -- not exist.  Assertion is aligned to this model's DMA-row
                -- boundary; the documented ~600 ns bus-release preamble can
                -- be refined later if hardware timing requires it.
                IF next_dma=to_unsigned(15,4) OR to_integer(next_dma)<=13 THEN
                  dma_pause_i <= '1';
                END IF;
              END IF;

              IF next_dma /= dmarow AND to_integer(next_dma) <= 12 THEN
                -- The UVI fetches $FD/$FE for each DMA row.  Sample the color
                -- mode and horizontal shift before CPU writes later in this
                -- row can modify the live register copies.
                r_cm_row <= r_cm;
                hshift_row <= hshift;
                row_origin <= HOFFSET + to_integer(hshift);
                hshift_zero_pending <= '0';
              END IF;
            END IF;
            hpos<=hpos+1;
          ELSE
            hpos<=0;
            -- End of the one-line SC2637 DMA ownership window.
            dma_pause_i <= '0';
            gmode<=r_gmode;

            IF vpos<vlen THEN
              next_v := vpos + 1;

              IF r_csize='1' THEN
                IF next_v < to_integer(voffset) THEN
                  next_dma := to_unsigned(15,4);
                ELSIF next_v < to_integer(voffset)+8*13 THEN
                  next_dma := to_unsigned((next_v-to_integer(voffset))/8,4);
                ELSIF next_v < to_integer(voffset)+8*13*2 AND r_ref='1' THEN
                  next_dma := to_unsigned((next_v-to_integer(voffset))/8-13,4);
                ELSE
                  next_dma := to_unsigned(13,4);
                END IF;
              ELSE
                IF next_v < to_integer(voffset) THEN
                  next_dma := to_unsigned(15,4);
                ELSIF next_v < to_integer(voffset)+16*13 THEN
                  next_dma := to_unsigned((next_v-to_integer(voffset))/16,4);
                ELSE
                  next_dma := to_unsigned(13,4);
                END IF;
              END IF;

              -- HSHIFT is captured at hpos=0 of the first raster, not here.

              vpos<=vpos+1;
            ELSE
              vpos<=0;
              hshift_row <= hshift;
              row_origin <= HOFFSET + to_integer(hshift);
              hshift_zero_pending <= '0';
            END IF;
            
            hpulse<='1';
            
          END IF;

          o1_hit<='0';
          o2_hit<='0';
          o3_hit<='0';
          o4_hit<='0';
          bg_hit<='0';

          IF r_csize='1' THEN -- Small chars
            IF vpos<to_integer(voffset) THEN
              dmarow<=to_unsigned(15,4);
            ELSIF vpos<to_integer(voffset)+8*13 THEN
              dmarow<=to_unsigned((vpos-to_integer(voffset))/8,4);
            ELSIF vpos<to_integer(voffset)+8*13*2 AND r_ref='1' THEN
              dmarow<=to_unsigned((vpos-to_integer(voffset))/8-13,4);
            ELSE
              dmarow<=to_unsigned(13,4);
            END IF;
          ELSE -- Tall chars
            IF vpos<to_integer(voffset) THEN
              dmarow<=to_unsigned(15,4);
            ELSIF vpos<to_integer(voffset)+16*13 THEN
              dmarow<=to_unsigned((vpos-to_integer(voffset))/16,4);
            ELSE
              dmarow<=to_unsigned(13,4);
            END IF;
          END IF;

          o12_coll<=o1_hit AND o2_hit;
          o23_coll<=o2_hit AND o3_hit;
          o34_coll<=o3_hit AND o4_hit;
          o13_coll<=o1_hit AND o3_hit;
          o14_coll<=o1_hit AND o4_hit;
          o24_coll<=o2_hit AND o4_hit;
          o1c_coll<=o1_hit AND bg_hit;
          o2c_coll<=o2_hit AND bg_hit;
          o3c_coll<=o3_hit AND bg_hit;
          o4c_coll<=o4_hit AND bg_hit;

          vid_argb<='1' & NOT (col_grb(1) & col_grb(2) & col_grb(0));

        WHEN 1 =>
          -- Wait !
          NULL;
          
        WHEN 2 =>
          -- Character address. Capture one byte per cell on the first raster
          -- and consume the retained row-buffer value on subsequent rasters.
          ch<=char_code_mux;
          IF hpos>=row_origin AND hpos<row_origin+16*8 AND
             vpos>=to_integer(voffset) AND
             to_integer(dmarow)<=12 AND
             first_char_raster(vpos,voffset,r_csize) AND
             ((hpos-row_origin) MOD 8)=0 THEN
            rowbuf((hpos-row_origin)/8) <= ram_dr;
          END IF;
          
        WHEN 3 =>


          -- Read Char. map : ROM + user char
          -- code charactère
          -- image ROM
          -- image user
          -- position écran
          -- paramètres : offset, hauteur, mode graphique
          IF ch(5 DOWNTO 0)<"111000" THEN
            dm_v:=rom_dr;
          ELSE
            dm_v:=ram_dr; -- User char.
          END IF;

          m:=true;

          IF r_csize='0' OR r_ref='1' THEN -- Full scree
            IF vpos<to_integer(voffset) OR --to_integer(voffset)>=128 OR
              vpos>=to_integer(voffset)+8*26 OR
              hpos<row_origin OR
              hpos>=16*8+row_origin THEN
              m:=false;
            END IF;

          ELSE -- Half, small chars
            IF vpos<to_integer(voffset) OR --to_integer(voffset)>=128 OR
              vpos>=to_integer(voffset)+8*13 OR
              hpos<row_origin OR
              hpos>=16*8+row_origin THEN
              m:=false;
            END IF;

          END IF;
          --IF r_csize='1' THEN -- 16x13 mode
          --  IF vpos<to_integer(voffset) OR to_integer(voffset)>=128 OR
          --    vpos>=to_integer(voffset)+16*13 OR
          --    hpos<row_origin OR
          --    hpos>=16*8+row_origin THEN
          --    m:=false;
          --  END IF;
          --ELSE -- 16x26 mode
          --  IF vpos<to_integer(voffset) OR to_integer(voffset)>=128 OR
          --    (vpos>=8*13+to_integer(voffset) AND r_ref='0') OR
          --    (vpos>=8*26+to_integer(voffset) AND r_ref='1') OR
          --    hpos<row_origin OR
          --    hpos>=16*8+row_origin THEN
          --    m:=false; 
          --  END IF;
          --END IF;
          
          -- $C0 / $40 switch block-graphics mode on / off from that cell to
          -- the end of the line, in ANY column (as in MAME and in the original
          -- MiSTer/Senhor core). The line starts in the mode set by $19F8 bit 7.
          -- Mobile Soldier Gundam switches modes mid-line for its katakana title;
          -- restricting the codes to the first column broke it.
          IF ch=x"C0" AND m THEN
            gmode<='1';
            h:=false;
            
          ELSIF ch=x"40" AND m THEN
            gmode<='0';
            h:=false;
            
          ELSIF r_csize='1' THEN -- high resolution: 8 raster lines/character
            -- 2637 block graphics are split into a 4-line upper half and a
            -- 4-line lower half.  The old core divided by 8 here, so it
            -- never selected the lower half in high-resolution mode.
            h:=pix(gmode,(hpos-row_origin) MOD 8,
                   ((vpos-to_integer(voffset))/4) MOD 2,dm_v,ch);
          ELSE -- low resolution: each 8-line character is doubled to 16 rasters
            -- With vertical doubling each block half occupies 8 scanlines.
            h:=pix(gmode,(hpos-row_origin) MOD 8,
                   ((vpos-to_integer(voffset))/8) MOD 2,dm_v,ch);
          END IF;
          
          bg_hit<=to_std_logic(h AND m);

          -- Start a fresh object-colour accumulator for this pixel.  Object
          -- colours are applied in phases 4..7 and wired-ORed on overlap.
          obj_grb_acc <= (OTHERS => '0');
          obj_any     <= '0';
          
          IF r_cm_row='0' THEN -- Character Color Mode = 0 (DMA-row latched)
            col_grb<=mux(h AND m,ch(7 DOWNTO 6) & r_cc(0),r_sc);
          ELSE -- Character Color Mode = 1 (board mode)
            -- Signetics mode-1 truth table:
            --   video=1, B6=1 : Cc1,Cc2,Cc3
            --   video=1, B6=0 : Cc'1,Cs'2,Cc'3
            --   video=0, B7=1 : Cs1,Cs2,Cs3
            --   video=0, B7=0 : Cs'1,Cs'2,Cs'3
            -- r_acc is Cc' and r_asc is Cs'.  The alternate foreground is
            -- deliberately a mixed colour: only its middle component comes
            -- from the alternate screen colour.
            IF m THEN
              IF h THEN
                IF ch(6)='1' THEN
                  col_grb<=r_cc;
                ELSE
                  col_grb<=r_acc(2) & r_asc(1) & r_acc(0);
                END IF;
              ELSE
                col_grb<=mux(ch(7),r_sc,r_asc);
              END IF;
            ELSE
              -- Outside the active character field the outer screen colour
              -- remains the normal screen colour.
              col_grb<=r_sc;
            END IF;
          END IF;
          
        WHEN 4 => -- Object 1
          i:=objbit(hpos,o1_hc);
          h:=objhit(hpos,vpos,o1_hc,o1_vc,o1_size);
          
          IF h AND ram_dr(i)='1' THEN
            o1_hit<='1';
            obj_grb_acc<=o1_col;
            obj_any<='1';
            col_grb<=o1_col;
          END IF;
          
        WHEN 5 => -- Object 2
          i:=objbit(hpos,o2_hc);
          h:=objhit(hpos,vpos,o2_hc,o2_vc,o2_size);
          
          IF h AND ram_dr(i)='1' THEN
            o2_hit<='1';
            IF obj_any='1' THEN
              obj_grb_acc<=obj_grb_acc OR o2_col;
              col_grb<=obj_grb_acc OR o2_col;
            ELSE
              obj_grb_acc<=o2_col;
              obj_any<='1';
              col_grb<=o2_col;
            END IF;
          END IF;
          
        WHEN 6 => -- Object 3
          i:=objbit(hpos,o3_hc);
          h:=objhit(hpos,vpos,o3_hc,o3_vc,o3_size);
          
          IF h AND ram_dr(i)='1' THEN
            o3_hit<='1';
            IF obj_any='1' THEN
              obj_grb_acc<=obj_grb_acc OR o3_col;
              col_grb<=obj_grb_acc OR o3_col;
            ELSE
              obj_grb_acc<=o3_col;
              obj_any<='1';
              col_grb<=o3_col;
            END IF;
          END IF;
          
        WHEN 7 => -- Object 4
          i:=objbit(hpos,o4_hc);
          h:=objhit(hpos,vpos,o4_hc,o4_vc,o4_size);
          
          IF h AND ram_dr(i)='1' THEN
            o4_hit<='1';
            IF obj_any='1' THEN
              obj_grb_acc<=obj_grb_acc OR o4_col;
              col_grb<=obj_grb_acc OR o4_col;
            ELSE
              obj_grb_acc<=o4_col;
              obj_any<='1';
              col_grb<=o4_col;
            END IF;
          END IF;
          
      END CASE;
      
      vid_hsyn<=to_std_logic(hpos>hsync);
      vid_vsyn<=to_std_logic(vpos>vsync);
      vrle    <=to_std_logic(vpos>vsync);
      vrle_pre<=vrle;
      hrle    <=to_std_logic(hpos>hsync);
      hrle_pre<=hrle;
      vid_de     <=to_std_logic(hpos<hdisp AND vpos<vdisp);
      vid_hblank <=to_std_logic(hpos>=hdisp);
      vid_vblank <=to_std_logic(vpos>=vdisp);
      
      vid_ce<=to_std_logic(cyc=0);
      
    --------------------------------------------
    END IF;


  END PROCESS Vid;

  vrst<=vrle;
  
  ------------------------------------------------------------------------------
  -- SC2637 sound generator rebuilt from the Signetics functional description.
  -- hpulse is asserted once per UVI horizontal line by the video timing block,
  -- which is the native timebase specified for both tone and random noise.
  i_sgs2637_sound: ENTITY work.sgs2637_sound
    PORT MAP (
      clk         => clk,
      reset_n     => reset_na,
      hline_pulse => hpulse,
      pitch       => r_freq,
      rng_enable  => r_rng,
      tone_enable => r_sen,
      loudness    => r_loud,
      sample      => sound_chip
    );

  sound <= sound_chip;
  
  
END ARCHITECTURE rtl;

