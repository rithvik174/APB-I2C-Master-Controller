`timescale 1ns/1ps

module apb_i2c_status_nack_only_tb_v2;

  localparam [7:0]
    A_CTRL   = 8'h00,
    A_SLAVE  = 8'h04,
    A_REG    = 8'h08,
    A_RDLEN  = 8'h0C,
    A_WRLEN  = 8'h10,
    A_PRECLK = 8'h14,
    A_STATUS = 8'h20;

  reg         PCLK;
  reg         PRESETn;
  reg  [7:0]  PADDR;
  reg         PSEL;
  reg         PENABLE;
  reg         PWRITE;
  reg  [31:0] PWDATA;
  wire [31:0] PRDATA;
  wire        PREADY;
  wire        PSLVERR;

  wire        pad_sda_o;
  wire        sda_padoen_o;
  wire        pad_scl_o;
  wire        scl_padoen_o;

  reg         slave_sda_drive_low;
  reg         slave_scl_drive_low;

  wire        sda_bus;
  wire        scl_bus;

  assign sda_bus = (sda_padoen_o || slave_sda_drive_low) ? 1'b0 : 1'b1;
  assign scl_bus = (scl_padoen_o || slave_scl_drive_low) ? 1'b0 : 1'b1;

  always #5 PCLK = ~PCLK;

  apb_i2c_top dut (
    .PCLK        (PCLK),
    .PRESETn     (PRESETn),
    .PADDR       (PADDR),
    .PSEL        (PSEL),
    .PENABLE     (PENABLE),
    .PWRITE      (PWRITE),
    .PWDATA      (PWDATA),
    .PRDATA      (PRDATA),
    .PREADY      (PREADY),
    .PSLVERR     (PSLVERR),
    .pad_sda_i   (sda_bus),
    .pad_sda_o   (pad_sda_o),
    .sda_padoen_o(sda_padoen_o),
    .pad_scl_i   (scl_bus),
    .pad_scl_o   (pad_scl_o),
    .scl_padoen_o(scl_padoen_o)
  );

  task automatic apb_write(input [7:0] addr, input [31:0] data);
    begin
      @(negedge PCLK);
      PADDR = addr; PWDATA = data; PWRITE = 1'b1; PSEL = 1'b1; PENABLE = 1'b0;
      @(negedge PCLK);
      PENABLE = 1'b1;
      @(negedge PCLK);
      PSEL = 1'b0; PENABLE = 1'b0; PWRITE = 1'b0; PADDR = 8'h00; PWDATA = 32'h0;
    end
  endtask

  task automatic apb_read(input [7:0] addr, output [31:0] data);
    begin
      @(negedge PCLK);
      PADDR = addr; PWRITE = 1'b0; PSEL = 1'b1; PENABLE = 1'b0;
      @(negedge PCLK);
      PENABLE = 1'b1;
      @(posedge PCLK);
      data = PRDATA;
      @(negedge PCLK);
      PSEL = 1'b0; PENABLE = 1'b0; PADDR = 8'h00;
    end
  endtask

  task automatic wait_done_or_nack(output [31:0] status_word);
    integer guard;
    begin
      guard = 0;
      while (guard < 2000) begin
        apb_read(A_STATUS, status_word);
        if (status_word[1] || status_word[2]) disable wait_done_or_nack;
        guard = guard + 1;
      end
      $fatal(1, "[TB][FAIL] STATUS NACK_ONLY done/nack timeout");
    end
  endtask

  task automatic wait_busy_low(output [31:0] status_word);
    integer guard;
    begin
      guard = 0;
      while (guard < 2000) begin
        apb_read(A_STATUS, status_word);
        if (!status_word[0]) disable wait_busy_low;
        guard = guard + 1;
      end
      $fatal(1, "[TB][FAIL] STATUS NACK_ONLY busy did not drop");
    end
  endtask

  task automatic wait_start;
    begin : WST
      forever begin
        @(negedge sda_bus);
        if (scl_bus === 1'b1) disable WST;
      end
    end
  endtask

  task automatic wait_stop;
    begin : WSP
      forever begin
        @(posedge sda_bus);
        if (scl_bus === 1'b1) disable WSP;
      end
    end
  endtask

  task automatic recv_byte(output reg [7:0] byte_out);
    integer i; reg [7:0] temp;
    begin
      temp = 8'h00;
      for (i = 7; i >= 0; i = i - 1) begin
        @(posedge scl_bus);
        temp[i] = sda_bus;
      end
      byte_out = temp;
    end
  endtask

  task automatic drive_nack;
    begin
      @(negedge scl_bus); slave_sda_drive_low = 1'b0;
      @(posedge scl_bus);
      @(negedge scl_bus); slave_sda_drive_low = 1'b0;
    end
  endtask

  reg [7:0] b0;
  initial begin : SLAVE_BFM
    slave_sda_drive_low = 1'b0;
    slave_scl_drive_low = 1'b0;
    wait(PRESETn === 1'b1);
    forever begin
      wait_start();
      recv_byte(b0);
      drive_nack();
      wait_stop();
    end
  end

  task do_reset;
    begin
      PCLK = 1'b0; PRESETn = 1'b0; PADDR = 8'h00; PSEL = 1'b0; PENABLE = 1'b0; PWRITE = 1'b0; PWDATA = 32'h0;
      repeat (5) @(negedge PCLK);
      PRESETn = 1'b1;
    end
  endtask

  reg [31:0] status_word;
  initial begin
    do_reset();

    apb_read(A_STATUS, status_word);
    if (status_word[3:0] !== 4'b0000)
      $fatal(1, "[TB][FAIL] STATUS NACK_ONLY reset status=0x%0h expected 0", status_word[3:0]);

    apb_write(A_PRECLK, 32'd8);
    $display("\n[TB] STATUS NACK_ONLY: wrong slave address");
    apb_write(A_SLAVE, 32'h00000055);
    apb_write(A_REG,   32'h00000000);
    apb_write(A_WRLEN, 32'h00000000);
    apb_write(A_RDLEN, 32'h00000001);
    apb_write(A_CTRL,  32'h00000007);

    // First observe nack sticky assertion.
    wait_done_or_nack(status_word);
    if (status_word[2] !== 1'b1)
      $fatal(1, "[TB][FAIL] STATUS NACK_ONLY expected nack_sticky=1");

    // Then wait until transaction fully goes idle before clearing sticky bits.
    wait_busy_low(status_word);

    apb_write(A_STATUS, 32'h00000006); // clear done + nack
    apb_read(A_STATUS, status_word);
    if (status_word[3:0] !== 4'b0000)
      $fatal(1, "[TB][FAIL] STATUS NACK_ONLY clear status=0x%0h expected 0", status_word[3:0]);

    $display("[TB][PASS] STATUS NACK_ONLY nack_sticky/clear");
    #50;
    $finish;
  end

endmodule
