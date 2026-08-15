import math

values = [ math.atan(math.pow(2, -i)) for i in range(8) ]

FRAC_BITS = 7

fixed = [round(x * (1 << FRAC_BITS)) for x in values]

for x in fixed:
    print(f"{x:07b}")