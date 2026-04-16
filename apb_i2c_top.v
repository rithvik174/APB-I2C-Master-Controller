module apb_i2c_top (
    input  wire        PCLK,
    input  wire        PRESETn,
    input  wire [7:0]  PADDR,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [31:0] PWDATA,
    output wire [31:0] PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,
    input  wire        pad_sda_i,
    output wire        pad_sda_o,
    output wire        sda_padoen_o,
    input  wire        pad_scl_i,
    output wire        pad_scl_o,
    output wire        scl_padoen_o
);

  wire        cmd_start;
  wire        cmd_rw;
  wire [6:0]  slave_addr;
  wire [7:0]  reg_addr;
  wire [7:0]  rd_len;
  wire [7:0]  wr_len;
  wire [15:0] pre_clk;
  wire [7:0]  wr_data;
  wire        wr_data_valid;

  wire        busy;
  wire        done;
  wire        error_nack;
  wire [7:0]  rd_byte;
  wire        rd_byte_valid;

  apb_i2c_regs_v4 u_regs (
    .PCLK         (PCLK),
    .PRESETn      (PRESETn),
    .PADDR        (PADDR),
    .PSEL         (PSEL),
    .PENABLE      (PENABLE),
    .PWRITE       (PWRITE),
    .PWDATA       (PWDATA),
    .PRDATA       (PRDATA),
    .PREADY       (PREADY),
    .PSLVERR      (PSLVERR),
    .cmd_start    (cmd_start),
    .cmd_rw       (cmd_rw),
    .slave_addr   (slave_addr),
    .reg_addr     (reg_addr),
    .rd_len       (rd_len),
    .wr_len       (wr_len),
    .pre_clk      (pre_clk),
    .wr_data      (wr_data),
    .wr_data_valid(wr_data_valid),
    .busy         (busy),
    .done         (done),
    .error_nack   (error_nack),
    .rd_byte      (rd_byte),
    .rd_byte_valid(rd_byte_valid)
  );

  i2c_master_top u_i2c (
    .clk          (PCLK),
    .rst_n        (PRESETn),
    .cmd_start    (cmd_start),
    .cmd_rw       (cmd_rw),
    .slave_addr   (slave_addr),
    .reg_addr     (reg_addr),
    .rd_len       (rd_len),
    .wr_len       (wr_len),
    .wr_data      (wr_data),
    .wr_data_valid(wr_data_valid),
    .pre_clk      (pre_clk),
    .busy         (busy),
    .done         (done),
    .error_nack   (error_nack),
    .rd_byte      (rd_byte),
    .rd_byte_valid(rd_byte_valid),
    .sda_pad_i    (pad_sda_i),
    .sda_pad_o    (pad_sda_o),
    .sda_padoen_o (sda_padoen_o),
    .scl_pad_i    (pad_scl_i),
    .scl_pad_o    (pad_scl_o),
    .scl_padoen_o (scl_padoen_o)
  );

endmodule
