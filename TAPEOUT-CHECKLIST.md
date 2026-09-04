# Tapeout checklist — `cleanup` branch

State after `78d9bc4`. Everything below was measured, not assumed.

## What was wrong and is now fixed

| | Symptom it caused | Fix |
|---|---|---|
| Bearing sign inverted | Objects reported on the wrong side | `atan2(I, Q)`, not `atan2(Q, I)` |
| No single-microphone mode | A one-mic board detects nothing at all | `single_mic` on `ui[6]` |
| Detect lines merged | `D054 9D063 ED7 1D094 00` in the demo video | Snapshot window/angle when the line starts |
| Accumulators not cleared on a new ping | Stale I/Q and stale window on the next measurement | Reset from any state |
| Forward-referenced nets | Would not build with Icarus 14 | Declare before use |
| Detection constants hardcoded | A quieter or noisier board can never detect | UART tuning registers |
| TX FIFO over-push | One byte silently dropped | Only decide when no push is in flight |
| No synchronisers on mic/restart | Rare unexplainable behaviour on silicon | Two-flop synchronisers |
| Stretched mic clock at mode switch | Possible mic upset at the 2→4 MHz change | Compare with `>=` |
| Gate-level covered only the clock divider | Netlist essentially unverified | `chip_pins_test` runs in GL |

## Verified

- **All 8 tests pass** on the final RTL: `angle_module_test`, `atan2_cordic`,
  `config_test` (×2), `chip_pins_test`, `uart_test` (×2),
  `mic_us_power_sequence`.
- **Bearing checked against ground truth**, not against a copy of the RTL:
  the synthetic target at +15° reads +16.9° (was −16.9°).
- **Verilator lint clean** (the linter LibreLane runs with `RUN_LINTER: 1`).
- **Yosys synthesis clean**, 0 problems, no inferred latches.
- **Area measured against the real sky130 liberty** from your own GDS run:
  43890 µm² vs 41919 µm² for `a287a44`, i.e. **+4.7 %**. Your last hardened run
  sat at 73 % utilisation, so this lands near 76 % — above the placer's 60 %
  target, exactly as before, and still well inside the 2×2 tile.
- `info.yaml` `source_files`, `test/Makefile` `PROJECT_SOURCES` and `src/*.v`
  all agree.

## Tuning registers (the point of the exercise)

Over UART, `Cnvv` writes register `n` with hex value `vv`, `V` reads them all
back. `rst_n` restores the defaults, so no setting can brick the chip.

| n | register | default | turn it up when | turn it down when |
|---|---|---|---|---|
| 0 | threshold | `07` | noise is triggering detections | nothing is detected |
| 1 | min_width | `05` | short noise bursts get through | real echoes are too short |
| 2 | blank | `40` (64 windows) | the ringdown is reported as a target | you need to see closer than 0.27 m |
| 3 | ping | `10` (16 half periods) | you need more range | you need a shorter ringdown |

`V` replies `Vttmmbbpp\n`. The video showed detections at window `040` — exactly
the blanking edge — so `C0nn` (higher threshold) and `C2nn` (longer blank) are
the first two things to try on the bench.

## Before you submit

1. **Push the branch and check the `gds` action is green** — that is the one
   thing I cannot run here. Watch the `gds` and `precheck` jobs.
   If global placement fails with `GPL-0302`, raise `PL_TARGET_DENSITY_PCT` in
   `src/config.json` from 60 to 75; that is the documented remedy and the file's
   own comment says values up to 80 are known to work.
2. **Merge `cleanup` into `main`.** I tested the merge: no conflicts, and the
   result is byte-identical to `cleanup`.

## Two judgement calls left, both yours

- **Measure the real microphone spacing.** `SENSOR_DISTANCE = 0.003` in
  `python_scripts/phase_to_angle_table.py` generates the angle table and is
  fixed in silicon. On your own synthetic data the reported 16.9° against a true
  15° is consistent with the real spacing being a little larger than 3 mm. If
  you measure it and regenerate the table, the bearing is calibrated; if not,
  the host can rescale in software, because the error is a pure scale factor.
- **The `gang` and `gang-ventilator-1m` captures still contain no detectable
  echo** (10 of 27 real captures). With tunable thresholds you can now find out
  on the bench whether that was the threshold or the recording.

## Notes for the FPGA

You are on a Zybo Z7-10 via Vivado, not the iCE40 the `fpga.yaml` workflow
targets, so the 40 MHz clock is not a problem there. Set `ui_in[6]` high while
you have one microphone: you will get correct ranges with the bearing reading 0.
Everything scales with the clock, including the UART baud (`clk / 347`), so
clocking the chip slower makes the UART easier to bit-bang during bring-up.
