#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include "params.h"
#include "xmss.h"

// Definiciones de hardware VHDL para GR-HEEP
#define BLOCK_BYTES 32
#define BRAM_XMSS_SIG_WOTS 68
#define BRAM_XMSS_SIG_AUTH 135
#define BRAM_XMSS_SIG      145
#define HW_SIG_BLOCKS      149 

void randombytes(unsigned char *out, unsigned long long outlen) {
    FILE *f = fopen("/dev/urandom", "rb");
    if (!f) {
        fprintf(stderr, "Error opening /dev/urandom\n");
        exit(1);
    }
    if (fread(out, 1, outlen, f) != outlen) {
        fprintf(stderr, "Error reading /dev/urandom\n");
        fclose(f);
        exit(1);
    }
    fclose(f);
} 

int main(int argc, char *argv[]) {
    // 1. Validar argumentos
    if (argc < 4) {
        printf("Uso: %s <binario_entrada> <binario_salida> <prefijo_claves>\n", argv[0]);
        printf("Ejemplo: %s app.bin spiflash.bin keys/app_key\n", argv[0]);
        return 1;
    }

    const char *input_bin = argv[1];
    const char *output_bin = argv[2];
    const char *key_prefix = argv[3];

    char key_sk_path[256];
    char key_pk_path[256];
    snprintf(key_sk_path, sizeof(key_sk_path), "%s.sk", key_prefix);
    snprintf(key_pk_path, sizeof(key_pk_path), "%s.pk", key_prefix);

    // 2. Inicializar parámetros XMSS
    uint32_t oid;
    xmss_params params;
    if (xmss_str_to_oid(&oid, "XMSS-SHA2_10_256") != 0) {
        fprintf(stderr, "Error: OID invalido para XMSS-SHA2_10_256.\n");
        return 1;
    }
    xmss_parse_oid(&params, oid);

    // 3. Leer el binario a firmar
    FILE *file = fopen(input_bin, "rb");
    if (!file) {
        fprintf(stderr, "Error: No se pudo abrir %s.\n", input_bin);
        return 1;
    }

    fseek(file, 0, SEEK_END);
    unsigned long long mlen = ftell(file);
    fseek(file, 0, SEEK_SET);

    unsigned char *m = malloc(mlen);
    if(fread(m, 1, mlen, file) != mlen) {
        fprintf(stderr, "Error leyendo %s.\n", input_bin);
        fclose(file); free(m); return 1;
    }
    fclose(file);

    printf("\n=======================================================\n");
    printf("[SIGNER] Firmando %s (%llu bytes)\n", input_bin, mlen);
    printf("[SIGNER] Claves: %s / %s\n", key_sk_path, key_pk_path);
    printf("=======================================================\n");

    // 4. Gestionar Claves (Reutilizar si existen, o generar la primera vez)
    size_t pk_size = XMSS_OID_LEN + params.pk_bytes; // 68 bytes
    size_t sk_size = XMSS_OID_LEN + params.sk_bytes; // Clave secreta
    unsigned char *pk = malloc(pk_size);
    unsigned char *sk = malloc(sk_size);
    unsigned char *sm = malloc(params.sig_bytes + mlen);
    unsigned long long smlen;

    FILE *f_sk = fopen(key_sk_path, "rb");
    FILE *f_pk = fopen(key_pk_path, "rb");

    if (f_sk && f_pk) {
        printf("[SIGNER] Usando par de claves existente...\n");
        if (fread(sk, 1, sk_size, f_sk) != sk_size || fread(pk, 1, pk_size, f_pk) != pk_size) {
            fprintf(stderr, "Error leyendo archivos de claves existentes.\n");
            fclose(f_sk); fclose(f_pk); free(m); free(pk); free(sk); free(sm);
            return 1;
        }
        fclose(f_sk); fclose(f_pk);
    } else {
        printf("[SIGNER] Claves no encontradas. Generando NUEVO par de claves XMSS...\n");
        xmss_keypair(pk, sk, oid);
        
        f_sk = fopen(key_sk_path, "wb");
        f_pk = fopen(key_pk_path, "wb");
        if (!f_sk || !f_pk) {
            fprintf(stderr, "Error guardando claves en %s o %s. ¿Existe el directorio?\n", key_sk_path, key_pk_path);
            free(m); free(pk); free(sk); free(sm);
            return 1;
        }
        fwrite(sk, 1, sk_size, f_sk);
        fwrite(pk, 1, pk_size, f_pk);
        fclose(f_sk); fclose(f_pk);
        printf("[SIGNER] Claves guardadas en %s y %s.\n", key_sk_path, key_pk_path);
    }
    
    // 5. Firmar el binario
    printf("[SIGNER] Calculando firma matematica XMSS...\n");
    xmss_sign(sk, sm, &smlen, m, mlen);

    // Guardar la clave privada con el índice actualizado
    f_sk = fopen(key_sk_path, "wb");
    if (f_sk) {
        fwrite(sk, 1, sk_size, f_sk);
        fclose(f_sk);
    }

    // 6. Preparar la estructura Hardware Ready (4768 bytes)
    size_t hw_sig_size = HW_SIG_BLOCKS * BLOCK_BYTES;
    unsigned char *hw_ready_signature = malloc(hw_sig_size);
    memset(hw_ready_signature, 0, hw_sig_size);

    memcpy(&hw_ready_signature[BRAM_XMSS_SIG_WOTS * BLOCK_BYTES], sm + 36, params.wots_len * params.n);
    memcpy(&hw_ready_signature[BRAM_XMSS_SIG_AUTH * BLOCK_BYTES], sm + 4 + params.n + (params.wots_len * params.n), params.full_height * params.n);
    memcpy(&hw_ready_signature[BRAM_XMSS_SIG * BLOCK_BYTES + 28], sm, 4); // Index
    memcpy(&hw_ready_signature[(BRAM_XMSS_SIG + 1) * BLOCK_BYTES], sm + 4, params.n); // Randomness

    // 7. Generar el contenedor para la Flash
    FILE *bin_out = fopen(output_bin, "wb");
    if (!bin_out) {
        fprintf(stderr, "Error creando %s\n", output_bin);
        free(m); free(pk); free(sk); free(sm); free(hw_ready_signature);
        return 1;
    }
    
    // Cabecera (4 bytes tamaño total de: PK + Firma HW + Payload)
    uint32_t firmware_total_size = pk_size + hw_sig_size + mlen;
    fwrite(&firmware_total_size, sizeof(uint32_t), 1, bin_out);

    // 1º: Clave Pública (68 bytes)
    fwrite(pk, 1, pk_size, bin_out);
    
    // 2º: Firma con formato hardware (4768 bytes)
    fwrite(hw_ready_signature, 1, hw_sig_size, bin_out);
    
    // 3º: Payload de la app
    fwrite(m, 1, mlen, bin_out);
    
    fclose(bin_out);
    
    printf("[SIGNER] Exito: Contenedor firmado generado en '%s'.\n", output_bin);
    printf("         - Cabecera: 4 bytes\n");
    printf("         - Clave Publica: %zu bytes\n", pk_size);
    printf("         - Firma HW: %zu bytes\n", hw_sig_size);
    printf("         - Payload: %llu bytes\n", mlen);
    printf("         - Tamaño Total Contenedor: %u bytes\n", firmware_total_size);
    printf("=======================================================\n\n");

    free(pk); free(sk); free(sm); free(m); free(hw_ready_signature);
    return 0;
}
