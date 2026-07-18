#include "gz.h"
#include "md5crypt.h"
#include "ops.h"
#include "tar.h"
#include "zip.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define VERSION "1.0.0"

static const char *arg(int argc, char **argv, const char *name, const char *fallback)
{
    for (int i = 1; i < argc - 1; i++)
        if (!strcmp(argv[i], name)) return argv[i + 1];
    return fallback;
}

static int usage(void)
{
    fputs(
        "fwz " VERSION " -- edits Bticino firmware files\n"
        "\n"
        "  fwz build --in <stock.fwz> --out <new.fwz> --model <C100X>\n"
        "            --changes <changes.txt> --work <directory>\n"
        "  fwz pack  --root <directory> --out <file.tar.gz>\n"
        "            [--exec <path inside the directory>]...\n"
        "  fwz passwd <salt> <password>\n"
        "  fwz version\n"
        "\n"
        "The archive password is the model name. The work directory needs about 1.2 GB\n"
        "free and is left as it is, so a second build can reuse it.\n"
        "\n"
        "pack writes the same bytes on every machine: sorted names, no timestamps, no\n"
        "owner, and permissions decided by --exec rather than read off the disk.\n", stderr);
    return 2;
}

static int build(int argc, char **argv)
{
    const char *in    = arg(argc, argv, "--in", NULL);
    const char *out   = arg(argc, argv, "--out", NULL);
    const char *model = arg(argc, argv, "--model", "C100X");
    const char *changes= arg(argc, argv, "--changes", NULL);
    const char *work  = arg(argc, argv, "--work", NULL);
    if (!in || !out || !changes || !work) return usage();

    char fs_gz[512], fs_raw[512];
    zip_listing listing;

    printf("== opening the firmware\n");
    if (zip_extract(in, model, work, &listing) != 0) {
        fprintf(stderr, "fwz: could not open %s\n", in);
        return 1;
    }
    printf("   %d files inside\n", listing.count);

    int found = -1;
    for (int i = 0; i < listing.count; i++)
        if (strstr(listing.names[i], ".ext4.gz") && !strstr(listing.names[i], "recovery"))
            found = i;
    if (found < 0) {
        fprintf(stderr, "fwz: no filesystem in this archive. Is it the right file?\n");
        return 1;
    }
    snprintf(fs_gz,  sizeof fs_gz,  "%s/%s", work, listing.names[found]);
    snprintf(fs_raw, sizeof fs_raw, "%s/filesystem.ext4", work);

    printf("== unpacking the filesystem\n");
    if (gz_inflate_file(fs_gz, fs_raw) != 0) {
        fprintf(stderr, "fwz: the filesystem inside is damaged\n");
        return 1;
    }

    printf("== making the changes\n");
    if (ops_run(fs_raw, changes, 1) != 0) return 1;

    printf("== packing it back up\n");
    if (gz_deflate_file(fs_raw, fs_gz, 6) != 0) {
        fprintf(stderr, "fwz: could not compress the filesystem\n");
        return 1;
    }
    if (zip_create(out, model, work, &listing) != 0) {
        fprintf(stderr, "fwz: could not write %s\n", out);
        return 1;
    }

    remove(fs_raw);

    printf("== done\n   %s\n", out);
    return 0;
}

static int pack(int argc, char **argv)
{
    const char *root = arg(argc, argv, "--root", NULL);
    const char *out  = arg(argc, argv, "--out", NULL);
    if (!root || !out) return usage();

    const char *execs[32];
    size_t n = 0;
    for (int i = 2; i < argc - 1 && n < 32; i++)
        if (!strcmp(argv[i], "--exec")) execs[n++] = argv[i + 1];

    char tar_path[1024];
    snprintf(tar_path, sizeof tar_path, "%s.tar", out);

    if (tar_write_tree(root, tar_path, execs, n) != 0) return 1;
    if (gz_deflate_file(tar_path, out, 6) != 0) {
        fprintf(stderr, "fwz: could not compress %s\n", tar_path);
        remove(tar_path);
        return 1;
    }
    remove(tar_path);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc < 2) return usage();

    if (!strcmp(argv[1], "build")) return build(argc, argv);

    if (!strcmp(argv[1], "pack")) return pack(argc, argv);

    if (!strcmp(argv[1], "passwd")) {
        if (argc < 4) return usage();
        char hash[64];
        md5crypt(argv[3], argv[2], hash, sizeof hash);
        printf("%s\n", hash);
        return 0;
    }

    if (!strcmp(argv[1], "version")) { printf("%s\n", VERSION); return 0; }

    return usage();
}
