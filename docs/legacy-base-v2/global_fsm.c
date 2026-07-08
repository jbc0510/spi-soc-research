#include "global_fsm.h"

static global_state_e state = STATE_BOOT;

void global_fsm_init(void) {
    state = STATE_BOOT;
}

void global_fsm_tick(bool fw_ok, bool pin_ok, bool tamper, bool reset) {
    /* RESET always wins */
    if (reset) {
        state = STATE_BOOT;
        return;
    }
    
    /* TAMPER always wins */
    if (tamper) {
        state = STATE_SAFE_MODE;
        return;
    }
    
    /* SAFE_MODE is absorbing except reset */
    if (state == STATE_SAFE_MODE) {
        return;
    }
    
    switch (state) {
    case STATE_BOOT:
        if (fw_ok) {
            state = STATE_LOCKED;
        }
        break;
        
    case STATE_LOCKED:
        if (fw_ok) {
            state = STATE_FW_VERIFIED;
        }
        break;
        
    case STATE_FW_VERIFIED:
        if (pin_ok) {
            state = STATE_AUTHORIZED;
        }
        break;
        
    case STATE_AUTHORIZED:
        /* no-op unless tamper/reset */
        break;
        
    case STATE_SAFE_MODE:
        /* unreachable due to early return */
        break;
    }
}

global_state_e global_fsm_state(void) {
    return state;
}

const char *global_state_to_str(global_state_e s) {
    switch (s) {
    case STATE_BOOT:        return "BOOT";
    case STATE_LOCKED:      return "LOCKED";
    case STATE_FW_VERIFIED: return "FW_VERIFIED";
    case STATE_AUTHORIZED:  return "AUTHORIZED";
    case STATE_SAFE_MODE:   return "SAFE_MODE";
    default:                return "UNKNOWN";
    }
}
