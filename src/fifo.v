
module fifo #(parameter DATA_WIDTH = 48,
              parameter ADDRESS_WIDTH = 8,
              parameter MAX_ENTRIES = 255)
(
    input wire clk,
    input wire[DATA_WIDTH - 1:0] data_in,
    output reg[DATA_WIDTH - 1:0] data_out,
    input wire write_enabled,
    input wire read_enabled,
    output reg fifo_empty,
    output reg fifo_full,
    output reg data_out_valid
);

reg[ADDRESS_WIDTH-1:0] fifo_counter = {(ADDRESS_WIDTH){1'b0}};
 
// Storage with MAX_ENTRIES unique entries with
// each entry having DATA_WIDTH bits of storage.
reg[DATA_WIDTH - 1:0] memory[0:MAX_ENTRIES - 1];
reg[ADDRESS_WIDTH - 1:0] write_pointer = {(ADDRESS_WIDTH){1'b0}};
reg[ADDRESS_WIDTH - 1:0] read_pointer = {(ADDRESS_WIDTH){1'b0}};


always @(fifo_counter)
begin : UPDATE_FLAGS
   fifo_empty = (fifo_counter==0);
   fifo_full = (fifo_counter == MAX_ENTRIES - 1);
end


always @(posedge clk)
begin : UPDATE_FIFO_COUNTER
   fifo_counter <= fifo_counter;

   if((!fifo_full && write_enabled) && (!fifo_empty && read_enabled)) begin
        fifo_counter <= fifo_counter;
   end else if(!fifo_full && write_enabled) begin
        fifo_counter <= fifo_counter + 1'b1;
   end else if(!fifo_empty && read_enabled) begin
       fifo_counter <= fifo_counter - 1'b1;
   end      
end


always @(posedge clk)
begin : READ_DATA_IN
	if(write_enabled && !fifo_full) begin
      // If a write has been requested and we
      // have space, store the data
      memory[write_pointer] <= data_in;
   end
end

always @(posedge clk)
begin
   write_pointer <= write_pointer;
   read_pointer <= read_pointer;

   if (!fifo_full && write_enabled) begin   
      write_pointer <= write_pointer + 1'b1;
   end
      
   if (read_enabled) begin
      if (fifo_empty) begin
         data_out <= 48'b0;
         data_out_valid <= 1'b0;
      end else begin
         // Set data_out if a read was requested
         // and we have data to provide.
         data_out <= memory[read_pointer];
         read_pointer <= read_pointer + 1'b1;
         data_out_valid <= 1'b1; 
      end
   end else begin
      data_out <= 48'b1;
      data_out_valid <= 1'b0;
   end
end

endmodule
