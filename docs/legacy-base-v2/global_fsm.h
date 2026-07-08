#ifndef GLOBAL_FSM_H
#define GLOBAL_FSM_H

#include <stdbool.h>

typedef enum {
    STATE_BOOT = 0,
    STATE_LOCKED,
    STATE_FW_VERIFIED,  // New intermediate state
    STATE_AUTHORIZED,
    STATE_SAFE_MODE
} global_state_e;

void global_fsm_init(void);
void global_fsm_tick(bool fw_ok, bool pin_ok, bool tamper, bool reset);
global_state_e global_fsm_state(void);
const char *global_state_to_str(global_state_e s);

#endif // GLOBAL_FSM_H
