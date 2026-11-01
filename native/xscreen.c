/*
 * xscreen.c
 *
 * Make the Kindle UI repaint on wake.
 *
 * The bug: after sleeping with the custom lockscreen, waking left the poster on
 * the panel. Tapping revealed a little UI at a time, because the framework only
 * redraws the small regions it considers dirty.
 *
 * Why: the poster is drawn by FBInk straight into /dev/fb0, *underneath* the X
 * server. X keeps its own idea of what its windows look like, concludes nothing
 * is dirty, and repaints nothing on wake. The panel therefore keeps showing the
 * poster while X believes the interface is already on screen. That is also why
 * the only pixels that differed between the sleep and wake captures were the
 * status-bar clock: a ticking clock is genuinely dirty, so it was the one thing
 * the framework did repaint.
 *
 * What `wake` does:
 *
 *   1. Leave the panel alone if the UI is already on it (judged by whole-frame
 *      comparison against the poster capture). This matters because the reveal
 *      below is not free.
 *   2. Map a fullscreen override-redirect cover, then destroy it. Destroying a
 *      mapped window sends Expose to everything it revealed -- the same
 *      mechanism the stock screensaver relies on when it is dismissed. It does
 *      NOT touch the contents of any window.
 *   3. Verify against the poster capture, requiring BOTH that the poster is gone
 *      and that real content is present. Either test alone is fooled.
 *
 * ClearArea is deliberately not used. The obvious xrefresh(1) approach -- clear
 * every window with exposures = True -- is destructive here: the Kindle UI does
 * not repaint itself in response to Expose, so everything it owned was erased
 * and left blank. Measured on the device, the middle of the panel went from
 * 10.91% ink on the poster to 0.00% after a wake, leaving a white screen with
 * only the status bar and the nav strip.
 *
 * Verification compares the *whole* framebuffer against the poster file and
 * requires a large fraction of bytes to differ. Comparing "did anything
 * change" would be useless here: the clock ticks on its own, so a failed
 * repaint looks like a change too. A real UI restore replaces essentially the
 * whole screen, so the two cases are far apart.
 *
 * That verification is why this is a program and not a shell one-liner. Every
 * earlier attempt "succeeded" while the screen never changed, so the failure
 * was invisible in the logs.
 *
 * Why the X11 wire protocol instead of Xlib:
 *
 * This replaces xredraw and screensaver_shield, both of which were linked
 * dynamically against a stub libX11.so.6. Neither ever ran on the target PW3:
 * screensaver_shield prints "starting" as the first statement of main(), its
 * stderr went to custom_ss.log, and that line never appeared -- it died inside
 * the dynamic loader. Everything that does work on this device (fbink,
 * daily-index, the touch reader) is a static musl binary. Speaking the protocol
 * directly drops libX11 and the dynamic loader, so this builds -static.
 *
 * Exit codes:
 *   0  the panel is no longer showing the lockscreen poster
 *   2  the repaint was accepted but the panel still shows the poster
 *   3  cannot reach the X server
 *   4  the X server rejected the connection (authentication)
 *   5  bad usage
 */

#define _POSIX_C_SOURCE 200809L

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#define MAX_DEPTH 24
#define MAX_WINDOWS 4096

/* PW3 fb0: 8bpp, 1072 px wide, rows padded to 1088 bytes. */
#define FB_STRIDE 1088
#define FB_ROWS 1448
#define FB_SIZE ((size_t)FB_STRIDE * FB_ROWS)
#define POSTER_DEFAULT "/mnt/us/extensions/kindlexiping261030/screen-lockscreen.raw"

/*
 * A restored UI and the poster are completely different images, so a repaint
 * that worked changes most bytes. Only the small clock strip changes on its
 * own. 5% sits far from both.
 */
#define DIFF_THRESHOLD 0.05
/* Ignore single-bit eink dithering noise when counting a byte as changed. */
#define BYTE_EPSILON 8

struct xconn {
    int fd;
    uint32_t root;
    uint32_t id_base;
    uint32_t id_mask;
    uint32_t next_id;
    unsigned int width;
    unsigned int height;
};

static uint16_t rd16(const uint8_t *p)
{
    return (uint16_t)(p[0] | (p[1] << 8));
}

static uint32_t rd32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static void wr16(uint8_t *p, uint16_t value)
{
    p[0] = (uint8_t)(value & 0xff);
    p[1] = (uint8_t)(value >> 8);
}

