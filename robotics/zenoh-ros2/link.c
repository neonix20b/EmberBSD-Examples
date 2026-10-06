#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <zenoh-pico.h>
#include "link.h"

struct robot_link {
	z_owned_session_t session;
	z_owned_subscriber_t sub;
	robot_receive_fn receive;
	void *context;
};
static const char *keys[] = { "", "ember/robotics/v1/demo/state",
    "ember/robotics/v1/demo/command", "ember/robotics/v1/demo/ack" };

uint64_t
robot_now_ms(void)
{
	struct timespec t;
	if (clock_gettime(CLOCK_MONOTONIC, &t) != 0) {
		perror("clock_gettime");
		abort();
	}
	return (uint64_t)t.tv_sec * 1000 + (uint64_t)t.tv_nsec / 1000000;
}

static void
receive_sample(z_loaned_sample_t *sample, void *context)
{
	struct robot_link *link = context;
	struct robot_frame frame;
	uint8_t wire[ROBOT_WIRE_SIZE];
	z_bytes_reader_t reader;
	z_view_string_t key;

	if (z_sample_kind(sample) != Z_SAMPLE_KIND_PUT ||
	    z_bytes_len(z_sample_payload(sample)) != sizeof(wire))
		return;
	reader = z_bytes_get_reader(z_sample_payload(sample));
	if (z_bytes_reader_read(&reader, wire, sizeof(wire)) != sizeof(wire) ||
	    robot_decode(&frame, wire, sizeof(wire)) != 0)
		return;
	z_keyexpr_as_view_string(z_sample_keyexpr(sample), &key);
	if (z_string_len(z_loan(key)) != strlen(keys[frame.kind]) ||
	    memcmp(z_string_data(z_loan(key)), keys[frame.kind], strlen(keys[frame.kind])) != 0)
		return;
	link->receive(&frame, link->context);
}

struct robot_link *
robot_link_open(const char *endpoint, int listen, robot_receive_fn receive, void *context)
{
	struct robot_link *link;
	z_owned_config_t config;
	z_owned_closure_sample_t callback;
	z_view_keyexpr_t key;

	if (strncmp(endpoint, "tcp/", 4) != 0 || receive == NULL)
		return NULL;
	link = calloc(1, sizeof(*link));
	if (link == NULL)
		return NULL;
	link->receive = receive;
	link->context = context;
	z_config_default(&config);
	if (zp_config_insert(z_loan_mut(config), Z_CONFIG_MODE_KEY, listen ? "peer" : "client") < 0 ||
	    zp_config_insert(z_loan_mut(config), Z_CONFIG_MULTICAST_SCOUTING_KEY, "false") < 0 ||
	    zp_config_insert(z_loan_mut(config), listen ? Z_CONFIG_LISTEN_KEY :
	    Z_CONFIG_CONNECT_KEY, endpoint) < 0) {
		z_drop(z_move(config));
		free(link);
		return NULL;
	}
	if (z_open(&link->session, z_move(config), NULL) < 0) {
		free(link);
		return NULL;
	}
	z_view_keyexpr_from_str(&key, "ember/robotics/v1/demo/**");
	z_closure(&callback, receive_sample, NULL, link);
	if (z_declare_subscriber(z_loan(link->session), &link->sub, z_loan(key),
	    z_move(callback), NULL) < 0) {
		z_drop(z_move(link->session));
		free(link);
		return NULL;
	}
	return link;
}

int
robot_link_put(struct robot_link *link, const struct robot_frame *frame)
{
	uint8_t wire[ROBOT_WIRE_SIZE];
	z_owned_bytes_t payload;
	z_view_keyexpr_t key;
	z_put_options_t options;
	if (frame->kind < ROBOT_STATE || frame->kind > ROBOT_ACK)
		return -1;
	robot_encode(wire, frame);
	if (z_bytes_copy_from_buf(&payload, wire, sizeof(wire)) < 0)
		return -1;
	z_view_keyexpr_from_str(&key, keys[frame->kind]);
	z_put_options_default(&options);
	options.congestion_control = Z_CONGESTION_CONTROL_DROP;
	options.is_express = true;
	return z_put(z_loan(link->session), z_loan(key), z_move(payload), &options);
}

void
robot_link_close(struct robot_link *link)
{
	if (link != NULL) {
		z_drop(z_move(link->sub));
		z_drop(z_move(link->session));
		free(link);
	}
}
