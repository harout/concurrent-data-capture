// This module is used to read from multiple
// mcp3002 ICs concurrently. All the mcp3002
// ICs should share the same clock line with
// traces of equal length. 

module mcp3002array #(// The number of mcp3002 ICs we are interfaced with.
                      // All the mcp3002 ICs will get the same clock, CS,
                      // and MOSI but each will have its own MISO line.
                      parameter NUM_ELEMENTS = 4,

                      // We prepend each sample pushed onto the
                      // FIFO with a sample number so that we can
                      // verify that samples aren't being dropped.
                      // The sample number is held in a register of
                      // COUNTER_WIDTH size.
                      parameter COUNTER_WIDTH = 8,
                      
                      // Divide the FPGA clock by the first
                      // number to produce the sample rate
                      // specified as the second number (in Hz). 
                      // 10 156250.0
                      // 20 78125.0
                      // 25 62500.0
                      parameter CLOCK_DIV = 25,
                      
                      // How many bits do we need to store the number
                      // of ticks of the main clock
                      parameter CLOCK_TICKS_CNTR_SZ = 5
                      )(
    input clk,
    output reg mosi,
    output reg spi_clock = 1'b1,
    output reg chip_select = 1'b1,
    input [NUM_ELEMENTS - 1:0] miso,
    input fifo_full,
    output reg fifo_write_enable,
    output reg [NUM_ELEMENTS * 10 + COUNTER_WIDTH - 1:0] sample_values = {(NUM_ELEMENTS * 10 + COUNTER_WIDTH - 1){1'b0}}
    );

   // Incremented once per sample. Used to watch
   // for discontinuities.
   reg[COUNTER_WIDTH - 1:0] sample_counter = {COUNTER_WIDTH{1'b0}};
   
   // Counts up ticks of the FPGA clock so that we
   // can take an action every CLOCK_DIV ticks.
   reg[CLOCK_TICKS_CNTR_SZ - 1:0] main_clock_count = {CLOCK_TICKS_CNTR_SZ{1'b0}};
   
   // Counts both the positive and negative edges of 
   // the SPI clock.
   reg[4:0] spi_clock_count = 5'b0;
   
   // Samples from the ADC are 10 bits.
   reg[9:0] last_sample[NUM_ELEMENTS - 1:0];
      
   reg [7:0] i;
   
   always @(posedge clk) begin: SPI_OPERATION
      fifo_write_enable <= 1'b0;
      chip_select <= chip_select;
      mosi <= mosi;
      sample_values <= sample_values;
      spi_clock <= spi_clock;
      spi_clock_count <= spi_clock_count;
      main_clock_count <= main_clock_count + 1'b1;
      sample_counter <= sample_counter;
      
      // In general, we set MOSI on the odd numbered edges
      // and read MISO on the even numbered edges.
      if (main_clock_count == CLOCK_DIV) begin
         spi_clock_count <= spi_clock_count + 1'b1;
         main_clock_count <= {CLOCK_TICKS_CNTR_SZ{1'b0}};               
         begin
            case(spi_clock_count)
            // Odd numbers are the negative edges of
            // the spi clock, where we set data. 

            // The datasheet says...
            // The first clock received with CS low 
            // and DIN high will constitute a start
            // bit.
            0:
               begin
                  // Set the chip select line high,
                  // so that we start from a known 
                  // state.
                  chip_select <= 1'b1;
                  mosi <= 1'b0;
                  spi_clock <= 1'b0;
                end
            1:
               begin
                  // This is first negative edge.
                  //
                  // Pull chip select low to signify 
                  // that we are going to talk to the
                  // chip. Also, mosi needs to be high
                  // when the positive edge of the spi
                  // clock occurs so that it is interpreted
                  // as the stat bit.
                  chip_select <= 1'b0;
                  mosi <= 1'b1;
                  spi_clock <= 1'b0;
               end
            5:
               begin
                  // This is the third negative edge.
                  //
                  // We need to specify that we want 
                  // to read channel 0.
                  mosi <= 1'b0;
                  spi_clock <= ~spi_clock;
               end
            7:
               begin
                  // This is the fourth negative edge.
                  //
                  // We need to specify that we want 
                  // data MSB first.
                  mosi <= 1'b1;
                  spi_clock <= ~spi_clock;
               end
             12,14,16,18,20,22,24,26,28,30:
               begin
                  for (i = 0; i < NUM_ELEMENTS; i = i + 1)
                  begin
                     // Shift left one bit
                     last_sample[i][9:1] <= last_sample[i][8:0];
                     
                     // Store MISO in the LSB position.
                     last_sample[i][0] <= miso[i];
                  end
                  
                  spi_clock <= ~spi_clock;
               end
             31:
               begin
                  // End the way we started.
                  chip_select <= 1'b1;
                  mosi <= 1'b0;
                  spi_clock <= 1'b0;
                  
                  sample_counter <= sample_counter + 1'b1;
                  if (fifo_full == 1'b0) begin
                     sample_values <= {sample_counter,
                                       last_sample[0], 
                                       last_sample[1], 
                                       last_sample[2], 
                                       last_sample[3]};
                     fifo_write_enable <= 1'b1;
                  end                  
               end
             default:
               begin
                  chip_select <= chip_select;  
                  mosi <= mosi;
                  spi_clock <= ~spi_clock;
               end
            endcase
         end
      end
   end
  

endmodule