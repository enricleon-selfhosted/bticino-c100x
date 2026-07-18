#include "ops.h"
#include "blockdev.h"

#include <ext4.h>
#include <ext4_mkfs.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MP "/mp/"

static void at(char *out, size_t n, const char *path)
{
    snprintf(out, n, "%s%s", MP, path[0] == '/' ? path + 1 : path);
}

static int put_bytes(const char *path, const void *data, size_t len, uint32_t mode,
                     uint32_t uid, uint32_t gid)
{
    char p[512];
    at(p, sizeof p, path);

    ext4_file f;
    int r = ext4_fopen(&f, p, "wb");
    if (r != EOK) return r;

    size_t done = 0;
    if (len) {
        r = ext4_fwrite(&f, data, len, &done);
        if (r == EOK && done != len) r = EIO;
    }
    ext4_fclose(&f);
    if (r != EOK) return r;

    ext4_owner_set(p, uid, gid);
    return ext4_mode_set(p, mode);
}

static char *read_whole(const char *path, size_t *len)
{
    char p[512];
    at(p, sizeof p, path);

    ext4_file f;
    if (ext4_fopen(&f, p, "rb") != EOK) return NULL;

    uint64_t size = ext4_fsize(&f);
    char *buf = malloc((size_t)size + 1);
    if (!buf) { ext4_fclose(&f); return NULL; }

    size_t got = 0;
    if (size && ext4_fread(&f, buf, (size_t)size, &got) != EOK) {
        free(buf); ext4_fclose(&f); return NULL;
    }
    ext4_fclose(&f);
    buf[got] = '\0';
    *len = got;
    return buf;
}

static int split(char *line, char **field, int max)
{
    int n = 0;
    char *p = line;
    while (n < max) {
        field[n++] = p;
        char *tab = strchr(p, '\t');
        if (!tab) break;
        *tab = '\0';
        p = tab + 1;
    }
    return n;
}

int ops_run(const char *image, const char *changes, int verbose)
{
    struct ext4_blockdev *bd = blockdev_open(image);
    if (!bd) { fprintf(stderr, "fwz: cannot open %s\n", image); return 1; }

    int r = ext4_device_register(bd, "img");
    if (r != EOK) { fprintf(stderr, "fwz: cannot register the image (%d)\n", r); return 1; }

    r = ext4_mount("img", MP, false);
    if (r != EOK) { fprintf(stderr, "fwz: this is not an ext4 filesystem (%d)\n", r); return 1; }

    ext4_recover(MP);
    ext4_cache_write_back(MP, true);

    FILE *fp = fopen(changes, "rb");
    if (!fp) { fprintf(stderr, "fwz: cannot read %s\n", changes); return 1; }

    char line[8192];
    int lineno = 0, failed = 0;
    while (fgets(line, sizeof line, fp)) {
        lineno++;
        line[strcspn(line, "\r\n")] = '\0';
        if (line[0] == '\0' || line[0] == '#') continue;

        char *f[8];
        int n = split(line, f, 8);
        char p[512];
        r = EOK;

        if (!strcmp(f[0], "mkdir") && n >= 2) {
            at(p, sizeof p, f[1]);
            r = ext4_dir_mk(p);
            if (r == EEXIST) r = EOK;
            if (r == EOK && n >= 5) {
                ext4_owner_set(p, (uint32_t)strtoul(f[3], NULL, 10),
                                  (uint32_t)strtoul(f[4], NULL, 10));
                ext4_mode_set(p, (uint32_t)strtoul(f[2], NULL, 8));
            }

        } else if (!strcmp(f[0], "put") && n >= 6) {
            FILE *src = fopen(f[1], "rb");
            if (!src) { fprintf(stderr, "fwz: line %d: no such file: %s\n", lineno, f[1]); failed++; continue; }
            fwz_fseek_end(src);
            long size = (long)fwz_ftell64(src);
            fwz_fseek64(src, 0);
            char *data = malloc(size ? (size_t)size : 1);
            if (!data || (size && fread(data, 1, (size_t)size, src) != (size_t)size)) {
                fprintf(stderr, "fwz: line %d: cannot read %s\n", lineno, f[1]);
                free(data); fclose(src); failed++; continue;
            }
            fclose(src);
            r = put_bytes(f[2], data, (size_t)size, (uint32_t)strtoul(f[3], NULL, 8),
                          (uint32_t)strtoul(f[4], NULL, 10), (uint32_t)strtoul(f[5], NULL, 10));
            free(data);
            if (verbose && r == EOK) printf("   %s (%ld bytes)\n", f[2], size);

        } else if (!strcmp(f[0], "append") && n >= 3) {
            size_t len = 0;
            char *cur = read_whole(f[1], &len);
            if (cur && strstr(cur, f[2])) { free(cur); continue; }

            size_t addlen = strlen(f[2]);
            char *merged = malloc(len + addlen + 2);
            if (!merged) { free(cur); failed++; continue; }
            if (cur) memcpy(merged, cur, len); else len = 0;
            if (len && merged[len - 1] != '\n') merged[len++] = '\n';
            memcpy(merged + len, f[2], addlen);
            len += addlen;
            merged[len++] = '\n';
            free(cur);

            uint32_t mode = n >= 4 ? (uint32_t)strtoul(f[3], NULL, 8) : 0644;
            r = put_bytes(f[1], merged, len, mode, 0, 0);
            free(merged);
            if (verbose && r == EOK) printf("   %s += %.40s\n", f[1], f[2]);

        } else if (!strcmp(f[0], "symlink") && n >= 3) {
            at(p, sizeof p, f[2]);
            ext4_fremove(p);
            r = ext4_fsymlink(f[1], p);
            if (verbose && r == EOK) printf("   %s -> %s\n", f[2], f[1]);

        } else if (!strcmp(f[0], "rm") && n >= 2) {
            at(p, sizeof p, f[1]);
            ext4_fremove(p);
            r = EOK;
            if (verbose) printf("   removed %s\n", f[1]);

        } else {
            fprintf(stderr, "fwz: line %d: do not understand '%s'\n", lineno, f[0]);
            failed++;
            continue;
        }

        if (r != EOK) {
            fprintf(stderr, "fwz: line %d: %s failed (%d)\n", lineno, f[0], r);
            failed++;
        }
    }
    fclose(fp);

    ext4_cache_write_back(MP, false);
    r = ext4_umount(MP);
    blockdev_close();

    if (r != EOK) { fprintf(stderr, "fwz: could not close the filesystem cleanly (%d)\n", r); return 1; }
    return failed ? 1 : 0;
}
