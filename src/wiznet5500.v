// This module interfaces with the wiznet5500. 
// The only funcitonality realy being used here
// is the transmission of UDP packets.
module wiznet5500#(parameter DATA_READ_SIZE = 8)
   (
   input clk,
   input miso,
 
   // Flag for the user of this module to indicate
   // that the signal at instruction_input is valid
   `ifdef WIZNET5500_ACCEPT_INSTRUCTIONS
   input instruction_input_valid,
   input [31:0] instruction_input,
   `endif
 
	input data_input_valid,
	input[47:0] data_input,
	
   // It is up to the client to request that the module
   // send the data in its TX buffer often enough that
   // it doesn't write over itself. Generaly this shouldn't
   // be a problem because data is loaded into the buffer
   // more slowly then it is sent out.
	input flush_requested, 
 
   output reg mosi,
   output reg spi_clk = 1'b0,
   output reg spi_chip_select_n,
 
   // This module is intended to support streaming
   // out data over UDP. Data read is meant to hold
   // the responses from the last 6 commands each
   // of which returns a byte of data. When you are
   // reading registers you will likely only ever
   // want the results from the last read, last two reads or
   // the last six reads. Some data is two bytes wide
   // and requires two register reads (for instance,
   // pointer addresses for the TX buffer). MAC
   // addresses fit in six bytes.
   output reg[DATA_READ_SIZE - 1:0] data_read = {(DATA_READ_SIZE - 1){1'b0}},
   
   `ifdef WIZNET5500_READ_DATA
   output reg data_read_valid = 1'b0,
   `endif
   
   output is_available
   );


parameter STATE_UNDEFINED =			 3'b000;
parameter STATE_IDLE =               3'b001;
parameter STATE_SENDING_COMMAND =    3'b010;
parameter STATE_INITIALIZING =       3'b011;
parameter STATE_PUSHING_DATA =       3'b100;
parameter STATE_UPDATING_TX_PTR =    3'b101;
parameter STATE_SENDING_PACKET =		 3'b110; 

parameter TX_BUFFER_FREE_SPACE_THRESHOLD = 14'd8192;

reg is_busy = 1'b0;

`include "wiznet5500_parameters.v"

reg [31:0] current_instruction;
reg [7:0] spi_clock_count;
reg [2:0] state = STATE_INITIALIZING;
reg [2:0] next_state = STATE_UNDEFINED;
reg [5:0] initialization_progress = 6'b000000;
reg waiting_for_socket = 1'b0;
reg is_initialized = 1'b0;
reg read_free_space_progress = 3'b000;
reg [71:0] send_data_instruction;

`ifdef WIZNET5500_ACCEPT_INSTRUCTIONS
   assign is_available = !is_busy && !data_input_valid && !flush_requested && !instruction_input_valid;
`else
   assign is_available = !is_busy && !data_input_valid && !flush_requested;
`endif


// The address space for the write pointer exceeds the
// actual space available. The module itself handles the 
// mapping.
reg [15:0] tx_buffer_write_pointer = 16'd0;

always @(posedge clk) begin
   state <= state;   
   is_busy <= is_busy;
   spi_clk <= spi_clk;
   is_initialized <= is_initialized;
   initialization_progress <= initialization_progress;
   waiting_for_socket <= waiting_for_socket;
	current_instruction <= current_instruction;
	spi_clock_count <= spi_clock_count;
	spi_chip_select_n <= spi_chip_select_n;
   `ifdef WIZNET5500_READ_DATA
   data_read_valid <= data_read_valid;
   `endif	
   
	if (state == STATE_IDLE && flush_requested) begin
			spi_clk <= 1'b0;
         state <= STATE_SENDING_COMMAND;
         spi_chip_select_n <= 1'b0;
         spi_clock_count <= 8'b0;
         is_busy <= 1'b1;
         current_instruction <= {16'h0025, 8'b00001100, tx_buffer_write_pointer[7:0]};
			next_state <= STATE_UPDATING_TX_PTR;
         `ifdef WIZNET5500_READ_DATA
         data_read_valid <= 1'b0;
         `endif         
	end else if (state == STATE_UPDATING_TX_PTR) begin
			spi_clk <= 1'b0;
         state <= STATE_SENDING_COMMAND;
         spi_chip_select_n <= 1'b0;
         spi_clock_count <= 8'b0;
         is_busy <= 1'b1;
         current_instruction <= {16'h0024, 8'b00001100, tx_buffer_write_pointer[15:8]};
			next_state <= STATE_SENDING_PACKET;
         `ifdef WIZNET5500_READ_DATA
         data_read_valid <= 1'b0;
         `endif         
	end else if (state == STATE_SENDING_PACKET) begin
			spi_clk <= 1'b0;
         state <= STATE_SENDING_COMMAND;
         spi_chip_select_n <= 1'b0;
         spi_clock_count <= 8'b0;
         is_busy <= 1'b1;
         current_instruction <= SEND_PACKET_SOCKET_0;
			next_state <= STATE_UNDEFINED;
         `ifdef WIZNET5500_READ_DATA         
         data_read_valid <= 1'b0;
         `endif
   end else if (state == STATE_INITIALIZING && waiting_for_socket == 1'b1) begin
      // If the socket is open, then we are done initializing.
      // If not, reissue the command to read the socket state.
      if (data_read[7:0] == 8'b00100010) begin
         state <= STATE_IDLE;
         is_initialized <= 1'b1;
         is_busy <= 1'b0;
         waiting_for_socket <= 1'b0;
       end else begin
         spi_clk <= 1'b0;
         state <= STATE_SENDING_COMMAND;
         spi_chip_select_n <= 1'b0;
         spi_clock_count <= 8'b0;
         is_busy <= 1'b1;
         current_instruction <= READ_SOCKET_0_STATE;
         `ifdef WIZNET5500_READ_DATA         
         data_read_valid <= 1'b0;
         `endif
       end
   end else if (state == STATE_INITIALIZING) begin
      spi_clk <= 1'b0;
      state <= STATE_SENDING_COMMAND;
      initialization_progress <= initialization_progress + 6'b000001;
      spi_chip_select_n <= 1'b0;
      spi_clock_count <= 8'b0;
      is_busy <= 1'b1;
      `ifdef WIZNET5500_READ_DATA      
      data_read_valid <= 1'b0;
      `endif
      
      case (initialization_progress)
         // TODO: Perhaps add software reset here?
      
         0: current_instruction <= SET_PHY_MODE;
      
         // Set our MAC address
         1: current_instruction <= SET_MAC_ADDRESS_BYTE_0;
         2: current_instruction <= SET_MAC_ADDRESS_BYTE_1;
         3: current_instruction <= SET_MAC_ADDRESS_BYTE_2;
         4: current_instruction <= SET_MAC_ADDRESS_BYTE_3;
         5: current_instruction <= SET_MAC_ADDRESS_BYTE_4;
         6: current_instruction <= SET_MAC_ADDRESS_BYTE_5;
       
         // Set our IP address
         7: current_instruction <= SET_SOURCE_IP_ADDRESS_0;
         8: current_instruction <= SET_SOURCE_IP_ADDRESS_1;
         9: current_instruction <= SET_SOURCE_IP_ADDRESS_2;
         10: current_instruction <= SET_SOURCE_IP_ADDRESS_3;
       
         // Set the gateway address
         11: current_instruction <= SET_GATEWAY_ADDRESS_0;
         12: current_instruction <= SET_GATEWAY_ADDRESS_1;
         13: current_instruction <= SET_GATEWAY_ADDRESS_2;
         14: current_instruction <= SET_GATEWAY_ADDRESS_3;
       
         // Set the subnet mask
         15: current_instruction <= SET_SUBNET_MASK_0;
         16: current_instruction <= SET_SUBNET_MASK_1;
         17: current_instruction <= SET_SUBNET_MASK_2;
         18: current_instruction <= SET_SUBNET_MASK_3;
       
         // Set socket 0's mode
         19: current_instruction <= SET_SOCKET_0_MODE;
         
         // Set the size of socket 0's TX buffer
         20: current_instruction <= SET_SOCKET_0_TX_BFR_SZ;
       
         // Set the source port for socket 0
         21: current_instruction <= SET_SOCKET_0_SRC_PORT_0;
         22: current_instruction <= SET_SOCKET_0_SRC_PORT_1;
       
         // Send the command to open the socket
         23: current_instruction <= OPEN_SOCKET_0;

         // Set the destination IP address for socket 0
         24: current_instruction <= SET_SOCKET_0_DST_IP_0;
         25: current_instruction <= SET_SOCKET_0_DST_IP_1;
         26: current_instruction <= SET_SOCKET_0_DST_IP_2;
         27: current_instruction <= SET_SOCKET_0_DST_IP_3;
       
         // Set the destination port to socket 0
         28: current_instruction <= SET_SOCKET_0_DST_PRT_0;
         29: current_instruction <= SET_SOCKET_0_DST_PRT_1;
         
         // Send the command to read the socket state
         30: begin
               current_instruction <= READ_SOCKET_0_STATE;
               waiting_for_socket <= 1'b1;
             end
      endcase
   `ifdef WIZNET5500_ACCEPT_INSTRUCTIONS      
   end else if (state == STATE_IDLE && instruction_input_valid == 1'b1) begin
      spi_clk <= 1'b0;
      state <= STATE_SENDING_COMMAND;
      spi_chip_select_n <= 1'b0;
      spi_clock_count <= 8'b0;
      current_instruction <= instruction_input;
      `ifdef WIZNET5500_READ_DATA
      data_read_valid <= 1'b0;
      `endif
      is_busy <= 1'b1;
   `endif
	end else if (state == STATE_IDLE && data_input_valid == 1'b1) begin
		send_data_instruction <= {tx_buffer_write_pointer, 8'b00010100, data_input};
		spi_clk <= 1'b0;
      state <= STATE_PUSHING_DATA;
      spi_chip_select_n <= 1'b0;
      spi_clock_count <= 8'b0;
      is_busy <= 1'b1;
      `ifdef WIZNET5500_READ_DATA      
      data_read_valid <= 1'b0;
      `endif      
    end else if (state == STATE_SENDING_COMMAND && spi_clock_count > 31) begin
      // We have completed 32 ticks of the SPI clock in the
      // STATE_SENDING_COMMAND so we are done sending the
      // command and reading the response. We let the module
      // know we are done communicating and we declare that
      // the input we have collected is valid.
      spi_chip_select_n <= 1'b1;
      
      `ifdef WIZNET5500_READ_DATA
      data_read_valid <= 1'b1;
      `endif

      // Don't raise the idle flag if we are not yet
      // done initializing.
      if (is_initialized == 1'b1) begin         
			if (next_state == STATE_UNDEFINED) begin
				is_busy <= 1'b0;
				state <= STATE_IDLE;
			end else begin
				state <= next_state;
			end
      end else begin
         state <= STATE_INITIALIZING;
      end
	end else if (state == STATE_PUSHING_DATA && spi_clock_count > 71) begin
		spi_chip_select_n <= 1'b1;
		state <= STATE_IDLE;
      // 6 bytes are pushed per message
		tx_buffer_write_pointer <= tx_buffer_write_pointer + 16'd6;
		is_busy <= 1'b0;
    end else if (state == STATE_SENDING_COMMAND || state == STATE_PUSHING_DATA) begin
        // We are effectively clocking the module at half the clock rate
        // of the FPGA itself.
        spi_clk <= ~spi_clk;
        if (spi_clk == 1'b0) begin
            spi_clock_count <= spi_clock_count + 1'b1;              
        end
    end
end


// Read MISO on the positive edge of the SPI clock
// on edges 24-31
always @(posedge clk) begin
    if (spi_clk == 1'b0 && state == STATE_SENDING_COMMAND && spi_clock_count >= 24 && spi_clock_count <= 31) begin
         data_read <= {data_read[DATA_READ_SIZE - 2:0], miso};
    end
end


// Set MOSI on the negative edge of the SPI clock
// so that the value is stable by the time the positive edge
// occurs. 
always @(posedge clk) begin
    if (spi_clk == 1'b1 && state == STATE_SENDING_COMMAND && spi_clock_count < 8'd32) begin
		mosi <= current_instruction[8'd31 - spi_clock_count];
    end else if (spi_clk == 1'b1 && state == STATE_PUSHING_DATA && spi_clock_count < 8'd72) begin
		mosi <= send_data_instruction[8'd71 - spi_clock_count];
	end
end



endmodule