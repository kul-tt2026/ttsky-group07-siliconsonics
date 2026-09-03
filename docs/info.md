<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The chip drives a 40kHz ultrasonic transducer (drive_a/drive_b) for a short burst, then listens on two PDM microphones. Each mic's PDM stream is correlated against 40kHz sine/cosine reference signals (ref_sig) in 100-sample (25microseconds) windows to produce I/Q values (windowed_iq_demodulator + correlator). When the combined I/Q magnitude on both mics crosses a threshold for at least 5 consecutive windows, the chip accumulates I/Q over that echo window, runs a CORDIC atan2 on each mic's accumulated I/Q to get its phase, and takes the phase difference between the two mics. A lookup table (phase_difference_to_angle) maps that phase difference to a 6-bit angle (some phase-difference ranges are geometrically invalid for a 2-mic array and are flagged as invalid rather than mapped). The window index at which the echo was first detected is reported as echo_window_index, from which target distance can be computed.

## How to test

1. Hold rst_n low (and connect the PCB)
2. Pulse the start_measurement pin to start a measurement
3. Set the mux_sel pin to LO for echo_window_index and HI for the horizontal angle
4. When angle_valid turns HI the output can be read

## Interpreting the output

### Window index
The window index can be used to calculate the distance to the target using the following formula:
distance \[m\] = $\text{window\_index} \cdot 100 / 4\,000\,000 \cdot 343 / 2$

### Output angles
The output_angle provided by the chip can be converted to radians or degrees using the formulas below:

angle \[rad\] = $\text{output\_angle} \cdot 2\pi / 2^6$

angle \[deg\] = $\text{output\_angle} \cdot 360 / 2^6 $

## External hardware

Custom PCB with microphones and a transducer. The design used for testing is available at https://github.com/milllep/TinyTapeout-PCB.

## Notes
- There is an off by one error in the correlator, causing accumulation over only 99 samples, and 1 sample being ignored. 