// src/api_uart.c
#include "api_uart.h"

#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include "group_fsm.h"
#include "perm_table.h"

// Your FSM
#include "global_fsm.h"

// =========================================================
// Patent-aligned minimal structure (repo B):
// - User interaction stream: read bytes -> build line -> parse Command -> enqueue
// - Controller: executes queued commands only at safe points
// - Compute stream: stub "busy" job to demonstrate queueing behavior
// =========================================================

typedef enum {
    CMD_NONE = 0,
    CMD_STATUS,
    CMD_FW_OK,
    CMD_GLOBAL_PIN_OK,
    CMD_FILE_DENIED_1,
    CMD_FILE_DENIED_2,
    CMD_GROUP_AUTOLOCK,
    CMD_TAMPER,
    CMD_RESET,
    CMD_HELP,
    CMD_GROUP_INIT,
    CMD_UNLOCK_OK,
    CMD_UNLOCK_FAIL,
    CMD_SUSPEND,
    CMD_GATE_READ,
    CMD_GATE_WRITE,
    CMD_SELECT_GROUP,
    CMD_GROUP_STATUS,
    CMD_GATE_RECEIVE,
} cmd_type_t;

typedef struct {
    cmd_type_t type;
    int arg;          // default -1 if not provided
    bool has_arg;
} Command;

// ------------------------------
// Command queue (ring buffer)
// ------------------------------
#define QCAP 8
static Command q[QCAP];
static uint8_t q_head = 0, q_tail = 0, q_count = 0;
#define MAX_GROUPS 3

typedef enum {
    G_TECHNICIAN = 0,
    G_ENGINEER   = 1,
    G_MACHINE    = 2,
} group_role_e;

static group_ctx_t groups[MAX_GROUPS];
static bool groups_inited[MAX_GROUPS] = {false,false,false};
static uint8_t active_gid = G_ENGINEER; // default selection

static bool q_push(Command c) {
    if (q_count == QCAP) return false;
    q[q_tail] = c;
    q_tail = (uint8_t)((q_tail + 1) % QCAP);
    q_count++;
    return true;
}

static bool q_pop(Command *out) {
    if (q_count == 0) return false;
    *out = q[q_head];
    q_head = (uint8_t)((q_head + 1) % QCAP);
    q_count--;
    return true;
}

// ------------------------------
// I/O abstraction (HOST FIRST)
// ------------------------------
// This version uses stdin/stdout so it works on your host test harness.
// Later, you can swap io_getc_blocking/io_puts to real UART reads/writes.

static int io_getc_blocking(void) {
    return getchar();
}

static void io_puts(const char *s) {
    fputs(s, stdout);
    fflush(stdout);
}

// ------------------------------
// Compute stream (stub)
// ------------------------------
static bool compute_busy = false;
static int  compute_ticks = 0;

// Start a fake long-running job to demonstrate queueing.
// You can later tie this to real work (crypto, receive, etc.).
static void compute_start_stub(int ticks) {
    compute_busy = true;
    compute_ticks = ticks;
}

static void compute_tick_stub(void) {
    if (!compute_busy) return;
    if (compute_ticks > 0) {
        compute_ticks--;
        return;
    }
    compute_busy = false;
    io_puts("[compute done]\n");
}

static void trim(char *s){
    size_t n = strlen(s);
    while (n > 0 && (s[n-1] == ' ' || s[n-1] == '\t')) s[--n] = 0;
    size_t i = 0;
    while (s[i] == ' ' || s[i] == '\t') i++;
    if (i) memmove(s, s+i, strlen(s+i) + 1);
}

// ------------------------------
// Parser: line -> Command
// ------------------------------
static bool valid_gid(int gid);
static const char *group_name(uint8_t gid);

