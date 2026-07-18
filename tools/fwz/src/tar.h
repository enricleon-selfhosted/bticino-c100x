#ifndef FWZ_TAR_H
#define FWZ_TAR_H

#include <stddef.h>

int tar_write_tree(const char *root, const char *out_path,
                   const char *const *exec_paths, size_t exec_count);

#endif
