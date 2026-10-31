/*
 * xredraw.c
 *
 * Force every X window to repaint, the way xrefresh(1) does.
 *
 * The Kindle UI runs on Xorg. FBInk writes straight to /dev/fb0 underneath it,
 * so the X server never learns that the pixels changed. On wake from a custom
 * screensaver the stock scripts call `xrefresh` to make X repaint; this device
 * does not ship xrefresh, so the screen stayed on whatever FBInk last wrote
 * (white), which is the white-screen-after-wake bug.
 *
 * xrefresh's approach, reproduced here: walk the window tree and XClearArea
 * each window with exposures enabled. The server then sends Expose events and
 * every client repaints itself.
 */

#include <X11/Xlib.h>

#include <stdio.h>
#include <stdlib.h>

static void
    refresh_tree(Display* display, Window window) {
	Window	      root, parent, *children = NULL;
	unsigned int  count = 0;

	if (XQueryTree(display, window, &root, &parent, &children, &count) && children != NULL) {
		for (unsigned int i = 0; i < count; i++) {
			refresh_tree(display, children[i]);
		}
		XFree(children);
	}

	// exposures = True: the client receives an Expose and redraws its content.
	XClearArea(display, window, 0, 0, 0, 0, True);
}

int
    main(void) {
	Display* display = XOpenDisplay(NULL);
	if (display == NULL) {
		fprintf(stderr, "xredraw: cannot open X display\n");
		return 1;
	}

	refresh_tree(display, XDefaultRootWindow(display));
	XSync(display, False);
	XCloseDisplay(display);
	return 0;
}
