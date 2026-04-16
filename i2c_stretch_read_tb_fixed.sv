`timescale 1ns/1ps

module i2c_stretch_read_tb;

  localparam [6:0] SLAVE_ADDR_P = 7'h48;

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

  reg [7:0] mem [0:255];
  reg [7:0] reg_ptr;
  reg [7:0] rd_capture0;
  reg [7:0] rd_capture1;
  integer   rd_count;

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

  // ------------------------------------------------------------
  // DEBUG MONITORS
  // ------------------------------------------------------------
  always @(posedge clk) begin
    if (dut.byte_start_w) begin
      $display(
        "[BYTE_START] t=%0t tx_byte=%02h byte_dir=%0b tx_bit=%0b",
        $time,
        dut.tx_byte_w,
        dut.byte_dir_w,
        dut.tx_bit
      );
    end
  end

  always @(posedge scl_bus) begin
    if (busy) begin
      $display(
        "[SCL_SAMPLE] t=%0t sda_bus=%0b tx_byte=%02h tx_bit=%0b start_hold=%0b sda_drv_bit=%0b scl_phase=%0b core_en=%0b stretch=%0b",
        $time,
        sda_bus,
        dut.tx_byte_w,
        dut.tx_bit,
        dut.start_hold,
        dut.sda_drive_low_bit,
        dut.scl_phase,
        dut.core_en,
        dut.stretch_active
      );
    end
  end

  // ------------------------------------------------------------
  // Stretch seen sticky
  // ------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      stretch_seen <= 1'b0;
    else if (stretch_active)
      stretch_seen <= 1'b1;
  end

  // ------------------------------------------------------------
  // Capture DUT read data
  // ------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_count    <= 0;
      rd_capture0 <= 8'h00;
      rd_capture1 <= 8'h00;
    end else if (rd_byte_valid) begin
      if (rd_count == 0) rd_capture0 <= rd_byte;
      if (rd_count == 1) rd_capture1 <= rd_byte;
      rd_count <= rd_count + 1;
      $display("[TB] rd_byte_valid at %0t : rd_byte=0x%02h", $time, rd_byte);
    end
  end

  // ------------------------------------------------------------
  // I2C slave helper tasks
  // ------------------------------------------------------------
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

  task automatic drive_ack;
    begin
      @(negedge scl_bus);
      slave_sda_drive_low = 1'b1;
      $display("[SLAVE] ACK drive LOW started at time %0t", $time);

      @(posedge scl_bus);
      $display("[SLAVE] ACK sampled window, sda_bus=%0b at time %0t", sda_bus, $time);

      @(negedge scl_bus);
      slave_sda_drive_low = 1'b0;
      $display("[SLAVE] ACK released at time %0t", $time);
    end
  endtask

  task automatic drive_nack;
    begin
      @(negedge scl_bus);
      slave_sda_drive_low = 1'b0;
      $display("[SLAVE] NACK released SDA at time %0t", $time);

      @(posedge scl_bus);
      $display("[SLAVE] NACK sampled window, sda_bus=%0b at time %0t", sda_bus, $time);

      @(negedge scl_bus);
      slave_sda_drive_low = 1'b0;
    end
  endtask

 task automatic send_byte(input [7:0] data_in, output reg ack_from_master);
    integer i;
    begin
      $display("[SLAVE] send byte 0x%02h at time %0t", data_in, $time);
  
      // IMPORTANT:
      // After SLA+R ACK, SCL is already low.
      // So drive MSB immediately if SCL is already low.
      // Do not wait for another negedge, otherwise slave becomes 1 bit late.
      if (scl_bus !== 1'b0)
        @(negedge scl_bus);
  
      slave_sda_drive_low = (data_in[7] == 1'b0);
  
      // Send 8 bits MSB first
      for (i = 7; i >= 0; i = i - 1) begin
        if (i != 7) begin
          @(negedge scl_bus);
          slave_sda_drive_low = (data_in[i] == 1'b0);
        end
  
        @(posedge scl_bus);
        $display("[SLAVE_TX_BIT] t=%0t bit[%0d]=%0b sda_bus=%0b",
                 $time, i, data_in[i], sda_bus);
      end
  
      // Release SDA for master's ACK/NACK bit
      @(negedge scl_bus);
      slave_sda_drive_low = 1'b0;
  
      @(posedge scl_bus);
      ack_from_master = (sda_bus == 1'b0);
      $display("[SLAVE] master ACK sampled as %0b at time %0t",
               ack_from_master, $time);
  
      @(negedge scl_bus);
      slave_sda_drive_low = 1'b0;
    end
  endtask

  reg [7:0] b0, b1;
  reg       ack_from_master;

  // ------------------------------------------------------------
  // Slave transaction BFM
  // ------------------------------------------------------------
  initial begin : SLAVE_BFM
    integer i;

    for (i = 0; i < 256; i = i + 1)
      mem[i] = 8'h00;

    mem[8'h20] = 8'hA5;
    mem[8'h21] = 8'h5A;

    slave_sda_drive_low = 1'b0;
    reg_ptr = 8'h00;

    wait(rst_n === 1'b1);

    forever begin
      wait_start();

      recv_byte(b0); // SLA+W
      $display("[SLAVE] received addr-W byte = 0x%02h at time %0t", b0, $time);

      if ((b0[7:1] == SLAVE_ADDR_P) && (b0[0] == 1'b0)) begin
        drive_ack();
      end else begin
        drive_nack();
        wait_stop();
      end

      recv_byte(b1); // register pointer
      $display("[SLAVE] received reg byte = 0x%02h at time %0t", b1, $time);
      reg_ptr = b1;
      drive_ack();

      wait_start();  // repeated START

      recv_byte(b0); // SLA+R
      $display("[SLAVE] received addr-R byte = 0x%02h at time %0t", b0, $time);

      if ((b0[7:1] == SLAVE_ADDR_P) && (b0[0] == 1'b1)) begin
        drive_ack();
      end else begin
        drive_nack();
        wait_stop();
      end

      send_byte(mem[reg_ptr], ack_from_master);
      if (ack_from_master)
        reg_ptr = reg_ptr + 8'd1;

      send_byte(mem[reg_ptr], ack_from_master);

      wait_stop();
      slave_sda_drive_low = 1'b0;
    end
  end

  // ------------------------------------------------------------
  // Correct clock-stretch BFM
  // Stretches while SCL is already low. No false posedge.
  // ------------------------------------------------------------
  initial begin : SLAVE_CLOCK_STRETCH_BFM
    wait(rst_n === 1'b1);

    forever begin
      @(negedge scl_bus);

      if (stretch_count < 14) begin
        stretch_count = stretch_count + 1;

        slave_scl_drive_low = 1'b1;

        // Wait until master releases SCL.
        wait(scl_padoen_o == 1'b0);

        // Hold SCL low for extra cycles.
        repeat (5) @(posedge clk);

        // Release SCL: this creates the real rising edge.
        slave_scl_drive_low = 1'b0;
      end
    end
  end

  task do_reset;
    begin
      clk                 = 1'b0;
      rst_n               = 1'b0;
      cmd_start           = 1'b0;
      cmd_rw              = 1'b0;
      slave_addr          = 7'h00;
      reg_addr            = 8'h00;
      rd_len              = 8'h00;
      wr_len              = 8'h00;
      wr_data             = 8'h00;
      wr_data_valid       = 1'b0;
      pre_clk             = 16'd8;
      rd_count            = 0;
      rd_capture0         = 8'h00;
      rd_capture1         = 8'h00;
      stretch_count       = 0;
      stretch_seen        = 1'b0;
      slave_sda_drive_low = 1'b0;
      slave_scl_drive_low = 1'b0;

      repeat (5) @(negedge clk);
      rst_n = 1'b1;
    end
  endtask

  task start_read_2bytes(input [6:0] addr, input [7:0] rega);
    begin
      @(negedge clk);
      cmd_rw        = 1'b1;
      slave_addr    = addr;
      reg_addr      = rega;
      rd_len        = 8'd2;
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

    $display("\n[TB] STRETCH READ: read 0xA5,0x5A from reg 0x20 with clock stretching");
    start_read_2bytes(SLAVE_ADDR_P, 8'h20);

    wait(done == 1'b1);
    @(negedge clk);

    if (error_nack)
      $fatal(1, "[TB][FAIL] STRETCH READ got unexpected NACK");

    if (!stretch_seen)
      $fatal(1, "[TB][FAIL] STRETCH READ stretch_active was never observed");

    if ((rd_capture0 !== 8'hA5) || (rd_capture1 !== 8'h5A))
      $fatal(1, "[TB][FAIL] STRETCH READ got 0x%02h 0x%02h expected 0xA5 0x5A",
             rd_capture0, rd_capture1);

    $display("[TB][PASS] STRETCH READ got 0x%02h 0x%02h, stretch_count=%0d",
             rd_capture0, rd_capture1, stretch_count);

    #50;
    $finish;
  end

endmodule
