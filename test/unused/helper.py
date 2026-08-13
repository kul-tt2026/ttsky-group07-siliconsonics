from pathlib import Path
import numpy as np

def load_pdm_data(file_path):
    """
    Reads a PDM file and extracts the bits for mic1 
    (and optionally other microphones) per time step.
    
    Args:
        file_path (str or Path): The path to the .pdm file.
        
    Returns:
        int: The combined PDM bits for mic as an integer.
    """
    pdm_path = Path(file_path)
    with open(pdm_path, "rb") as f:
        pdm_data = f.read()

    mic1 = []
    # mic4 = []
    # mic5 = []

    for time_step, byte_value in enumerate(pdm_data):
        # Limit the loop by 25000 steps
        if time_step >= 25000:
            break
            
        mic_values = [(byte_value >> i) & 1 for i in range(7)]
        mic1.append(mic_values[0])
        # mic4.append(mic_values[3])
        # mic5.append(mic_values[4])

    # Convert the list of individual bits
    echo_pattern = 0
    for bit in mic1:
        echo_pattern = (echo_pattern << 1) | int(bit)

    return echo_pattern

#print(load_pdm_data("captured_data.pdm"))