`timescale 1ns/1ps

module apb_i2c_status_write_only_tb;

  localparam [6:0] SLAVE_ADDR_P = 7'h48;

  localparam [7:0]
    A_CTRL   = 8'h00,
    A_SLAVE  = 8'h04,
    A_REG    = 8'h08,
    A_RDLEN  = 8'h0C,
    A_WRLEN  = 8'h10,
    A_PRECLK = 8'h14,
    A_TXDATA = 8'h18,
    A_RXDATA = 8'h1C,
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

  reg [7:0] mem [0:255];
  reg [7:0] reg_ptr;

  assign sda_bus = (sda_padoen_o || slave_sda_drive_low) ? 1'b0 : 1'b1;
  assign scl_bus = (scl_padoen_o || slave_scl_drive_low) ? 1'b0 : 1'b1;

  always #5 PCLK = ~PCLK;

  apb_i2c_top_v3 dut (
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
      PADDR   = addr; PWDATA = data; PWRITE = 1'b1; PSEL = 1'b1; PENABLE = 1'b0;
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

  task automatic wait_busy_high(output [31:0] status_word);
    integer guard;
    begin
      guard = 0;
      while (guard < 1000) begin
        apb_read(A_STATUS, status_word);
        if (status_word[0]) disable wait_busy_high;
        guard = guard + 1;
      end
      $fatal(1, "[TB][FAIL] STATUS WRITE_ONLY busy never went high");
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
      $fatal(1, "[TB][FAIL] STATUS WRITE_ONLY done/nack timeout");
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

  task automatic drive_ack;
    begin
      @(negedge scl_bus); slave_sda_drive_low = 1'b1;
      @(posedge scl_bus);
      @(negedge scl_bus); slave_sda_drive_low = 1'b0;
    end
  endtask

  task automatic drive_nack;
    begin
      @(negedge scl_bus); slave_sda_drive_low = 1'b0;
      @(posedge scl_bus);
      @(negedge scl_bus); slave_sda_drive_low = 1'b0;
    end
  endtask

  reg [7:0] b0, b1, b2;
  initial begin : SLAVE_BFM
    integer i;
    for (i = 0; i < 256; i = i + 1) mem[i] = 8'h00;
    slave_sda_drive_low = 1'b0;
    slave_scl_drive_low = 1'b0;
    reg_ptr = 8'h00;
    wait(PRESETn === 1'b1);

    forever begin
      wait_start();
      recv_byte(b0);
      if ((b0[7:1] == SLAVE_ADDR_P) && (b0[0] == 1'b0)) drive_ack();
      else begin drive_nack(); wait_stop(); end

      recv_byte(b1);
      reg_ptr = b1;
      drive_ack();

      recv_byte(b2);
      mem[reg_ptr] = b2;
      drive_ack();

      wait_stop();
      slave_sda_drive_low = 1'b0;
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
      $fatal(1, "[TB][FAIL] STATUS WRITE_ONLY reset status=0x%0h expected 0", status_word[3:0]);

    apb_write(A_PRECLK, 32'd8);
    $display("\n[TB] STATUS WRITE_ONLY: write transfer status");
    apb_write(A_SLAVE,  32'h00000048);
    apb_write(A_REG,    32'h00000010);
    apb_write(A_RDLEN,  32'h00000000);
    apb_write(A_WRLEN,  32'h00000001);
    apb_write(A_TXDATA, 32'h0000003C);
    apb_write(A_CTRL,   32'h00000003);

    wait_busy_high(status_word);
    wait_done_or_nack(status_word);

    if (status_word[2]) $fatal(1, "[TB][FAIL] STATUS WRITE_ONLY unexpected nack");
    if (status_word[1] !== 1'b1 || status_word[0] !== 1'b0)
      $fatal(1, "[TB][FAIL] STATUS WRITE_ONLY final busy/done=%b%b expected 01", status_word[0], status_word[1]);
    if (mem[8'h10] !== 8'h3C)
      $fatal(1, "[TB][FAIL] STATUS WRITE_ONLY mem[0x10]=0x%02h expected 0x3C", mem[8'h10]);

    apb_write(A_STATUS, 32'h00000002);
    apb_read(A_STATUS, status_word);
    if (status_word[3:0] !== 4'b0000)
      $fatal(1, "[TB][FAIL] STATUS WRITE_ONLY clear status=0x%0h expected 0", status_word[3:0]);

    $display("[TB][PASS] STATUS WRITE_ONLY busy/done/clear");
    #50;
    $finish;
  end

endmodule
