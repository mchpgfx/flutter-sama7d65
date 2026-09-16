// Block until the SAMA7D65 Curiosity USER button (PC10) is pressed, then exit 0.
//
// The board DTS exposes it through gpio-keys:
//     gpio-keys {
//         compatible = "gpio-keys";
//         button { label = "PB_USER"; gpios = <&pioa PIN_PC10 GPIO_ACTIVE_LOW>;
//                  linux,code = <KEY_0>; wakeup-source; };
//     };
// so it arrives as an ordinary evdev key event and needs no GPIO access. Note the
// keycode really is KEY_0 (the digit zero), not a dedicated button code.
//
// The device is found by CAPABILITY, not by name. Matching on the name "gpio-keys"
// looks obvious and does not work: gpio_keys.c does
//     input->name = pdata->name ? : pdev->name;
// where pdata->name is the "label" property of the gpio-keys NODE - which this DTS
// does not set, it labels only the child button - so it falls back to pdev->name,
// and of_device_alloc() creates OF platform devices via platform_device_alloc("", ..).
// The result is an input device whose name is the EMPTY STRING. Any name match fails.
//
// So instead: ask each device which keys it can emit (EVIOCGBIT) and take the one
// that can emit KEY_0. A USB keyboard can also emit KEY_0, so a device that also has
// letter keys is treated as a lower-priority fallback and the bare button wins.
//
// Exit codes are meaningful to the caller: 0 = pressed, 2 = no usable device, 3 = read
// error. The launcher must distinguish these, or a setup failure looks like a press.

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define TARGET_CODE KEY_0

#define EXIT_PRESSED   0
#define EXIT_NO_DEVICE 2
#define EXIT_READ_ERR  3

#define NBITS(x) ((((x) - 1) / (sizeof(long) * 8)) + 1)
#define TESTBIT(bit, array) \
	((array[(bit) / (sizeof(long) * 8)] >> ((bit) % (sizeof(long) * 8))) & 1)

/* Can this fd emit TARGET_CODE? Returns 0 no, 1 yes, 2 yes-but-looks-like-a-keyboard. */
static int rates(int fd)
{
	unsigned long evbit[NBITS(EV_MAX)];
	unsigned long keybit[NBITS(KEY_MAX)];

	memset(evbit, 0, sizeof(evbit));
	if (ioctl(fd, EVIOCGBIT(0, sizeof(evbit)), evbit) < 0)
		return 0;
	if (!TESTBIT(EV_KEY, evbit))
		return 0;

	memset(keybit, 0, sizeof(keybit));
	if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keybit)), keybit) < 0)
		return 0;
	if (!TESTBIT(TARGET_CODE, keybit))
		return 0;

	/* A real keyboard has letters; a one-button gpio-keys node does not. */
	if (TESTBIT(KEY_A, keybit) || TESTBIT(KEY_Z, keybit))
		return 2;
	return 1;
}

static int open_button_device(char *path_out, size_t path_len)
{
	DIR *dir = opendir("/dev/input");
	if (!dir) {
		fprintf(stderr, "userbtn-wait: /dev/input: %s\n", strerror(errno));
		return -1;
	}

	int best_fd = -1, best_rank = 0;
	char best[300] = {0};
	struct dirent *de;

	while ((de = readdir(dir)) != NULL) {
		if (strncmp(de->d_name, "event", 5) != 0)
			continue;

		char path[280];
		snprintf(path, sizeof(path), "/dev/input/%s", de->d_name);

		int fd = open(path, O_RDONLY);
		if (fd < 0) {
			fprintf(stderr, "userbtn-wait: %s: %s\n", path, strerror(errno));
			continue;
		}

		char name[256] = {0};
		if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) < 0)
			name[0] = '\0';

		int rank = rates(fd);
		fprintf(stderr, "userbtn-wait: %s name='%s' KEY_%d=%s\n",
			path, name, TARGET_CODE,
			rank == 1 ? "yes" : rank == 2 ? "yes (keyboard-like)" : "no");

		/* rank 1 beats rank 2; first of equal rank wins. */
		if (rank != 0 && (best_rank == 0 || rank < best_rank)) {
			if (best_fd >= 0)
				close(best_fd);
			best_fd = fd;
			best_rank = rank;
			snprintf(best, sizeof(best), "%s (name='%s')", path, name);
			continue;
		}
		close(fd);
	}
	closedir(dir);

	if (best_fd < 0) {
		fprintf(stderr, "userbtn-wait: no input device can emit KEY_%d\n",
			TARGET_CODE);
		return -1;
	}
	snprintf(path_out, path_len, "%s", best);
	return best_fd;
}

int main(void)
{
	char which[320] = {0};
	int fd = open_button_device(which, sizeof(which));
	if (fd < 0)
		return EXIT_NO_DEVICE;

	printf("userbtn-wait: watching %s for KEY_%d press\n", which, TARGET_CODE);
	fflush(stdout);

	struct input_event ev;
	for (;;) {
		ssize_t n = read(fd, &ev, sizeof(ev));
		if (n == (ssize_t)sizeof(ev)) {
			/* value 1 = press, 2 = autorepeat, 0 = release */
			if (ev.type == EV_KEY && ev.code == TARGET_CODE && ev.value == 1) {
				close(fd);
				return EXIT_PRESSED;
			}
		} else if (n < 0 && errno != EINTR) {
			fprintf(stderr, "userbtn-wait: read: %s\n", strerror(errno));
			close(fd);
			return EXIT_READ_ERR;
		}
	}
}
