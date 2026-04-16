module i2c_clk_div (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        run_en,
    input  wire        scl_drive_low,
    input  wire        scl_in,
    input  wire [15:0] pre_clk,
    output reg         scl_phase,
    output reg         core_en,
    output wire        stretch_active
);

  reg [15:0] count;
  reg        run_d;
  reg        tick_pending;

  assign stretch_active = run_en &&
                          (scl_phase == 1'b1) &&
                          (scl_drive_low == 1'b0) &&
                          (scl_in == 1'b0);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scl_phase    <= 1'b1;
      count        <= 16'd0;
      core_en      <= 1'b0;
      run_d        <= 1'b0;
      tick_pending <= 1'b0;
    end else begin
      core_en <= 1'b0;
      run_d   <= run_en;

      if (!run_en) begin
        scl_phase    <= 1'b1;
        count        <= 16'd0;
        tick_pending <= 1'b0;
      end else if (run_en && !run_d) begin
        scl_phase    <= 1'b0;
        count        <= pre_clk;
        tick_pending <= 1'b1;
      end else if (tick_pending) begin
        if (stretch_active) begin
          tick_pending <= 1'b1;
          count        <= count;
        end else begin
          core_en      <= 1'b1;
          tick_pending <= 1'b0;
        end
      end else if (stretch_active) begin
        scl_phase <= scl_phase;
        count     <= count;
      end else begin
        if (count == 16'd0) begin
          scl_phase    <= ~scl_phase;
          count        <= pre_clk;
          tick_pending <= 1'b1;
        end else begin
          count <= count - 16'd1;
        end
      end
    end
  end

endmodule
