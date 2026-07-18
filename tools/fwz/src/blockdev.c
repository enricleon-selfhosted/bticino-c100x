#include "blockdev.h"

#include <stdio.h>
#include <string.h>

#define SECTOR 512

static FILE *img;
static uint64_t img_sectors;

static int bd_open(struct ext4_blockdev *bdev)  { (void)bdev; return img ? EOK : EIO; }
static int bd_close(struct ext4_blockdev *bdev) { (void)bdev; return EOK; }
static int bd_lock(struct ext4_blockdev *bdev)   { (void)bdev; return EOK; }
static int bd_unlock(struct ext4_blockdev *bdev) { (void)bdev; return EOK; }

static int bd_bread(struct ext4_blockdev *bdev, void *buf, uint64_t blk, uint32_t cnt)
{
    (void)bdev;
    if (!img) return EIO;
    if (fwz_fseek64(img, (int64_t)blk * SECTOR) != 0) return EIO;
    if (cnt == 0) return EOK;
    return fread(buf, SECTOR, cnt, img) == cnt ? EOK : EIO;
}

static int bd_bwrite(struct ext4_blockdev *bdev, const void *buf, uint64_t blk, uint32_t cnt)
{
    (void)bdev;
    if (!img) return EIO;
    if (fwz_fseek64(img, (int64_t)blk * SECTOR) != 0) return EIO;
    if (cnt == 0) return EOK;
    return fwrite(buf, SECTOR, cnt, img) == cnt ? EOK : EIO;
}

EXT4_BLOCKDEV_STATIC_INSTANCE(fwz_bd, SECTOR, 0, bd_open, bd_bread, bd_bwrite, bd_close,
                              bd_lock, bd_unlock);

struct ext4_blockdev *blockdev_open(const char *path)
{
    img = fopen(path, "r+b");
    if (!img) return NULL;

    if (fwz_fseek_end(img) != 0) { fclose(img); img = NULL; return NULL; }
    int64_t size = fwz_ftell64(img);
    if (size <= 0) { fclose(img); img = NULL; return NULL; }

    img_sectors = (uint64_t)size / SECTOR;
    fwz_bd.bdif->ph_bcnt = img_sectors;
    fwz_bd.part_offset = 0;
    fwz_bd.part_size = img_sectors * SECTOR;
    return &fwz_bd;
}

void blockdev_close(void)
{
    if (img) { fflush(img); fclose(img); img = NULL; }
}
