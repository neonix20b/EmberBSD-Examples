#include <limits.h>
#include <string.h>
#include "protocol.h"

static uint64_t
get_be(const uint8_t *p, size_t n)
{
	uint64_t v = 0;
	while (n-- > 0)
		v = (v << 8) | *p++;
	return v;
}

static void
put_be(uint8_t *p, uint64_t v, size_t n)
{
	while (n > 0) {
		p[--n] = (uint8_t)v;
		v >>= 8;
	}
}

static int32_t
signed32(uint32_t v)
{
	return v <= INT32_MAX ? (int32_t)v : -1 - (int32_t)(UINT32_MAX - v);
}

int
robot_decode(struct robot_frame *f, const uint8_t *p, size_t n)
{
	if (n != ROBOT_WIRE_SIZE || memcmp(p, "EBR1", 4) != 0 ||
	    p[4] < ROBOT_STATE || p[4] > ROBOT_ACK || p[5] > ROBOT_EXHAUSTED ||
	    p[6] != 0 || p[7] != 0)
		return -1;
	f->kind = p[4];
	f->status = p[5];
	f->boot = get_be(p + 8, 8);
	f->stamp_ms = get_be(p + 16, 8);
	f->command_id = get_be(p + 24, 8);
	f->measured = signed32((uint32_t)get_be(p + 32, 4));
	f->setpoint = signed32((uint32_t)get_be(p + 36, 4));
	f->applied = (uint32_t)get_be(p + 40, 4);
	return 0;
}

void
robot_encode(uint8_t p[ROBOT_WIRE_SIZE], const struct robot_frame *f)
{
	memcpy(p, "EBR1", 4);
	p[4] = f->kind; p[5] = f->status; p[6] = p[7] = 0;
	put_be(p + 8, f->boot, 8);
	put_be(p + 16, f->stamp_ms, 8);
	put_be(p + 24, f->command_id, 8);
	put_be(p + 32, (uint32_t)f->measured, 4);
	put_be(p + 36, (uint32_t)f->setpoint, 4);
	put_be(p + 40, f->applied, 4);
}

enum robot_status
robot_apply(struct robot_frame *state, const struct robot_frame *cmd, uint64_t now)
{
	if (cmd->kind != ROBOT_COMMAND || cmd->status != ROBOT_OK ||
	    cmd->setpoint < 0 || cmd->setpoint > 100000)
		return ROBOT_RANGE;
	if (cmd->boot != state->boot)
		return ROBOT_BOOT;
	if (cmd->stamp_ms > now || now - cmd->stamp_ms > ROBOT_MAX_AGE_MS)
		return ROBOT_EXPIRED;
	if (cmd->command_id <= state->command_id)
		return ROBOT_REPLAY;
	if (state->applied == UINT32_MAX)
		return ROBOT_EXHAUSTED;
	state->command_id = cmd->command_id;
	state->setpoint = cmd->setpoint;
	state->applied++;
	return ROBOT_OK;
}
