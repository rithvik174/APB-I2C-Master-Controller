module apb_i2c_regs_v4 #(
    parameter ADDR_W = 8
)(
    input  wire              PCLK,
    input  wire              PRESETn,
    input  wire [ADDR_W-1:0] PADDR,
    input  wire              PSEL,
    input  wire              PENABLE,
    input  wire              PWRITE,
    input  wire [31:0]       PWDATA,
    output reg  [31:0]       PRDATA,
    output wire              PREADY,
    output wire              PSLVERR,

    output reg               cmd_start,
    output reg               cmd_rw,
    output reg  [6:0]        slave_addr,
    output reg  [7:0]        reg_addr,
    output reg  [7:0]        rd_len,
    output reg  [7:0]        wr_len,
    output reg  [15:0]       pre_clk,
    output reg  [7:0]        wr_data,
    output reg               wr_data_valid,

    input  wire              busy,
    input  wire              done,
    input  wire              error_nack,
    input  wire [7:0]        rd_byte,
    input  wire              rd_byte_valid
);

  assign PREADY  = 1'b1;
  assign PSLVERR = 1'b0;

  wire apb_wr = PSEL && PENABLE &&  PWRITE;
  wire apb_rd = PSEL && PENABLE && !PWRITE;

  localparam [ADDR_W-1:0]
    A_CTRL   = 8'h00,
    A_SLAVE  = 8'h04,
    A_REG    = 8'h08,
    A_RDLEN  = 8'h0C,
    A_WRLEN  = 8'h10,
    A_PRECLK = 8'h14,
    A_TXDATA = 8'h18,
    A_RXDATA = 8'h1C,
    A_STATUS = 8'h20;

  reg enable;
  reg done_sticky;
  reg nack_sticky;
  reg rx_valid;
  reg [7:0] rxdata_hold;

  reg start_pending;

  // Edge detect status inputs from I2C core.
  // This is the key fix for NACK clear behavior:
  // error_nack from the core can remain high beyond the exact failure cycle,
  // so sticky logic must latch the EVENT, not the LEVEL.
  reg done_d;
  reg error_nack_d;

  always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      cmd_start      <= 1'b0;
      cmd_rw         <= 1'b0;
      slave_addr     <= 7'h00;
      reg_addr       <= 8'h00;
      rd_len         <= 8'h00;
      wr_len         <= 8'h00;
      pre_clk        <= 16'd8;
      wr_data        <= 8'h00;
      wr_data_valid  <= 1'b0;
      enable         <= 1'b0;
      done_sticky    <= 1'b0;
      nack_sticky    <= 1'b0;
      rx_valid       <= 1'b0;
      rxdata_hold    <= 8'h00;
      start_pending  <= 1'b0;
      done_d         <= 1'b0;
      error_nack_d   <= 1'b0;
    end else begin
      cmd_start      <= 1'b0;
      wr_data_valid  <= 1'b0;

      // Delay registers for edge detect
      done_d       <= done;
      error_nack_d <= error_nack;

      if (rd_byte_valid) begin
        rxdata_hold <= rd_byte;
        rx_valid    <= 1'b1;
      end

      // Latch only rising-edge events, not sustained levels
      if (done && !done_d)
        done_sticky <= 1'b1;
      if (error_nack && !error_nack_d)
        nack_sticky <= 1'b1;

      // Defer start by one cycle so config fields are already stable
      if (start_pending && !busy) begin
        cmd_start     <= 1'b1;
        start_pending <= 1'b0;
        done_sticky   <= 1'b0;
        nack_sticky   <= 1'b0;
      end

      if (apb_wr) begin
        case (PADDR)
          A_CTRL: begin
            enable <= PWDATA[0];
            cmd_rw <= PWDATA[2];
            if (PWDATA[1] && PWDATA[0] && !busy)
              start_pending <= 1'b1;
          end

          A_SLAVE:  slave_addr <= PWDATA[6:0];
          A_REG:    reg_addr   <= PWDATA[7:0];
          A_RDLEN:  rd_len     <= PWDATA[7:0];
          A_WRLEN:  wr_len     <= PWDATA[7:0];
          A_PRECLK: pre_clk    <= PWDATA[15:0];

          A_TXDATA: begin
            wr_data       <= PWDATA[7:0];
            wr_data_valid <= 1'b1;
          end

          // W1C for sticky status bits:
          // bit[1] clear done_sticky
          // bit[2] clear nack_sticky
          // bit[3] clear rx_valid
          A_STATUS: begin
            if (PWDATA[1]) done_sticky <= 1'b0;
            if (PWDATA[2]) nack_sticky <= 1'b0;
            if (PWDATA[3]) rx_valid    <= 1'b0;
          end

          default: ;
        endcase
      end

      // Reading RXDATA consumes rx_valid
      if (apb_rd && (PADDR == A_RXDATA))
        rx_valid <= 1'b0;
    end
  end

  always @(*) begin
    PRDATA = 32'h0;
    case (PADDR)
      A_CTRL:   PRDATA = {29'd0, cmd_rw, 1'b0, enable};
      A_SLAVE:  PRDATA = {25'd0, slave_addr};
      A_REG:    PRDATA = {24'd0, reg_addr};
      A_RDLEN:  PRDATA = {24'd0, rd_len};
      A_WRLEN:  PRDATA = {24'd0, wr_len};
      A_PRECLK: PRDATA = {16'd0, pre_clk};
      A_TXDATA: PRDATA = {24'd0, wr_data};
      A_RXDATA: PRDATA = {24'd0, rxdata_hold};
      // STATUS = {28'd0, rx_valid[3], nack_sticky[2], done_sticky[1], busy[0]}
      A_STATUS: PRDATA = {28'd0, rx_valid, nack_sticky, done_sticky, busy};
      default:  PRDATA = 32'h0;
    endcase
  end

endmodule
