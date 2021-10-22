// PRESS BTN6-RIGHT to increase SDRAM chip phase shift
// PRESS BTN5-LEFT  to decrease SDRAM chip phase shift

// MEMTEST FOR EMI test

// DIP SW
// 1: enable ESP32
// 2: enable GPDI
// 3: enable SDRAM
// 4: enable ADC

// go up and down with BTNs and check that
// default phase shift is approx in the middle of the
// working range where errors don't appear

// counter on screen will increase immediately when BTN is pressed
// phase shift will be applied when BTN is released

module top_memtest_emi
(
    input         clk_25mhz,
    input   [6:0] btn,
    input   [3:0] sw,
    output  [7:0] led,
    output  [3:0] gpdi_dp,
    //  SDRAM interface (For use with 16Mx16bit or 32Mx16bit SDR DRAM, depending on version)
    output        sdram_csn,  // chip select
    output        sdram_clk,  // clock to SDRAM
    output        sdram_cke,  // clock enable to SDRAM	
    output        sdram_rasn, // SDRAM RAS
    output        sdram_casn, // SDRAM CAS
    output        sdram_wen,  // SDRAM write-enable
    output [12:0] sdram_a,    // SDRAM address bus
    output  [1:0] sdram_ba,   // SDRAM bank-address
    output  [1:0] sdram_dqm,  // byte select
    inout  [15:0] sdram_d,    // data bus to/from SDRAM	
    output        wifi_en,
    output        wifi_rxd,
    input         wifi_txd,
    output        ftdi_rxd,
    input         ftdi_txd
);
    parameter C_ddr = 1'b1; // 0:SDR 1:DDR
    parameter C_clk_pixel_Hz  =  27500000; // Hz
    parameter C_clk_gui_Hz    =  50000000; // Hz
    parameter C_clk_sdram_Hz  = 112500000; // Hz
    parameter C_sdram_clk_deg =       120; // deg phase shift for chip
    parameter C_size_MB = 32; // 8/16/32/64 MB

    localparam [31:0] C_sec_max = C_clk_gui_Hz - 1;
    localparam [31:0] C_min_max = C_clk_gui_Hz*60 - 1;

    localparam [15:0] C_clk_sdram_1MHz = C_clk_sdram_Hz / 1000000;
    localparam [15:0] C_clk_sdram_10MHz = C_clk_sdram_1MHz / 10;
    localparam [15:0] C_clk_sdram_100MHz = C_clk_sdram_10MHz / 10;
    localparam [11:0] C_clk_sdram_bcd = (C_clk_sdram_100MHz % 10) * 'h100
                                      + (C_clk_sdram_10MHz  % 10) * 'h10
                                      + (C_clk_sdram_1MHz   % 10);

    // DIP SW 1 enables wifi
    assign wifi_en    = sw[0];
    assign wifi_rxd   = ftdi_txd;
    assign ftdi_rxd   = wifi_txd;

    // clock generator for video and sys
    wire clk_video_locked;
    wire [3:0] clocks;
    ecp5pll
    #(
        .in_hz(25*1000000), // 25 MHz
      .out0_hz(C_ddr ? C_clk_pixel_Hz*5 : C_clk_pixel_Hz*10),
      .out1_hz(C_clk_pixel_Hz),
      .out2_hz(C_clk_gui_Hz)
    )
    clk_25_video
    (
      .clk_i(clk_25mhz),
      .clk_o(clocks),
      .locked(clk_video_locked)
    );
    wire clk_shift = clocks[0];
    wire clk_pixel = clocks[1];
    wire clk_sys   = clocks[2];
    wire clk_gui   = clk_pixel;

    wire [7:0] S_phase;
    btn_ecp5pll_phase
    #(
      .c_debounce_bits(16)
    )
    btn_ecp5pll_phase_inst
    (
      .clk(clk_gui),
      .inc(btn[6]),
      .dec(btn[5]),
      .phase(S_phase),
      .phasedir(S_phasedir),
      .phasestep(S_phasestep),
      .phaseloadreg(S_phaseloadreg)
    );

    wire clk_sdram;
    wire clk_sdram_locked;
    wire [3:0] clocks_sdram;
    ecp5pll
    #(
        .in_hz(25*1000000), // 25 MHz
      .out0_hz(C_clk_sdram_Hz),
      .out1_hz(C_clk_sdram_Hz), .out1_deg(C_sdram_clk_deg),
      .dynamic_en(1)
    )
    clk_25_sdram
    (
      .clk_i(clk_25mhz),
      .clk_o(clocks_sdram),
      .phasesel(2'd1), // select out1
      .phasedir(S_phasedir),
      .phasestep(S_phasestep),
      .phaseloadreg(S_phaseloadreg),
      .locked(clk_sdram_locked)
    );
    wire   clk_sdram = clocks_sdram[0];
    assign sdram_clk = clocks_sdram[1]; // phase shifted for the chip

    reg timer_reset;
    always @(posedge clk_gui) // FIXME should we use hardware 25 MHz here?
        timer_reset <= ~(btn[0] & clk_video_locked);

///////////////////////////////////////////////////////////////////

    wire [31:0] passcount, failcount;

    reg resetn;
    always @(posedge clk_sdram) // FIXME should we use hardware 25 MHz here?
        resetn <= btn[0] & clk_sdram_locked;

    defparam my_memtst.DRAM_COL_SIZE = C_size_MB == 64 ? 10 : C_size_MB == 32 ? 9 : 8; // 8:8-16MB 9:32MB 10:64MB
    defparam my_memtst.DRAM_ROW_SIZE = C_size_MB > 8 ? 13 : 12; // 12:8MB 13:>=16MB
    mem_tester my_memtst
    (
	.clk(clk_sdram),
	.rst_n(resetn),
	.passcount(passcount),
	.failcount(failcount),
	.DRAM_DQ(sdram_d),
	.DRAM_ADDR(sdram_a),
	.DRAM_LDQM(sdram_dqm[0]),
	.DRAM_UDQM(sdram_dqm[1]),
	.DRAM_WE_N(sdram_wen),
	.DRAM_CS_N(sdram_csn),
	.DRAM_RAS_N(sdram_rasn),
	.DRAM_CAS_N(sdram_casn),
	.DRAM_BA_0(sdram_ba[0]),
	.DRAM_BA_1(sdram_ba[1])
    );
    assign sdram_cke = sw[2]; // DIP SW 3 enables SDRAM

    // most important info is failcount - lower 8 bits shown on LEDs
    //assign led = failcount[7:0];
    assign led[7:4] = 0;
    // show DIP SW position on LEDs
    // bit reverse to make same order on LEDs as on DIP SW
    assign led[3:0] = {sw[0],sw[1],sw[2],sw[3]};

    // VGA signal generator
    wire VGA_DE;
    wire [1:0] vga_r, vga_g, vga_b;
    vgaout showrez
    (
        .clk(clk_pixel),
        .rez1(passcount),
        .rez2(failcount),
        .freq(S_phase),
        .hs(vga_hsync),
        .vs(vga_vsync),
        .de(VGA_DE),
        .r(vga_r),
        .g(vga_g),
        .b(vga_b)
    );
    assign vga_blank = ~VGA_DE;

    // VGA to digital video converter
    wire [1:0] tmds[3:0];
    vga2dvid
    /*
    #(
      .c_depth(2),
      .c_ddr(C_ddr)
    )
    */
    vga2dvid_instance
    (
      .clk_pixel(clk_pixel),
      .clk_shift(clk_shift),
      .in_red(vga_r),
      .in_green(vga_g),
      .in_blue(vga_b),
      .in_hsync(~vga_hsync),
      .in_vsync(~vga_vsync),
      .in_blank(vga_blank),
      .out_clock(tmds[3]),
      .out_red(tmds[2]),
      .out_green(tmds[1]),
      .out_blue(tmds[0])
    );

  reg dvi_out_reset;
  always @(posedge clk_shift)
    dvi_out_reset <= ~sw[1]; // DIP SW 2 enables GPDI
  generate
    if(C_ddr)
    begin
      // vendor specific DDR modules
      // convert SDR 2-bit input to DDR clocked 1-bit output (single-ended)
      // onboard GPDI
      ODDRX1F ddr0_clock (.D0(tmds[3][0]), .D1(tmds[3][1]), .Q(gpdi_dp[3]), .SCLK(clk_shift), .RST(dvi_out_reset));
      ODDRX1F ddr0_red   (.D0(tmds[2][0]), .D1(tmds[2][1]), .Q(gpdi_dp[2]), .SCLK(clk_shift), .RST(dvi_out_reset));
      ODDRX1F ddr0_green (.D0(tmds[1][0]), .D1(tmds[1][1]), .Q(gpdi_dp[1]), .SCLK(clk_shift), .RST(dvi_out_reset));
      ODDRX1F ddr0_blue  (.D0(tmds[0][0]), .D1(tmds[0][1]), .Q(gpdi_dp[0]), .SCLK(clk_shift), .RST(dvi_out_reset));
    end
    else
    begin
      assign gpdi_dp[3] = tmds[3][0];
      assign gpdi_dp[2] = tmds[2][0];
      assign gpdi_dp[1] = tmds[1][0];
      assign gpdi_dp[0] = tmds[0][0];
    end
  endgenerate

endmodule
