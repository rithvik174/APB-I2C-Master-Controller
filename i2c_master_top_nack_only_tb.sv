`timescale 1ns/1ps

module i2c_master_top_nack_only_tb;

  localparam [6:0] REAL_SLAVE_ADDR_P = 7'h48;

  reg         clk;
  reg         rst_n;

  reg         cmd_start;
  reg         cmd_rw;
  reg  [6:0]  slave_addr;
  reg  [7:0]  reg_addr;
  reg  [7:0]  rd_len;
  reg  [7:0]  wr_len;
  reg  [7:0]  wr_data;
  reg         wr_data_valid;
  reg  [15:0] pre_clk;

  wire        busy;
  wire        done;
  wire        error_nack;
  wire [7:0]  rd_byte;
  wire        rd_byte_valid;

  wire        sda_pad_o;
  wire        sda_padoen_o;
  wire        scl_pad_o;
  wire        scl_padoen_o;

  reg         slave_sda_drive_low;
  reg         slave_scl_drive_low;

  wire        sda_bus;
  wire        scl_bus;

  assign sda_bus = (sda_padoen_o || slave_sda_drive_low) ? 1'b0 : 1'b1;
  assign scl_bus = (scl_padoen_o || slave_scl_drive_low) ? 1'b0 : 1'b1;

  always #5 clk = ~clk;

  i2c_master_top dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .cmd_start     (cmd_start),
    .cmd_rw        (cmd_rw),
    .slave_addr    (slave_addr),
    .reg_addr      (reg_addr),
    .rd_len        (rd_len),
    .wr_len        (wr_len),
    .wr_data       (wr_data),
    .wr_data_valid (wr_data_valid),
    .pre_clk       (pre_clk),
    .busy          (busy),
    .done          (done),
    .error_nack    (error_nack),
    .rd_byte       (rd_byte),
    .rd_byte_valid (rd_byte_valid),
    .sda_pad_i     (sda_bus),
    .sda_pad_o     (sda_pad_o),
    .sda_padoen_o  (sda_padoen_o),
    .scl_pad_i     (scl_bus),
    .scl_pad_o     (scl_pad_o),
    .scl_padoen_o  (scl_padoen_o)
  );

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
    integer i;
    reg [7:0] temp;
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
      @(negedge scl_bus);
      slave_sda_drive_low = 1'b0;
      @(posedge scl_bus);
      @(negedge scl_bus);
      slave_sda_drive_low = 1'b0;
    end
  endtask

  reg [7:0] byte0;
  initial begin : SLAVE_BFM
    slave_sda_drive_low = 1'b0;
    slave_scl_drive_low = 1'b0;

    wait(rst_n === 1'b1);
    forever begin
      wait_start();
      recv_byte(byte0);  // wrong address from DUT expected
      if ((byte0[7:1] == REAL_SLAVE_ADDR_P))
        slave_sda_drive_low = 1'b1; // should never happen in this TB
      drive_nack();
      wait_stop();
      slave_sda_drive_low = 1'b0;
    end
  end

  task do_reset;
    begin
      clk           = 1'b0;
      rst_n         = 1'b0;
      cmd_start     = 1'b0;
      cmd_rw        = 1'b0;
      slave_addr    = 7'h00;
      reg_addr      = 8'h00;
      rd_len        = 8'h00;
      wr_len        = 8'h00;
      wr_data       = 8'h00;
      wr_data_valid = 1'b0;
      pre_clk       = 16'd8;
      repeat (5) @(negedge clk);
      rst_n = 1'b1;
    end
  endtask

  task start_read_expect_nack(input [6:0] addr, input [7:0] rega);
    begin
      @(negedge clk);
      cmd_rw        = 1'b1;
      slave_addr    = addr;
      reg_addr      = rega;
      rd_len        = 8'd1;
      wr_len        = 8'd0;
      wr_data       = 8'h00;
      wr_data_valid = 1'b0;
      cmd_start     = 1'b1;
      @(negedge clk);
      cmd_start     = 1'b0;
    end
  endtask

  initial begin
    do_reset();

    $display("\n[TB] NACK_ONLY: wrong slave address -> expect NACK");
    start_read_expect_nack(7'h55, 8'h00);

    wait(done == 1'b1);
    @(negedge clk);

    if (!error_nack)
      $fatal(1, "[TB][FAIL] NACK_ONLY expected error_nack=1");
    $display("[TB][PASS] NACK_ONLY error_nack=1 as expected");

    #50;
    $finish;
  end

endmodule
