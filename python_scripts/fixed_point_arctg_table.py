import math

BITS = 12

rad_per_bit = 2 * math.pi/ (2**BITS)

values = [ math.atan(math.pow(2, -i)) for i in range(8) ]

adjusted = [ round(x / rad_per_bit) for x in values ]

#FRAC_BITS = 7

#fixed = [round(x * (1 << FRAC_BITS)) for x in values]

print(values)
print(adjusted)

for i in range(len(adjusted)):
    print(f"angle_table[{i}] = {BITS}'b{adjusted[i]:012b};")

for i in range(len(adjusted)):
    print(f"angle_table[{i}] = {BITS}'d{adjusted[i]};")