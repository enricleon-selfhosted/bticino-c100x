#include "zip.h"
#include "blockdev.h"

#include "miniz.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHUNK (256 * 1024)

#define FAIL(msg) do { fprintf(stderr, "fwz: zip: %s\n", (msg)); goto done; } while (0)

#define SIG_LOCAL   0x04034b50u
#define SIG_CENTRAL 0x02014b50u
#define SIG_END     0x06054b50u

static uint32_t crc_tab[256];
static int crc_tab_ready;

static void crc_tab_init(void)
{
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320u ^ (c >> 1)) : (c >> 1);
        crc_tab[i] = c;
    }
    crc_tab_ready = 1;
}

static uint32_t crc_step(uint32_t c, uint8_t b) { return (c >> 8) ^ crc_tab[(c ^ b) & 0xff]; }

static void key_update(uint32_t k[3], uint8_t c)
{
    k[0] = crc_step(k[0], c);
    k[1] = (k[1] + (k[0] & 0xff)) * 134775813u + 1u;
    k[2] = crc_step(k[2], (uint8_t)(k[1] >> 24));
}

static void key_init(uint32_t k[3], const char *pw)
{
    if (!crc_tab_ready) crc_tab_init();
    k[0] = 0x12345678u; k[1] = 0x23456789u; k[2] = 0x34567890u;
    for (const char *p = pw; *p; p++) key_update(k, (uint8_t)*p);
}

static uint8_t key_stream(uint32_t k[3])
{
    uint32_t t = ((k[2] & 0xffffu) | 2u);
    return (uint8_t)(((t * (t ^ 1u)) >> 8) & 0xff);
}

static uint8_t decrypt_byte(uint32_t k[3], uint8_t c)
{
    c ^= key_stream(k);
    key_update(k, c);
    return c;
}

static uint8_t encrypt_byte(uint32_t k[3], uint8_t c)
{
    uint8_t t = key_stream(k);
    key_update(k, c);
    return (uint8_t)(c ^ t);
}

static uint32_t rd32(const unsigned char *p) { return p[0] | (p[1]<<8) | ((uint32_t)p[2]<<16) | ((uint32_t)p[3]<<24); }
static uint16_t rd16(const unsigned char *p) { return (uint16_t)(p[0] | (p[1]<<8)); }
static void wr32(unsigned char *p, uint32_t v) { p[0]=(unsigned char)v; p[1]=(unsigned char)(v>>8); p[2]=(unsigned char)(v>>16); p[3]=(unsigned char)(v>>24); }
static void wr16(unsigned char *p, uint16_t v) { p[0]=(unsigned char)v; p[1]=(unsigned char)(v>>8); }

static int find_end_record(FILE *f, long *cd_offset, int *count)
{
    if (fwz_fseek_end(f) != 0) return -1;
    int64_t size = fwz_ftell64(f);
    int64_t back = size < 66000 ? size : 66000;
    unsigned char *buf = malloc((size_t)back);
    if (!buf) return -1;
    if (fwz_fseek64(f, size - back) != 0 || fread(buf, 1, (size_t)back, f) != (size_t)back) {
        free(buf); return -1;
    }
    for (int64_t i = back - 22; i >= 0; i--) {
        if (rd32(buf + i) == SIG_END) {
            *count     = rd16(buf + i + 10);
            *cd_offset = (long)rd32(buf + i + 16);
            free(buf);
            return 0;
        }
    }
    free(buf);
    return -1;
}

