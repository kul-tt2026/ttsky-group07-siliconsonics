<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

Reads the pdm signals of a microphone and times the echo of a 40kHz signal.

## How to test

Power the transducer for 8 cycles simultaniously with a HI signal to the "restart" pin. When echo_found turns HI the "window index" can be read and transformed into a distance using: window_index * 100 / 4,000,000 * 343 / 2 = distance \[m\]

## External hardware

Custom PCB with microphones and a transducer.
