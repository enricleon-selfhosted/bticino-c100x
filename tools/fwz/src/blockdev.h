#ifndef FWZ_BLOCKDEV_H
#define FWZ_BLOCKDEV_H

#include <ext4.h>
#include <ext4_blockdev.h>
#include <stdint.h>
#include <stdio.h>

#if defined(_WIN32)
  #define fwz_fseek64(f, off)  _fseeki64((f), (int64_t)(off), SEEK_SET)
  #define fwz_fseek_end(f)     _fseeki64((f), 0, SEEK_END)
  #define fwz_ftell64(f)       _ftelli64(f)
#else
  #define _FILE_OFFSET_BITS 64
  #define fwz_fseek64(f, off)  fseeko((f), (off_t)(off), SEEK_SET)
  #define fwz_fseek_end(f)     fseeko((f), 0, SEEK_END)
  #define fwz_ftell64(f)       ((int64_t)ftello(f))
#endif

struct ext4_blockdev *blockdev_open(const char *path);
void blockdev_close(void);

#endif
