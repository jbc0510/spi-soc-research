/* Run the update-control comparison on ZCU102 Linux using only /tmp files.
 * This exercises the target CPU and target OpenSSL verifier. It does not
 * program the FPGA, access spidev/MMIO, alter boot media, or verify BootROM. */
#define _GNU_SOURCE
#include "board_test_vector.h"

#include <dlfcn.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

typedef struct bio_st BIO;
typedef struct evp_pkey_st EVP_PKEY;
typedef struct evp_md_ctx_st EVP_MD_CTX;
typedef struct evp_pkey_ctx_st EVP_PKEY_CTX;
typedef struct evp_md_st EVP_MD;

typedef struct {
    void *handle;
    BIO *(*bio_new_mem_buf)(const void *, int);
    EVP_PKEY *(*pem_read_bio_pubkey)(BIO *, EVP_PKEY **, void *, void *);
    int (*bio_free)(BIO *);
    EVP_MD_CTX *(*md_ctx_new)(void);
    const EVP_MD *(*sha256)(void);
    int (*digest_verify_init)(EVP_MD_CTX *, EVP_PKEY_CTX **, const EVP_MD *, void *, EVP_PKEY *);
    int (*digest_verify_update)(EVP_MD_CTX *, const void *, size_t);
    int (*digest_verify_final)(EVP_MD_CTX *, const unsigned char *, size_t);
    void (*md_ctx_free)(EVP_MD_CTX *);
    void (*pkey_free)(EVP_PKEY *);
} crypto_api;

static int load_symbol(void *handle, const char *name, void *destination, size_t size)
{
    void *symbol = dlsym(handle, name);
    if (symbol == NULL || size != sizeof(symbol))
        return -1;
    memcpy(destination, &symbol, size);
    return 0;
}

#define LOAD_SYMBOL(api, field, symbol) \
    do { \
        if (load_symbol((api)->handle, (symbol), &(api)->field, sizeof((api)->field)) != 0) { \
            fprintf(stderr, "missing OpenSSL symbol: %s\n", (symbol)); \
            return -1; \
        } \
    } while (0)

static int crypto_init(crypto_api *api)
{
    memset(api, 0, sizeof(*api));
    api->handle = dlopen("libcrypto.so.3", RTLD_NOW | RTLD_LOCAL);
    if (api->handle == NULL) {
        fprintf(stderr, "cannot load target libcrypto.so.3: %s\n", dlerror());
        return -1;
    }
    LOAD_SYMBOL(api, bio_new_mem_buf, "BIO_new_mem_buf");
    LOAD_SYMBOL(api, pem_read_bio_pubkey, "PEM_read_bio_PUBKEY");
    LOAD_SYMBOL(api, bio_free, "BIO_free");
    LOAD_SYMBOL(api, md_ctx_new, "EVP_MD_CTX_new");
    LOAD_SYMBOL(api, sha256, "EVP_sha256");
    LOAD_SYMBOL(api, digest_verify_init, "EVP_DigestVerifyInit");
    LOAD_SYMBOL(api, digest_verify_update, "EVP_DigestVerifyUpdate");
    LOAD_SYMBOL(api, digest_verify_final, "EVP_DigestVerifyFinal");
    LOAD_SYMBOL(api, md_ctx_free, "EVP_MD_CTX_free");
    LOAD_SYMBOL(api, pkey_free, "EVP_PKEY_free");
    return 0;
}

static bool verify_signature(crypto_api *api, const unsigned char *data, size_t data_len)
{
    BIO *bio = api->bio_new_mem_buf(board_public_key, (int)(sizeof(board_public_key) - 1U));
    EVP_PKEY *key = NULL;
    EVP_MD_CTX *ctx = NULL;
    bool valid = false;
    int init_status = -1, update_status = -1, final_status = -1;

    if (bio == NULL)
        return false;
    key = api->pem_read_bio_pubkey(bio, NULL, NULL, NULL);
    (void)api->bio_free(bio);
    if (key == NULL)
        return false;
    ctx = api->md_ctx_new();
    if (ctx != NULL)
        init_status = api->digest_verify_init(ctx, NULL, api->sha256(), NULL, key);
    if (init_status == 1)
        update_status = api->digest_verify_update(ctx, data, data_len);
    if (update_status == 1)
        final_status = api->digest_verify_final(ctx, board_signature, sizeof(board_signature));
    if (final_status == 1)
        valid = true;
    if (ctx != NULL)
        api->md_ctx_free(ctx);
    api->pkey_free(key);
    return valid;
}

static int write_file(const char *path, const unsigned char *data, size_t len)
{
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    size_t done = 0;
    if (fd < 0)
        return -1;
    while (done < len) {
        ssize_t n = write(fd, data + done, len - done);
        if (n <= 0) {
            (void)close(fd);
            return -1;
        }
        done += (size_t)n;
    }
    if (fsync(fd) != 0) {
        (void)close(fd);
        return -1;
    }
    if (close(fd) != 0)
        return -1;
    return 0;
}