int zip_extract(const char *zip_path, const char *password, const char *dir, zip_listing *out)
{
    FILE *f = fopen(zip_path, "rb");
    if (!f) { perror(zip_path); return -1; }

    long cd; int count;
    if (find_end_record(f, &cd, &count) != 0) {
        fprintf(stderr, "fwz: zip: no directory at the end -- is this a zip file?\n");
        fclose(f); return -1;
    }
    if (count > ZIP_MAX_ENTRIES) count = ZIP_MAX_ENTRIES;
    out->count = 0;

    int rc = -1;
    unsigned char *ibuf = malloc(CHUNK), *obuf = malloc(CHUNK);
    if (!ibuf || !obuf) FAIL("out of memory");

    for (int i = 0; i < count; i++) {
        unsigned char h[46];
        if (fwz_fseek64(f, cd) != 0 || fread(h, 1, 46, f) != 46) FAIL("directory ends early");
        if (rd32(h) != SIG_CENTRAL) FAIL("directory entry is not where it should be");

        uint16_t flags   = rd16(h + 8);
        uint16_t method  = rd16(h + 10);
        uint32_t csize   = rd32(h + 20);
        uint16_t namelen = rd16(h + 28);
        uint32_t lho     = rd32(h + 42);

        char name[256];
        size_t n = namelen < sizeof name - 1 ? namelen : sizeof name - 1;
        if (fread(name, 1, n, f) != n) FAIL("cannot read an entry name");
        name[n] = '\0';
        cd += 46 + namelen + rd16(h + 30) + rd16(h + 32);

        unsigned char lh[30];
        if (fwz_fseek64(f, lho) != 0 || fread(lh, 1, 30, f) != 30) FAIL("cannot reach an entry");
        if (rd32(lh) != SIG_LOCAL) FAIL("an entry header is missing");
        if (fwz_fseek64(f, lho + 30 + rd16(lh + 26) + rd16(lh + 28)) != 0) FAIL("cannot skip an entry header");

        uint32_t remaining = csize;
        uint32_t keys[3];
        int encrypted = (flags & 1) != 0;
        if (encrypted) {
            key_init(keys, password);
            unsigned char eh[12];
            if (fread(eh, 1, 12, f) != 12) FAIL("entry too short to be encrypted");
            for (int j = 0; j < 12; j++) eh[j] = decrypt_byte(keys, eh[j]);
            remaining -= 12;
            unsigned char want = (flags & 8) ? (unsigned char)(rd16(h + 12) >> 8)
                                             : (unsigned char)(rd32(h + 16) >> 24);
            if (eh[11] != want) {
                fprintf(stderr, "fwz: wrong password for %s\n", name);
                goto done;
            }
        }

        char path[512];
        snprintf(path, sizeof path, "%s/%s", dir, name);
        FILE *o = fopen(path, "wb");
        if (!o) { fprintf(stderr, "fwz: zip: cannot write %s\n", path); goto done; }

        mz_stream s;
        memset(&s, 0, sizeof s);
        int inflating = (method == 8);
        if (inflating && mz_inflateInit2(&s, -MZ_DEFAULT_WINDOW_BITS) != MZ_OK) {
            fprintf(stderr, "fwz: zip: cannot start decompressing %s\n", name); fclose(o); goto done; }

        while (remaining) {
            size_t want = remaining < CHUNK ? remaining : CHUNK;
            size_t got = fread(ibuf, 1, want, f);
            if (got != want) {
                fprintf(stderr, "fwz: zip: %s ends early -- the file is truncated\n", name);
                if (inflating) mz_inflateEnd(&s); fclose(o); goto done; }
            remaining -= (uint32_t)got;
            if (encrypted) for (size_t j = 0; j < got; j++) ibuf[j] = decrypt_byte(keys, ibuf[j]);

            if (!inflating) {
                if (fwrite(ibuf, 1, got, o) != got) {
                    fprintf(stderr, "fwz: cannot write -- is the disk full?\n"); fclose(o); goto done; }
                continue;
            }
            s.next_in = ibuf; s.avail_in = (unsigned)got;
            for (;;) {
                unsigned before = s.avail_in;
                s.next_out = obuf; s.avail_out = CHUNK;
                int r = mz_inflate(&s, MZ_NO_FLUSH);
                if (r != MZ_OK && r != MZ_STREAM_END && r != MZ_BUF_ERROR) {
                    fprintf(stderr, "fwz: zip: %s does not decompress (%d). Wrong password, "
                                    "or the file is damaged\n", name, r);
                    mz_inflateEnd(&s); fclose(o); goto done;
                }
                size_t have = CHUNK - s.avail_out;
                if (have && fwrite(obuf, 1, have, o) != have) {
                    fprintf(stderr, "fwz: cannot write -- is the disk full?\n");
                    mz_inflateEnd(&s); fclose(o); goto done; }
                if (r == MZ_STREAM_END) { remaining = 0; break; }
                if (s.avail_in == 0) break;
                if (s.avail_in == before && have == 0) break;
            }
        }
        if (inflating) mz_inflateEnd(&s);
        if (fclose(o) != 0) { fprintf(stderr, "fwz: cannot finish writing %s\n", name); goto done; }

        snprintf(out->names[out->count], sizeof out->names[0], "%s", name);
        out->count++;
    }
    rc = 0;

done:
    free(ibuf); free(obuf);
    fclose(f);
    return rc;
}

typedef struct { uint32_t crc, csize, usize, offset; char name[256]; } written;