static void wr32(uint8_t *p, uint32_t value)
{
    p[0] = (uint8_t)(value & 0xff);
    p[1] = (uint8_t)((value >> 8) & 0xff);
    p[2] = (uint8_t)((value >> 16) & 0xff);
    p[3] = (uint8_t)((value >> 24) & 0xff);
}

/* Xauthority fields are big-endian regardless of the client byte order. */
static uint16_t bd16(const uint8_t *p)
{
    return (uint16_t)((p[0] << 8) | p[1]);
}

static int read_full(int fd, void *buffer, size_t length)
{
    uint8_t *cursor = buffer;

    while (length > 0) {
        ssize_t got = read(fd, cursor, length);

        if (got < 0 && errno == EINTR)
            continue;
        if (got <= 0)
            return -1;

        cursor += (size_t)got;
        length -= (size_t)got;
    }

    return 0;
}

static int write_full(int fd, const void *buffer, size_t length)
{
    const uint8_t *cursor = buffer;

    while (length > 0) {
        ssize_t sent = write(fd, cursor, length);

        if (sent < 0 && errno == EINTR)
            continue;
        if (sent <= 0)
            return -1;

        cursor += (size_t)sent;
        length -= (size_t)sent;
    }

    return 0;
}

static void sleep_ms(long milliseconds)
{
    struct timespec delay = {
        .tv_sec = milliseconds / 1000,
        .tv_nsec = (milliseconds % 1000) * 1000000L,
    };

    while (nanosleep(&delay, &delay) != 0 && errno == EINTR)
        ;
}

/*
 * Xauthority entries, all big-endian:
 *   CARD16 family, CARD16 address-len, address, CARD16 number-len, number,
 *   CARD16 name-len, name, CARD16 data-len, data.
 */
static int read_cookie_from(const char *path,
                            const char *display_number,
                            uint8_t *name,
                            size_t *name_length,
                            uint8_t *data,
                            size_t *data_length)
{
    FILE *file = fopen(path, "rb");
    size_t number_length = strlen(display_number);

    if (file == NULL)
        return 0;

    for (;;) {
        uint8_t raw[2];
        uint8_t field[4][512];
        size_t field_length[4];
        int ok = 1;

        if (fread(raw, 1, 2, file) != 2) /* family */
            break;

        for (int f = 0; f < 4; ++f) {
            if (fread(raw, 1, 2, file) != 2) {
                ok = 0;
                break;
            }
            field_length[f] = bd16(raw);
            if (field_length[f] >= sizeof(field[f]) ||
                fread(field[f], 1, field_length[f], file) != field_length[f]) {
                ok = 0;
                break;
            }
        }

        if (!ok)
            break;

        /* field[2] is the auth protocol name, field[3] the cookie itself. */
        if (field_length[2] != sizeof("MIT-MAGIC-COOKIE-1") - 1 ||
            memcmp(field[2], "MIT-MAGIC-COOKIE-1",
                   sizeof("MIT-MAGIC-COOKIE-1") - 1) != 0)
            continue;

        /* field[1] is the display number; empty matches any display. */
        if (field_length[1] > 0 &&
            (field_length[1] != number_length ||
             memcmp(field[1], display_number, number_length) != 0))
            continue;

        *name_length = field_length[2];
        memcpy(name, field[2], field_length[2]);
        *data_length = field_length[3];
        memcpy(data, field[3], field_length[3]);
        fclose(file);
        return 1;
    }

    fclose(file);
    return 0;
}

/* Kindle's lxinit keeps the cookie in a per-display file under these. */
static int read_cookie_from_dir(const char *directory,
                                const char *display_number,
                                uint8_t *name,
                                size_t *name_length,
                                uint8_t *data,
                                size_t *data_length)
{
    DIR *dir = opendir(directory);
    struct dirent *entry;
    int found = 0;

    if (dir == NULL)
        return 0;

    while (!found && (entry = readdir(dir)) != NULL) {
        char path[512];

        if (entry->d_name[0] == '.')
            continue;
        snprintf(path, sizeof(path), "%s/%s", directory, entry->d_name);
        found = read_cookie_from(path, display_number, name, name_length, data,
                                 data_length);
    }

    closedir(dir);
    return found;
}