static Command parse_line(const char *line_in) {
    char line[128];
    snprintf(line, sizeof(line), "%s", line_in);
    trim(line);
    int gid;
    char name[32];

    if (sscanf(line, "select %31s", name) == 1) {
        if (strcmp(name, "tech") == 0 || strcmp(name, "technician") == 0) gid = 0;
        else if (strcmp(name, "eng") == 0 || strcmp(name, "engineer") == 0) gid = 1;
        else if (strcmp(name, "machine") == 0) gid = 2;
        else if (sscanf(name, "%d", &gid) != 1) gid = -1;

        if (gid >= 0 && gid < 3)
            return (Command){ .type = CMD_SELECT_GROUP, .arg = gid, .has_arg = true };
        return (Command){ .type = CMD_NONE };
    }

    if (strcmp(line, "group_status") == 0) {
        return (Command){ .type = CMD_GROUP_STATUS };
    }
    if (strcmp(line, "gate_receive") == 0) return (Command){ .type = CMD_GATE_RECEIVE };
    if (strcmp(line, "status") == 0)         return (Command){ .type = CMD_STATUS };
    if (strcmp(line, "fw_ok") == 0)          return (Command){ .type = CMD_FW_OK };
    if (strcmp(line, "global_pin_ok") == 0)  return (Command){ .type = CMD_GLOBAL_PIN_OK };
    if (strcmp(line, "file_denied_1") == 0)  return (Command){ .type = CMD_FILE_DENIED_1 };
    if (strcmp(line, "file_denied_2") == 0)  return (Command){ .type = CMD_FILE_DENIED_2 };
    if (strcmp(line, "group_autolock") == 0) return (Command){ .type = CMD_GROUP_AUTOLOCK };
    if (strcmp(line, "tamper") == 0)         return (Command){ .type = CMD_TAMPER };
    if (strcmp(line, "reset") == 0)          return (Command){ .type = CMD_RESET };
    if (strcmp(line, "help") == 0)           return (Command){ .type = CMD_HELP };

    if (sscanf(line, "group_init %31s", name) == 1) {
        if (strcmp(name, "tech") == 0 || strcmp(name, "technician") == 0) gid = 0;
        else if (strcmp(name, "eng") == 0 || strcmp(name, "engineer") == 0) gid = 1;
        else if (strcmp(name, "machine") == 0) gid = 2;
        else if (sscanf(name, "%d", &gid) != 1) gid = -1;

        if (valid_gid(gid))
            return (Command){ .type = CMD_GROUP_INIT, .arg = gid, .has_arg = true };
        return (Command){ .type = CMD_NONE };
    }

    if (strcmp(line, "group_init") == 0) {
        return (Command){
            .type = CMD_GROUP_INIT,
            .has_arg = false
        };
    }

    if (strcmp(line, "unlock_ok") == 0)  return (Command){ .type = CMD_UNLOCK_OK };
    if (strcmp(line, "unlock_fail") == 0)return (Command){ .type = CMD_UNLOCK_FAIL };
    if (strcmp(line, "suspend") == 0)    return (Command){ .type = CMD_SUSPEND };
    if (strcmp(line, "gate_read") == 0)  return (Command){ .type = CMD_GATE_READ };
    if (strcmp(line, "gate_write") == 0) return (Command){ .type = CMD_GATE_WRITE };

    return (Command){ .type = CMD_NONE };
}

static const char *group_name(uint8_t gid) {
    switch (gid) {
        case G_TECHNICIAN: return "TECHNICIAN";
        case G_ENGINEER:   return "ENGINEER";
        case G_MACHINE:    return "MACHINE";
        default:           return "UNKNOWN";
    }
}

static bool valid_gid(int gid) {
    return gid >= 0 && gid < MAX_GROUPS;
}

static group_ctx_t *active_group(void) {
    return &groups[active_gid];
}

// ------------------------------
// Controller: execute at safe points
// ------------------------------
static bool require_global_authorized(void) {
    return strcmp(global_state_to_str(global_fsm_state()), "AUTHORIZED") == 0;
}