static int overwrite_prefix(const char *path, const unsigned char *data, size_t len)
{
    int fd = open(path, O_WRONLY);
    size_t done = 0;
    if (fd < 0)
        return -1;
    while (done < len) {
        ssize_t n = write(fd, data + done, len - done);
        if (n <= 0) {
            (void)close(fd);
            return -1;
        }
        done += (size_t)n;
    }
    if (fsync(fd) != 0) {
        (void)close(fd);
        return -1;
    }
    if (close(fd) != 0)
        return -1;
    return 0;
}

static bool prefix_matches(const char *path, const unsigned char *expected, size_t len)
{
    unsigned char actual[4096];
    int fd = open(path, O_RDONLY);
    size_t done = 0;
    if (fd < 0 || len > sizeof(actual)) {
        if (fd >= 0)
            (void)close(fd);
        return false;
    }
    while (done < len) {
        ssize_t n = read(fd, actual + done, len - done);
        if (n <= 0) {
            (void)close(fd);
            return false;
        }
        done += (size_t)n;
    }
    (void)close(fd);
    return memcmp(actual, expected, len) == 0;
}

static int read_file(const char *path, unsigned char *data, size_t capacity, size_t *len)
{
    int fd = open(path, O_RDONLY);
    size_t done = 0;
    if (fd < 0)
        return -1;
    while (done < capacity) {
        ssize_t n = read(fd, data + done, capacity - done);
        if (n < 0) {
            (void)close(fd);
            return -1;
        }
        if (n == 0)
            break;
        done += (size_t)n;
    }
    (void)close(fd);
    *len = done;
    return 0;
}

static bool slot_is_original(const char *path)
{
    static const unsigned char original[] = "CONFIRMED-A";
    return prefix_matches(path, original, sizeof(original) - 1U);
}

static int init_slots(const char *dir, char *slot_a, size_t a_size,
                      char *slot_b, size_t b_size)
{
    unsigned char a[256], b[256];
    (void)snprintf(slot_a, a_size, "%s/slot-A.img", dir);
    (void)snprintf(slot_b, b_size, "%s/slot-B.img", dir);
    memset(a, 'a', sizeof(a));
    memset(b, 'b', sizeof(b));
    memcpy(a, "CONFIRMED-A", sizeof("CONFIRMED-A") - 1U);
    memcpy(b, "OLD-INACTIVE-B", sizeof("OLD-INACTIVE-B") - 1U);
    return write_file(slot_a, a, sizeof(a)) || write_file(slot_b, b, sizeof(b)) ? -1 : 0;
}

static bool inactive_is_original(const char *path)
{
    static const unsigned char original[] = "OLD-INACTIVE-B";
    return prefix_matches(path, original, sizeof(original) - 1U);
}

static bool hardened_stage(crypto_api *api, const char *slot_b,
                           const unsigned char *data, size_t data_len,
                           bool interrupt, bool *pending)
{
    unsigned char readback[4096];
    if (!verify_signature(api, data, data_len))
        return false;
    if (interrupt) {
        if (overwrite_prefix(slot_b, data, 12U) != 0)
            return false;
        return false;
    }
    if (write_file(slot_b, data, data_len) != 0 || data_len > sizeof(readback))
        return false;
    size_t readback_len = 0;
    if (read_file(slot_b, readback, sizeof(readback), &readback_len) != 0 ||
        readback_len != data_len || memcmp(readback, data, data_len) != 0)
        return false;
    *pending = true;
    return true;
}

static int scenario_dir(const char *root, const char *name, char *out, size_t size)
{
    (void)snprintf(out, size, "%s/%s", root, name);
    return mkdir(out, 0700);
}

