module i2c_cond_gen (
    input  wire clk,
    input  wire rst_n,

    input  wire core_en,
    input  wire scl_phase,

    input  wire scl_in,
    input  wire sda_in,

    input  wire req_start,
    input  wire req_rep_start,
    input  wire req_stop,

    output reg  sda_force_low,
    output reg  sda_force_release,
    output reg  scl_force_low,

    output reg  busy,
    output reg  cond_done
);

  localparam [2:0]
    ST_IDLE    = 3'd0,
    ST_WAIT_L  = 3'd1,
    ST_REL_SDA = 3'd2,
    ST_WAIT_H  = 3'd3,
    ST_DO1     = 3'd4,
    ST_DO2     = 3'd5,
    ST_DONE    = 3'd6;

  localparam [1:0]
    OP_NONE  = 2'd0,
    OP_START = 2'd1,
    OP_RSTA  = 2'd2,
    OP_STOP  = 2'd3;

  reg [2:0] state, next_state;
  reg [1:0] op, op_n;

  always @(*) begin
    next_state = state;
    op_n       = op;

    case (state)
      ST_IDLE: begin
        if (req_start) begin
          next_state = ST_WAIT_H;
          op_n       = OP_START;
        end else if (req_rep_start) begin
          next_state = ST_WAIT_L;
          op_n       = OP_RSTA;
        end else if (req_stop) begin
          next_state = ST_WAIT_H;
          op_n       = OP_STOP;
        end
      end

      ST_WAIT_L: begin
        if (scl_in == 1'b0)
          next_state = ST_REL_SDA;
      end

      ST_REL_SDA: begin
        next_state = ST_WAIT_H;
      end

      ST_WAIT_H: begin
        if (scl_in == 1'b1)
          next_state = ST_DO1;
      end

      ST_DO1: begin
        if (op == OP_STOP)
          next_state = ST_DO2;
        else
          next_state = ST_DONE;
      end

      ST_DO2: begin
        next_state = ST_DONE;
      end

      ST_DONE: begin
        next_state = ST_IDLE;
        op_n       = OP_NONE;
      end

      default: begin
        next_state = ST_IDLE;
        op_n       = OP_NONE;
      end
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state             <= ST_IDLE;
      op                <= OP_NONE;
      sda_force_low     <= 1'b0;
      sda_force_release <= 1'b0;
      scl_force_low     <= 1'b0;
      busy              <= 1'b0;
      cond_done         <= 1'b0;
    end else begin
      state     <= next_state;
      op        <= op_n;
      cond_done <= 1'b0;

      case (state)
        ST_IDLE: begin
          busy              <= 1'b0;
          sda_force_low     <= 1'b0;
          sda_force_release <= 1'b0;
          scl_force_low     <= 1'b0;
          if (req_start || req_rep_start || req_stop)
            busy <= 1'b1;
        end

        ST_WAIT_L: begin
          busy              <= 1'b1;
          sda_force_low     <= 1'b0;
          sda_force_release <= 1'b1;
          scl_force_low     <= 1'b1;
        end

        ST_REL_SDA: begin
          busy              <= 1'b1;
          sda_force_low     <= 1'b0;
          sda_force_release <= 1'b1;
          scl_force_low     <= 1'b1;
        end

        ST_WAIT_H: begin
          busy          <= 1'b1;
          scl_force_low <= 1'b0;

          if (op == OP_STOP) begin
            sda_force_low     <= 1'b1;
            sda_force_release <= 1'b0;
          end else begin
            sda_force_low     <= 1'b0;
            sda_force_release <= 1'b1;
          end
        end

        ST_DO1: begin
          busy          <= 1'b1;
          scl_force_low <= 1'b0;

          if (op == OP_STOP) begin
            sda_force_low     <= 1'b1;
            sda_force_release <= 1'b0;
          end else begin
            sda_force_low     <= 1'b1;
            sda_force_release <= 1'b0;
          end
        end

        ST_DO2: begin
          busy              <= 1'b1;
          scl_force_low     <= 1'b0;
          sda_force_low     <= 1'b0;
          sda_force_release <= 1'b1;
        end

        ST_DONE: begin
          busy          <= 1'b1;
          cond_done     <= 1'b1;
          scl_force_low <= 1'b0;

          if (op == OP_STOP) begin
            sda_force_low     <= 1'b0;
            sda_force_release <= 1'b1;
          end else begin
            sda_force_low     <= 1'b1;
            sda_force_release <= 1'b0;
          end
        end
      endcase
    end
  end

  wire _unused = core_en | scl_phase | sda_in;

endmodule