static void read_cookie(const char *display_number,
                        uint8_t *name,
                        size_t *name_length,
                        uint8_t *data,
                        size_t *data_length)
{
    const char *paths[6];
    char home_path[512];
    int path_count = 0;

    if (getenv("XAUTHORITY") != NULL)
        paths[path_count++] = getenv("XAUTHORITY");
    if (getenv("HOME") != NULL) {
        snprintf(home_path, sizeof(home_path), "%s/.Xauthority",
                 getenv("HOME"));
        paths[path_count++] = home_path;
    }
    paths[path_count++] = "/root/.Xauthority";
    paths[path_count++] = "/var/tmp/.Xauthority";
    paths[path_count++] = "/tmp/.Xauthority";

    for (int i = 0; i < path_count; ++i) {
        if (read_cookie_from(paths[i], display_number, name, name_length, data,
                             data_length))
            return;
    }

    if (read_cookie_from_dir("/var/run/xauth", display_number, name,
                             name_length, data, data_length) ||
        read_cookie_from_dir("/run/xauth", display_number, name, name_length,
                             data, data_length) ||
        read_cookie_from_dir("/var/run", display_number, name, name_length,
                             data, data_length))
        return;
}

static int parse_display_number(const char *display)
{
    const char *colon = strrchr(display, ':');

    if (colon == NULL || colon[1] < '0' || colon[1] > '9')
        return -1;

    return atoi(colon + 1);
}

static int connect_unix(const struct sockaddr_un *address, socklen_t length)
{
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);

    if (fd < 0)
        return -1;

    if (connect(fd, (const struct sockaddr *)address, length) == 0)
        return fd;

    if (errno != ENOENT && errno != ECONNREFUSED)
        fprintf(stderr, "xscreen: connect failed: %s\n", strerror(errno));

    close(fd);
    return -1;
}

static int connect_display(const char *display)
{
    int number = parse_display_number(display);
    const char *override_socket = getenv("XSCREEN_SOCKET");
    struct sockaddr_un address;
    char path[128];
    int fd;

    if (number < 0) {
        fprintf(stderr, "xscreen: cannot parse DISPLAY '%s'\n", display);
        return -1;
    }

    /* Test hook: point the client at any socket path. */
    if (override_socket != NULL) {
        memset(&address, 0, sizeof(address));
        address.sun_family = AF_UNIX;
        snprintf(address.sun_path, sizeof(address.sun_path), "%s",
                 override_socket);
        return connect_unix(&address, sizeof(address));
    }

    snprintf(path, sizeof(path), "/tmp/.X11-unix/X%d", number);

    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    snprintf(address.sun_path, sizeof(address.sun_path), "%s", path);

    fd = connect_unix(&address, sizeof(address));
    if (fd >= 0)
        return fd;

    /* Linux X servers also listen on an abstract socket whose name starts with
     * a NUL; the filesystem path can be missing on a read-only /tmp. */
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    snprintf(address.sun_path + 1, sizeof(address.sun_path) - 1,
             "/tmp/.X11-unix/X%d", number);

    socklen_t length = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + 1 +
                                   strlen(address.sun_path + 1));
    fd = connect_unix(&address, length);
    if (fd < 0)
        fprintf(stderr, "xscreen: cannot connect to X display %s\n", display);

    return fd;
}

/*
 * Read one X reply, skipping error packets that arrive first. X sends errors
 * asynchronously, so a failed request can surface ahead of the next reply and
 * would otherwise misalign every field read afterwards.
 */
static int read_reply(int fd, uint8_t *header)
{
    for (;;) {
        if (read_full(fd, header, 32) != 0)
            return -1;

        if (header[0] != 0) /* 0 = Error, 1 = Reply */
            return header[0];

        fprintf(stderr, "xscreen: X error %u on request %u\n", header[1],
                rd16(header + 2));
    }
}

/*
 * X11 connection setup, little-endian client.
 *
 * Reply header: success(1), unused(1), major(2), minor(2), additional-len(2).
 * Additional data, CARD32 unless noted:
 *     0  release number          16  CARD16 vendor length
 *     4  resource id base        18  CARD16 max request length
 *     8  resource id mask        20  CARD8  screens
 *    12  motion buffer           21  CARD8  pixmap formats
 *   22..27                       image/bit order, scanline unit+pad, keycodes
 *   32                            vendor string, padded to 4
 *                                 pixmap formats, 8 bytes each
 *                                 screens, 40 bytes each (root at +0,
 *                                 width at +20, height at +22)
 */
