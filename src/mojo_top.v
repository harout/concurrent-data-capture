module mojo_top(
    // 50MHz clock input
    input clk,

    output eth_spi_mosi,
    input eth_spi_miso,
    output eth_spi_ss_n,
    output eth_spi_sck,
     
    output audio_sampler_mosi,
    output audio_sampler_chip_select,
    output audio_sampler_spi_clock,
    input [3:0] audio_sampler_miso
    );

`include "wiznet5500_parameters.v"


reg fifo_read_enabled = 1'b0;
wire [47:0] fifo_data_out;
wire fifo_write_enabled;
wire fifo_empty;
wire fifo_full;
wire fifo_data_out_valid;

// This holds data from the FIFO until we hand
// the data off to the ethernet module.
reg [47:0] buffer = 48'b0;
reg buffer_valid = 1'b0;

// Used to flush data from the ehternet module
// every so often
reg [7:0] counter = 8'd0;
reg flush_requested = 1'b0;
reg [47:0] data_to_ethernet = 48'b111111000000_111111000000_111111000000_111111000000;
reg data_out_valid = 1'b0;
`ifdef WIZNET5500_ACCEPT_INSTRUCTIONS
reg [31:0] instruction_input = 32'd0;
reg instruction_input_valid = 1'b0;
`endif
wire ethernet_available;


//assign led[7:0] = 8'b00000000;
reg has_pushed_samples = 1'b0;
wire [47:0] sample_values;


wiznet5500 eth_iface (
    .clk(clk),
    .miso(eth_spi_miso),
    .mosi(eth_spi_mosi),
    .spi_clk(eth_spi_sck),
    .spi_chip_select_n(eth_spi_ss_n),
    .is_available(ethernet_available),
	 .data_input(data_to_ethernet),
	 .data_input_valid(data_out_valid),
	 .flush_requested(flush_requested)
    `ifdef WIZNET5500_READ_DATA
    .data_read(data_read),
    .data_read_valid(data_read_valid),
    `endif
    `ifdef WIZNET5500_ACCEPT_INSTRUCTIONS
    .instruction_input_valid(instruction_input_valid),
    .instruction_input(instruction_input),
    `endif
);


fifo fifo
(
    .clk(clk),
    .data_in(sample_values),
    .data_out(fifo_data_out),
    .write_enabled(fifo_write_enabled),
    .read_enabled(fifo_read_enabled),
    .fifo_empty(fifo_empty),
    .fifo_full(fifo_full),
    .data_out_valid(fifo_data_out_valid)
);


mcp3002array mcp3002array
(
   .clk(clk),
   .mosi(audio_sampler_mosi),
   .chip_select(audio_sampler_chip_select),
   .spi_clock(audio_sampler_spi_clock),
   .miso(audio_sampler_miso),
   .fifo_full(fifo_full),
   .fifo_write_enable(fifo_write_enabled),
   .sample_values(sample_values)
);


// Take sample data from the FIFO and push it to the ethernet module.
// Every so often, ask the ethernet module to send the contents of its
// TX buffer.
always @(posedge clk) begin
	data_out_valid <= 1'b0;
	data_to_ethernet <= data_to_ethernet;
   has_pushed_samples <= has_pushed_samples;
	flush_requested <= 1'b0;
	counter <= counter;   
   buffer_valid <= buffer_valid;
   data_to_ethernet <= data_to_ethernet;
   buffer <= buffer;
   fifo_read_enabled <= 1'b0;
   
   if (fifo_data_out_valid == 1'b1) begin
      buffer <= fifo_data_out;
      buffer_valid <= 1'b1;
   end else if (buffer_valid == 1'b0 && fifo_empty == 1'b0 && fifo_read_enabled == 1'b0) begin
      fifo_read_enabled <= 1'b1;
   end else if (ethernet_available) begin
		if (counter % 8'b00100000 == 0 && has_pushed_samples == 1'b1) begin
         // After pushing data into the ethernet module for a while,
         // request that the data be sent out.
         flush_requested <= 1'b1;
			has_pushed_samples <= 1'b0;
		end else if (buffer_valid == 1'b1) begin
         data_to_ethernet <= buffer;
			counter <= counter + 1'b1;
			has_pushed_samples <= 1'b1;
			data_out_valid <= 1'b1;
         buffer_valid <= 1'b0;
		end
	end
end

endmodule