static void exec_command(Command c) {
    switch (c.type) {
    case CMD_STATUS: {
        char buf[128];
        snprintf(buf, sizeof(buf), "GLOBAL=%s\n", global_state_to_str(global_fsm_state()));
        io_puts(buf);
        break;
    }

    case CMD_FW_OK:
        global_fsm_tick(true, false, false, false);
        io_puts("Applied: fw_ok\n");
        break;

    case CMD_GLOBAL_PIN_OK:
        global_fsm_tick(false, true, false, false);
        io_puts("Applied: global_pin_ok\n");
        break;

    case CMD_TAMPER:
        global_fsm_tick(false, false, true, false);
        io_puts("Applied: tamper_event\n");
        break;

    case CMD_RESET:
        global_fsm_tick(false, false, false, true);
        io_puts("Applied: reset_event\n");
        break;

    case CMD_FILE_DENIED_1:
        io_puts("NOTE: file_denied_1 not wired in this 3-event FSM\n");
        break;

    case CMD_FILE_DENIED_2:
        io_puts("NOTE: file_denied_2 not wired in this 3-event FSM\n");
        break;

    case CMD_GROUP_AUTOLOCK:
        io_puts("NOTE: group_autolock not wired in this 3-event FSM\n");
        break;

    case CMD_HELP:
        io_puts(
            "Commands:\n"
            "  status\n"
            "  fw_ok\n"
            "  global_pin_ok\n"
            "  tamper\n"
            "  reset\n"
            "  file_denied_1 (note)\n"
            "  file_denied_2 (note)\n"
            "  group_autolock (note)\n"
            "\n"
            "Group / Gate:\n"
            "  group_init\n"
            "  select <tech|eng|machine|0|1|2>\n"
            "  group_status\n"
            "  group_init [<tech|eng|machine|0|1|2>]\n"
            "  unlock_ok\n"
            "  unlock_fail\n"
            "  suspend\n"
            "  gate_read\n"
            "  gate_write\n"
            "  gate_receive\n"
            "\n"
            "  help\n"
        );
        break;

    case CMD_GROUP_INIT: {
        if (!require_global_authorized()) { io_puts("DENY: global not AUTHORIZED\n"); break; }

        uint8_t gid = (c.has_arg && valid_gid(c.arg)) ? (uint8_t)c.arg : active_gid;
        active_gid = gid;

        group_fsm_init(&groups[gid], gid);
        groups_inited[gid] = true;

        char buf[96];
        snprintf(buf, sizeof(buf), "Group initialized: id=%u (%s) [active]\n", gid, group_name(gid));
        io_puts(buf);
        break;
    }

    case CMD_UNLOCK_OK: {
        if (!require_global_authorized()) { io_puts("DENY: global not AUTHORIZED\n"); break; }
        if (!groups_inited[active_gid]) { io_puts("ERR: run group_init first\n"); break; }
        group_ctx_t *g = active_group();
        group_fsm_tick_auth(g, true);
        io_puts("Group auth success\n");
        break;
    }

    case CMD_UNLOCK_FAIL: {
        if (!require_global_authorized()) { io_puts("DENY: global not AUTHORIZED\n"); break; }
        if (!groups_inited[active_gid]) { io_puts("ERR: run group_init first\n"); break; }
        group_ctx_t *g = active_group();
        group_fsm_tick_auth(g, false);
        io_puts("Group auth fail\n");
        break;
    }

    case CMD_SUSPEND: {
        if (!require_global_authorized()) { io_puts("DENY: global not AUTHORIZED\n"); break; }
        if (!groups_inited[active_gid]) { io_puts("ERR: run group_init first\n"); break; }
        group_ctx_t *g = active_group();
        group_fsm_admin_suspend(g);
        io_puts("Group suspended\n");
        break;
    }

    case CMD_SELECT_GROUP: {
        if (!require_global_authorized()) { io_puts("DENY: global not AUTHORIZED\n"); break; }
        if (!c.has_arg || c.arg < 0 || c.arg >= 3) { io_puts("ERR: bad group id\n"); break; }
        active_gid = (uint8_t)c.arg;

        char buf[96];
        snprintf(buf, sizeof(buf), "Active group set to id=%u (%s)\n",
                 active_gid, group_name(active_gid));
        io_puts(buf);
        break;
    }

    case CMD_GROUP_STATUS: {
        group_ctx_t *g = active_group();
        char buf[160];
        snprintf(buf, sizeof(buf),
                 "ACTIVE_GROUP=%u (%s) state=%s\n",
                 active_gid, group_name(active_gid), group_state_to_str(g->state));
        io_puts(buf);
        break;
    }

    case CMD_GATE_READ:
    case CMD_GATE_WRITE: {
        if (!require_global_authorized()) { io_puts("DENY: global not AUTHORIZED\n"); break; }
        if (!groups_inited[active_gid]) { io_puts("ERR: run group_init first\n"); break; }

        group_ctx_t *g = active_group();
        uint8_t op_bit = (c.type == CMD_GATE_READ) ? PERM_READ : PERM_WRITE;

        // For now, "owner_group" = active group (same behavior you had)
        uint8_t owner_group = g->group_id;

        if (g->state != G_UNLOCKED) { io_puts("DENY: group not UNLOCKED\n"); break; }
        if (!perm_check(g->group_id, op_bit)) { io_puts("DENY: permission\n"); break; }
        if (g->group_id != owner_group) { io_puts("DENY: ownership\n"); break; }

        io_puts("ALLOW\n");
        break;
    }

    case CMD_GATE_RECEIVE: {
        if (!require_global_authorized()) { io_puts("DENY: global not AUTHORIZED\n"); break; }
        if (!groups_inited[active_gid]) { io_puts("ERR: run group_init first\n"); break; }

        group_ctx_t *g = active_group();
        uint8_t op_bit = PERM_RECEIVE;

        // For now, "owner_group" = active group (same behavior you had)
        uint8_t owner_group = g->group_id;

        if (g->state != G_UNLOCKED) { io_puts("DENY: group not UNLOCKED\n"); break; }
        if (!perm_check(g->group_id, op_bit)) { io_puts("DENY: permission\n"); break; }
        if (g->group_id != owner_group) { io_puts("DENY: ownership\n"); break; }

        io_puts("ALLOW\n");
        break;
    }

    default:
        io_puts("ERR: unknown command\n");
        break;
    }
}

