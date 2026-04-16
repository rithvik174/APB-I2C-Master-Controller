module i2c_master_top (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        cmd_start,
    input  wire        cmd_rw,
    input  wire [6:0]  slave_addr,
    input  wire [7:0]  reg_addr,
    input  wire [7:0]  rd_len,
    input  wire [7:0]  wr_len,
    input  wire [7:0]  wr_data,
    input  wire        wr_data_valid,
    input  wire [15:0] pre_clk,

    output wire        busy,
    output wire        done,
    output wire        error_nack,
    output wire [7:0]  rd_byte,
    output wire        rd_byte_valid,

    output wire        stretch_active,

    input  wire        sda_pad_i,
    output wire        sda_pad_o,
    output wire        sda_padoen_o,
    input  wire        scl_pad_i,
    output wire        scl_pad_o,
    output wire        scl_padoen_o
);

  wire sda_in, scl_in;
  wire core_en, scl_phase;

  wire cond_start_req, cond_repstart_req, cond_stop_req;
  wire cond_done, cond_busy;
  wire sda_force_low, sda_force_release, scl_force_low;

  wire bit_start, bit_dir, tx_bit;
  wire bit_done, bit_rx_value, bit_last, bit_busy;
  wire sda_drive_low_bit;

  wire       byte_start_w, byte_dir_w, master_ack_w;
  wire [7:0] tx_byte_w, rx_byte_w;
  wire       byte_done_w, ack_ok_w, byte_busy_w;

  reg start_hold;

  wire bit_xfer_active = byte_busy_w | bit_busy | bit_start;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      start_hold <= 1'b0;
    end else begin
      if (cond_done && sda_force_low) begin
        start_hold <= 1'b1;
      end else if (start_hold && bit_xfer_active && (scl_in == 1'b0)) begin
        start_hold <= 1'b0;
      end else if (done) begin
        start_hold <= 1'b0;
      end
    end
  end

  wire sda_drive_low_final =
      cond_busy  ? sda_force_low :
      start_hold ? 1'b1 :
                   sda_drive_low_bit;

  wire scl_drive_low_final =
      cond_busy       ? scl_force_low :
      bit_xfer_active ? (scl_phase == 1'b0) :
                        1'b0;

  i2c_pad_ctrl u_pad (
    .clk          (clk),
    .rst_n        (rst_n),
    .sda_drive_low(sda_drive_low_final),
    .scl_drive_low(scl_drive_low_final),
    .sda_in       (sda_in),
    .scl_in       (scl_in),
    .sda_pad_i    (sda_pad_i),
    .sda_pad_o    (sda_pad_o),
    .sda_padoen_o (sda_padoen_o),
    .scl_pad_i    (scl_pad_i),
    .scl_pad_o    (scl_pad_o),
    .scl_padoen_o (scl_padoen_o)
  );

  i2c_clk_div u_div (
    .clk           (clk),
    .rst_n         (rst_n),
    .run_en        (bit_xfer_active),
    .scl_drive_low (scl_drive_low_final),
    .scl_in        (scl_in),
    .pre_clk       (pre_clk),
    .scl_phase     (scl_phase),
    .core_en       (core_en),
    .stretch_active(stretch_active)
  );

  i2c_cond_gen u_cond (
    .clk              (clk),
    .rst_n            (rst_n),
    .core_en          (core_en),
    .scl_phase        (scl_phase),
    .scl_in           (scl_in),
    .sda_in           (sda_in),
    .req_start        (cond_start_req),
    .req_rep_start    (cond_repstart_req),
    .req_stop         (cond_stop_req),
    .sda_force_low    (sda_force_low),
    .sda_force_release(sda_force_release),
    .scl_force_low    (scl_force_low),
    .busy             (cond_busy),
    .cond_done        (cond_done)
  );

  i2c_bit_engine u_bit (
    .clk          (clk),
    .rst_n        (rst_n),
    .sda_in       (sda_in),
    .scl_in       (scl_in),
    .core_en      (core_en),
    .scl_phase    (scl_phase),
    .bit_start    (bit_start),
    .bit_dir      (bit_dir),
    .tx_bit       (tx_bit),
    .sda_drive_low(sda_drive_low_bit),
    .bit_rx_value (bit_rx_value),
    .bit_last     (bit_last),
    .bit_done     (bit_done),
    .busy         (bit_busy)
  );

  i2c_byte_engine_v2 u_byte (
    .clk         (clk),
    .rst_n       (rst_n),
    .byte_start  (byte_start_w),
    .byte_dir    (byte_dir_w),
    .tx_byte     (tx_byte_w),
    .master_ack  (master_ack_w),
    .byte_done   (byte_done_w),
    .busy        (byte_busy_w),
    .ack_ok      (ack_ok_w),
    .rx_byte     (rx_byte_w),
    .bit_done    (bit_done),
    .bit_rx_value(bit_rx_value),
    .bit_start_o (bit_start),
    .bit_dir_o   (bit_dir),
    .tx_bit_o    (tx_bit)
  );

  i2c_transaction_fsm u_fsm (
    .clk              (clk),
    .rst_n            (rst_n),
    .cmd_start        (cmd_start),
    .cmd_rw           (cmd_rw),
    .slave_addr       (slave_addr),
    .reg_addr         (reg_addr),
    .rd_len           (rd_len),
    .wr_len           (wr_len),
    .wr_data          (wr_data),
    .wr_data_valid    (wr_data_valid),
    .busy             (busy),
    .done             (done),
    .error_nack       (error_nack),
    .rd_byte          (rd_byte),
    .rd_byte_valid    (rd_byte_valid),
    .cond_start_req   (cond_start_req),
    .cond_repstart_req(cond_repstart_req),
    .cond_stop_req    (cond_stop_req),
    .cond_done        (cond_done),
    .cond_busy        (cond_busy),
    .byte_start       (byte_start_w),
    .byte_dir         (byte_dir_w),
    .tx_byte          (tx_byte_w),
    .master_ack       (master_ack_w),
    .byte_done        (byte_done_w),
    .ack_ok           (ack_ok_w),
    .rx_byte          (rx_byte_w)
  );

  wire _unused_release = sda_force_release;
  wire _unused_bitlast = bit_last;

endmodule
