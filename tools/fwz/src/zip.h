#ifndef FWZ_ZIP_H
#define FWZ_ZIP_H

#include <stddef.h>

#define ZIP_MAX_ENTRIES 32

typedef struct {
    char names[ZIP_MAX_ENTRIES][256];
    int  count;
} zip_listing;

int zip_extract(const char *zip_path, const char *password, const char *dir, zip_listing *out);

int zip_create(const char *zip_path, const char *password, const char *dir,
               const zip_listing *names);

#endif
