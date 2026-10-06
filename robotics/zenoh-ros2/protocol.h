#ifndef EMBER_ROBOT_PROTOCOL_H
#define EMBER_ROBOT_PROTOCOL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ROBOT_WIRE_SIZE 44
#define ROBOT_MAX_AGE_MS 1000
enum robot_kind { ROBOT_STATE = 1, ROBOT_COMMAND = 2, ROBOT_ACK = 3 };
enum robot_status {
	ROBOT_OK = 0, ROBOT_BOOT = 1, ROBOT_EXPIRED = 2,
	ROBOT_REPLAY = 3, ROBOT_RANGE = 4, ROBOT_EXHAUSTED = 5
};
struct robot_frame {
	uint8_t kind, status;
	uint64_t boot, stamp_ms, command_id;
	int32_t measured, setpoint;
	uint32_t applied;
};
int robot_decode(struct robot_frame *, const uint8_t *, size_t);
void robot_encode(uint8_t [ROBOT_WIRE_SIZE], const struct robot_frame *);
enum robot_status robot_apply(struct robot_frame *, const struct robot_frame *,
    uint64_t);

#ifdef __cplusplus
}
#endif
#endif
