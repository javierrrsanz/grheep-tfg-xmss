import sys
import os

input_file = sys.argv[1] if len(sys.argv) > 1 else "sw/applications/bootloader/spiflash.bin"
output_file = sys.argv[2] if len(sys.argv) > 2 else "sw/applications/bootloader/spiflash.hex"

try:
    with open(input_file, "rb") as f_in:
        data = f_in.read()

    with open(output_file, "w") as f_out:
        # Directiva de direccion en Verilog $readmemh: empezar en el byte 0x010000 (64 KB)
        f_out.write("@010000\n")
        for byte in data:
            f_out.write(f"{byte:02x}\n")
            
    print(f"[+] Éxito: {output_file} generado con {len(data)} bytes en offset @010000.")
except FileNotFoundError:
    print(f"[-] Error: No se encuentra {input_file}.")