// Safe point policy (ground zero):
// - If compute is busy, do not execute commands.
// - If not busy, pop and execute at most one queued command per loop.
static void controller_tick(void) {
    if (compute_busy) return;

    Command c;
    if (q_pop(&c)) {
        exec_command(c);
    }
}

// =========================================================
// Test helpers (non-interactive)
// - api_uart_exec_line(): execute one command line immediately (no queue)
// - api_uart_exec_lines(): execute a list of lines
// - api_uart_test_reset(): reset CLI-local state for repeatable tests
// =========================================================

int api_uart_exec_line(const char *line) {
    Command c = parse_line(line);
    if (c.type == CMD_NONE) {
        io_puts("ERR: parse (try 'help')\n");
        return -1;
    }
    exec_command(c);
    return 0;
}

void api_uart_exec_lines(const char *const *lines, unsigned count) {
    for (unsigned i = 0; i < count; i++) {
        (void)api_uart_exec_line(lines[i]);
    }
}

void api_uart_test_reset(void) {
    // Clear queue
    q_head = q_tail = q_count = 0;

    // Reset group contexts
    memset(groups_inited, 0, sizeof(groups_inited));
    memset(groups, 0, sizeof(groups));
    active_gid = G_ENGINEER;

    // Reset compute stub
    compute_busy = false;
    compute_ticks = 0;

    // Reset FSMs / tables
    perm_table_init();
    global_fsm_init();
}

// =========================================================
// Public API
// =========================================================

void api_uart_init(void) {
    // Host mode uses stdin/stdout; nothing to init.
    // STM32 mode: replace io_getc_blocking/io_puts with UART driver functions.
}

void api_uart_run_loop(void) {
    char line[128];
    size_t n = 0;

    io_puts("UART CLI ready. Type 'help'.\n");

    // Demo: start a fake long compute job so you can see queueing works.
    //compute_start_stub(200);
    //io_puts("[compute started; commands will queue until done]\n");

    while (1) {
        // USER INTERACTION STREAM: read a line (blocking)
        int ch = io_getc_blocking();
        if (ch == EOF) continue;

        if (ch == '\r') continue;

        if (ch == '\n') {
            line[n] = 0;
            n = 0;

            Command c = parse_line(line);
            if (c.type == CMD_NONE) {
                io_puts("ERR: parse (try 'help')\n");
            } else {
                if (!q_push(c)) {
                    io_puts("ERR: queue full\n");
                } else {
                    io_puts("OK: queued\n");
                }
            }
        } else {
            if (n + 1 < sizeof(line)) {
                line[n++] = (char)ch;
            }
        }

        // COMPUTE STREAM
        compute_tick_stub();

        // CONTROLLER (authority scheduling)
        controller_tick();
    }
}
