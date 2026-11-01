/*
 * daily-index -- choose which excerpt a sleep screen shows.
 *
 * Two modes:
 *
 *   daily-index YYYY-MM-DD TOTAL
 *       Date-seeded pick (FNV-1a over "kindlexiping261030:v1:<date>"), matching
 *       web/app.js and tools/render.py. Same date, same index, everywhere.
 *
 *   daily-index random TOTAL BOOKS LAST
 *       Random pick for a single sleep. The previous pick is passed in so the
 *       next one never lands in the same book block, which makes the title and
 *       the excerpt change together on every sleep.
 *
 * The random mode exists because the date-seeded pick showed one excerpt for a
 * whole day: every sleep in those 24 hours repeated the same poster.
 *
 * Randomness comes from /dev/urandom rather than from busybox tools, because
 * this device's busybox is not trustworthy (awk is known to segfault) and
 * because a static C binary is the one thing here already proven to run.
 *
 * Exit: 0 ok, 2 bad usage.
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static uint32_t random_u32(void)
{
    uint32_t value = 0;
    int fd = open("/dev/urandom", O_RDONLY);

    if (fd >= 0) {
        if (read(fd, &value, sizeof(value)) != (ssize_t)sizeof(value))
            value = 0;
        close(fd);
    }

    if (value == 0) {
        /* No usable urandom: still better than a fixed answer. */
        struct timespec now;

        clock_gettime(CLOCK_MONOTONIC, &now);
        value = (uint32_t)(now.tv_sec * 1000000007u + (uint32_t)now.tv_nsec) ^
                (uint32_t)getpid();
        if (value == 0)
            value = 0x9e3779b9u;
    }

    return value;
}

static int date_index(const char *date, int total)
{
    char salt[64];
    uint32_t hash = UINT32_C(2166136261);

    if (snprintf(salt, sizeof(salt), "kindlexiping261030:v1:%s", date) < 0)
        return -1;

    for (const unsigned char *p = (const unsigned char *)salt; *p; p++) {
        hash ^= *p;
        hash *= UINT32_C(16777619);
    }

    return (int)(hash % (uint32_t)total);
}

/*
 * Random pick whose book differs from the previous one.
 *
 * The data file holds each book's excerpts as one consecutive block, so the
 * book is index / block. Rejection sampling is fine here: with 100 books the
 * expected number of tries is barely above one.
 */
static int random_index(int total, int books, int last)
{
    int block;
    int last_book;
    int book;
    int attempt;

    if (books < 1)
        books = 1;
    if (books > total)
        books = total;

    block = total / books;
    if (block < 1)
        block = 1;

    last_book = (last >= 0 && last < total) ? last / block : -1;

    for (attempt = 0; attempt < 64; attempt++) {
        book = (int)(random_u32() % (uint32_t)books);
        if (book != last_book || books < 2)
            break;
    }

    return book * block + (int)(random_u32() % (uint32_t)block);
}

int main(int argc, char **argv)
{
    int total;

    if (argc >= 2 && strcmp(argv[1], "random") == 0) {
        int index;

        if (argc != 5)
            return 2;

        total = atoi(argv[2]);
        if (total < 1 || total > 5000)
            return 2;

        index = random_index(total, atoi(argv[3]), atoi(argv[4]));
        if (index < 0 || index >= total)
            return 2;

        printf("%d\n", index);
        return 0;
    }

    if (argc != 3 || strlen(argv[1]) != 10)
        return 2;

    total = atoi(argv[2]);
    if (total < 1 || total > 5000)
        return 2;

    int index = date_index(argv[1], total);
    if (index < 0)
        return 2;

    printf("%d\n", index);
    return 0;
}