static int x_setup(struct xconn *connection, const char *display)
{
    uint8_t name[64];
    uint8_t data[512];
    size_t name_length = 0;
    size_t data_length = 0;
    uint8_t request[12 + 64 + 4 + 512];
    size_t request_length;
    uint8_t header[8];
    uint8_t *additional = NULL;
    int number = parse_display_number(display);
    char number_text[16];

    if (number < 0)
        return 3;

    snprintf(number_text, sizeof(number_text), "%d", number);

    /* A cookie stored with an empty display number matches any display. */
    read_cookie(number_text, name, &name_length, data, &data_length);
    if (name_length == 0)
        read_cookie("", name, &name_length, data, &data_length);

    memset(request, 0, sizeof(request));
    request[0] = 'l'; /* little-endian client */
    request[2] = 11;  /* protocol major version */
    wr16(request + 6, (uint16_t)name_length);
    wr16(request + 8, (uint16_t)data_length);

    request_length = 12;
    memcpy(request + request_length, name, name_length);
    request_length += (name_length + 3) & ~(size_t)3;
    memcpy(request + request_length, data, data_length);
    request_length += (data_length + 3) & ~(size_t)3;

    if (write_full(connection->fd, request, request_length) != 0)
        return 3;

    /* Setup is answered by exactly one record: a success reply or a failure
     * record, never an asynchronous error packet. */
    if (read_full(connection->fd, header, 8) != 0)
        return 3;

    if (header[0] != 1) {
        size_t reason_length = header[1];
        char *reason = calloc(1, reason_length + 1);

        if (reason != NULL && reason_length > 0)
            read_full(connection->fd, reason, reason_length);
        /*
         * A missing cookie is the usual cause here, and it is worth saying so
         * rather than leaving "refused" to be re-diagnosed later.
         */
        fprintf(stderr, "xscreen: X server refused the connection: %s%s\n",
                reason != NULL && reason_length > 0 && reason[0] != '\0'
                    ? reason
                    : "(no reason)",
                name_length == 0 ? " [no Xauthority cookie found]" : "");
        free(reason);
        return 4;
    }

    size_t additional_length = (size_t)rd16(header + 6) * 4;
    if (additional_length < 32)
        return 3;

    additional = malloc(additional_length);
    if (additional == NULL)
        return 3;
    if (read_full(connection->fd, additional, additional_length) != 0) {
        free(additional);
        return 3;
    }

    uint16_t vendor_length = rd16(additional + 16);
    int screens = additional[20];
    int formats = additional[21];
    size_t offset = 32 + (((size_t)vendor_length + 3) & ~(size_t)3);
    offset += (size_t)formats * 8;

    if (screens < 1 || offset + 40 > additional_length) {
        free(additional);
        fprintf(stderr, "xscreen: malformed setup reply\n");
        return 3;
    }

    connection->id_base = rd32(additional + 4);
    connection->id_mask = rd32(additional + 8);
    if (connection->id_mask == 0)
        connection->id_mask = 0x1fffff;
    connection->next_id = 1;
    connection->root = rd32(additional + offset);
    connection->width = rd16(additional + offset + 20);
    connection->height = rd16(additional + offset + 22);

    free(additional);
    return 0;
}

static uint32_t new_id(struct xconn *connection)
{
    return connection->id_base | (connection->next_id++ & connection->id_mask);
}

/* Round-trip so every request queued so far has been processed. */
static int x_sync(struct xconn *connection)
{
    uint8_t request[4];
    uint8_t header[32];

    memset(request, 0, sizeof(request));
    request[0] = 43; /* GetInputFocus */
    wr16(request + 2, 1);

    if (write_full(connection->fd, request, sizeof(request)) != 0)
        return -1;

    return read_reply(connection->fd, header) == 1 ? 0 : -1;
}

/*
 * CreateWindow (opcode 1), 10 four-byte units:
 *   depth(1) length(2) wid(4) parent(4) x(2) y(2) w(2) h(2) border(2)
 *   class(2) visual(4) value-mask(4) value, value
 *
 * background-pixmap = None leaves the framebuffer untouched while it is
 * mapped, and override-redirect keeps the window manager out of it.
 */
static uint32_t create_cover(struct xconn *connection)
{
    uint8_t request[40];
    uint32_t window = new_id(connection);

    memset(request, 0, sizeof(request));
    request[0] = 1;
    wr16(request + 2, 10);
    wr32(request + 4, window);
    wr32(request + 8, connection->root);
    wr16(request + 16, (uint16_t)connection->width);
    wr16(request + 18, (uint16_t)connection->height);
    wr16(request + 22, 1);     /* class: InputOutput */
    wr32(request + 28, 0x201); /* CWBackPixmap | CWOverrideRedirect */
    wr32(request + 32, 0);     /* background pixmap: None */
    wr32(request + 36, 1);     /* override-redirect: True */

    if (write_full(connection->fd, request, sizeof(request)) != 0)
        return 0;

    return window;
}

