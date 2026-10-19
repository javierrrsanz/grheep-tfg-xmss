#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include "params.h"
#include "xmss.h"

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
        printf("Ejemplo: %s app.bin app_signed_sw.bin keys/app_key\n", argv[0]);
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
    if (!m) {
        fprintf(stderr, "Error asignando memoria para el mensaje.\n");
        fclose(file);
        return 1;
    }
    if (fread(m, 1, mlen, file) != mlen) {
        fprintf(stderr, "Error leyendo %s.\n", input_bin);
        fclose(file); free(m); return 1;
    }
    fclose(file);

    printf("\n=======================================================\n");
    printf("[SIGNER SW] Firmando %s (%llu bytes)\n", input_bin, mlen);
    printf("[SIGNER SW] Claves: %s / %s\n", key_sk_path, key_pk_path);
    printf("[SIGNER SW] Formato: RFC 8391 Nativo (Zero-BRAM, 2500B Sig)\n");
    printf("=======================================================\n");

    // 4. Gestionar Claves (Reutilizar si existen, o generar la primera vez)
    size_t pk_size = XMSS_OID_LEN + params.pk_bytes; // 68 bytes
    size_t sk_size = XMSS_OID_LEN + params.sk_bytes; // Clave secreta
    size_t sig_size = params.sig_bytes;              // 2500 bytes
    unsigned char *pk = malloc(pk_size);
    unsigned char *sk = malloc(sk_size);
    unsigned char *sm = malloc(sig_size + mlen);
    unsigned long long smlen = 0;

    if (!pk || !sk || !sm) {
        fprintf(stderr, "Error asignando memoria para claves o firmas.\n");
        free(m); free(pk); free(sk); free(sm);
        return 1;
    }

    FILE *f_sk = fopen(key_sk_path, "rb");
    FILE *f_pk = fopen(key_pk_path, "rb");

    if (f_sk && f_pk) {
        printf("[SIGNER SW] Usando par de claves existente...\n");
        if (fread(sk, 1, sk_size, f_sk) != sk_size || fread(pk, 1, pk_size, f_pk) != pk_size) {
            fprintf(stderr, "Error leyendo archivos de claves existentes.\n");
            fclose(f_sk); fclose(f_pk); free(m); free(pk); free(sk); free(sm);
            return 1;
        }
        fclose(f_sk); fclose(f_pk);
    } else {
        printf("[SIGNER SW] Claves no encontradas. Generando NUEVO par de claves XMSS...\n");
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
        printf("[SIGNER SW] Claves guardadas en %s y %s.\n", key_sk_path, key_pk_path);
    }

    // 5. Firmar el binario
    printf("[SIGNER SW] Calculando firma matematica XMSS...\n");
    if (xmss_sign(sk, sm, &smlen, m, mlen) != 0) {
        fprintf(stderr, "Error durante xmss_sign!\n");
        free(m); free(pk); free(sk); free(sm);
        return 1;
    }

    // Actualizar la clave privada con el índice incrementado
    f_sk = fopen(key_sk_path, "wb");
    if (f_sk) {
        fwrite(sk, 1, sk_size, f_sk);
        fclose(f_sk);
    }

    // 6. Verificación de control inmediata en host
    printf("[SIGNER SW] Verificando firma generada...\n");
    unsigned char *verify_m = malloc(sig_size + mlen);
    unsigned long long verify_mlen = 0;
    if (xmss_sign_open(verify_m, &verify_mlen, sm, smlen, pk) != 0 ||
        verify_mlen != mlen || memcmp(verify_m, m, mlen) != 0) {
        fprintf(stderr, "[ERROR CRITICO] La firma generada fallo la verificacion matematica de control!\n");
        free(verify_m); free(m); free(pk); free(sk); free(sm);
        return 1;
    }
    free(verify_m);
    printf("[SIGNER SW] Verificacion matematica de control: OK (Valida 100%%).\n");

    // 7. Generar el contenedor para la Flash en formato Nativo Software
    // Estructura:
    // [4B Total Size] || [68B PK] || [2500B Native RFC 8391 Sig] || [mlen Payload]
    FILE *bin_out = fopen(output_bin, "wb");
    if (!bin_out) {
        fprintf(stderr, "Error creando %s\n", output_bin);
        free(m); free(pk); free(sk); free(sm);
        return 1;
    }

    // Cabecera: tamaño total de (PK + Firma RFC 8391 + Payload)
    uint32_t firmware_total_size = (uint32_t)(pk_size + sig_size + mlen);
    fwrite(&firmware_total_size, sizeof(uint32_t), 1, bin_out);

    // 1º: Clave Pública (68 bytes)
    fwrite(pk, 1, pk_size, bin_out);

    // 2º: Firma en formato RFC 8391 nativo (2500 bytes, sin padding BRAM)
    fwrite(sm, 1, sig_size, bin_out);

    // 3º: Payload de la app / FSBL (mlen bytes)
    fwrite(m, 1, mlen, bin_out);

    fclose(bin_out);

    printf("[SIGNER SW] Exito: Contenedor firmado generado en '%s'.\n", output_bin);
    printf("            - Cabecera      : 4 bytes\n");
    printf("            - Clave Publica : %zu bytes\n", pk_size);
    printf("            - Firma Nativa  : %zu bytes (RFC 8391 puro)\n", sig_size);
    printf("            - Payload       : %llu bytes\n", mlen);
    printf("            - Tamano Total  : %u bytes (Ahorro de 2268B vs HW BRAM)\n", firmware_total_size);
    printf("=======================================================\n\n");

    free(pk); free(sk); free(sm); free(m);
    return 0;
}
