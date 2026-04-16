`timescale 1ns/1ps

module i2c_master_top_read2_only_fixed_tb;

  localparam [6:0] SLAVE_ADDR_P = 7'h48;

  localparam [3:0]
    SLV_IDLE            = 4'd0,
    SLV_ADDR_W          = 4'd1,
    SLV_ADDR_W_ACK      = 4'd2,
    SLV_REG             = 4'd3,
    SLV_REG_ACK         = 4'd4,
    SLV_ADDR_R          = 4'd5,
    SLV_ADDR_R_ACK      = 4'd6,
    SLV_READ_BYTE0      = 4'd7,
    SLV_READ_WAIT_ACK0  = 4'd8,
    SLV_READ_BYTE1      = 4'd9,
    SLV_READ_WAIT_ACK1  = 4'd10,
    SLV_STOP            = 4'd11,
    SLV_IGNORE          = 4'd12;

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

  // waveform/debug signals
  reg [3:0] slv_state;
  reg [7:0] mem [0:255];
  reg [7:0] rx_shift;
  reg [7:0] tx_shift;
  reg [7:0] last_rx_byte;
  reg [7:0] reg_ptr;
  reg       rw_latched;
  reg       addr_match;
  reg       master_ack_bit;
  integer   bit_idx;

  integer rd_count;
  reg [7:0] rd_capture0;
  reg [7:0] rd_capture1;

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

  task slave_init;
    integer i;
    begin
      for (i = 0; i < 256; i = i + 1)
        mem[i] = 8'h00;
      mem[8'h20] = 8'hA5;
      mem[8'h21] = 8'h5A;
      mem[8'h22] = 8'h3C;

      slave_sda_drive_low = 1'b0;
      slave_scl_drive_low = 1'b0;
      slv_state           = SLV_IDLE;
      rx_shift            = 8'h00;
      tx_shift            = 8'h00;
      last_rx_byte        = 8'h00;
      reg_ptr             = 8'h00;
      rw_latched          = 1'b0;
      addr_match          = 1'b0;
      master_ack_bit      = 1'b1;
      bit_idx             = 7;
    end
  endtask

  task automatic wait_start;
    begin : WST
      forever begin
        @(negedge sda_bus);
        if (scl_bus === 1'b1)
          disable WST;
      end
    end
  endtask

  task automatic wait_stop;
    begin : WSP
      forever begin
        @(posedge sda_bus);
        if (scl_bus === 1'b1)
          disable WSP;
      end
    end
  endtask

  task automatic recv_byte(output reg [7:0] byte_out);
    integer i;
    reg [7:0] temp;
    begin
      temp = 8'h00;
      for (i = 7; i >= 0; i = i - 1) begin
        bit_idx = i;
        @(posedge scl_bus);
        temp[i]  = sda_bus;
        rx_shift = temp;
      end
      byte_out     = temp;
      last_rx_byte = temp;
      bit_idx      = 7;
    end
  endtask

  task automatic drive_ack;
    begin
      @(negedge scl_bus);
      slave_sda_drive_low = 1'b1;
      @(posedge scl_bus);
      @(negedge scl_bus);
      slave_sda_drive_low = 1'b0;
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

  task automatic send_byte(input [7:0] data_in, output reg ack_from_master);
    integer i;
    begin
      tx_shift = data_in;

      // IMPORTANT FIX:
      // This task is called immediately after the preceding ACK task returns,
      // and drive_ack() returns on an SCL negedge. That means the bus is already
      // in the LOW phase for the first read-data bit when we enter here.
      //
      // If we wait for *another* negedge before driving data_in[7], we miss the
      // first data bit completely. The master then samples a stale released '1'
      // for bit[7], and the received byte becomes:
      //   {1'b1, actual_byte[7:1]}
      // which is exactly why 0xA5 was showing up as 0xD2.
      //
      // So we must drive the MSB immediately, not on the next negedge.
      slave_sda_drive_low = (data_in[7] == 1'b0);
      bit_idx             = 7;

      // First bit sampled on the next SCL rising edge
      @(posedge scl_bus);

      // Remaining bits 6..0
      for (i = 6; i >= 0; i = i - 1) begin
        @(negedge scl_bus);
        slave_sda_drive_low = (data_in[i] == 1'b0);
        bit_idx             = i;
        @(posedge scl_bus);
      end

      // ACK/NACK bit from master
      @(negedge scl_bus);
      slave_sda_drive_low = 1'b0;
      bit_idx             = 7;

      @(posedge scl_bus);
      ack_from_master = (sda_bus == 1'b0); // ACK = SDA low
      master_ack_bit  = ~ack_from_master;

      @(negedge scl_bus);
      slave_sda_drive_low = 1'b0;
    end
  endtask

  reg [7:0] addr_byte;
  reg [7:0] ptr_byte;
  reg       ack_from_master;

  initial begin : SLAVE_BFM
    wait(rst_n === 1'b1);

    forever begin : READ_TXN
      slv_state           = SLV_IDLE;
      slave_sda_drive_low = 1'b0;

      // START + SLA+W
      wait_start();

      slv_state = SLV_ADDR_W;
      recv_byte(addr_byte);
      rw_latched = addr_byte[0];
      addr_match = (addr_byte[7:1] == SLAVE_ADDR_P);

      slv_state = SLV_ADDR_W_ACK;
      if (addr_match && (rw_latched == 1'b0))
        drive_ack();
      else
        drive_nack();

      if (!(addr_match && (rw_latched == 1'b0))) begin
        slv_state = SLV_IGNORE;
        wait_stop();
        disable READ_TXN;
      end

      // register pointer byte
      slv_state = SLV_REG;
      recv_byte(ptr_byte);
      reg_ptr = ptr_byte;

      slv_state = SLV_REG_ACK;
      drive_ack();

      // repeated START + SLA+R
      wait_start();

      slv_state = SLV_ADDR_R;
      recv_byte(addr_byte);
      rw_latched = addr_byte[0];
      addr_match = (addr_byte[7:1] == SLAVE_ADDR_P);

      slv_state = SLV_ADDR_R_ACK;
      if (addr_match && (rw_latched == 1'b1))
        drive_ack();
      else
        drive_nack();

      if (!(addr_match && (rw_latched == 1'b1))) begin
        slv_state = SLV_IGNORE;
        wait_stop();
        disable READ_TXN;
      end

      // data byte 0
      slv_state = SLV_READ_BYTE0;
      send_byte(mem[reg_ptr], ack_from_master);
      slv_state = SLV_READ_WAIT_ACK0;
      if (!ack_from_master) begin
        wait_stop();
        disable READ_TXN;
      end
      reg_ptr = reg_ptr + 8'd1;

      // data byte 1
      slv_state = SLV_READ_BYTE1;
      send_byte(mem[reg_ptr], ack_from_master);
      slv_state = SLV_READ_WAIT_ACK1;

      // master should NACK the last byte
      wait_stop();
      slv_state           = SLV_STOP;
      slave_sda_drive_low = 1'b0;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_count    <= 0;
      rd_capture0 <= 8'h00;
      rd_capture1 <= 8'h00;
    end else if (rd_byte_valid) begin
      if (rd_count == 0) rd_capture0 <= rd_byte;
      if (rd_count == 1) rd_capture1 <= rd_byte;
      rd_count <= rd_count + 1;
      $display("[TB] rd_byte_valid at %0t : rd_byte = 0x%02h", $time, rd_byte);
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
      rd_count      = 0;
      rd_capture0   = 8'h00;
      rd_capture1   = 8'h00;
      slave_init();
      repeat (5) @(negedge clk);
      rst_n = 1'b1;
    end
  endtask

  task start_read_nbytes;
    input [6:0] addr;
    input [7:0] rega;
    input [7:0] nbytes;
    begin
      @(negedge clk);
      cmd_rw        = 1'b1;
      slave_addr    = addr;
      reg_addr      = rega;
      rd_len        = nbytes;
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

    $display("\n[TB] TEST2_ONLY: READ 2 bytes from reg 0x20");
    start_read_nbytes(SLAVE_ADDR_P, 8'h20, 8'd2);

    wait (done == 1'b1);
    @(negedge clk);

    if (error_nack) begin
      $fatal(1, "[TB][FAIL] TEST2_ONLY got unexpected NACK");
    end

    if ((rd_capture0 !== 8'hA5) || (rd_capture1 !== 8'h5A)) begin
      $fatal(1, "[TB][FAIL] TEST2_ONLY read bytes = 0x%02h 0x%02h expected 0xA5 0x5A",
             rd_capture0, rd_capture1);
    end

    $display("[TB][PASS] TEST2_ONLY read bytes = 0x%02h 0x%02h", rd_capture0, rd_capture1);
    #50;
    $finish;
  end

endmodule