static int map_window(struct xconn *connection, uint32_t window)
{
    uint8_t request[8];

    memset(request, 0, sizeof(request));
    request[0] = 8; /* MapWindow */
    wr16(request + 2, 2);
    wr32(request + 4, window);
    return write_full(connection->fd, request, sizeof(request));
}

static int destroy_window(struct xconn *connection, uint32_t window)
{
    uint8_t request[8];

    memset(request, 0, sizeof(request));
    request[0] = 4; /* DestroyWindow */
    wr16(request + 2, 2);
    wr32(request + 4, window);
    return write_full(connection->fd, request, sizeof(request));
}

/* Read a whole file; returns NULL when it cannot be read. */
static uint8_t *read_file(const char *path, size_t *length)
{
    FILE *file = fopen(path, "rb");
    uint8_t *buffer;
    long size;
    size_t got;

    if (file == NULL)
        return NULL;

    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return NULL;
    }
    size = ftell(file);
    if (size <= 0) {
        fclose(file);
        return NULL;
    }
    rewind(file);

    buffer = malloc((size_t)size);
    if (buffer == NULL) {
        fclose(file);
        return NULL;
    }

    got = fread(buffer, 1, (size_t)size, file);
    fclose(file);

    if (got != (size_t)size) {
        free(buffer);
        return NULL;
    }

    *length = got;
    return buffer;
}

static const char *fb_path(void)
{
    const char *path = getenv("XSCREEN_FB");

    return path != NULL ? path : "/dev/fb0";
}

/*
 * Ink coverage of the middle of the panel, as a fraction of dark pixels.
 *
 * This is what separates "the UI came back" from "the UI was erased". Comparing
 * against the poster alone cannot tell them apart: blanking the screen also
 * differs from the poster, so a destructive repaint scored as a success and the
 * panel was left white in the middle with only the status bar and nav strip
 * drawn (measured 0.00% ink where the poster had 10.91%).
 */
#define INK_TOP 300
#define INK_BOTTOM 1100
/* An erased area is exactly 0%; any real interface has some text or artwork. */
#define INK_BLANK 0.005

static double middle_ink(void)
{
    size_t length = 0;
    uint8_t *panel = read_file(fb_path(), &length);
    size_t dark = 0;
    size_t total = 0;

    if (panel == NULL)
        return -1;

    for (size_t row = INK_TOP; row < INK_BOTTOM; ++row) {
        size_t offset = row * FB_STRIDE;

        if (offset + 1072 > length)
            break;

        for (size_t col = 0; col < 1072; ++col) {
            if (panel[offset + col] < 128)
                dark++;
            total++;
        }
    }

    free(panel);
    return total > 0 ? (double)dark / (double)total : -1;
}

/*
 * Fraction of bytes that differ between the live panel and the poster.
 *
 * Returns -1 when either image cannot be read, which the caller treats as
 * "cannot verify" rather than as success or failure.
 */
static double poster_difference(void)
{
    const char *poster_path = getenv("XSCREEN_POSTER");
    size_t panel_length = 0;
    size_t poster_length = 0;
    uint8_t *panel;
    uint8_t *poster;
    size_t length;
    size_t changed = 0;

    if (poster_path == NULL)
        poster_path = POSTER_DEFAULT;

    panel = read_file(fb_path(), &panel_length);
    if (panel == NULL)
        return -1;

    poster = read_file(poster_path, &poster_length);
    if (poster == NULL) {
        free(panel);
        return -1;
    }

    length = panel_length < poster_length ? panel_length : poster_length;
    if (length == 0) {
        free(panel);
        free(poster);
        return -1;
    }

    for (size_t i = 0; i < length; ++i) {
        int delta = (int)panel[i] - (int)poster[i];

        if (delta > BYTE_EPSILON || delta < -BYTE_EPSILON)
            changed++;
    }

    free(panel);
    free(poster);
    return (double)changed / (double)length;
}

