/* Origin: EmberBSD; AI-assisted EGL/GBM pixel readback check. */
/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 EmberBSD contributors. */

#include <sys/types.h>
#include <err.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <gbm.h>

#define SIDE 64

static void
egl_failure(const char *operation)
{

	errx(1, "%s: EGL error 0x%x", operation, eglGetError());
}

int
main(int argc, char **argv)
{
	static const EGLint config_attributes[] = {
		EGL_SURFACE_TYPE, 0, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
		EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
		EGL_ALPHA_SIZE, 8, EGL_NONE
	};
	static const EGLint context_attributes[] = {
		EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE
	};
	static const unsigned char colors[4][4] = {
		{255, 0, 0, 255}, {0, 255, 0, 255},
		{0, 0, 255, 255}, {255, 255, 255, 255}
	};
	PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display;
	struct gbm_device *gbm = NULL;
	EGLDisplay display;
	EGLContext context;
	EGLConfig config;
	EGLint count, major, minor;
	GLuint texture, framebuffer;
	unsigned char pixels[SIDE * SIDE * 4];
	const char *renderer;
	int fd = -1, software, frame, quadrant, x, y, channel;

	if (argc != 2)
		errx(2, "usage: egl-readback DRM_RENDER_NODE | --software");
	software = strcmp(argv[1], "--software") == 0;
	get_platform_display = (PFNEGLGETPLATFORMDISPLAYEXTPROC)
	    eglGetProcAddress("eglGetPlatformDisplayEXT");
	if (get_platform_display == NULL)
		errx(1, "EGL_EXT_platform_base is unavailable");
	if (software) {
		display = get_platform_display(EGL_PLATFORM_SURFACELESS_MESA,
		    EGL_DEFAULT_DISPLAY, NULL);
	} else {
		fd = open(argv[1], O_RDWR | O_CLOEXEC);
		if (fd < 0)
			err(1, "open %s", argv[1]);
		gbm = gbm_create_device(fd);
		if (gbm == NULL)
			errx(1, "gbm_create_device failed");
		display = get_platform_display(EGL_PLATFORM_GBM_KHR, gbm, NULL);
	}
	if (display == EGL_NO_DISPLAY || !eglInitialize(display, &major, &minor))
		egl_failure("eglInitialize");
	if (!eglBindAPI(EGL_OPENGL_ES_API))
		egl_failure("eglBindAPI");
	if (!eglChooseConfig(display, config_attributes, &config, 1, &count) || count != 1)
		egl_failure("eglChooseConfig");
	context = eglCreateContext(display, config, EGL_NO_CONTEXT, context_attributes);
	if (context == EGL_NO_CONTEXT)
		egl_failure("eglCreateContext");
	if (!eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context))
		egl_failure("eglMakeCurrent without a surface");
	renderer = (const char *)glGetString(GL_RENDERER);
	if (renderer == NULL)
		errx(1, "GL_RENDERER unavailable");
	printf("EGL %d.%d\nGL_VENDOR: %s\nGL_RENDERER: %s\nGL_VERSION: %s\n",
	    major, minor, glGetString(GL_VENDOR), renderer, glGetString(GL_VERSION));
	if (!software && (strstr(renderer, "virgl") == NULL ||
	    strstr(renderer, "llvmpipe") != NULL || strstr(renderer, "softpipe") != NULL))
		errx(1, "a VirGL renderer is required for the GPU check");

	/* Reallocate and read every pixel, exercising object and transfer lifetime. */
	for (frame = 0; frame < 64; frame++) {
		glGenTextures(1, &texture);
		glBindTexture(GL_TEXTURE_2D, texture);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, SIDE, SIDE, 0,
		    GL_RGBA, GL_UNSIGNED_BYTE, NULL);
		glGenFramebuffers(1, &framebuffer);
		glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
		    GL_TEXTURE_2D, texture, 0);
		if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
			errx(1, "incomplete framebuffer at frame %d", frame);
		glEnable(GL_SCISSOR_TEST);
		for (quadrant = 0; quadrant < 4; quadrant++) {
			const unsigned char *color = colors[(quadrant + frame) % 4];
			glScissor((quadrant % 2) * (SIDE / 2),
			    (quadrant / 2) * (SIDE / 2), SIDE / 2, SIDE / 2);
			glClearColor(color[0] / 255.f, color[1] / 255.f,
			    color[2] / 255.f, 1.f);
			glClear(GL_COLOR_BUFFER_BIT);
		}
		glDisable(GL_SCISSOR_TEST);
		glFinish();
		memset(pixels, 0x5a, sizeof(pixels));
		glReadPixels(0, 0, SIDE, SIDE, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
		if (glGetError() != GL_NO_ERROR)
			errx(1, "GL operation failed at frame %d", frame);
		for (y = 0; y < SIDE; y++) {
			for (x = 0; x < SIDE; x++) {
				quadrant = (y / (SIDE / 2)) * 2 + x / (SIDE / 2);
				for (channel = 0; channel < 4; channel++) {
					int expected = colors[(quadrant + frame) % 4][channel];
					int actual = pixels[(y * SIDE + x) * 4 + channel];
					if (abs(actual - expected) > 1)
						errx(1, "frame %d pixel %d,%d channel %d: %d != %d",
						    frame, x, y, channel, actual, expected);
				}
			}
		}
		glDeleteFramebuffers(1, &framebuffer);
		glDeleteTextures(1, &texture);
	}
	if (!eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT))
		egl_failure("release context");
	eglDestroyContext(display, context);
	eglTerminate(display);
	if (gbm != NULL)
		gbm_device_destroy(gbm);
	if (fd >= 0)
		close(fd);
	printf("PASS: 64 allocations, four-color rendering and complete pixel readback (%s).\n",
	    software ? "software plumbing only" : "VirGL; verify host GPU separately");
	return 0;
}
