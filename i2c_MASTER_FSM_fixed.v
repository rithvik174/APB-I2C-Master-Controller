module i2c_transaction_fsm (
    input  wire        clk,
    input  wire        rst_n,

    // Command (APB wrapper)
    input  wire        cmd_start,      // 1-cycle pulse
    input  wire        cmd_rw,         // 0=write, 1=read
    input  wire [6:0]  slave_addr,
    input  wire [7:0]  reg_addr,
    input  wire [7:0]  rd_len,
    input  wire [7:0]  wr_len,
    input  wire [7:0]  wr_data,
    input  wire        wr_data_valid,  // kept for compatibility; not used for single holding-register write path

    // Status/data out
    output reg         busy,
    output reg         done,           // 1-cycle pulse
    output reg         error_nack,     // sticky until next cmd_start
    output reg [7:0]   rd_byte,
    output reg         rd_byte_valid,  // 1-cycle pulse per received byte

    // Bus condition generator
    output reg         cond_start_req,     // 1-cycle pulse
    output reg         cond_repstart_req,  // 1-cycle pulse
    output reg         cond_stop_req,      // 1-cycle pulse
    input  wire        cond_done,
    input  wire        cond_busy,

    // To byte_engine
    output reg         byte_start,      // 1-cycle pulse
    output reg         byte_dir,        // 0=TX byte, 1=RX byte
    output reg [7:0]   tx_byte,
    output reg         master_ack,      // after RX byte: 0=ACK, 1=NACK

    // From byte_engine
    input  wire        byte_done,       // 1-cycle pulse
    input  wire        ack_ok,          // valid after TX byte
    input  wire [7:0]  rx_byte
);

  // Latch command fields on cmd_start
  reg        cmd_rw_l;
  reg [6:0]  slave_addr_l;
  reg [7:0]  reg_addr_l;
  reg [7:0]  rd_len_l;
  reg [7:0]  wr_len_l;

  reg [7:0]  rd_cnt;
  reg [7:0]  wr_cnt;

  localparam [4:0]
    S_IDLE          = 5'd0,
    S_START_REQ     = 5'd1,
    S_START_WAIT    = 5'd2,
    S_SLA_W_SEND    = 5'd3,
    S_SLA_W_WAIT    = 5'd4,
    S_REG_SEND      = 5'd5,
    S_REG_WAIT      = 5'd6,
    S_WR_SEND       = 5'd7,
    S_WR_WAIT       = 5'd8,
    S_RSTA_REQ      = 5'd9,
    S_RSTA_WAIT     = 5'd10,
    S_SLA_R_SEND    = 5'd11,
    S_SLA_R_WAIT    = 5'd12,
    S_RD_SEND       = 5'd13,
    S_RD_WAIT       = 5'd14,
    S_STOP_REQ      = 5'd15,
    S_STOP_WAIT     = 5'd16,
    S_DONE          = 5'd17;

  reg [4:0] state, next_state;

  always @(*) begin
    next_state = state;

    case (state)
      S_IDLE:        if (cmd_start) next_state = S_START_REQ;
      S_START_REQ:   next_state = S_START_WAIT;
      S_START_WAIT:  if (cond_done) next_state = S_SLA_W_SEND;

      S_SLA_W_SEND:  next_state = S_SLA_W_WAIT;
      S_SLA_W_WAIT:  if (byte_done) next_state = (ack_ok ? S_REG_SEND : S_STOP_REQ);

      S_REG_SEND:    next_state = S_REG_WAIT;
      S_REG_WAIT: begin
        if (byte_done) begin
          if (!ack_ok) begin
            next_state = S_STOP_REQ;
          end else if (cmd_rw_l) begin
            next_state = (rd_len_l == 8'd0) ? S_STOP_REQ : S_RSTA_REQ;
          end else begin
            next_state = (wr_len_l == 8'd0) ? S_STOP_REQ : S_WR_SEND;
          end
        end
      end

      // Single holding-register write path: directly launch write byte.
      S_WR_SEND:     next_state = S_WR_WAIT;
      S_WR_WAIT: begin
        if (byte_done) begin
          if (!ack_ok) next_state = S_STOP_REQ;
          else if ((wr_cnt + 8'd1) >= wr_len_l) next_state = S_STOP_REQ;
          else next_state = S_WR_SEND;
        end
      end

      S_RSTA_REQ:    next_state = S_RSTA_WAIT;
      S_RSTA_WAIT:   if (cond_done) next_state = S_SLA_R_SEND;

      S_SLA_R_SEND:  next_state = S_SLA_R_WAIT;
      S_SLA_R_WAIT:  if (byte_done) next_state = (ack_ok ? S_RD_SEND : S_STOP_REQ);

      S_RD_SEND:     next_state = S_RD_WAIT;
      S_RD_WAIT: begin
        if (byte_done) begin
          if ((rd_cnt + 8'd1) >= rd_len_l) next_state = S_STOP_REQ;
          else next_state = S_RD_SEND;
        end
      end

      S_STOP_REQ:    next_state = S_STOP_WAIT;
      S_STOP_WAIT:   if (cond_done) next_state = S_DONE;
      S_DONE:        next_state = S_IDLE;

      default:       next_state = S_IDLE;
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state             <= S_IDLE;
      busy              <= 1'b0;
      done              <= 1'b0;
      error_nack        <= 1'b0;
      rd_byte           <= 8'd0;
      rd_byte_valid     <= 1'b0;
      cond_start_req    <= 1'b0;
      cond_repstart_req <= 1'b0;
      cond_stop_req     <= 1'b0;
      byte_start        <= 1'b0;
      byte_dir          <= 1'b0;
      tx_byte           <= 8'd0;
      master_ack        <= 1'b1;
      cmd_rw_l          <= 1'b0;
      slave_addr_l      <= 7'd0;
      reg_addr_l        <= 8'd0;
      rd_len_l          <= 8'd0;
      wr_len_l          <= 8'd0;
      rd_cnt            <= 8'd0;
      wr_cnt            <= 8'd0;
    end else begin
      state             <= next_state;
      done              <= 1'b0;
      rd_byte_valid     <= 1'b0;
      cond_start_req    <= 1'b0;
      cond_repstart_req <= 1'b0;
      cond_stop_req     <= 1'b0;
      byte_start        <= 1'b0;

      case (state)
        S_IDLE: begin
          busy <= 1'b0;
          if (cmd_start) begin
            cmd_rw_l     <= cmd_rw;
            slave_addr_l <= slave_addr;
            reg_addr_l   <= reg_addr;
            rd_len_l     <= rd_len;
            wr_len_l     <= wr_len;
            error_nack   <= 1'b0;
            rd_cnt       <= 8'd0;
            wr_cnt       <= 8'd0;
            busy         <= 1'b1;
          end
        end

        S_START_REQ: begin
          cond_start_req <= 1'b1;
        end

        S_SLA_W_SEND: begin
          byte_dir   <= 1'b0;
          tx_byte    <= {slave_addr_l, 1'b0};
          byte_start <= 1'b1;
        end

        S_SLA_W_WAIT: begin
          if (byte_done && !ack_ok) error_nack <= 1'b1;
        end

        S_REG_SEND: begin
          byte_dir   <= 1'b0;
          tx_byte    <= reg_addr_l;
          byte_start <= 1'b1;
        end

        S_REG_WAIT: begin
          if (byte_done && !ack_ok) error_nack <= 1'b1;
        end

        S_WR_SEND: begin
          byte_dir   <= 1'b0;
          tx_byte    <= wr_data;
          byte_start <= 1'b1;
        end

        S_WR_WAIT: begin
          if (byte_done) begin
            if (!ack_ok) error_nack <= 1'b1;
            else wr_cnt <= wr_cnt + 8'd1;
          end
        end

        S_RSTA_REQ: begin
          cond_repstart_req <= 1'b1;
        end

        S_SLA_R_SEND: begin
          byte_dir   <= 1'b0;
          tx_byte    <= {slave_addr_l, 1'b1};
          byte_start <= 1'b1;
        end

        S_SLA_R_WAIT: begin
          if (byte_done && !ack_ok) error_nack <= 1'b1;
        end

        S_RD_SEND: begin
          byte_dir   <= 1'b1;
          master_ack <= ((rd_cnt + 8'd1) >= rd_len_l) ? 1'b1 : 1'b0;
          byte_start <= 1'b1;
        end

        S_RD_WAIT: begin
          if (byte_done) begin
            rd_byte       <= rx_byte;
            rd_byte_valid <= 1'b1;
            rd_cnt        <= rd_cnt + 8'd1;
          end
        end

        S_STOP_REQ: begin
          cond_stop_req <= 1'b1;
        end

        S_DONE: begin
          busy <= 1'b0;
          done <= 1'b1;
        end
      endcase
    end
  end

  // avoid unused-port warnings in some simulators
  wire _unused_ok = cond_busy | wr_data_valid;

endmodule