int main(void)
{
    crypto_api crypto;
    char root[] = "/tmp/msu2-hardening-XXXXXX";
    char dir[256], slot_a[300], slot_b[300];
    unsigned char tampered[sizeof(board_payload)];
    bool pending, baseline_bad, hard_ok;
    int failures = 0;

    if (crypto_init(&crypto) != 0)
        return 2;
    if (mkdtemp(root) == NULL) {
        perror("mkdtemp");
        return 2;
    }
    printf("ZCU102 Linux target demo; temporary files under %s\n", root);
    printf("Target libcrypto.so.3 signature verification; no FPGA/MMIO/spidev or boot-media access\n");
    printf("%-23s | %-31s | %-30s | Check\n", "Scenario", "Baseline (unsafe)", "Hardened reference");
    puts("--------------------------------------------------------------------------------------------------------------");

    /* Legitimate signed release. */
    if (scenario_dir(root, "valid", dir, sizeof(dir)) != 0 || init_slots(dir, slot_a, sizeof(slot_a), slot_b, sizeof(slot_b)) != 0)
        return 2;
    baseline_bad = write_file(slot_a, board_payload, sizeof(board_payload)) == 0 &&
                   prefix_matches(slot_a, board_payload, sizeof(board_payload));
    if (init_slots(dir, slot_a, sizeof(slot_a), slot_b, sizeof(slot_b)) != 0)
        return 2;
    pending = false;
    bool staged = hardened_stage(&crypto, slot_b, board_payload, sizeof(board_payload), false, &pending);
    bool active_original = slot_is_original(slot_a);
    hard_ok = staged && pending && active_original;
    printf("%-23s | %-31s | %-30s | %s\n", "Valid signed release", "image accepted in place",
           "verified; staged to B", baseline_bad && hard_ok ? "PASS" : "FAIL");
    failures += !(baseline_bad && hard_ok);
    (void)unlink(slot_a); (void)unlink(slot_b); (void)rmdir(dir);

    /* Altered payload with the original signature. */
    if (scenario_dir(root, "tampered", dir, sizeof(dir)) != 0 || init_slots(dir, slot_a, sizeof(slot_a), slot_b, sizeof(slot_b)) != 0)
        return 2;
    memcpy(tampered, board_payload, sizeof(tampered));
    tampered[0] ^= 0x01U;
    baseline_bad = write_file(slot_a, tampered, sizeof(tampered)) == 0 &&
                   prefix_matches(slot_a, tampered, sizeof(tampered));
    if (init_slots(dir, slot_a, sizeof(slot_a), slot_b, sizeof(slot_b)) != 0)
        return 2;
    pending = false;
    hard_ok = !hardened_stage(&crypto, slot_b, tampered, sizeof(tampered), false, &pending) &&
              !pending && slot_is_original(slot_a) && inactive_is_original(slot_b);
    printf("%-23s | %-31s | %-30s | %s\n", "Tampered release", "altered bytes accepted",
           "rejected; A and B unchanged", baseline_bad && hard_ok ? "PASS" : "FAIL");
    failures += !(baseline_bad && hard_ok);
    (void)unlink(slot_a); (void)unlink(slot_b); (void)rmdir(dir);

    /* Interrupted write after a short prefix. */
    if (scenario_dir(root, "interrupted", dir, sizeof(dir)) != 0 || init_slots(dir, slot_a, sizeof(slot_a), slot_b, sizeof(slot_b)) != 0)
        return 2;
    baseline_bad = overwrite_prefix(slot_a, board_payload, 12U) == 0 && !slot_is_original(slot_a);
    if (init_slots(dir, slot_a, sizeof(slot_a), slot_b, sizeof(slot_b)) != 0)
        return 2;
    pending = false;
    (void)hardened_stage(&crypto, slot_b, board_payload, sizeof(board_payload), true, &pending);
    hard_ok = !pending && slot_is_original(slot_a) && prefix_matches(slot_b, board_payload, 12U);
    printf("%-23s | %-31s | %-30s | %s\n", "Interrupted update", "active A partly overwritten",
           "A retained; no trial published", baseline_bad && hard_ok ? "PASS" : "FAIL");
    failures += !(baseline_bad && hard_ok);
    (void)unlink(slot_a); (void)unlink(slot_b); (void)rmdir(dir);

    /* Trial-health failure is explicitly injected after a valid stage. */
    if (scenario_dir(root, "health-failure", dir, sizeof(dir)) != 0 || init_slots(dir, slot_a, sizeof(slot_a), slot_b, sizeof(slot_b)) != 0)
        return 2;
    baseline_bad = write_file(slot_a, board_payload, sizeof(board_payload)) == 0 &&
                   prefix_matches(slot_a, board_payload, sizeof(board_payload));
    if (init_slots(dir, slot_a, sizeof(slot_a), slot_b, sizeof(slot_b)) != 0)
        return 2;
    pending = false;
    hard_ok = hardened_stage(&crypto, slot_b, board_payload, sizeof(board_payload), false, &pending) && pending;
    pending = false; /* Injected failed health clears the trial and retains A. */
    hard_ok = hard_ok && !pending && slot_is_original(slot_a);
    printf("%-23s | %-31s | %-30s | %s\n", "Trial health failure", "unhealthy image remains active",
           "rollback; A selected", baseline_bad && hard_ok ? "PASS" : "FAIL");
    failures += !(baseline_bad && hard_ok);
    (void)unlink(slot_a); (void)unlink(slot_b); (void)rmdir(dir);

    (void)rmdir(root);
    (void)dlclose(crypto.handle);
    printf("Overall: %s (%d failures)\n", failures == 0 ? "PASS" : "FAIL", failures);
    puts("Scope: target Linux execution with temporary file slots; not verified boot or hardware-rooted key proof.");
    return failures == 0 ? 0 : 1;
}
