/* Minimal touchscreen reader for a jailbroken Kindle; no system files are modified. */
#include <fcntl.h>
#include <linux/input.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#define BASE "/mnt/us/extensions/kindlexiping261030/"
static int read_int(const char *path, int fallback) {
    FILE *file = fopen(path, "r"); int value;
    if (!file) return fallback;
    if (fscanf(file, "%d", &value) != 1) value = fallback;
    fclose(file); return value;
}
static int write_int(const char *path, int value) {
    char temp[128]; snprintf(temp, sizeof(temp), "%s.tmp", path);
    FILE *file = fopen(temp, "w"); if (!file) return -1;
    fprintf(file, "%d\n", value); fclose(file); return rename(temp, path);
}
static int text(const char *value, int top, int bottom) {
    char command[2048];
    snprintf(command, sizeof(command),
        BASE "bin/fbink_hf -q -o -B WHITE -C BLACK -t regular=" BASE "SmileySans-Oblique.ttf,px=28,top=%d,bottom=%d,left=0,right=0,notrunc -m \"%s\"",
        top, bottom, value);
    return system(command);
}
static int draw(int index) {
    char command[512];
    snprintf(command, sizeof(command), "sh " BASE "scripts/draw.sh %d browse", index);
    return system(command);
}
int main(int argc, char **argv) {
    const char *device = argc > 1 ? argv[1] : "/dev/input/event1";
    int input = open(device, O_RDONLY);
    if (input < 0) { perror("kindlexiping: touchscreen"); return 1; }
    struct input_absinfo ax = {0}, ay = {0};
    ioctl(input, EVIOCGABS(ABS_MT_POSITION_X), &ax);
    ioctl(input, EVIOCGABS(ABS_MT_POSITION_Y), &ay);
    if (ioctl(input, EVIOCGRAB, 1) != 0) perror("kindlexiping: input grab");
    int count = read_int(BASE "state/count", 0);
    if (count < 1 || count > 5000) { fprintf(stderr, "kindlexiping: content is missing\n"); return 2; }
    int index = read_int(BASE "state/browser-index", read_int(BASE "state/daily-index", 0));
    if (index < 0 || index >= count) index = 0;
    if (draw(index) != 0) { fprintf(stderr, "kindlexiping: failed to draw PNG\n"); return 3; }
    struct input_event event; int active = 0, x = 0, y = 0;
    while (read(input, &event, sizeof(event)) == sizeof(event)) {
        if (event.type == EV_ABS && event.code == ABS_MT_POSITION_X) x = event.value;
        if (event.type == EV_ABS && event.code == ABS_MT_POSITION_Y) y = event.value;
        if (event.type == EV_KEY && event.code == BTN_TOUCH && event.value == 0) {
            if (!active) continue;
            active = 0;
            int px = ax.maximum > ax.minimum ? (x - ax.minimum) * 1072 / (ax.maximum - ax.minimum) : x;
            int py = ay.maximum > ay.minimum ? (y - ay.minimum) * 1448 / (ay.maximum - ay.minimum) : y;
            if (py > 1300) {
                if (px < 357) index = (index + count - 1) % count;
                else if (px > 715) index = (index + 1) % count;
                else break;
            } else if (px < 536) index = (index + count - 1) % count;
            else index = (index + 1) % count;
            if (write_int(BASE "state/browser-index", index) != 0) perror("kindlexiping: state");
            if (draw(index) != 0) break;
        }
        if (event.type != EV_ABS || event.code != ABS_MT_TRACKING_ID) continue;
        if (event.value >= 0) { active = 1; continue; }
        if (!active) continue;
        active = 0;
        if (y > 1300) {
            if (x < 357) index = (index + count - 1) % count;
            else if (x > 715) index = (index + 1) % count;
            else break;
        } else if (x < 536) index = (index + count - 1) % count;
        else index = (index + 1) % count;
        if (write_int(BASE "state/browser-index", index) != 0) perror("kindlexiping: state");
        if (draw(index) != 0) break;
    }
    close(input); system("DISPLAY=:0 xrefresh"); return 0;
}
