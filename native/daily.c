/* Same FNV-1a daily selection as web/app.js and tools/render.py. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv) {
    if (argc != 3 || strlen(argv[1]) != 10) return 2;
    char salt[64];
    if (snprintf(salt, sizeof(salt), "kindlexiping261030:v1:%s", argv[1]) < 0) return 2;
    uint32_t hash = UINT32_C(2166136261);
    for (const unsigned char *p=(const unsigned char *)salt; *p; p++) {
        hash ^= *p;
        hash *= UINT32_C(16777619);
    }
    int total = atoi(argv[2]);
    if (total < 1 || total > 5000) return 2;
    printf("%u\n", hash % (uint32_t)total);
    return 0;
}
