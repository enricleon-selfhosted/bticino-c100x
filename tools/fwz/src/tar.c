#include "tar.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#define BLOCK 512
#define NAME_MAX_LEN 100

typedef struct {
    char *path;
    int   is_dir;
    long  size;
} entry;

typedef struct {
    entry *v;
    size_t n, cap;
} entries;

static int push(entries *e, const char *path, int is_dir, long size)
{
    if (e->n == e->cap) {
        size_t cap = e->cap ? e->cap * 2 : 64;
        entry *v = realloc(e->v, cap * sizeof *v);
        if (!v) return -1;
        e->v = v;
        e->cap = cap;
    }
    char *copy = malloc(strlen(path) + 1);
    if (!copy) return -1;
    strcpy(copy, path);
    e->v[e->n].path = copy;
    e->v[e->n].is_dir = is_dir;
    e->v[e->n].size = size;
    e->n++;
    return 0;
}

static int by_name(const void *a, const void *b)
{
    return strcmp(((const entry *)a)->path, ((const entry *)b)->path);
}

static int walk(const char *root, const char *prefix, entries *out)
{
    char dir_path[2048];
    if (prefix[0])
        snprintf(dir_path, sizeof dir_path, "%s/%s", root, prefix);
    else
        snprintf(dir_path, sizeof dir_path, "%s", root);

    DIR *d = opendir(dir_path);
    if (!d) {
        fprintf(stderr, "fwz: cannot read %s\n", dir_path);
        return -1;
    }

    struct dirent *de;
    int rc = 0;
    while ((de = readdir(d)) != NULL) {
        if (!strcmp(de->d_name, ".") || !strcmp(de->d_name, "..")) continue;

        char rel[1024], full[2048];
        if (prefix[0])
            snprintf(rel, sizeof rel, "%s/%s", prefix, de->d_name);
        else
            snprintf(rel, sizeof rel, "%s", de->d_name);
        snprintf(full, sizeof full, "%s/%s", root, rel);

        struct stat st;
        if (stat(full, &st) != 0) {
            fprintf(stderr, "fwz: cannot look at %s\n", full);
            rc = -1;
            break;
        }

        if (strlen(rel) + 1 > NAME_MAX_LEN) {
            fprintf(stderr, "fwz: the name %s is too long for a plain tar\n", rel);
            rc = -1;
            break;
        }

        if (S_ISDIR(st.st_mode)) {
            if (push(out, rel, 1, 0) != 0) { rc = -1; break; }
            if (walk(root, rel, out) != 0) { rc = -1; break; }
        } else if (S_ISREG(st.st_mode)) {
            if (push(out, rel, 0, (long)st.st_size) != 0) { rc = -1; break; }
        } else {
            fprintf(stderr, "fwz: %s is not a plain file or a directory\n", rel);
            rc = -1;
            break;
        }
    }
    closedir(d);
    return rc;
}

static void put_octal(char *field, size_t width, unsigned long value)
{
    char tmp[32];
    snprintf(tmp, sizeof tmp, "%0*lo", (int)(width - 1), value);
    memcpy(field, tmp, width - 1);
    field[width - 1] = '\0';
}

static void header(char *h, const char *name, int is_dir, long size, unsigned mode)
{
    memset(h, 0, BLOCK);

    char stored[NAME_MAX_LEN + 1];
    snprintf(stored, sizeof stored, "%s%s", name, is_dir ? "/" : "");
    memcpy(h, stored, strlen(stored));

    put_octal(h + 100, 8, mode);
    put_octal(h + 108, 8, 0);
    put_octal(h + 116, 8, 0);
    put_octal(h + 124, 12, is_dir ? 0UL : (unsigned long)size);
    put_octal(h + 136, 12, 0);
    h[156] = is_dir ? '5' : '0';
    memcpy(h + 257, "ustar", 5);
    memcpy(h + 263, "00", 2);
    put_octal(h + 329, 8, 0);
    put_octal(h + 337, 8, 0);

    memset(h + 148, ' ', 8);
    unsigned long sum = 0;
    for (int i = 0; i < BLOCK; i++) sum += (unsigned char)h[i];
    snprintf(h + 148, 8, "%06lo", sum);
    h[154] = '\0';
    h[155] = ' ';
}

static int is_exec(const char *rel, const char *const *exec_paths, size_t exec_count)
{
    for (size_t i = 0; i < exec_count; i++)
        if (!strcmp(rel, exec_paths[i])) return 1;
    return 0;
}

int tar_write_tree(const char *root, const char *out_path,
                   const char *const *exec_paths, size_t exec_count)
{
    entries e;
    memset(&e, 0, sizeof e);
    if (walk(root, "", &e) != 0) { free(e.v); return -1; }
    qsort(e.v, e.n, sizeof *e.v, by_name);

    FILE *out = fopen(out_path, "wb");
    if (!out) {
        fprintf(stderr, "fwz: cannot write %s\n", out_path);
        for (size_t i = 0; i < e.n; i++) free(e.v[i].path);
        free(e.v);
        return -1;
    }

    char h[BLOCK];
    char buf[65536];
    int rc = 0;
    long written = 0;

    for (size_t i = 0; i < e.n && rc == 0; i++) {
        entry *en = &e.v[i];
        unsigned mode = en->is_dir ? 0755u
                      : (is_exec(en->path, exec_paths, exec_count) ? 0755u : 0644u);
        header(h, en->path, en->is_dir, en->size, mode);
        if (fwrite(h, 1, BLOCK, out) != BLOCK) { rc = -1; break; }
        written += BLOCK;
        if (en->is_dir) continue;

        char full[2048];
        snprintf(full, sizeof full, "%s/%s", root, en->path);
        FILE *f = fopen(full, "rb");
        if (!f) { fprintf(stderr, "fwz: cannot read %s\n", full); rc = -1; break; }

        long left = en->size;
        while (left > 0) {
            size_t want = (size_t)(left < (long)sizeof buf ? left : (long)sizeof buf);
            size_t got = fread(buf, 1, want, f);
            if (got != want) { fprintf(stderr, "fwz: %s got shorter while reading\n", full); rc = -1; break; }
            if (fwrite(buf, 1, got, out) != got) { rc = -1; break; }
            written += (long)got;
            left -= (long)got;
        }
        fclose(f);
        if (rc != 0) break;

        long pad = (BLOCK - (en->size % BLOCK)) % BLOCK;
        if (pad) {
            memset(buf, 0, (size_t)pad);
            if (fwrite(buf, 1, (size_t)pad, out) != (size_t)pad) { rc = -1; break; }
            written += pad;
        }
    }

    if (rc == 0) {
        memset(buf, 0, BLOCK);
        for (int i = 0; i < 2 && rc == 0; i++) {
            if (fwrite(buf, 1, BLOCK, out) != BLOCK) rc = -1;
            written += BLOCK;
        }
        while (rc == 0 && written % 10240) {
            if (fwrite(buf, 1, BLOCK, out) != BLOCK) rc = -1;
            written += BLOCK;
        }
    }

    if (fclose(out) != 0) rc = -1;
    for (size_t i = 0; i < e.n; i++) free(e.v[i].path);
    free(e.v);
    if (rc != 0) remove(out_path);
    return rc;
}
