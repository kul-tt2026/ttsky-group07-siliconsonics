![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# SiliconSonics - ultrasonic sonar: range and bearing

A Tiny Tapeout digital sonar processor. It drives a 40 kHz ultrasonic
transducer, demodulates the returning echo from two PDM microphones with
square-wave I/Q correlators, and reports the echo's distance and bearing on
parallel pins and over a 115200 baud UART.

- **Range** from the echo's window index, 0.27 m to about 17 m in 4.3 mm steps.
- **Bearing** from the phase difference between the two microphones, in 5.625
  degree steps. Boards with only one microphone set `single_mic` and get range
  only.
- **Tunable**: the threshold, minimum echo width, blanking window and burst
  length are UART-writable registers, not fixed constants.
- Single-shot, pin-triggered or once-per-second automatic measurement.

See [docs/info.md](docs/info.md) for the pinout, the UART protocol and the
tuning registers.

## External hardware

Custom PCB with the microphones and the transducer:
https://github.com/milllep/TinyTapeout-PCB

## Building and testing

```sh
cd test
make                # RTL simulation
make GATES=yes      # gate-level, after copying in gate_level_netlist.v
```

The GitHub actions build the GDS with LibreLane, run the testbench and publish
the datasheet.

## Resources

- [Tiny Tapeout FAQ](https://tinytapeout.com/faq/)
- [Digital design lessons](https://tinytapeout.com/digital_design/)
- [Join the community](https://tinytapeout.com/discord)
