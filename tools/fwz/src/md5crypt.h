#ifndef FWZ_MD5CRYPT_H
#define FWZ_MD5CRYPT_H

#include <stddef.h>

void md5crypt(const char *password, const char *salt, char *out, size_t outlen);

#endif
