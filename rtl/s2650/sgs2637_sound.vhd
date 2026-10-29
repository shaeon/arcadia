--------------------------------------------------------------------------------
-- Signetics 2637 UVI sound generator - preservation rebuild H
--------------------------------------------------------------------------------
-- H1 is a minimal hardware-oriented correction to REBUILD H.
--
-- REBUILD H contained a synthetic 256-horizontal-line post-disable completion
-- window.  When software disabled FEN/RNG, that wrapper continued presenting the
-- last pitch/mode/loudness to the sound generator for ~16.2 ms on NTSC.  The
-- SC2637 documentation does not describe such a post-disable hold, so H1 removes
-- that compatibility wrapper and presents the live SC2637 registers directly.
--
-- IMPORTANT: this is deliberately a MINIMAL change.  The REBUILD H digital
-- sequencer itself is otherwise unchanged:
--   * shared running divider
--   * 9-bit LFSR, seed 0x0F0, feedback bit0 XOR bit4
--   * tone/noise source selection and AND combination
--   * bipolar PCM presentation for MiSTer
--
-- REBUILD H's measured output-coupling model is retained unchanged.  The supplied
-- real-console recording shows an exponential AC-coupled step response with tau
-- about 0.74-0.78 ms.  At one update per UVI horizontal line (~63.4 us NTSC),
-- 235/256 gives tau ~0.741 ms (fc ~215 Hz), matching the recording closely.
--
-- The filter remains a first-order high-pass/DC coupling model:
--   y[n] = a * ( y[n-1] + x[n] - x[n-1] ), a = 235/256
--
-- This build intentionally does NOT claim that all undocumented SC2637 divider,
-- FEN phase, or current-output details are proven.  It only removes the known
-- synthetic post-disable extension while preserving the tested RC5/H baseline.
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY sgs2637_sound IS
  PORT (
    clk          : IN  std_logic;
    reset_n      : IN  std_logic;
    hline_pulse  : IN  std_logic;

    pitch        : IN  unsigned(6 DOWNTO 0); -- FD[6:0] = N
    rng_enable   : IN  std_logic;             -- FE[4]
    tone_enable  : IN  std_logic;             -- FE[3] = FEN
    loudness     : IN  unsigned(2 DOWNTO 0);  -- FE[2:0] = LS

    sample       : OUT unsigned(7 DOWNTO 0)
  );
END ENTITY sgs2637_sound;

