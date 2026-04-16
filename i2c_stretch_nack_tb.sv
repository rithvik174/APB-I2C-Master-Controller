`timescale 1ns/1ps

module i2c_stretch_nack_tb;

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
  wire        stretch_active;

  wire        sda_pad_o;
  wire        sda_padoen_o;
  wire        scl_pad_o;
  wire        scl_padoen_o;

  reg         slave_sda_drive_low;
  reg         slave_scl_drive_low;

  wire        sda_bus;
  wire        scl_bus;

  integer stretch_count;
  reg     stretch_seen;

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
    .stretch_active(stretch_active),
    .sda_pad_i     (sda_bus),
    .sda_pad_o     (sda_pad_o),
    .sda_padoen_o  (sda_padoen_o),
    .scl_pad_i     (scl_bus),
    .scl_pad_o     (scl_pad_o),
    .scl_padoen_o  (scl_padoen_o)
  );

  always @(negedge scl_padoen_o) begin
    if (rst_n && (stretch_count < 5) && !slave_scl_drive_low) begin
      stretch_count = stretch_count + 1;
      slave_scl_drive_low = 1'b1;
      repeat (5) @(posedge clk);
      slave_scl_drive_low = 1'b0;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      stretch_seen <= 1'b0;
    else if (stretch_active)
      stretch_seen <= 1'b1;
  end

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

  reg [7:0] b0;

  initial begin : SLAVE_BFM
    slave_sda_drive_low = 1'b0;
    slave_scl_drive_low = 1'b0;

    wait(rst_n === 1'b1);

    forever begin
      wait_start();
      recv_byte(b0);
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
      stretch_count = 0;
      stretch_seen  = 1'b0;
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

    $display("\n[TB] STRETCH NACK: wrong address with clock stretching");
    start_read_expect_nack(7'h55, 8'h00);

    wait(done == 1'b1);
    @(negedge clk);

    if (!error_nack)
      $fatal(1, "[TB][FAIL] STRETCH NACK expected error_nack=1");
    if (!stretch_seen)
      $fatal(1, "[TB][FAIL] STRETCH NACK stretch_active was never observed");

    $display("[TB][PASS] STRETCH NACK error_nack=1, stretch_count=%0d", stretch_count);
    #50;
    $finish;
  end

endmodule
