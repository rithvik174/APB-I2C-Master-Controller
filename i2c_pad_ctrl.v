module i2c_pad_ctrl (
    input  wire clk,
    input  wire rst_n,

    // From core/bit-FSM (intent signals)
    input  wire sda_drive_low,   // 1 => pull SDA low, 0 => release
    input  wire scl_drive_low,   // 1 => pull SCL low, 0 => release

    // To core (clean samples)
    output wire sda_in,
    output wire scl_in,

    // Pads (physical pins)
    input  wire sda_pad_i,
    output wire sda_pad_o,
    output wire sda_padoen_o,    // ACTIVE-HIGH OE: 1=drive low, 0=Hi-Z

    input  wire scl_pad_i,
    output wire scl_pad_o,
    output wire scl_padoen_o     // ACTIVE-HIGH OE: 1=drive low, 0=Hi-Z
);

    //--------------------------------------------------------------------------
    // Open-drain drive
    //--------------------------------------------------------------------------
    assign sda_pad_o    = 1'b0;          // only ever drive 0
    assign sda_padoen_o = sda_drive_low; // 1 => enable low driver

    assign scl_pad_o    = 1'b0;          // only ever drive 0
    assign scl_padoen_o = scl_drive_low; // 1 => enable low driver

    //--------------------------------------------------------------------------
    // 2-FF synchronizers for asynchronous pad inputs
    //--------------------------------------------------------------------------
    reg sda_1st_flop;
    reg scl_1st_flop;
    reg sda_2nd_flop;
	reg scl_2nd_flop;
    always @(posedge clk or negedge rst_n) 
	 begin
        if (!rst_n) 
		  begin
            sda_1st_flop <= 1'b1;
		    scl_1st_flop <= 1'b1;
			sda_2nd_flop <= 1'b1;
			scl_2nd_flop <= 1'b1;
          end
		else 
		   begin
            sda_1st_flop <= sda_pad_i;
		    scl_1st_flop <= scl_pad_i;
			sda_2nd_flop <= sda_1st_flop;
			scl_2nd_flop <= scl_1st_flop;
           end
    end

    assign sda_in = sda_2nd_flop;
    assign scl_in = scl_2nd_flop;

endmodule