ARCHITECTURE rtl OF sgs2637_sound IS

  CONSTANT LFSR_INIT : unsigned(8 DOWNTO 0) := to_unsigned(16#0F0#, 9);

  -- REBUILD C UVI state.
  SIGNAL div_count : unsigned(6 DOWNTO 0) := (OTHERS => '0');
  SIGNAL tone_ff   : std_logic := '1';
  SIGNAL noise_ff  : std_logic := '0';
  SIGNAL lfsr      : unsigned(8 DOWNTO 0) := LFSR_INIT;
  SIGNAL mode_prev : unsigned(1 DOWNTO 0) := (OTHERS => '0');

  SIGNAL eff_pitch : unsigned(6 DOWNTO 0);
  SIGNAL eff_mode  : unsigned(1 DOWNTO 0);
  SIGNAL eff_loud  : unsigned(2 DOWNTO 0);

  -- Raw reconstructed UVI PCM level before the measured console coupling model.
  SIGNAL raw_pcm   : integer RANGE -16 TO 16 := 0;

  -- Q8 state for the measured first-order AC-coupling/high-pass stage.
  -- 235/256 at the horizontal-line update rate gives tau ~0.74 ms.
  SIGNAL hp_y_q    : integer RANGE -32768 TO 32767 := 0;
  SIGNAL hp_x_prev : integer RANGE -16 TO 16 := 0;

  FUNCTION level_amp(ls : unsigned(2 DOWNTO 0)) RETURN integer IS
  BEGIN
    CASE to_integer(ls) IS
      WHEN 0 => RETURN 0;
      WHEN 1 => RETURN 2;
      WHEN 2 => RETURN 5;
      WHEN 3 => RETURN 7;
      WHEN 4 => RETURN 9;
      WHEN 5 => RETURN 11;
      WHEN 6 => RETURN 14;
      WHEN 7 => RETURN 16;
      WHEN OTHERS => RETURN 0;
    END CASE;
  END FUNCTION;

BEGIN

  ------------------------------------------------------------------------------
  -- Live SC2637 register presentation.
  --
  -- No synthetic post-disable completion is applied.  When software disables
  -- FEN/RNG or changes pitch/loudness, the reconstructed generator immediately
  -- sees the current register state.  The analog coupling stage below may still
  -- ring/decay naturally from its stored state; that is separate from extending
  -- the digital sound request itself.
  ------------------------------------------------------------------------------
  eff_pitch <= pitch;
  eff_mode  <= unsigned'(rng_enable & tone_enable);
  eff_loud  <= loudness;

  ------------------------------------------------------------------------------
  -- Shared UVI sequencer from REBUILD C.
  ------------------------------------------------------------------------------
  Seq:PROCESS(clk, reset_n) IS
    VARIABLE feedback  : std_logic;
    VARIABLE mode_now  : unsigned(1 DOWNTO 0);
    VARIABLE tone_next : std_logic;
    VARIABLE next_pos  : integer RANGE 0 TO 128;
  BEGIN
    IF reset_n='0' THEN
      div_count <= (OTHERS => '0');
      tone_ff   <= '1';
      noise_ff  <= '0';
      lfsr      <= LFSR_INIT;
      mode_prev <= (OTHERS => '0');

    ELSIF rising_edge(clk) THEN
      mode_now  := eff_mode;
      tone_next := tone_ff;

      IF mode_now /= mode_prev THEN
        tone_next := '0';
      END IF;
      mode_prev <= mode_now;

      IF eff_pitch=0 THEN
        lfsr <= LFSR_INIT;

      ELSIF hline_pulse='1' THEN
        next_pos := to_integer(div_count) + 1;

        IF next_pos >= to_integer(eff_pitch) THEN
          div_count <= (OTHERS => '0');

          noise_ff <= lfsr(0);
          feedback := lfsr(0) XOR lfsr(4);
          lfsr <= feedback & lfsr(8 DOWNTO 1);

          tone_next := NOT tone_next;
        ELSE
          div_count <= to_unsigned(next_pos, div_count'length);
        END IF;
      END IF;

      tone_ff <= tone_next;
    END IF;
  END PROCESS Seq;

  ------------------------------------------------------------------------------
  -- Raw SC2637/UVI output.  This is exactly REBUILD E's bipolar mixer.
  ------------------------------------------------------------------------------
  Mix:PROCESS(eff_pitch, eff_mode, eff_loud, tone_ff, noise_ff) IS
    VARIABLE wave : std_logic;
    VARIABLE amp  : integer RANGE 0 TO 16;
  BEGIN
    wave := '0';
    amp  := level_amp(eff_loud);

    IF eff_pitch=0 OR amp=0 OR eff_mode="00" THEN
      raw_pcm <= 0;
    ELSE
      CASE eff_mode IS
        WHEN "11"   => wave := tone_ff AND noise_ff;
        WHEN "01"   => wave := tone_ff;
        WHEN "10"   => wave := noise_ff;
        WHEN OTHERS => wave := '0';
      END CASE;

      IF wave='1' THEN
        raw_pcm <= amp;
      ELSE
        raw_pcm <= -amp;
      END IF;
    END IF;
  END PROCESS Mix;

  ------------------------------------------------------------------------------
  -- Measured Arcadia console output coupling.
  --
  -- The supplied real-console recording shows a repeatable exponential decay
  -- after each UVI transition: tau ~0.74-0.78 ms.  Updating at hline_pulse and
  -- using a=235/256 gives tau ~0.741 ms on the core's NTSC raster.
  --
  -- Q8 form of: y[n] = a * (y[n-1] + x[n] - x[n-1]).
  -- There is deliberately NO low-pass filter.  H1 has no synthetic
  -- post-disable completion tail; only this coupling state may decay naturally.
  ------------------------------------------------------------------------------
  AnalogCoupling:PROCESS(clk, reset_n) IS
    VARIABLE tmp_q   : integer RANGE -65536 TO 65535;
    VARIABLE new_y_q : integer RANGE -32768 TO 32767;
    VARIABLE out_i   : integer RANGE -127 TO 127;
  BEGIN
    IF reset_n='0' THEN
      hp_y_q    <= 0;
      hp_x_prev <= 0;
      sample    <= to_unsigned(0, 8);

    ELSIF rising_edge(clk) THEN
      IF hline_pulse='1' THEN
        tmp_q := hp_y_q + (raw_pcm - hp_x_prev) * 256;
        new_y_q := (tmp_q * 235) / 256;

        hp_y_q    <= new_y_q;
        hp_x_prev <= raw_pcm;

        out_i := new_y_q / 256;
        IF out_i > 127 THEN
          out_i := 127;
        ELSIF out_i < -127 THEN
          out_i := -127;
        END IF;

        IF out_i < 0 THEN
          sample <= to_unsigned(256 + out_i, 8);
        ELSE
          sample <= to_unsigned(out_i, 8);
        END IF;
      END IF;
    END IF;
  END PROCESS AnalogCoupling;

END ARCHITECTURE rtl;
