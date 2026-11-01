/*
 * Touchscreen browser for a jailbroken Kindle; no system files are modified.
 *
 * Two views:
 *   quote view -- tap left/right half to move; bottom bar = 上一句/书目/下一句/退出
 *   book view  -- one page of book titles; tap a row to read that book
 *
 * Geometry contract with the drawing scripts: every label is drawn inside the
 * same rectangle this file hit-tests. Earlier versions drew one centred label
 * string while hit-testing screen thirds, so tapping 上一句 could fall into the
 * middle zone (exit), release the touch grab, and let the next tap land in the
 * Amazon UI behind us.
 */
#include <fcntl.h>
#include <linux/input.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#define BASE "/mnt/us/extensions/kindlexiping261030/"
#define SCREEN_W 1072
#define SCREEN_H 1448

/* Quote view bar: 4 equal zones, one label centred in each. Matches draw.sh. */
#define ZONE_W 268
#define BAR_TOP 1280

/* Book view: 3 zones in the bar, 8 rows per page. Matches draw_books.sh. */
#define BOOK_ZONE_W 357
#define BOOK_PER_PAGE 8
#define BOOK_ROW_TOP 220
#define BOOK_ROW_H 120

#define CMD_MAX 512
#define MAX_BOOKS 128

struct book_row {
    char title[192];
    char author[128];
    int  first;
    int  count;
};

static int read_int(const char *path, int fallback) {
    FILE *file = fopen(path, "r");
    int value;
    if (!file) return fallback;
    if (fscanf(file, "%d", &value) != 1) value = fallback;
    fclose(file);
    return value;
}

static int write_int(const char *path, int value) {
    char temp[160];
    FILE *file;
    snprintf(temp, sizeof(temp), "%s.tmp", path);
    file = fopen(temp, "w");
    if (!file) return -1;
    fprintf(file, "%d\n", value);
    fclose(file);
    return rename(temp, path);
}

/* Stamp the date of a manual pick so the sleep daemon keeps it for that day.
 * ASCII-only format string: this busybox misbehaves with multibyte formats. */
static void stamp_today(const char *path) {
    time_t now = time(NULL);
    struct tm *tm = localtime(&now);
    char temp[160];
    FILE *file;
    if (!tm) return;
    snprintf(temp, sizeof(temp), "%s.tmp", path);
    file = fopen(temp, "w");
    if (!file) return;
    fprintf(file, "%04d-%02d-%02d\n", tm->tm_year + 1900, tm->tm_mon + 1, tm->tm_mday);
    fclose(file);
    rename(temp, path);
}

static int run(const char *fmt, ...) {
    char command[CMD_MAX];
    va_list args;
    va_start(args, fmt);
    vsnprintf(command, sizeof(command), fmt, args);
    va_end(args);
    return system(command);
}

static void draw_quote(int index) {
    run("sh " BASE "scripts/draw.sh %d browse", index);
}

static void draw_books(int page) {
    run("sh " BASE "scripts/draw_books.sh %d", page);
}

static int load_books(struct book_row *out, int capacity) {
    FILE *file = fopen(BASE "books.tsv", "r");
    int n = 0;
    if (!file) return 0;
    while (n < capacity) {
        char line[512];
        char id[64];
        if (!fgets(line, sizeof(line), file)) break;
        if (sscanf(line, "%63[^\t]\t%191[^\t]\t%127[^\t]\t%d\t%d",
                   id, out[n].title, out[n].author,
                   &out[n].first, &out[n].count) == 5) {
            n++;
        }
    }
    fclose(file);
    return n;
}

/* Step inside the focused book when one is chosen, else across the library. */
static int step_index(int index, int delta, int total, int ffirst, int fcount) {
    int rel;
    if (fcount > 0) {
        rel = index - ffirst;
        if (rel < 0 || rel >= fcount) rel = 0;
        rel = (rel + delta + fcount) % fcount;
        return ffirst + rel;
    }
    return (index + delta + total) % total;
}

static void save_position(int index) {
    if (write_int(BASE "state/browser-index", index) != 0) perror("kindlexiping: state");
    stamp_today(BASE "state/manual-date");
}

