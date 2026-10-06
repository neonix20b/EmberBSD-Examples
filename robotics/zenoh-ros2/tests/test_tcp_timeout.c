/* Regression for the Ports POSIX send-timeout patch; internal API is version-pinned. */
#include <sys/socket.h>
#include <sys/wait.h>
#include <arpa/inet.h>
#include <assert.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <zenoh-pico.h>
#include <zenoh-pico/link/transport/tcp.h>

int
main(int argc, char **argv)
{
	struct sockaddr_in address = {0};
	socklen_t length = sizeof(address);
	_z_sys_net_endpoint_t endpoint;
	_z_sys_net_socket_t connection, listening;
	struct pollfd ready;
	uint8_t bytes[65536] = {0};
	char port[16];
	pid_t child;
	int listener, peer, small = 4096, status;
	unsigned int writes = 0;
	int accepting;

	assert(argc == 2);
	assert(strcmp(argv[1], "connect") == 0 || strcmp(argv[1], "accept") == 0);
	accepting = strcmp(argv[1], "accept") == 0;

	listener = socket(AF_INET, SOCK_STREAM, 0);
	assert(listener >= 0);
	address.sin_family = AF_INET;
	address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	assert(bind(listener, (struct sockaddr *)&address, sizeof(address)) == 0);
	assert(getsockname(listener, (struct sockaddr *)&address, &length) == 0);
	assert(listen(listener, 1) == 0);
	snprintf(port, sizeof(port), "%u", ntohs(address.sin_port));
	child = fork();
	assert(child >= 0);
	if (child == 0) {
		if (accepting) {
			peer = socket(AF_INET, SOCK_STREAM, 0);
			if (peer < 0 || connect(peer, (struct sockaddr *)&address, sizeof(address)) != 0)
				_exit(1);
		} else {
			peer = accept(listener, NULL, NULL);
		}
		if (peer < 0) _exit(1);
		(void)setsockopt(peer, SOL_SOCKET, SO_RCVBUF, &small, sizeof(small));
		sleep(4); /* Deliberately never read. Unpatched send exceeds the parent alarm. */
		close(peer); close(listener); _exit(0);
	}
	assert(_z_tcp_endpoint_init(&endpoint, "127.0.0.1", port) == 0);
	if (accepting) {
		listening._fd = listener;
		ready.fd = listener;
		ready.events = POLLIN;
		ready.revents = 0;
		assert(poll(&ready, 1, 2000) == 1);
		assert(_z_tcp_accept(&listening, &connection) == 0);
	} else {
		assert(_z_tcp_open(&connection, endpoint, 100) == 0);
	}
	assert(setsockopt(connection._fd, SOL_SOCKET, SO_SNDBUF, &small, sizeof(small)) == 0);
	alarm(2);
	while (_z_tcp_write(connection, bytes, sizeof(bytes)) != SIZE_MAX) {
		assert(++writes < 4096);
	}
	alarm(0);
	_z_tcp_close(&connection);
	_z_tcp_endpoint_clear(&endpoint);
	close(listener);
	assert(waitpid(child, &status, 0) == child);
	assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
	puts("PASS: a full TCP send buffer returns before the 2 s deadline");
	return 0;
}
