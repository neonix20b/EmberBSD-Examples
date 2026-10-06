#ifndef EMBER_ROBOT_LINK_H
#define EMBER_ROBOT_LINK_H
#include "protocol.h"
#ifdef __cplusplus
extern "C" {
#endif
struct robot_link;
typedef void (*robot_receive_fn)(const struct robot_frame *, void *);
struct robot_link *robot_link_open(const char *, int, robot_receive_fn, void *);
int robot_link_put(struct robot_link *, const struct robot_frame *);
void robot_link_close(struct robot_link *);
uint64_t robot_now_ms(void);
#ifdef __cplusplus
}
#endif
#endif