static int add_one(FILE *z, const char *dir, const char *name, const char *password,
                   written *rec, int level)
{
    char path[512];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    FILE *in = fopen(path, "rb");
    if (!in) return -1;

    uint16_t namelen = (uint16_t)strlen(name);
    rec->offset = (uint32_t)fwz_ftell64(z);
    snprintf(rec->name, sizeof rec->name, "%s", name);

    unsigned char lh[30];
    memset(lh, 0, sizeof lh);
    wr32(lh, SIG_LOCAL);
    wr16(lh + 4, 20);
    wr16(lh + 6, 1);
    wr16(lh + 8, 8);
    wr16(lh + 10, 0); wr16(lh + 12, 0x21);
    wr16(lh + 26, namelen);
    if (fwrite(lh, 1, 30, z) != 30 || fwrite(name, 1, namelen, z) != namelen) { fclose(in); return -1; }

    mz_ulong crc = mz_crc32(MZ_CRC32_INIT, NULL, 0);
    uint64_t usize = 0;
    unsigned char *ibuf = malloc(CHUNK), *obuf = malloc(CHUNK);
    if (!ibuf || !obuf) { free(ibuf); free(obuf); fclose(in); return -1; }
    for (;;) {
        size_t got = fread(ibuf, 1, CHUNK, in);
        if (!got) break;
        crc = mz_crc32(crc, ibuf, got);
        usize += got;
    }
    fwz_fseek64(in, 0);

    uint32_t keys[3];
    key_init(keys, password);

    unsigned char eh[12];
    for (int i = 0; i < 11; i++) eh[i] = (unsigned char)(0x5a + i);
    eh[11] = (unsigned char)((uint32_t)crc >> 24);
    for (int i = 0; i < 12; i++) eh[i] = encrypt_byte(keys, eh[i]);
    if (fwrite(eh, 1, 12, z) != 12) { free(ibuf); free(obuf); fclose(in); return -1; }
    uint64_t csize = 12;

    mz_stream s;
    memset(&s, 0, sizeof s);
    if (mz_deflateInit2(&s, level, MZ_DEFLATED, -MZ_DEFAULT_WINDOW_BITS, 9,
                        MZ_DEFAULT_STRATEGY) != MZ_OK) { free(ibuf); free(obuf); fclose(in); return -1; }

    int done = 0;
    while (!done) {
        size_t got = fread(ibuf, 1, CHUNK, in);
        int last = (got < CHUNK);
        s.next_in = ibuf; s.avail_in = (unsigned)got;
        for (;;) {
            unsigned before = s.avail_in;
            s.next_out = obuf; s.avail_out = CHUNK;
            int r = mz_deflate(&s, last ? MZ_FINISH : MZ_NO_FLUSH);
            if (r != MZ_OK && r != MZ_STREAM_END && r != MZ_BUF_ERROR) {
                mz_deflateEnd(&s); free(ibuf); free(obuf); fclose(in); return -1;
            }
            size_t have = CHUNK - s.avail_out;
            for (size_t j = 0; j < have; j++) obuf[j] = encrypt_byte(keys, obuf[j]);
            if (have && fwrite(obuf, 1, have, z) != have) {
                mz_deflateEnd(&s); free(ibuf); free(obuf); fclose(in); return -1;
            }
            csize += have;
            if (r == MZ_STREAM_END) { done = 1; break; }
            if (s.avail_in == 0 && !last) break;
            if (s.avail_in == before && have == 0) break;
        }
    }
    mz_deflateEnd(&s);
    free(ibuf); free(obuf);
    fclose(in);

    rec->crc = (uint32_t)crc;
    rec->csize = (uint32_t)csize;
    rec->usize = (uint32_t)usize;

    int64_t here = fwz_ftell64(z);
    unsigned char fix[12];
    wr32(fix, rec->crc); wr32(fix + 4, rec->csize); wr32(fix + 8, rec->usize);
    if (fwz_fseek64(z, rec->offset + 14) != 0 || fwrite(fix, 1, 12, z) != 12) return -1;
    if (fwz_fseek64(z, here) != 0) return -1;
    return 0;
}

int zip_create(const char *zip_path, const char *password, const char *dir,
               const zip_listing *names)
{
    FILE *z = fopen(zip_path, "w+b");
    if (!z) return -1;

    written *recs = calloc((size_t)names->count, sizeof *recs);
    if (!recs) { fclose(z); return -1; }

    for (int i = 0; i < names->count; i++) {
        if (add_one(z, dir, names->names[i], password, &recs[i], 6) != 0) {
            fprintf(stderr, "fwz: could not add %s\n", names->names[i]);
            free(recs); fclose(z); return -1;
        }
    }

    uint32_t cd_start = (uint32_t)fwz_ftell64(z);
    for (int i = 0; i < names->count; i++) {
        unsigned char h[46];
        memset(h, 0, sizeof h);
        uint16_t namelen = (uint16_t)strlen(recs[i].name);
        wr32(h, SIG_CENTRAL);
        wr16(h + 4, 20); wr16(h + 6, 20);
        wr16(h + 8, 1); wr16(h + 10, 8);
        wr16(h + 12, 0); wr16(h + 14, 0x21);
        wr32(h + 16, recs[i].crc);
        wr32(h + 20, recs[i].csize);
        wr32(h + 24, recs[i].usize);
        wr16(h + 28, namelen);
        wr32(h + 38, 0x81a40000u);
        wr32(h + 42, recs[i].offset);
        if (fwrite(h, 1, 46, z) != 46 || fwrite(recs[i].name, 1, namelen, z) != namelen) {
            free(recs); fclose(z); return -1;
        }
    }
    uint32_t cd_size = (uint32_t)fwz_ftell64(z) - cd_start;

    unsigned char end[22];
    memset(end, 0, sizeof end);
    wr32(end, SIG_END);
    wr16(end + 8, (uint16_t)names->count);
    wr16(end + 10, (uint16_t)names->count);
    wr32(end + 12, cd_size);
    wr32(end + 16, cd_start);
    int ok = fwrite(end, 1, 22, z) == 22;

    free(recs);
    if (fclose(z) != 0) ok = 0;
    return ok ? 0 : -1;
}
