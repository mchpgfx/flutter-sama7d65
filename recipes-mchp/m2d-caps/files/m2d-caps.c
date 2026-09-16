// Print the 2D GPU's libm2d capabilities.
//
// These constrain any integration and are cheaper to read off the hardware than
// to discover halfway through writing a compositor. M2D_CAP_STRIDE_ALIGNMENT in
// particular dictates the row_bytes an m2d-allocated buffer must be given before
// Skia can rasterise into it.

#include <stdint.h>
#include <stdio.h>
#include <m2d/m2d.h>

struct cap {
	enum m2d_capability id;
	const char *name;
	const char *why;
};

static const struct cap caps[] = {
	{ M2D_CAP_STRIDE_ALIGNMENT,       "M2D_CAP_STRIDE_ALIGNMENT",
	  "row_bytes a GPU-visible buffer must be aligned to" },
	{ M2D_CAP_BLIT_MAX_SOURCES,       "M2D_CAP_BLIT_MAX_SOURCES",
	  "layers compositable in one pass" },
	{ M2D_CAP_PER_SOURCE_BLEND_PARAMS,"M2D_CAP_PER_SOURCE_BLEND_PARAMS",
	  "whether each source can blend differently" },
	{ M2D_CAP_DRAW_LINES,             "M2D_CAP_DRAW_LINES",
	  "hardware line drawing (charts?)" },
	{ M2D_CAP_STRETCHED_BLIT,         "M2D_CAP_STRETCHED_BLIT",
	  "hardware scaling - the 131-190ms image case" },
};

int main(void)
{
	if (m2d_init() != 0) {
		fprintf(stderr, "m2d-caps: m2d_init() failed - is nano2d loaded "
				"and /dev/nano2d present?\n");
		return 1;
	}

	printf("M2DCAPS,pixel_formats,%s|%s|%s\n",
	       m2d_format_name(M2D_PF_ARGB8888),
	       m2d_format_name(M2D_PF_RGB565),
	       m2d_format_name(M2D_PF_A8));

	for (unsigned i = 0; i < sizeof(caps) / sizeof(caps[0]); i++) {
		uint32_t v = 0;
		int rc = m2d_get_capability(caps[i].id, &v);
		if (rc == 0)
			printf("M2DCAPS,%s,%u    (%s)\n", caps[i].name, v, caps[i].why);
		else
			printf("M2DCAPS,%s,UNSUPPORTED rc=%d    (%s)\n",
			       caps[i].name, rc, caps[i].why);
	}

	m2d_cleanup();
	return 0;
}
