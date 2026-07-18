// FreeBSD "$1$" md5crypt: the only scheme the unit accepts
#include "md5crypt.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct { uint32_t s[4]; uint64_t len; unsigned char buf[64]; size_t n; } md5;

static uint32_t rol(uint32_t x, int c) { return (x << c) | (x >> (32 - c)); }

static void md5_block(md5 *m, const unsigned char *p)
{
    static const uint32_t K[64] = {
        0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,
        0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,
        0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,
        0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,
        0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,
        0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,
        0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,
        0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391 };
    static const int R[64] = {
        7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22, 5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,
        4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23, 6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21 };

    uint32_t w[16];
    for (int i = 0; i < 16; i++)
        w[i] = p[i*4] | (p[i*4+1] << 8) | ((uint32_t)p[i*4+2] << 16) | ((uint32_t)p[i*4+3] << 24);

    uint32_t a = m->s[0], b = m->s[1], c = m->s[2], d = m->s[3];
    for (int i = 0; i < 64; i++) {
        uint32_t f; int g;
        if      (i < 16) { f = (b & c) | (~b & d);        g = i; }
        else if (i < 32) { f = (d & b) | (~d & c);        g = (5*i + 1) & 15; }
        else if (i < 48) { f = b ^ c ^ d;                 g = (3*i + 5) & 15; }
        else             { f = c ^ (b | ~d);              g = (7*i) & 15; }
        uint32_t tmp = d; d = c; c = b;
        b = b + rol(a + f + K[i] + w[g], R[i]);
        a = tmp;
    }
    m->s[0] += a; m->s[1] += b; m->s[2] += c; m->s[3] += d;
}

static void md5_init(md5 *m)
{
    m->s[0] = 0x67452301; m->s[1] = 0xefcdab89;
    m->s[2] = 0x98badcfe; m->s[3] = 0x10325476;
    m->len = 0; m->n = 0;
}

static void md5_update(md5 *m, const void *data, size_t len)
{
    const unsigned char *p = data;
    m->len += len;
    while (len) {
        size_t take = 64 - m->n;
        if (take > len) take = len;
        memcpy(m->buf + m->n, p, take);
        m->n += take; p += take; len -= take;
        if (m->n == 64) { md5_block(m, m->buf); m->n = 0; }
    }
}

static void md5_final(md5 *m, unsigned char out[16])
{
    uint64_t bits = m->len * 8;
    unsigned char pad = 0x80;
    md5_update(m, &pad, 1);
    unsigned char zero = 0;
    while (m->n != 56) md5_update(m, &zero, 1);
    unsigned char l[8];
    for (int i = 0; i < 8; i++) l[i] = (unsigned char)(bits >> (8 * i));
    md5_update(m, l, 8);
    for (int i = 0; i < 4; i++) {
        out[i*4]     = (unsigned char)(m->s[i]);
        out[i*4 + 1] = (unsigned char)(m->s[i] >> 8);
        out[i*4 + 2] = (unsigned char)(m->s[i] >> 16);
        out[i*4 + 3] = (unsigned char)(m->s[i] >> 24);
    }
}

static const char itoa64[] = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

static char *to64(char *p, uint32_t v, int n)
{
    while (n-- > 0) { *p++ = itoa64[v & 0x3f]; v >>= 6; }
    return p;
}

void md5crypt(const char *password, const char *salt, char *out, size_t outlen)
{
    static const char magic[] = "$1$";
    size_t pwlen = strlen(password), saltlen = strlen(salt);
    if (saltlen > 8) saltlen = 8;

    md5 ctx, alt;
    unsigned char final[16];

    md5_init(&alt);
    md5_update(&alt, password, pwlen);
    md5_update(&alt, salt, saltlen);
    md5_update(&alt, password, pwlen);
    md5_final(&alt, final);

    md5_init(&ctx);
    md5_update(&ctx, password, pwlen);
    md5_update(&ctx, magic, 3);
    md5_update(&ctx, salt, saltlen);
    for (size_t i = pwlen; i > 0; i -= (i > 16 ? 16 : i))
        md5_update(&ctx, final, i > 16 ? 16 : i);

    for (size_t i = pwlen; i; i >>= 1) {
        unsigned char z = 0;
        if (i & 1) md5_update(&ctx, &z, 1);
        else       md5_update(&ctx, password, 1);
    }
    md5_final(&ctx, final);

    for (int i = 0; i < 1000; i++) {
        md5_init(&ctx);
        if (i & 1) md5_update(&ctx, password, pwlen); else md5_update(&ctx, final, 16);
        if (i % 3) md5_update(&ctx, salt, saltlen);
        if (i % 7) md5_update(&ctx, password, pwlen);
        if (i & 1) md5_update(&ctx, final, 16);       else md5_update(&ctx, password, pwlen);
        md5_final(&ctx, final);
    }

    char buf[64], *p = buf;
    p += snprintf(buf, sizeof buf, "$1$%.*s$", (int)saltlen, salt);
    p = to64(p, ((uint32_t)final[0] << 16) | ((uint32_t)final[6] << 8) | final[12], 4);
    p = to64(p, ((uint32_t)final[1] << 16) | ((uint32_t)final[7] << 8) | final[13], 4);
    p = to64(p, ((uint32_t)final[2] << 16) | ((uint32_t)final[8] << 8) | final[14], 4);
    p = to64(p, ((uint32_t)final[3] << 16) | ((uint32_t)final[9] << 8) | final[15], 4);
    p = to64(p, ((uint32_t)final[4] << 16) | ((uint32_t)final[10] << 8) | final[5], 4);
    p = to64(p, final[11], 2);
    *p = '\0';
    snprintf(out, outlen, "%s", buf);
}
