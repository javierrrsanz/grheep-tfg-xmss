#!/bin/bash
set -e

TARGET=${1:-sim}

echo "=============================================="
echo "0. Limpiando compilaciones previas (TARGET=${TARGET})"
echo "=============================================="
make clean

echo ""
echo "=============================================="
echo "1. Recompilando Herramienta de Firma (Signer)"
echo "=============================================="
gcc -O2 -Isw/applications/xmss_test_sw sw/tools/signer.c sw/applications/xmss_test_sw/xmss.c sw/applications/xmss_test_sw/params.c sw/applications/xmss_test_sw/hash.c sw/applications/xmss_test_sw/sha256.c sw/applications/xmss_test_sw/hash_address.c sw/applications/xmss_test_sw/wots.c sw/applications/xmss_test_sw/xmss_commons.c sw/applications/xmss_test_sw/xmss_core.c sw/applications/xmss_test_sw/utils.c -o sw/tools/signer

echo ""
echo "=============================================="
echo "2. Compilando FSBL (Etapa 1 - TARGET=${TARGET})"
echo "=============================================="
make -C hw/vendor/x-heep/sw clean
make app PROJECT=fsbl TARGET=$TARGET
cp hw/vendor/x-heep/sw/build/main.bin sw/applications/fsbl/fsbl.bin

echo ""
echo "=============================================="
echo "3. Compilando App (Etapa 2 - TARGET=${TARGET})"
echo "=============================================="
make -C hw/vendor/x-heep/sw clean
make app PROJECT=app_dummy TARGET=$TARGET
cp hw/vendor/x-heep/sw/build/main.bin sw/applications/app_dummy/app.bin

echo ""
echo "=============================================="
echo "4. Preparando Claves y Firmando Binarios"
echo "=============================================="

# Firmar FSBL
sw/tools/signer sw/applications/fsbl/fsbl.bin sw/applications/fsbl/fsbl_signed.bin sw/tools/keys/rot_key


# Firmar APP
sw/tools/signer sw/applications/app_dummy/app.bin sw/applications/app_dummy/app_signed.bin sw/tools/keys/app_key

echo ""
echo "=============================================="
echo "5. Generando Imágenes SPI Flash (.hex y .bin)"
echo "=============================================="
python3 sw/tools/combine_flash.py

echo ""
echo "=============================================="
echo "6. Compilando ZSBL (Boot ROM en Ensamblador)"
echo "=============================================="
make -C hw/vendor/x-heep/hw/ip/boot_rom clean
make -C hw/vendor/x-heep/hw/ip/boot_rom
cp sw/applications/zsbl/spiflash.hex hw/vendor/x-heep/sw/build/main.hex

echo ""
echo "=============================================="
echo "7. Comprobando spiflash.hex y spiflash.bin"
echo "=============================================="
ls -la sw/applications/zsbl/spiflash.hex
ls -la sw/applications/zsbl/spiflash.bin

echo "TODO LISTO PARA SIMULACIÓN Y FPGA FÍSICA!"
