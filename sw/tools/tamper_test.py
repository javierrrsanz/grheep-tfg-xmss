#!/usr/bin/env python3
import sys
import shutil
import os

FLASH_HEX = "sw/applications/zsbl/spiflash.hex"
TARGET_HEX = "hw/vendor/x-heep/sw/build/main.hex"

def restore():
    if not os.path.exists(FLASH_HEX):
        print(f"[-] Error: No se encuentra '{FLASH_HEX}'. Ejecuta primero ./build_secure_boot.sh")
        sys.exit(1)
    shutil.copyfile(FLASH_HEX, TARGET_HEX)
    print(f"[+] '{TARGET_HEX}' restaurado al estado original legítimo y firmado.")

def tamper(mode):
    if not os.path.exists(FLASH_HEX):
        print(f"[-] Error: No se encuentra '{FLASH_HEX}'. Ejecuta primero ./build_secure_boot.sh")
        sys.exit(1)

    with open(FLASH_HEX, 'r') as f:
        lines = f.readlines()

    modified = list(lines)

    # =========================================================================
    # MAPA COMPLETO DE MEMORIA EN spiflash.hex (1 byte por línea):
    #
    # --- ETAPA 0 / FSBL (Offset @000000, Línea 0) ---
    # Línea 0:          @000000
    # Líneas 1..4:      Cabecera longitud total FSBL (4 bytes)
    # Líneas 5..72:     Clave Pública RoTPK (68 bytes) -> ROOT en Líneas 9..40
    # Líneas 73..4840:  Firma XMSS FSBL (4768 bytes)   -> WOTS+ en Líneas 2249..4392
    # Líneas 4841..:    Binario ejecutable FSBL (Payload)
    #
    # --- ETAPA 1 / APP (Offset @010000, Línea 19994) ---
    # Línea 19994:      @010000
    # Líneas 19995..19998: Cabecera longitud total App (4 bytes)
    # Líneas 19999..20066: Clave Pública App (68 bytes) -> ROOT en Líneas 20003..20034
    # Líneas 20067..24834: Firma XMSS App (4768 bytes)  -> WOTS+ en Líneas 22243..24386
    # Líneas 24835..:      Binario ejecutable App (Payload)
    # =========================================================================

    if mode in ["corrupt-fsbl-sig", "corrupt-sig"]:
        idx = 3000  # Cadenas WOTS+ de la firma del FSBL
        original = modified[idx].strip()
        corrupted = "ff\n" if original != "ff" else "00\n"
        print(f"[!] [ETAPA 0] Inyectando fallo en Firma XMSS del FSBL (línea {idx}): {original} -> {corrupted.strip()}")
        modified[idx] = corrupted

    elif mode in ["corrupt-fsbl-payload", "corrupt-payload"]:
        idx = 6000  # Código ejecutable del FSBL (Payload)
        original = modified[idx].strip()
        corrupted = "ff\n" if original != "ff" else "00\n"
        print(f"[!] [ETAPA 0] Inyectando fallo en Payload FSBL (línea {idx}): {original} -> {corrupted.strip()}")
        modified[idx] = corrupted

    elif mode in ["corrupt-fsbl-pk", "corrupt-pk"]:
        idx = 20  # Campo ROOT de la Clave Pública RoTPK
        original = modified[idx].strip()
        corrupted = "ff\n" if original != "ff" else "00\n"
        print(f"[!] [ETAPA 0] Inyectando fallo en Clave RoTPK (línea {idx}): {original} -> {corrupted.strip()}")
        modified[idx] = corrupted

    elif mode == "corrupt-app-sig":
        idx = 23000  # Cadenas WOTS+ de la firma de la App
        original = modified[idx].strip()
        corrupted = "ff\n" if original != "ff" else "00\n"
        print(f"[!] [ETAPA 1] Inyectando fallo en Firma XMSS de la App (línea {idx}): {original} -> {corrupted.strip()}")
        modified[idx] = corrupted

    elif mode == "corrupt-app-pk":
        idx = 20015  # Campo ROOT de la Clave Pública de la App
        original = modified[idx].strip()
        corrupted = "ff\n" if original != "ff" else "00\n"
        print(f"[!] [ETAPA 1] Inyectando fallo en Clave Pública de la App (línea {idx}): {original} -> {corrupted.strip()}")
        modified[idx] = corrupted

    elif mode == "corrupt-app-payload":
        idx = 26000  # Código ejecutable de la App (Payload)
        original = modified[idx].strip()
        corrupted = "ff\n" if original != "ff" else "00\n"
        print(f"[!] [ETAPA 1] Inyectando fallo en Payload de la App (línea {idx}): {original} -> {corrupted.strip()}")
        modified[idx] = corrupted

    else:
        print(f"[-] Modo desconocido: '{mode}'.")
        print("\nOpciones disponibles:")
        print("  [Etapa 0 - ZSBL / ROM]")
        print("    - corrupt-fsbl-sig     : Modifica la firma XMSS del FSBL")
        print("    - corrupt-fsbl-pk      : Modifica la Clave RoTPK del FSBL")
        print("    - corrupt-fsbl-payload : Modifica el código binario del FSBL")
        print("\n  [Etapa 1 - FSBL / SRAM]")
        print("    - corrupt-app-sig      : Modifica la firma XMSS de la App")
        print("    - corrupt-app-pk       : Modifica la Clave Pública de la App")
        print("    - corrupt-app-payload  : Modifica el código binario de la App")
        print("\n  [Restaurar]")
        print("    - restore              : Restaura la imagen legítima original")
        sys.exit(1)

    with open(TARGET_HEX, 'w') as f:
        f.writelines(modified)
    print(f"[+] Imagen alterada guardada en '{TARGET_HEX}'. Listo para simular con 'make questasim-run-opt'.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Uso: python3 sw/tools/tamper_test.py [modo]")
        print("Ejecuta 'python3 sw/tools/tamper_test.py help' para ver la lista completa de opciones.")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "restore":
        restore()
    else:
        tamper(cmd)
