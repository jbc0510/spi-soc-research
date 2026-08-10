`timescale 1ns/1ps
// Round-6 keyhole sim v2: fixes static-n bug, wrong idle gate,
// adds SPICR=0x180 anchor read to prove the read path first.
import axi_vip_pkg::*;
import sim_keyhole_axi_vip_0_0_pkg::*;
import sim_keyhole_axi_vip_1_0_pkg::*;

module tb_keyhole;
  bit aclk = 0, aresetn = 0;
  always #5 aclk = ~aclk;

  sim_keyhole_wrapper dut(.aclk(aclk), .aresetn(aresetn));
  sim_keyhole_axi_vip_0_0_mst_t     mst;
  sim_keyhole_axi_vip_1_0_slv_mem_t ddr;

  localparam bit[31:0] QSPI = 32'hA000_0000, CDMA = 32'hA001_0000;

  task automatic wr32(input bit[31:0] a, input bit[31:0] d);
    xil_axi_resp_t r;
    mst.AXI4LITE_WRITE_BURST(a, 0, d, r);
    if (r != XIL_AXI_RESP_OKAY)
      $display("WRESP!=OKAY addr=%08x resp=%0d", a, r);
  endtask
  task automatic rd32(input bit[31:0] a, output bit[31:0] d);
    xil_axi_resp_t r;
    bit [4095:0] wide;
    mst.AXI4LITE_READ_BURST(a, 0, wide, r);
    d = wide[31:0];
    if (r != XIL_AXI_RESP_OKAY)
      $display("RRESP!=OKAY addr=%08x resp=%0d", a, r);
  endtask

  // Wait for CDMASR.Idle (bit1) — valid only AFTER a transfer is kicked.
  task automatic wait_done(output bit ok, output bit[31:0] sr);
    automatic int n = 0; ok = 0;
    do begin
      rd32(CDMA + 32'h04, sr);
      if (sr[1]) begin ok = 1; break; end
      #200; n++;
    end while (n < 2000);
  endtask

  task automatic run_phase(input bit keyhole, input string tag);
    bit ok; bit[31:0] sr, ocy, spisr, cr;
    wr32(QSPI + 32'h40, 32'h0000000A);      // QSPI soft reset
    wr32(CDMA + 32'h00, 32'h00000004);      // CDMA soft reset
    #1000;
    rd32(CDMA + 32'h00, cr);                // reset bit must self-clear
    $display("%s: post-reset CDMACR = 0x%08x (rst bit2=%0d)", tag, cr, cr[2]);
    wr32(CDMA + 32'h00, keyhole ? 32'h20 : 32'h0);
    rd32(CDMA + 32'h00, cr);
    $display("%s: CDMACR readback = 0x%08x (keyhole bit5=%0d)", tag, cr, cr[5]);
    wr32(CDMA + 32'h18, 32'h5A5A1234);      // SA probe: RW register
    rd32(CDMA + 32'h18, cr);
    $display("%s: SA probe wrote 5A5A1234 read 0x%08x", tag, cr);
    wr32(CDMA + 32'h18, 32'h00000000);      // SA
    wr32(CDMA + 32'h20, QSPI + 32'h68);     // DA = DTR
    wr32(CDMA + 32'h28, 32'd64);            // BTT -> go
    rd32(CDMA + 32'h04, sr);
    $display("%s: CDMASR just after kick = 0x%08x", tag, sr);
    wait_done(ok, sr);
    rd32(QSPI + 32'h74, ocy);
    rd32(QSPI + 32'h64, spisr);
    $display("%s: done=%0d CDMASR=0x%08x OCY=%0d SPISR=0x%08x TxEmpty=%0d",
             tag, ok, sr, ocy, spisr, spisr[2]);
    if (tag == "PHASE_A") begin
      if (ok && !sr[6] && !sr[5] && !sr[4] && ocy == 15 && !spisr[2])
        $display("KEYHOLE_SIM: PASS — 16/16 words held at DTR");
      else
        $display("KEYHOLE_SIM: FAIL — see PHASE_A line above");
    end else
      $display("KEYHOLE_SIM: control (INCR) OCY=%0d TxEmpty=%0d CDMASR=0x%08x",
               ocy, spisr[2], sr);
  endtask

  initial begin
    bit[31:0] anchor;
    mst = new("mst", dut.sim_keyhole_i.axi_vip_0.inst.IF);
    ddr = new("ddr", dut.sim_keyhole_i.axi_vip_1.inst.IF);
    ddr.start_slave();  mst.start_master();
    for (int i = 0; i < 16; i++)
      ddr.mem_model.backdoor_memory_write_4byte(i*4, 32'hA5B00000 + i, 4'hF);
    #200 aresetn = 1; #500;
    rd32(QSPI + 32'h60, anchor);            // SPICR reset value = 0x180
    $display("ANCHOR: QSPI SPICR = 0x%08x (expect 0x00000180)", anchor);
    if (anchor != 32'h180)
      $display("KEYHOLE_SIM: READPATH FAIL — anchor mismatch, results untrustworthy");
    run_phase(1, "PHASE_A");
    run_phase(0, "PHASE_B");
    $display("KEYHOLE_SIM: DONE");
    $finish;
  end

  initial begin #5_000_000;
    $display("KEYHOLE_SIM: TIMEOUT"); $finish;
  end

  // ---- bus-truth monitors (netlist wires, names from sim_keyhole.v) ----
  `define SK dut.sim_keyhole_i
  always @(posedge aclk) begin
    // CDMA lite port (axi_ic_0 M01, post-auto_pc Lite-shaped): every AR/R/AW/W/B handshake
    if (`SK.axi_ic_0_M01_AXI_ARVALID && `SK.axi_ic_0_M01_AXI_ARREADY)
      $display("MON M01.AR  addr=0x%02x            t=%0t",
               `SK.axi_ic_0_M01_AXI_ARADDR, $time);
    if (`SK.axi_ic_0_M01_AXI_RVALID && `SK.axi_ic_0_M01_AXI_RREADY)
      $display("MON M01.R   data=0x%08x resp=%0d t=%0t",
               `SK.axi_ic_0_M01_AXI_RDATA,
               `SK.axi_ic_0_M01_AXI_RRESP, $time);
    if (`SK.axi_ic_0_M01_AXI_AWVALID && `SK.axi_ic_0_M01_AXI_AWREADY)
      $display("MON M01.AW  addr=0x%02x            t=%0t",
               `SK.axi_ic_0_M01_AXI_AWADDR, $time);
    if (`SK.axi_ic_0_M01_AXI_WVALID && `SK.axi_ic_0_M01_AXI_WREADY)
      $display("MON M01.W   data=0x%08x          t=%0t",
               `SK.axi_ic_0_M01_AXI_WDATA, $time);
    // CDMA data master: the keyhole evidence itself
    if (`SK.axi_cdma_0_M_AXI_AWVALID && `SK.axi_cdma_0_M_AXI_AWREADY)
      $display("MON CDMA.AW addr=0x%08x len=%0d burst=%0d t=%0t",
               `SK.axi_cdma_0_M_AXI_AWADDR, `SK.axi_cdma_0_M_AXI_AWLEN,
               `SK.axi_cdma_0_M_AXI_AWBURST, $time);
    if (`SK.axi_cdma_0_M_AXI_ARVALID && `SK.axi_cdma_0_M_AXI_ARREADY)
      $display("MON CDMA.AR addr=0x%08x len=%0d burst=%0d t=%0t",
               `SK.axi_cdma_0_M_AXI_ARADDR, `SK.axi_cdma_0_M_AXI_ARLEN,
               `SK.axi_cdma_0_M_AXI_ARBURST, $time);
    // QSPI side of axi_ic_0 (M00): what actually arrives
    if (`SK.axi_ic_0_M00_AXI_AWVALID && `SK.axi_ic_0_M00_AXI_AWREADY)
      $display("MON M00.AW  addr=0x%02x            t=%0t",
               `SK.axi_ic_0_M00_AXI_AWADDR, $time);
    if (`SK.axi_ic_0_M00_AXI_WVALID && `SK.axi_ic_0_M00_AXI_WREADY)
      $display("MON M00.W   data=0x%08x          t=%0t",
               `SK.axi_ic_0_M00_AXI_WDATA, $time);
    if (`SK.axi_ic_0_M00_AXI_BVALID && `SK.axi_ic_0_M00_AXI_BREADY)
      $display("MON M00.B   resp=%0d               t=%0t",
               `SK.axi_ic_0_M00_AXI_BRESP, $time);
  end
endmodule
