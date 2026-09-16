// Block until the SAMA7D65 Curiosity USER button (PC10) is pressed, then exit 0.
//
// The board DTS exposes it through gpio-keys:
//     button { label = "PB_USER"; gpios = <&pioa PIN_PC10 GPIO_ACTIVE_LOW>;
//              linux,code = <KEY_0>; wakeup-source; };
// so it arrives as an ordinary evdev key event and needs no GPIO access. Note the
// keycode really is KEY_0 (the digit zero), not a dedicated button code.
//
// The device is found by name rather than hardcoding /dev/input/event0, because
// enumeration order is not guaranteed. ivi-homescreen also reads this device via
// libinput; evdev delivers to all readers, so both see the press.

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define TARGET_CODE KEY_0
#define DEV_NAME_MATCH "gpio-keys"

static int open_button_device(char *path_out, size_t path_len)
{
	DIR *dir = opendir("/dev/input");
	if (!dir) {
		fprintf(stderr, "userbtn-wait: /dev/input: %s\n", strerror(errno));
		return -1;
	}

	struct dirent *de;
	while ((de = readdir(dir)) != NULL) {
		if (strncmp(de->d_name, "event", 5) != 0)
			continue;

		char path[280];
		snprintf(path, sizeof(path), "/dev/input/%s", de->d_name);

		int fd = open(path, O_RDONLY);
		if (fd < 0)
			continue;

		char name[256] = {0};
		if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) >= 0 &&
		    strstr(name, DEV_NAME_MATCH) != NULL) {
			snprintf(path_out, path_len, "%s (%s)", path, name);
			closedir(dir);
			return fd;
		}
		close(fd);
	}

	closedir(dir);
	fprintf(stderr, "userbtn-wait: no input device matching '%s'\n",
		DEV_NAME_MATCH);
	return -1;
}

int main(void)
{
	char which[340] = {0};
	int fd = open_button_device(which, sizeof(which));
	if (fd < 0)
		return 1;

	printf("userbtn-wait: watching %s for KEY_%d press\n", which, TARGET_CODE);
	fflush(stdout);

	struct input_event ev;
	for (;;) {
		ssize_t n = read(fd, &ev, sizeof(ev));
		if (n == (ssize_t)sizeof(ev)) {
			/* value 1 = press, 2 = autorepeat, 0 = release */
			if (ev.type == EV_KEY && ev.code == TARGET_CODE && ev.value == 1) {
				close(fd);
				return 0;
			}
		} else if (n < 0 && errno != EINTR) {
			fprintf(stderr, "userbtn-wait: read: %s\n", strerror(errno));
			close(fd);
			return 1;
		}
	}
}
