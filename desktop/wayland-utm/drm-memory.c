/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 EmberBSD contributors. */
/* Origin: EmberBSD, AI-assisted. Native GEM/PRIME process-lifetime probe. */
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <xf86drm.h>
#include <drm.h>
#include <drm_mode.h>

static uint32_t
pattern(size_t i)
{

	return UINT32_C(0x5a000000) ^ (uint32_t)i * UINT32_C(0x10203);
}

static void
check(const uint32_t *mapping, size_t size)
{
	size_t i;

	for (i = 0; i < size / sizeof(*mapping); i++)
		if (mapping[i] != pattern(i))
			errx(1, "memory mismatch at word %zu: %08x != %08x",
			    i, mapping[i], pattern(i));
}

static void
signal_peer(int fd)
{
	const char byte = 'x';

	if (write(fd, &byte, 1) != 1)
		err(1, "write lifetime handshake");
}

static void
wait_peer(int fd)
{
	char byte;

	if (read(fd, &byte, 1) != 1)
		errx(1, "peer exited before lifetime handshake");
}

static uint32_t *
map_handle(int fd, uint32_t handle, size_t size)
{
	struct drm_mode_map_dumb request = { .handle = handle };
	void *mapping;

	if (drmIoctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &request) < 0)
		err(1, "MAP_DUMB");
	mapping = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED,
	    fd, (off_t)request.offset);
	if (mapping == MAP_FAILED)
		err(1, "GEM mmap");
	return mapping;
}

static void
roundtrip(const char *path, uint32_t width, uint32_t height)
{
	struct drm_mode_create_dumb create = {
		.width = width, .height = height, .bpp = 32
	};
	struct drm_gem_close close_handle = { 0 };
	uint32_t *original, *shared, *imported;
	uint32_t handle;
	size_t size, i;
	int fd, prime, child_fd, to_child[2], from_child[2], status;
	pid_t child;

	alarm(30);
	fd = open(path, O_RDWR | O_CLOEXEC);
	if (fd < 0)
		err(1, "open %s", path);
	if (drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &create) < 0)
		err(1, "CREATE_DUMB %ux%u", width, height);
	if (create.size > SIZE_MAX || create.size == 0)
		errx(1, "invalid size returned by CREATE_DUMB");
	size = (size_t)create.size;
	original = map_handle(fd, create.handle, size);
	for (i = 0; i < size / sizeof(*original); i++)
		original[i] = pattern(i);
	if (drmPrimeHandleToFD(fd, create.handle, DRM_CLOEXEC | DRM_RDWR, &prime) < 0)
		err(1, "PRIME_HANDLE_TO_FD");
	if (pipe(to_child) < 0 || pipe(from_child) < 0)
		err(1, "pipe");
	child = fork();
	if (child < 0)
		err(1, "fork");
	if (child == 0) {
		alarm(30);
		close(to_child[1]);
		close(from_child[0]);
		munmap(original, size);
		close(fd);
		child_fd = open(path, O_RDWR | O_CLOEXEC);
		if (child_fd < 0)
			err(1, "child open");
		if (drmPrimeFDToHandle(child_fd, prime, &handle) < 0)
			err(1, "PRIME_FD_TO_HANDLE on independent DRM file");
		shared = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, prime, 0);
		if (shared == MAP_FAILED)
			err(1, "PRIME fd mmap");
		imported = map_handle(child_fd, handle, size);
		close_handle.handle = handle;
		if (drmIoctl(child_fd, DRM_IOCTL_GEM_CLOSE, &close_handle) < 0)
			err(1, "child GEM_CLOSE");
		close(child_fd);
		close(prime);
		signal_peer(from_child[1]);
		wait_peer(to_child[0]);
		/* Only the child's two mappings remain after the parent handshake. */
		check(shared, size);
		check(imported, size);
		shared[0] ^= UINT32_C(0xffffffff);
		if (imported[0] != shared[0])
			errx(1, "PRIME import aliases a different object");
		munmap(shared, size);
		if (imported[0] != (pattern(0) ^ UINT32_C(0xffffffff)))
			errx(1, "remaining mapping lost after other mapping closed");
		munmap(imported, size);
		_exit(0);
	}
	close(to_child[0]);
	close(from_child[1]);
	wait_peer(from_child[0]);
	close_handle.handle = create.handle;
	if (drmIoctl(fd, DRM_IOCTL_GEM_CLOSE, &close_handle) < 0)
		err(1, "parent GEM_CLOSE");
	munmap(original, size);
	close(prime);
	close(fd);
	signal_peer(to_child[1]);
	close(to_child[1]);
	close(from_child[0]);
	if (waitpid(child, &status, 0) != child || !WIFEXITED(status) || WEXITSTATUS(status) != 0)
		errx(1, "PRIME child failed");
	alarm(0);
}

static void
invalid_requests(const char *path)
{
	struct drm_mode_create_dumb create = { .width = 0, .height = 1, .bpp = 32 };
	struct drm_mode_map_dumb map = { .handle = 0 };
	int fd;

	fd = open(path, O_RDWR | O_CLOEXEC);
	if (fd < 0)
		err(1, "open %s", path);
	if (drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &create) != -1 || errno != EINVAL)
		errx(1, "zero-width buffer was not rejected with EINVAL");
	create.width = UINT32_MAX;
	create.height = UINT32_MAX;
	if (drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &create) != -1 || errno != EINVAL)
		errx(1, "overflowing buffer was not rejected with EINVAL");
	if (drmIoctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &map) != -1 || errno != ENOENT)
		errx(1, "invalid GEM handle was not rejected with ENOENT");
	close(fd);
}

int
main(int argc, char **argv)
{
	int iteration;

	if (argc != 2)
		errx(2, "usage: drm-memory DRM_PRIMARY_NODE");
	invalid_requests(argv[1]);
	for (iteration = 0; iteration < 16; iteration++) {
		roundtrip(argv[1], 64, 16);
		roundtrip(argv[1], 2048, 1024);
	}
	puts("PASS: malformed requests and 32 cross-process GEM/PRIME mapping lifetimes");
	puts("This is a memory/ABI check; visible scanout and GPU rendering are separate.");
	return 0;
}
