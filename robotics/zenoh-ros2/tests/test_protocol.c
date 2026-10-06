#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "protocol.h"

int
main(void)
{
	struct robot_frame state = { ROBOT_STATE, 0, 0x1234, 100, 0,
	    -12345, 20000, 0 };
	struct robot_frame command = { ROBOT_COMMAND, 0, 0x1234, 100,
	    1, 0, 30000, 0 }, decoded;
	uint8_t wire[ROBOT_WIRE_SIZE + 1];
	unsigned int i;

	robot_encode(wire, &state);
	assert(memcmp(wire, "EBR1", 4) == 0);
	assert(wire[4] == ROBOT_STATE && wire[14] == 0x12 && wire[15] == 0x34);
	assert(wire[32] == 0xff && wire[35] == 0xc7);
	assert(robot_decode(&decoded, wire, ROBOT_WIRE_SIZE) == 0);
	assert(decoded.measured == -12345 && decoded.setpoint == 20000);
	assert(decoded.boot == state.boot && decoded.stamp_ms == 100);
	for (i = 0; i < ROBOT_WIRE_SIZE; i++)
		assert(robot_decode(&decoded, wire, i) != 0);
	assert(robot_decode(&decoded, wire, ROBOT_WIRE_SIZE + 1) != 0);
	wire[0] = 'X'; assert(robot_decode(&decoded, wire, ROBOT_WIRE_SIZE) != 0);
	robot_encode(wire, &state);
	wire[6] = 1; assert(robot_decode(&decoded, wire, ROBOT_WIRE_SIZE) != 0);
	robot_encode(wire, &state);
	wire[4] = 4; assert(robot_decode(&decoded, wire, ROBOT_WIRE_SIZE) != 0);
	robot_encode(wire, &state);
	wire[5] = 255; assert(robot_decode(&decoded, wire, ROBOT_WIRE_SIZE) != 0);
	assert(robot_apply(&state, &command, 1100) == ROBOT_OK);
	assert(state.applied == 1 && state.setpoint == 30000 && state.command_id == 1);
	assert(robot_apply(&state, &command, 1100) == ROBOT_REPLAY);
	command.command_id = 2;
	assert(robot_apply(&state, &command, 1101) == ROBOT_EXPIRED);
	assert(robot_apply(&state, &command, 99) == ROBOT_EXPIRED);
	command.boot++;
	assert(robot_apply(&state, &command, 100) == ROBOT_BOOT);
	command.boot = state.boot; command.setpoint = -1;
	assert(robot_apply(&state, &command, 100) == ROBOT_RANGE);
	command.setpoint = 100001;
	assert(robot_apply(&state, &command, 100) == ROBOT_RANGE);
	assert(state.applied == 1 && state.setpoint == 30000 && state.command_id == 1);
	command.setpoint = 100000; state.applied = UINT32_MAX;
	assert(robot_apply(&state, &command, 100) == ROBOT_EXHAUSTED);
	state.applied = 1; command.command_id = UINT64_MAX;
	assert(robot_apply(&state, &command, 100) == ROBOT_OK);
	command.command_id = 0;
	assert(robot_apply(&state, &command, 100) == ROBOT_REPLAY);
	puts("PASS: wire format, malformed inputs, expiry, boot, replay, range and counters");
	return 0;
}
