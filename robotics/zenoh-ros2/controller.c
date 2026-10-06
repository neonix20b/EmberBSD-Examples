#include <errno.h>
#include <inttypes.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "link.h"

struct controller {
	pthread_mutex_t mutex;
	struct robot_frame state;
	struct robot_link *link;
};
static volatile sig_atomic_t stopping;

static void
stop(int sig)
{
	(void)sig;
	stopping = 1;
}

static void
command_received(const struct robot_frame *command, void *context)
{
	struct controller *controller = context;
	struct robot_frame ack;
	if (command->kind != ROBOT_COMMAND)
		return;
	pthread_mutex_lock(&controller->mutex);
	ack.status = robot_apply(&controller->state, command, robot_now_ms());
	ack.kind = ROBOT_ACK;
	ack.boot = controller->state.boot;
	ack.stamp_ms = robot_now_ms();
	ack.command_id = command->command_id;
	ack.measured = controller->state.measured;
	ack.setpoint = controller->state.setpoint;
	ack.applied = controller->state.applied;
	printf("ACK id=%" PRIu64 " status=%u applied=%u setpoint=%" PRId32 "\n",
	    ack.command_id, ack.status, ack.applied, ack.setpoint);
	pthread_mutex_unlock(&controller->mutex);
	/* The main thread installs link before releasing the initialization lock. */
	if (robot_link_put(controller->link, &ack) < 0)
		fprintf(stderr, "Acknowledgement was not sent\n");
}

int
main(int argc, char **argv)
{
	struct controller controller = { .mutex = PTHREAD_MUTEX_INITIALIZER };
	struct robot_frame snapshot;
	FILE *random;
	if (argc != 2) {
		fprintf(stderr, "Usage: robot-controller tcp/LISTEN_ADDRESS:PORT\n");
		return 2;
	}
	setvbuf(stdout, NULL, _IOLBF, 0);
	random = fopen("/dev/urandom", "rb");
	if (random == NULL || fread(&controller.state.boot, sizeof(uint64_t), 1, random) != 1) {
		fprintf(stderr, "Cannot obtain boot identity\n");
		return 1;
	}
	fclose(random);
	if (controller.state.boot == 0)
		return 1;
	controller.state.kind = ROBOT_STATE;
	controller.state.setpoint = 20000;
	signal(SIGINT, stop); signal(SIGTERM, stop);
	pthread_mutex_lock(&controller.mutex);
	controller.link = robot_link_open(argv[1], 1, command_received, &controller);
	pthread_mutex_unlock(&controller.mutex);
	if (controller.link == NULL) {
		fprintf(stderr, "Cannot open Zenoh listener\n");
		return 1;
	}
	printf("READY simulated controller boot=%" PRIu64 "\n", controller.state.boot);
	while (!stopping) {
		pthread_mutex_lock(&controller.mutex);
		controller.state.stamp_ms = robot_now_ms();
		controller.state.measured = 22000 + (int32_t)(controller.state.stamp_ms / 250 % 1000);
		snapshot = controller.state;
		pthread_mutex_unlock(&controller.mutex);
		if (robot_link_put(controller.link, &snapshot) < 0)
			fprintf(stderr, "State was not sent; waiting for peer recovery\n");
		usleep(250000);
	}
	robot_link_close(controller.link);
	pthread_mutex_destroy(&controller.mutex);
	return 0;
}
