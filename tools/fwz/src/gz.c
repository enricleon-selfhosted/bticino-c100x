#include "gz.h"
#include "blockdev.h"

#include "miniz.h"

#include <stdio.h>
#include <string.h>

#define CHUNK (256 * 1024)

static int read_gzip_header(FILE *f)
{
    unsigned char h[10];
    if (fread(h, 1, 10, f) != 10) return -1;
    if (h[0] != 0x1f || h[1] != 0x8b || h[2] != 8) return -1;

    unsigned flags = h[3];
    if (flags & 0x04) {
        unsigned char n[2];
        if (fread(n, 1, 2, f) != 2) return -1;
        if (fwz_fseek64(f, fwz_ftell64(f) + (n[0] | (n[1] << 8))) != 0) return -1;
    }
    if (flags & 0x08) while (fgetc(f) > 0) {}
    if (flags & 0x10) while (fgetc(f) > 0) {}
    if (flags & 0x02) { if (fwz_fseek64(f, fwz_ftell64(f) + 2) != 0) return -1; }
    return 0;
}

int gz_inflate_file(const char *in_path, const char *out_path)
{
    FILE *in = fopen(in_path, "rb");
    if (!in) return -1;
    FILE *out = fopen(out_path, "wb");
    if (!out) { fclose(in); return -1; }

    int rc = -1;
    unsigned char *ibuf = NULL, *obuf = NULL;
    mz_stream s;
    memset(&s, 0, sizeof s);

    if (read_gzip_header(in) != 0) goto done;
    if (mz_inflateInit2(&s, -MZ_DEFAULT_WINDOW_BITS) != MZ_OK) goto done;

    ibuf = malloc(CHUNK);
    obuf = malloc(CHUNK);
    if (!ibuf || !obuf) goto cleanup;

    for (;;) {
        size_t got = fread(ibuf, 1, CHUNK, in);
        if (got == 0 && s.avail_in == 0) break;
        s.next_in = ibuf;
        s.avail_in = (unsigned)got;

        for (;;) {
            unsigned before = s.avail_in;
            s.next_out = obuf;
            s.avail_out = CHUNK;
            int r = mz_inflate(&s, MZ_NO_FLUSH);
            if (r != MZ_OK && r != MZ_STREAM_END && r != MZ_BUF_ERROR) goto cleanup;

            size_t have = CHUNK - s.avail_out;
            if (have && fwrite(obuf, 1, have, out) != have) goto cleanup;
            if (r == MZ_STREAM_END) { rc = 0; goto cleanup; }
            if (s.avail_in == 0) break;
            if (s.avail_in == before && have == 0) break;
        }
    }
    rc = 0;

cleanup:
    mz_inflateEnd(&s);
done:
    free(ibuf); free(obuf);
    fclose(in);
    if (fclose(out) != 0) rc = -1;
    return rc;
}

int gz_deflate_file(const char *in_path, const char *out_path, int level)
{
    FILE *in = fopen(in_path, "rb");
    if (!in) return -1;
    FILE *out = fopen(out_path, "wb");
    if (!out) { fclose(in); return -1; }

    static const unsigned char hdr[10] = { 0x1f, 0x8b, 8, 0, 0,0,0,0, 0, 0x03 };
    int rc = -1;
    unsigned char *ibuf = NULL, *obuf = NULL;
    mz_ulong crc = mz_crc32(MZ_CRC32_INIT, NULL, 0);
    uint64_t total = 0;
    mz_stream s;
    memset(&s, 0, sizeof s);

    if (fwrite(hdr, 1, 10, out) != 10) goto done;
    if (mz_deflateInit2(&s, level, MZ_DEFLATED, -MZ_DEFAULT_WINDOW_BITS, 9,
                        MZ_DEFAULT_STRATEGY) != MZ_OK) goto done;

    ibuf = malloc(CHUNK);
    obuf = malloc(CHUNK);
    if (!ibuf || !obuf) goto cleanup;

    for (;;) {
        size_t got = fread(ibuf, 1, CHUNK, in);
        int last = (got < CHUNK);
        crc = mz_crc32(crc, ibuf, got);
        total += got;

        s.next_in = ibuf;
        s.avail_in = (unsigned)got;
        int finished = 0;
        for (;;) {
            unsigned before = s.avail_in;
            s.next_out = obuf;
            s.avail_out = CHUNK;
            int r = mz_deflate(&s, last ? MZ_FINISH : MZ_NO_FLUSH);
            if (r != MZ_OK && r != MZ_STREAM_END && r != MZ_BUF_ERROR) goto cleanup;

            size_t have = CHUNK - s.avail_out;
            if (have && fwrite(obuf, 1, have, out) != have) goto cleanup;
            if (r == MZ_STREAM_END) { finished = 1; break; }
            if (s.avail_in == 0 && !last) break;
            if (s.avail_in == before && have == 0) break;
        }

        if (finished || last) break;
    }

    {
        unsigned char tail[8];
        uint32_t c = (uint32_t)crc, n = (uint32_t)total;
        for (int i = 0; i < 4; i++) tail[i]     = (unsigned char)(c >> (8 * i));
        for (int i = 0; i < 4; i++) tail[4 + i] = (unsigned char)(n >> (8 * i));
        if (fwrite(tail, 1, 8, out) != 8) goto cleanup;
    }
    rc = 0;

cleanup:
    mz_deflateEnd(&s);
done:
    free(ibuf); free(obuf);
    fclose(in);
    if (fclose(out) != 0) rc = -1;
    return rc;
}
