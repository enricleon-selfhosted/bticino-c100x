#ifndef FWZ_GZ_H
#define FWZ_GZ_H

int gz_inflate_file(const char *in_path, const char *out_path);
int gz_deflate_file(const char *in_path, const char *out_path, int level);

#endif
