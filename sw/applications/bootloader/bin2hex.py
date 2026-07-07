import sys
import os

input_file = "secure_firmware.bin"
output_file = "spiflash.hex"

try:
    with open(input_file, "rb") as f_in, open(output_file, "w") as f_out:
        data = f_in.read()
        # Le decimos al simulador que empiece a escribir en la direccion 0 de la Flash
        f_out.write("@000000\n") 
        for byte in data:
            f_out.write(f"{byte:02X}\n") # Escribe un byte en Hexadecimal por línea
            
    print(f"[+] Éxito: {output_file} generado con {len(data)} bytes.")
except FileNotFoundError:
    print(f"[-] Error: No se encuentra {input_file}. Ejecuta el empaquetador en C primero.")