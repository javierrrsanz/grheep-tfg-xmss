import sys
import os

# Generador de imagen completa de SPI Flash para Bootloader Bi-etapa
# Offset 0x000000: FSBL firmado con rot_key (fsbl_signed.bin)
# Offset 0x010000: APP firmado con app_key (spiflash.bin de la app)

fsbl_signed_path = "sw/applications/fsbl/fsbl_signed.bin"
app_signed_path  = "sw/applications/app_dummy/app_signed.bin"
output_hex_path  = "sw/applications/zsbl/spiflash.hex"

try:
    with open(fsbl_signed_path, "rb") as f:
        fsbl_data = f.read()

    with open(app_signed_path, "rb") as f:
        app_data = f.read()

    print(f"[+] FSBL firmado: {len(fsbl_data)} bytes")
    print(f"[+] App firmada : {len(app_data)} bytes")
    output_bin_path  = "sw/applications/zsbl/spiflash.bin"

    # 1. Generar archivo .hex para simulación (Questasim)
    with open(output_hex_path, "w") as f_out:
        # FSBL en offset @000000
        f_out.write("@000000\n")
        for b in fsbl_data:
            f_out.write(f"{b:02x}\n")

        # APP en offset @010000
        f_out.write("@010000\n")
        for b in app_data:
            f_out.write(f"{b:02x}\n")

    # 2. Generar archivo .bin continuo para la SPI Flash física (FPGA real)
    flash_size = 0x010000 + len(app_data)
    flash_binary = bytearray([0xFF] * flash_size)  # 0xFF = Flash virgen / borrada
    flash_binary[0:len(fsbl_data)] = fsbl_data
    flash_binary[0x010000:0x010000 + len(app_data)] = app_data

    with open(output_bin_path, "wb") as f_bin:
        f_bin.write(flash_binary)

    print(f"[+] Éxito: {output_hex_path} generado correctamente para simulación.")
    print(f"[+] Éxito: {output_bin_path} generado ({len(flash_binary)} bytes) listo para la FPGA física.")

except FileNotFoundError as e:
    print(f"[-] Error: {e}")
