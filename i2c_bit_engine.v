module i2c_bit_engine (
    input  wire clk,
    input  wire rst_n,

    input  wire sda_in,
    input  wire scl_in,
    input  wire core_en,
    input  wire scl_phase,

    input  wire bit_start,
    input  wire bit_dir,
    input  wire tx_bit,

    output reg  sda_drive_low,
    output reg  bit_rx_value,
    output reg  bit_last,
    output reg  bit_done,
    output reg  busy
);

  localparam [1:0]
    ST_IDLE      = 2'd0,
    ST_LOW_SETUP = 2'd1,
    ST_HIGH_WAIT = 2'd2;

  reg [1:0] state;
  reg       latched_dir;
  reg [1:0] high_wait_cnt;

  wire real_scl_high = (scl_phase == 1'b1) && (scl_in == 1'b1);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state         <= ST_IDLE;
      sda_drive_low <= 1'b0;
      bit_rx_value  <= 1'b0;
      bit_last      <= 1'b0;
      bit_done      <= 1'b0;
      busy          <= 1'b0;
      latched_dir   <= 1'b0;
      high_wait_cnt <= 2'd0;
    end else begin
      bit_done <= 1'b0;

      case (state)
        ST_IDLE: begin
          busy          <= 1'b0;
          high_wait_cnt <= 2'd0;

          if (bit_start) begin
            busy  <= 1'b1;
            state <= ST_LOW_SETUP;
          end
        end

        ST_LOW_SETUP: begin
          busy <= 1'b1;

          if (scl_phase == 1'b0) begin
            latched_dir <= bit_dir;

            if (bit_dir == 1'b0) begin
              sda_drive_low <= (tx_bit == 1'b0);
              bit_last      <= tx_bit;
            end else begin
              sda_drive_low <= 1'b0;
            end

            high_wait_cnt <= 2'd0;
            state         <= ST_HIGH_WAIT;
          end
        end

        ST_HIGH_WAIT: begin
          busy <= 1'b1;

          if (real_scl_high) begin
            if (high_wait_cnt != 2'd2) begin
              high_wait_cnt <= high_wait_cnt + 2'd1;
            end else begin
              if (latched_dir == 1'b1) begin
                bit_rx_value <= sda_in;
                bit_last     <= sda_in;
              end

              bit_done <= 1'b1;
              busy     <= 1'b0;
              state    <= ST_IDLE;
            end
          end
        end

        default: begin
          state <= ST_IDLE;
          busy  <= 1'b0;
        end
      endcase
    end
  end

endmodule