int main(int argc, char **argv) {
    const char *device = argc > 1 ? argv[1] : "/dev/input/event1";
    struct input_absinfo ax = {0}, ay = {0};
    struct input_event event;
    struct book_row books[MAX_BOOKS];
    int input, count, index, book_count;
    int book_page = 0, in_books = 0;
    int ffirst = 0, fcount = 0;   /* focus range; fcount 0 means whole library */
    int active = 0, x = 0, y = 0;

    input = open(device, O_RDONLY);
    if (input < 0) { perror("kindlexiping: touchscreen"); return 1; }
    ioctl(input, EVIOCGABS(ABS_MT_POSITION_X), &ax);
    ioctl(input, EVIOCGABS(ABS_MT_POSITION_Y), &ay);
    if (ioctl(input, EVIOCGRAB, 1) != 0) perror("kindlexiping: input grab");

    count = read_int(BASE "state/count", 0);
    if (count < 1 || count > 5000) {
        fprintf(stderr, "kindlexiping: content is missing\n");
        return 2;
    }
    book_count = load_books(books, MAX_BOOKS);
    index = read_int(BASE "state/browser-index", read_int(BASE "state/daily-index", 0));
    if (index < 0 || index >= count) index = 0;
    draw_quote(index);

    while (read(input, &event, sizeof(event)) == sizeof(event)) {
        int px, py, changed = 0;

        if (event.type == EV_ABS && event.code == ABS_MT_POSITION_X) x = event.value;
        if (event.type == EV_ABS && event.code == ABS_MT_POSITION_Y) y = event.value;

        if (event.type == EV_KEY && event.code == BTN_TOUCH && event.value == 0) {
            if (!active) continue;
            active = 0;
            changed = 1;
        } else if (event.type == EV_ABS && event.code == ABS_MT_TRACKING_ID) {
            if (event.value >= 0) { active = 1; continue; }
            if (!active) continue;
            active = 0;
            changed = 1;
        }
        if (!changed) continue;

        px = ax.maximum > ax.minimum
             ? (x - ax.minimum) * SCREEN_W / (ax.maximum - ax.minimum) : x;
        py = ay.maximum > ay.minimum
             ? (y - ay.minimum) * SCREEN_H / (ay.maximum - ay.minimum) : y;

        if (in_books) {
            if (py >= BAR_TOP) {
                int pages = book_count ? (book_count + BOOK_PER_PAGE - 1) / BOOK_PER_PAGE : 1;
                if (px < BOOK_ZONE_W) {
                    if (book_page > 0) book_page--;
                    draw_books(book_page);
                } else if (px < BOOK_ZONE_W * 2) {
                    if (book_page + 1 < pages) book_page++;
                    draw_books(book_page);
                } else {
                    in_books = 0;
                    draw_quote(index);
                }
                continue;
            }
            if (py >= BOOK_ROW_TOP && book_count > 0) {
                int row = (py - BOOK_ROW_TOP) / BOOK_ROW_H;
                int slot = book_page * BOOK_PER_PAGE + row;
                if (row >= 0 && row < BOOK_PER_PAGE && slot < book_count) {
                    /* Focus the chosen book so prev/next stay inside it. */
                    ffirst = books[slot].first;
                    fcount = books[slot].count;
                    index = ffirst;
                    if (index < 0 || index >= count) { index = 0; ffirst = 0; fcount = 0; }
                    save_position(index);
                    in_books = 0;
                    draw_quote(index);
                }
            }
            continue;
        }

        if (py >= BAR_TOP) {
            if (px < ZONE_W) {
                index = step_index(index, -1, count, ffirst, fcount);
            } else if (px < ZONE_W * 2) {
                in_books = 1;
                draw_books(book_page);
                continue;
            } else if (px < ZONE_W * 3) {
                index = step_index(index, 1, count, ffirst, fcount);
            } else {
                goto done;
            }
        } else if (px < SCREEN_W / 2) {
            index = step_index(index, -1, count, ffirst, fcount);
        } else {
            index = step_index(index, 1, count, ffirst, fcount);
        }

        save_position(index);
        draw_quote(index);
    }

done:
    close(input);
    /* The browser draws with FBInk, straight into /dev/fb0, so X still thinks
     * its own windows are on screen and repaints nothing -- the quote would
     * stay painted over the home UI. xscreen forces the redraw.
     *
     * Run it from /var/tmp, not from BASE: /mnt/us is a noexec FAT filesystem,
     * so a program stored there cannot be executed at all. */
    run("DISPLAY=:0 /var/tmp/kindlexiping-bin/xscreen wake "
        "</dev/null >/dev/null 2>&1");
    return 0;
}
