`default_nettype none

module pdm_detectors #(
    parameter WINDOW_SIZE = 16,     // Sliding window length in bits
    parameter THRESHOLD   = 14,     // Number of ones required for a valid echo detection
    parameter NUM_SENSORS = 3       // Number of PDM microphone sensors
)(
    input  wire                   clk,
    input  wire                   rst_n,          // Active-low asynchronous reset
    input  wire                   tx_trigger,     // Transmission start signal from controller
    input  wire [NUM_SENSORS-1:0] pdm_in,         // PDM microphone inputs
    output wire [NUM_SENSORS-1:0] echo_detected   // Detected echo pulses (single-cycle active high)
);
    // Instantiate an independent PDM detector unit for each microphone channel
    genvar i;
    generate
        for (i = 0; i < NUM_SENSORS; i = i + 1) begin : gen_pdm_channels
            pdm_detector_holdoff #(
                .WINDOW_SIZE    (WINDOW_SIZE),
                .THRESHOLD      (THRESHOLD)
            ) pdm_detector_unit (
                .clk           (clk),
                .rst_n         (rst_n),
                .tx_trigger    (tx_trigger),
                .pdm_in        (pdm_in[i]),
                .echo_detected (echo_detected[i])
            );
        end
    endgenerate

endmodule

module pdm_detector_holdoff #(
    parameter WINDOW_SIZE = 16,
    parameter THRESHOLD   = 14
)(
    input  wire clk,
    input  wire rst_n,
    input  wire tx_trigger,
    input  wire pdm_in,
    output wire echo_detected
);

    reg [WINDOW_SIZE-1:0] shift_reg;        // Holds the recent PDM bit history
    reg                   echo_raw;         // High when density exceeds threshold
    reg                   echo_raw_dly;     // Delayed echo_raw (1 cycle) for edge detection
    reg                   detect_pulse;     // Single-cycle pulse on rising edge of echo_raw
    reg                   listening;        // Active after tx_trigger, listening for echoes

    // Note: The delay ignores the initial startup peak that occurs when the ultrasonic/transmitting sensors are activated.
    reg [11:0] delay_counter;               // 12 bits is sufficient to count up to 4095
    reg delay_passed;                       // Flag indicating the requested cycles have elapsed
    
    // COMBINATORIAL: 
    // Dynamically calculate required bit width for the density sum (0 to WINDOW_SIZE)
    localparam DENSITY_WIDTH = $clog2(WINDOW_SIZE + 1);

    // Count the number of set bits (1s) in the current shift register
    reg [DENSITY_WIDTH-1:0] density;
    integer j;

    always @(*) begin
        density = {DENSITY_WIDTH{1'b0}};
        for (j = 0; j < WINDOW_SIZE; j = j + 1) begin
            density = density + {{(DENSITY_WIDTH-1){1'b0}}, shift_reg[j]};
        end
    end

    // SYNCHRONOUS: 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg    <= {WINDOW_SIZE{1'b0}};
            echo_raw     <= 1'b0;
            echo_raw_dly <= 1'b0;
            detect_pulse <= 1'b0;
            listening    <= 1'b0;
            delay_counter <= 12'd0;
            delay_passed  <= 1'b0;
        end else if (tx_trigger) begin
            // Reset window and start listening upon a transmission trigger
            shift_reg    <= {WINDOW_SIZE{1'b0}};
            echo_raw     <= 1'b0;
            echo_raw_dly <= 1'b0;
            detect_pulse <= 1'b0;
            listening    <= 1'b1;
            delay_counter <= 12'd0;
            delay_passed  <= 1'b0;
        end else if (listening) begin
            // Put the newest PDM-bit in the window register and push oldest bit out
            shift_reg <= {shift_reg[WINDOW_SIZE-2:0], pdm_in};

            // Wait until the sensor's startup peak (e.g. 4000 clock cycles) has passed (blanking window)
            // This prevents the echo of the transmission itself from being falsely detected.
            if (!delay_passed) begin
                if (delay_counter == 12'd4000) begin
                    delay_passed <= 1'b1;   // Delay period completed
                end else begin
                    delay_counter <= delay_counter + 1'b1;  // Increment counter
                end
            end 
            
            // Active only after the delay, check against the threshold
            else begin
                // Compare calculated density against the threshold
                if (density >= THRESHOLD) begin
                    echo_raw <= 1'b1;
                end else begin
                    echo_raw <= 1'b0;
                end

                // Edge detection (Rising edge: 0 -> 1 transition)
                echo_raw_dly <= echo_raw;
                
                if ((echo_raw == 1'b1) && (echo_raw_dly == 1'b0)) begin
                    detect_pulse <= 1'b1;
                    listening    <= 1'b0;   // Stop listening after detection so it fires only once
                end else begin
                    detect_pulse <= 1'b0;
                end
            end

        end else begin
            detect_pulse <= 1'b0;
        end
    end

    assign echo_detected = detect_pulse;

endmodule

/*
module pdm_detector #(
    parameter WINDOW_SIZE = 16,
    parameter THRESHOLD   = 13
)(
    input  wire clk,
    input  wire rst_n,
    input  wire tx_trigger,
    input  wire pdm_in,
    output wire echo_detected
);

    reg [WINDOW_SIZE-1:0] shift_reg;        // Holds the recent PDM bit history
    reg                   echo_raw;         // High when density exceeds threshold
    reg                   echo_raw_dly;     // Delayed echo_raw (1 cycle) for edge detection
    reg                   detect_pulse;     // Single-cycle pulse on rising edge of echo_raw
    reg                   listening;        // Active after tx_trigger, listening for echoes
    
    // COMBINATORIAL: 
    // Dynamically calculate required bit width for the density sum (0 to WINDOW_SIZE)
    localparam DENSITY_WIDTH = $clog2(WINDOW_SIZE + 1);

    // Count the number of set bits (1s) in the current shift register
    reg [DENSITY_WIDTH-1:0] density;
    integer j;

    always @(*) begin
        density = {DENSITY_WIDTH{1'b0}};
        for (j = 0; j < WINDOW_SIZE; j = j + 1) begin
            density = density + {{(DENSITY_WIDTH-1){1'b0}}, shift_reg[j]};
        end
    end

    // SYNCHRONOUS: 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg    <= {WINDOW_SIZE{1'b0}};
            echo_raw     <= 1'b0;
            echo_raw_dly <= 1'b0;
            detect_pulse <= 1'b0;
            listening    <= 1'b0;
        end else if (tx_trigger) begin
            // Reset window and start listening upon a transmission trigger
            shift_reg    <= {WINDOW_SIZE{1'b0}};
            echo_raw     <= 1'b0;
            echo_raw_dly <= 1'b0;
            detect_pulse <= 1'b0;
            listening    <= 1'b1;
        end else if (listening) begin
            // Put the newest PDM-bit in the window register and push oldest bit out
            shift_reg <= {shift_reg[WINDOW_SIZE-2:0], pdm_in};

            // Compare calculated density against the threshold
            if (density >= THRESHOLD) begin
                echo_raw <= 1'b1;
            end else begin
                echo_raw <= 1'b0;
            end

            // Edge detection (Rising edge: 0 -> 1 transition)
            echo_raw_dly <= echo_raw;
            
            if ((echo_raw == 1'b1) && (echo_raw_dly == 1'b0)) begin
                detect_pulse <= 1'b1;
                listening    <= 1'b0;   // Stop listening after detection so it fires only once
            end else begin
                detect_pulse <= 1'b0;
            end
        end else begin
            detect_pulse <= 1'b0;
        end
    end

    assign echo_detected = detect_pulse;

endmodule
*/