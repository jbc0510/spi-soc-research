// =============================================================================
// top_de25.sv — FPGA Top-Level for BASE v2.0 on Terasic DE25-Standard
// Target: Intel Agilex 5 (A5ED013BB32AE4S, 138K LEs)
// Tool:   Quartus Pro (free license w/ board)
//
// Replaces user_project_wrapper.v for FPGA emulation.
// Wires: Pushbutton Wishbone master → secure_boot_control_plane → FSM
//        FSM outputs (io_out[21:28]) → 8 LEDs
//        Wishbone readback           → 6 seven-segment displays
//        Slide switches              → io_in[7:20] (FSM inputs)
//
// Architecture (from Implementation Spec):
//   secure_boot_control_plane (4 WB registers: GLOBAL_STATE, STATUS_FLAGS,
//                              TIMEOUTS, CONTROL)
//     └── secure_boot_system_wrapper
//           ├── secure_boot_fsm    (global FSM)
//           └── group_fsm          (group FSM)
//
// GPIO mapping (preserved from v1.0):
//   io_in[7:20]   — 14 input pads to FSM
//   io_out[21:28] — 8 output pads from FSM
//   user_irq[0]   — IRQ from control plane (OR of shadow sticky flags)
// =============================================================================

`include "defines.v"

module top_de25 (
    // -------------------------------------------------------------------------
    // Clock & Reset
    // -------------------------------------------------------------------------
    input  logic        CLOCK_50,           // 50 MHz on-board oscillator
    input  logic        KEY_RESET_N,        // Active-low pushbutton reset

    // -------------------------------------------------------------------------
    // Slide Switches — directly mapped to FSM inputs
    // -------------------------------------------------------------------------
    input  logic [9:0]  SW,                 // 10 slide switches

    // -------------------------------------------------------------------------
    // Push Buttons — Wishbone master control
    // -------------------------------------------------------------------------
    input  logic [3:0]  KEY,                // Active-low pushbuttons [3:0]

    // -------------------------------------------------------------------------
    // LEDs — FSM outputs + IRQ
    // -------------------------------------------------------------------------
    output logic [9:0]  LEDR,               // 10 red LEDs

    // -------------------------------------------------------------------------
    // Seven-Segment Displays (active-low segments a–g)
    // -------------------------------------------------------------------------
    output logic [6:0]  HEX0,               // 7-seg digit 0 (rightmost)
    output logic [6:0]  HEX1,
    output logic [6:0]  HEX2,
    output logic [6:0]  HEX3,
    output logic [6:0]  HEX4,
    output logic [6:0]  HEX5                // 7-seg digit 5 (leftmost)
);

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    logic clk;
    logic rst_n;
    logic rst;

    assign clk   = CLOCK_50;
    assign rst_n = KEY_RESET_N;
    assign rst   = ~rst_n;

    // =========================================================================
    // Wishbone Signals
    // =========================================================================
    logic        wbs_stb_i;
    logic        wbs_cyc_i;
    logic        wbs_we_i;
    logic [3:0]  wbs_sel_i;
    logic [31:0] wbs_dat_i;
    logic [31:0] wbs_adr_i;
    logic        wbs_ack_o;
    logic [31:0] wbs_dat_o;

    // =========================================================================
    // Caravel-equivalent GPIO signals
    // =========================================================================
    // Match the actual Caravel mprj_io mapping from the Implementation Spec
    logic [37:0] io_in;
    logic [37:0] io_out;
    logic [37:0] io_oeb;
    logic [2:0]  user_irq;

    // -------------------------------------------------------------------------
    // io_in[7:20] — 14 FSM input signals from slide switches
    // -------------------------------------------------------------------------
    // From Implementation Spec GPIO mapping:
    //   io_in[7]  = fw_ok           SW[0]
    //   io_in[8]  = fw_fail         SW[1]
    //   io_in[9]  = size_mismatch   SW[2]
    //   io_in[10] = hdr_parse_fail  SW[3]
    //   io_in[11] = power_glitch    SW[4]
    //   io_in[12] = clock_glitch    SW[5]
    //   io_in[13] = warm_reset_req  SW[6]
    //   io_in[14] = cold_reset_req  SW[7]
    //   io_in[15] = global_pin_ok   SW[8]
    //   io_in[16] = unlock_req      SW[9]
    //   io_in[17] = file_denied     (directly active via KEY active-low logic
    //   io_in[18] = group_autolock     active-low inverted below, directly active)
    //   io_in[19] = tamper_in
    //   io_in[20] = illegal_in

    // Directly map first 10 switches to io_in[7:16]
    assign io_in[6:0]   = 7'd0;            // Unused — tied LOW
    assign io_in[7]      = SW[0];           // fw_ok
    assign io_in[8]      = SW[1];           // fw_fail
    assign io_in[9]      = SW[2];           // size_mismatch
    assign io_in[10]     = SW[3];           // hdr_parse_fail
    assign io_in[11]     = SW[4];           // power_glitch
    assign io_in[12]     = SW[5];           // clock_glitch
    assign io_in[13]     = SW[6];           // warm_reset_req
    assign io_in[14]     = SW[7];           // cold_reset_req
    assign io_in[15]     = SW[8];           // global_pin_ok
    assign io_in[16]     = SW[9];           // unlock_req
    // Remaining 4 inputs — directly active from active-low KEY buttons (active via inversion)
    assign io_in[17]     = ~KEY[3];         // file_denied (active when pressed)
    assign io_in[18]     = ~KEY[2];         // group_autolock (active when pressed)
    assign io_in[19]     = ~KEY[1];         // tamper_in (active when pressed)
    assign io_in[20]     = ~KEY[0];         // illegal_in (active when pressed)
    assign io_in[37:21]  = 17'd0;          // Unused — tied LOW

    // =========================================================================
    // Wishbone Master — Directly driven from active-low KEY buttons
    // =========================================================================
    // This is the bringup debug master. For HPS integration, replace this
    // block with an Avalon-to-Wishbone bridge.
    //
    // When no KEY is pressed, the master does a continuous read of the register
    // selected by SW[9:8]. This provides a live view of FSM state on the 7-seg.
    //
    // Control plane Wishbone register map (from Implementation Spec §4):
    //   Offset 0x00: GLOBAL_STATE  (R)   — global_state_bits[4:0], group_state_bits[3:0]
    //   Offset 0x04: STATUS_FLAGS  (R)   — sticky flags, error flags, security_breach
    //   Offset 0x08: TIMEOUTS      (R)   — global_timeout_count
    //   Offset 0x0C: CONTROL       (W1C) — write-one-to-clear shadow sticky flags
    //
    // Reads from 0x0C always return 0x00000000.
    // Writes to any address other than 0x0C are silently ignored (ACK still asserts).

    localparam [31:0] WB_BASE_ADDR = 32'h3000_0000;

    // Auto-poll: continuously read register selected by SW[9:8]
    logic [31:0] wb_read_data;
    logic [1:0]  poll_state;

    localparam POLL_IDLE = 2'd0;
    localparam POLL_REQ  = 2'd1;
    localparam POLL_WAIT = 2'd2;

    // Debounced edge detection not needed — we auto-poll, KEY maps to io_in

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            poll_state   <= POLL_IDLE;
            wbs_stb_i    <= 1'b0;
            wbs_cyc_i    <= 1'b0;
            wbs_we_i     <= 1'b0;
            wbs_sel_i    <= 4'hF;
            wbs_dat_i    <= 32'd0;
            wbs_adr_i    <= 32'd0;
            wb_read_data <= 32'd0;
        end else begin
            case (poll_state)
                POLL_IDLE: begin
                    // Start a read of register SW[9:8]
                    wbs_adr_i <= WB_BASE_ADDR + {28'd0, SW[9:8], 2'b00};
                    wbs_we_i  <= 1'b0;
                    wbs_stb_i <= 1'b1;
                    wbs_cyc_i <= 1'b1;
                    poll_state <= POLL_REQ;
                end

                POLL_REQ: begin
                    // Wait one cycle then check ACK
                    poll_state <= POLL_WAIT;
                end

                POLL_WAIT: begin
                    if (wbs_ack_o) begin
                        wb_read_data <= wbs_dat_o;
                        wbs_stb_i    <= 1'b0;
                        wbs_cyc_i    <= 1'b0;
                        poll_state   <= POLL_IDLE;
                    end
                    // If no ACK, keep waiting (single-cycle ACK expected)
                end

                default: poll_state <= POLL_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Design Under Test — Secure Boot Control Plane
    // =========================================================================
    // Port list matches user_project_wrapper.v instantiation.
    // The control plane internally instantiates:
    //   secure_boot_system_wrapper → secure_boot_fsm + group_fsm

    secure_boot_control_plane u_secure_boot_cp (
        // Wishbone Slave Interface
        .wb_clk_i   (clk),
        .wb_rst_i   (rst),
        .wbs_stb_i  (wbs_stb_i),
        .wbs_cyc_i  (wbs_cyc_i),
        .wbs_we_i   (wbs_we_i),
        .wbs_sel_i  (wbs_sel_i),
        .wbs_dat_i  (wbs_dat_i),
        .wbs_adr_i  (wbs_adr_i),
        .wbs_ack_o  (wbs_ack_o),
        .wbs_dat_o  (wbs_dat_o),

        // GPIO — directly wired to Caravel-equivalent buses
        .io_in      (io_in),
        .io_out     (io_out),
        .io_oeb     (io_oeb),

        // IRQ
        .user_irq   (user_irq)
    );

    // =========================================================================
    // Output Mapping
    // =========================================================================

    // ---- LEDs ----
    // LEDR[7:0] = io_out[28:21] — the 8 FSM output signals:
    //   [21] unlock_enable, [22] debug_enable, [23] safe_led,
    //   [24] fsm_error, [25] security_breach,
    //   [26] group_unlocked, [27] group_suspended, [28] group_error
    assign LEDR[7:0] = io_out[28:21];

    // LEDR[8] = user_irq[0] — IRQ indicator (OR of shadow sticky flags)
    assign LEDR[8] = user_irq[0];

    // LEDR[9] = heartbeat — confirms clock is running
    logic [24:0] heartbeat_ctr;
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            heartbeat_ctr <= '0;
        else
            heartbeat_ctr <= heartbeat_ctr + 1'b1;
    end
    assign LEDR[9] = heartbeat_ctr[24]; // ~1.5 Hz blink at 50 MHz

    // ---- Seven-Segment Displays ----
    // Display the Wishbone read-back register (wb_read_data) as 6 hex digits.
    // This provides live visibility into whichever register SW[9:8] selects:
    //   SW=00 → GLOBAL_STATE (FSM state bits)
    //   SW=01 → STATUS_FLAGS (sticky flags, errors)
    //   SW=10 → TIMEOUTS     (timeout counter)
    //   SW=11 → CONTROL      (always reads 0x00000000)

    function automatic logic [6:0] hex_to_7seg(input logic [3:0] hex);
        case (hex)
            4'h0: hex_to_7seg = 7'b100_0000;
            4'h1: hex_to_7seg = 7'b111_1001;
            4'h2: hex_to_7seg = 7'b010_0100;
            4'h3: hex_to_7seg = 7'b011_0000;
            4'h4: hex_to_7seg = 7'b001_1001;
            4'h5: hex_to_7seg = 7'b001_0010;
            4'h6: hex_to_7seg = 7'b000_0010;
            4'h7: hex_to_7seg = 7'b111_1000;
            4'h8: hex_to_7seg = 7'b000_0000;
            4'h9: hex_to_7seg = 7'b001_0000;
            4'hA: hex_to_7seg = 7'b000_1000;
            4'hB: hex_to_7seg = 7'b000_0011;
            4'hC: hex_to_7seg = 7'b100_0110;
            4'hD: hex_to_7seg = 7'b010_0001;
            4'hE: hex_to_7seg = 7'b000_0110;
            4'hF: hex_to_7seg = 7'b000_1110;
            default: hex_to_7seg = 7'b111_1111;
        endcase
    endfunction

    // wb_read_data[23:0] → HEX5..HEX0 (6 hex nibbles = 24 bits)
    assign HEX0 = hex_to_7seg(wb_read_data[3:0]);
    assign HEX1 = hex_to_7seg(wb_read_data[7:4]);
    assign HEX2 = hex_to_7seg(wb_read_data[11:8]);
    assign HEX3 = hex_to_7seg(wb_read_data[15:12]);
    assign HEX4 = hex_to_7seg(wb_read_data[19:16]);
    assign HEX5 = hex_to_7seg(wb_read_data[23:20]);

endmodule