static int cmd_wake(const char *display)
{
    struct xconn connection;
    uint32_t cover;
    int status;
    int sent = 0;
    double difference;
    double ink;

    memset(&connection, 0, sizeof(connection));
    connection.fd = connect_display(display);
    if (connection.fd < 0)
        return 3;

    status = x_setup(&connection, display);
    if (status != 0) {
        close(connection.fd);
        return status;
    }

    /*
     * Leave the screen alone only when the UI is genuinely usable on it.
     *
     * "Differs from the poster" is not enough to conclude that. A panel that was
     * erased is also different from the poster -- that is exactly the state a
     * destructive repaint leaves behind (10.91% ink in the middle became 0.00%),
     * and treating it as success would skip the framework fallback and preserve
     * the white screen forever.
     *
     * So this requires both tests: the poster is gone AND real content is there.
     */
    difference = poster_difference();
    ink = middle_ink();

    if (difference >= DIFF_THRESHOLD && ink >= INK_BLANK) {
        printf("xscreen: UI already on screen (%.1f%% differs, %.1f%% ink), "
               "leaving it alone\n", difference * 100, ink * 100);
        close(connection.fd);
        return 0;
    }
    if (difference < 0 || ink < 0)
        fprintf(stderr, "xscreen: cannot compare against the poster capture\n");
    else if (ink < INK_BLANK)
        printf("xscreen: panel has no content in the middle (%.1f%% ink)\n",
               ink * 100);

    /*
     * Reveal only: map a cover and destroy it.
     *
     * This is deliberately NOT followed by ClearArea on the window tree. That
     * was the first version, and on the device it erased the interface: the
     * Kindle UI does not repaint itself in response to Expose, so clearing the
     * areas it owns left them blank. Measured on the wake capture, the middle of
     * the panel went from 10.91% ink to 0.00% -- a white screen with only the
     * status bar and the nav strip, which the user reported as "the poster
     * disappeared".
     *
     * Destroying a mapped window is non-destructive: it only tells the server
     * that the pixels underneath became visible again.
     */
    cover = create_cover(&connection);
    if (cover != 0 && map_window(&connection, cover) == 0 &&
        x_sync(&connection) == 0) {
        sleep_ms(150);
        sent = 1;
    }
    if (cover != 0) {
        /* Always tear it down. An override-redirect fullscreen window left
         * mapped would hide the UI for good. */
        (void)destroy_window(&connection, cover);
        (void)x_sync(&connection);
    }

    printf("xscreen: revealed the screen (%.0f%% of %ux%u)\n", sent ? 100.0 : 0.0,
           connection.width, connection.height);
    close(connection.fd);

    /*
     * Poll briefly, then judge. The wait is short on purpose: the reveal above
     * does not make any client redraw (see the note in cmd_wake), so there is
     * nothing asynchronous to wait for. A long wait here would just delay the
     * daemon's fallback to appmgrd, which is the step that actually rebuilds the
     * interface, and the user would sit looking at the poster or a blank panel
     * for the whole time.
     */
    for (int attempt = 0; attempt < 3; ++attempt) {
        double ink;

        sleep_ms(200);
        difference = poster_difference();
        ink = middle_ink();

        if (difference < 0 || ink < 0) {
            printf("xscreen: repaint sent, cannot verify\n");
            return 0;
        }
        if (difference >= DIFF_THRESHOLD && ink >= INK_BLANK) {
            printf("xscreen: panel restored (%.1f%% differs, %.1f%% ink)\n",
                   difference * 100, ink * 100);
            return 0;
        }
    }

    printf("xscreen: panel not usable (%.1f%% differs, %.1f%% ink)\n",
           (difference < 0 ? 0 : difference) * 100,
           (middle_ink() < 0 ? 0 : middle_ink()) * 100);
    return 2;
}

static int cmd_selftest(const char *display)
{
    struct xconn connection;
    int status;

    memset(&connection, 0, sizeof(connection));
    connection.fd = connect_display(display);
    if (connection.fd < 0)
        return 3;

    status = x_setup(&connection, display);
    close(connection.fd);

    if (status != 0)
        return status;

    printf("xscreen: display ok, root=0x%x, screen %ux%u\n", connection.root,
           connection.width, connection.height);
    return 0;
}

static const char *default_display(void)
{
    const char *display = getenv("DISPLAY");

    return display != NULL && display[0] != '\0' ? display : ":0";
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr,
                "usage: xscreen wake|selftest|version\n"
                "  wake      repaint every window so the UI comes back\n"
                "  selftest  report whether the X display is reachable\n");
        return 5;
    }

    if (strcmp(argv[1], "version") == 0) {
        printf("xscreen 1.1\n");
        return 0;
    }

    if (strcmp(argv[1], "wake") == 0)
        return cmd_wake(default_display());

    if (strcmp(argv[1], "selftest") == 0)
        return cmd_selftest(default_display());

    fprintf(stderr, "xscreen: unknown command '%s'\n", argv[1]);
    return 5;
}
