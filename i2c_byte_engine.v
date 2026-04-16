module i2c_byte_engine_v2 (
    input  wire       clk,
    input  wire       rst_n,

    // From master transaction FSM
    input  wire       byte_start,     // 1-cycle pulse
    input  wire       byte_dir,       // 0: TX byte, 1: RX byte
    input  wire [7:0] tx_byte,        // valid when byte_dir=0
    input  wire       master_ack,     // valid when byte_dir=1, 0=ACK,1=NACK after RX byte

    output reg        byte_done,      // 1-cycle pulse
    output reg        busy,
    output reg        ack_ok,         // valid after TX byte (1 if slave ACKed)
    output reg [7:0]  rx_byte,        // valid after RX byte

    // To/From bit engine
    input  wire       bit_done,       // 1-cycle pulse
    input  wire       bit_rx_value,

    output reg        bit_start_o,    // 1-cycle pulse
    output reg        bit_dir_o,      // 0: TX, 1: RX (for bit engine)
    output reg        tx_bit_o
);

  // FSM states
  localparam [2:0]
    S_IDLE     = 3'd0,
    S_KICK     = 3'd1,
    S_WAIT     = 3'd2,
    S_UPDATE   = 3'd3,
    S_ACK_KICK = 3'd4,
    S_ACK_WAIT = 3'd5,
    S_DONE     = 3'd6;

  reg [2:0] state, next_state;

  reg [7:0] shreg;
  reg [2:0] bit_cnt;     // counts remaining bits (7..0)
  reg       mode_dir;    // latched byte_dir

  // Next-state logic
  always @(*) begin
    next_state = state;
    case(state)
      S_IDLE:     if(byte_start) next_state = S_KICK;
      S_KICK:     next_state = S_WAIT;
      S_WAIT:     if(bit_done) next_state = S_UPDATE;
      S_UPDATE:   if(bit_cnt != 3'd0) next_state = S_KICK; else next_state = S_ACK_KICK;
      S_ACK_KICK: next_state = S_ACK_WAIT;
      S_ACK_WAIT: if(bit_done) next_state = S_DONE;
      S_DONE:     next_state = S_IDLE;
      default:    next_state = S_IDLE;
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      state       <= S_IDLE;
      busy        <= 1'b0;
      byte_done   <= 1'b0;
      ack_ok      <= 1'b0;
      rx_byte     <= 8'd0;
      bit_start_o <= 1'b0;
      bit_dir_o   <= 1'b0;
      tx_bit_o    <= 1'b1;
      shreg       <= 8'd0;
      bit_cnt     <= 3'd0;
      mode_dir    <= 1'b0;
    end else begin
      state       <= next_state;
      byte_done   <= 1'b0;
      bit_start_o <= 1'b0;

      case(state)
        S_IDLE: begin
          busy <= 1'b0;
          if (byte_start) begin
            // IMPORTANT: assert busy immediately when the byte is accepted.
            // This keeps the SCL divider alive across the byte-start boundary.
            busy     <= 1'b1;
            mode_dir <= byte_dir;
            bit_cnt  <= 3'd7;
            ack_ok   <= 1'b0;
            if (byte_dir == 1'b0)
              shreg <= tx_byte;
            else
              shreg <= 8'd0;
          end
        end

        S_KICK: begin
          bit_start_o <= 1'b1;
          busy        <= 1'b1;
          if(mode_dir == 1'b0) begin
            bit_dir_o <= 1'b0;
            tx_bit_o  <= shreg[7];
          end else begin
            bit_dir_o <= 1'b1;
            tx_bit_o  <= 1'b1;
          end
        end

        S_WAIT: begin
          busy <= 1'b1;
        end

        S_UPDATE: begin
          busy <= 1'b1;
          if(mode_dir == 1'b0)
            shreg <= {shreg[6:0], 1'b0};
          else
            shreg <= {shreg[6:0], bit_rx_value};

          if(bit_cnt != 3'd0)
            bit_cnt <= bit_cnt - 3'd1;
        end

        S_ACK_KICK: begin
          busy        <= 1'b1;
          bit_start_o <= 1'b1;
          if(mode_dir == 1'b0) begin
            // After TX byte: read slave ACK
            bit_dir_o <= 1'b1;
          end else begin
            // After RX byte: send master ACK/NACK
            bit_dir_o <= 1'b0;
            tx_bit_o  <= master_ack;
          end
        end

        S_ACK_WAIT: begin
          busy <= 1'b1;
        end

        S_DONE: begin
          busy <= 1'b0;
          if(mode_dir == 1'b0)
            ack_ok <= (bit_rx_value == 1'b0);
          else
            rx_byte <= shreg;
          byte_done <= 1'b1;
        end
      endcase
    end
  end

endmodule
