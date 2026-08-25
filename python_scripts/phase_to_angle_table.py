import numpy as np

# 64 -> 6 bits
BITS = 6
WAVE_SPEED = 343
FREQUENCY = 40_000
SENSOR_DISTANCE = 0.003

def calculate_angle(twelve_bit_phase: int) -> int:
    if twelve_bit_phase >= 2048:
        signed_phase = twelve_bit_phase - 4096
    else:
        signed_phase = twelve_bit_phase

    phase = signed_phase * 2 * np.pi / (2**12)
    
    x = phase * WAVE_SPEED / (2 * np.pi * FREQUENCY * SENSOR_DISTANCE)

    if x > 1:
        return None
    if x < -1:
        return None
    
    angle = np.arcsin(x)

    return round(angle / (2*np.pi) * (2 ** BITS)) % 64

for i in range(np.power(2, BITS)):
    val = calculate_angle(i * (2**6))
    if val == None:
        continue
    print(f'6\'d{i}: angle_out = 6\'d{val};')

#print(calculate_angle(200))