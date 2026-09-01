# Guía de Flujo de Secure Boot (X-HEEP)

Este documento describe el flujo de comandos necesario para compilar, firmar y simular el arranque seguro (Secure Boot) en el SoC X-HEEP, usando esquemas criptográficos XMSS.

## Opción A: Flujo Automatizado (Recomendado)

Si dispones del script `build_secure_boot.sh`, puedes automatizar todo el proceso.

**1. Compilar C, firmar y generar imágenes**
Este script compila la herramienta de firmas, el software de ZSBL, FSBL y la App, genera las firmas y monta la memoria SPI Flash y la ROM.
```bash
./build_secure_boot.sh
```

**2. Recompilar el hardware y Boot ROM en el simulador**
Es **obligatorio** reconstruir el simulador si el archivo `boot_rom.sv` ha cambiado (lo cual ocurre al recompilar ZSBL), o si has modificado código VHDL/SystemVerilog.
```bash
make questasim-build-opt
```

**3. Ejecutar la simulación**
Lanza Questasim para simular todo el proceso desde el ZSBL.
```bash
make questasim-run-app PROJECT=zsbl
```

---

## Opción B: Flujo Manual (Paso a paso)

Si necesitas depurar paso a paso sin usar el script automatizado, sigue estrictamente este orden:

**1. Compilar la herramienta de firmas (Signer)**
*(Solo necesario si modificas `signer.c` o las librerías `xmss.c`)*
```bash
gcc -O2 -Isw/applications/xmss_test_sw sw/tools/signer.c \
  sw/applications/xmss_test_sw/xmss.c \
  sw/applications/xmss_test_sw/params.c \
  sw/applications/xmss_test_sw/hash.c \
  sw/applications/xmss_test_sw/sha256.c \
  sw/applications/xmss_test_sw/hash_address.c \
  sw/applications/xmss_test_sw/wots.c \
  sw/applications/xmss_test_sw/xmss_commons.c \
  sw/applications/xmss_test_sw/xmss_core.c \
  sw/applications/xmss_test_sw/utils.c \
  -o sw/tools/signer
```

**2. Compilar el FSBL (Software Etapa 1)**
```bash
make -C hw/vendor/x-heep/sw clean
make app PROJECT=fsbl
cp hw/vendor/x-heep/sw/build/main.bin sw/applications/fsbl/fsbl.bin
```

**3. Compilar la Aplicación de Usuario (Software Etapa 2)**
```bash
make -C hw/vendor/x-heep/sw clean
make app PROJECT=app_dummy
cp hw/vendor/x-heep/sw/build/main.bin sw/applications/app_dummy/app.bin
```

**4. Firmar los binarios criptográficamente**
Generará los binarios firmados `_signed.bin` y avanzará internamente el índice de las claves secretas `.sk`.
```bash
sw/tools/signer sw/applications/fsbl/fsbl.bin sw/applications/fsbl/fsbl_signed.bin sw/tools/keys/rot_key
sw/tools/signer sw/applications/app_dummy/app.bin sw/applications/app_dummy/app_signed.bin sw/tools/keys/app_key
```

**5. Generar la imagen de memoria externa (SPI Flash)**
Embalará el FSBL firmado y la App firmada en un único archivo `spiflash.hex` según el mapa de memoria definido en el script en Python.
```bash
python3 sw/tools/combine_flash.py
```

**6. Compilar el ZSBL e inyectarlo en el Boot ROM**
```bash
make -C hw/vendor/x-heep/sw clean
make app PROJECT=zsbl
make -C hw/vendor/x-heep/hw/ip/boot_rom
```

**7. Reconstruir la base de datos de simulación**
Vital para que el simulador detecte que se ha inyectado un nuevo Boot ROM en el paso anterior, o detecte cambios en tus módulos VHDL/SV.
```bash
make -C hw/vendor/x-heep questasim-build-opt
```

**8. Ejecutar Questasim**
```bash
make questasim-run-app PROJECT=zsbl
```
