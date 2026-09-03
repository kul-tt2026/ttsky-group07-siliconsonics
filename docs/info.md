<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

Reads the pdm signals of a microphone and times the echo of a 40kHz signal.

## How to test


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