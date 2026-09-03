// Measurement controller.
//
// Sits between the outside world and the ping generator / echo detector.
// It owns the decision of WHEN a ping may fire, and it talks to the host
// over a tiny UART protocol.
//
// A ping fires only when ALL of these hold:
//   - mic_ready is high (mic has finished its power-up sequence and is in
//     ultrasonic mode; before that 40 kHz is filtered out and you would
//     capture nothing)
//   - at least LOCKOUT_TICKS have passed since the previous ping (the
//     transducer draws its burst energy from the 470 uF reservoir on the
//     PCB; pinging faster than it recharges gives weaker and weaker bursts)
//
// Ping requests come from three places, all treated the same:
//   - rising edge on the ext_start pin
//   - UART command 'P'
//   - the auto-measurement timer (one ping every AUTO_PERIOD_TICKS)
//
// UART commands (single bytes, host -> chip):
//   'A'  auto measurement ON       reply: status line
//   'S'  auto measurement OFF      reply: status line
//   'P'  single ping now           reply: nothing, or "B\n" if refused
//   '?'  query                     reply: status line
//
// UART replies (chip -> host), every line ends in '\n':
//   "AR\n" / "AW\n" / "SR\n" / "SW\n"
//         first char : A = auto on,  S = auto off
//         second char: R = mic ready, W = mic still warming up
//   "Dwww aa\n"
//         echo detected. www = echo start window (3 hex digits),
//         aa = angle (2 hex digits, 0..3F). One line per detected echo.
//   "N\n"   measurement finished with no echo detected
//   "B\n"   ping refused (mic not ready or lockout still running)
//
// All timers count tick_4mhz pulses, so 4000 ticks = 1 ms.
module measurement_controller #(
    parameter AUTO_PERIOD_TICKS = 22'd4000000,  // 1 s
    parameter LOCKOUT_TICKS     = 22'd1600000,  // 400 ms  - MEASURE THIS on the bench
    parameter MEAS_TICKS        = 22'd409600    // 102.4 ms = 4096 windows, matches the demodulator
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        tick_4mhz,
    input  wire        mic_ready,

    // Ping request sources
    input  wire        ext_start,       // pin, rising edge = one ping
    input  wire        ext_auto,        // pin, level, ORed with the UART 'A' flag

    // From the echo detector
    input  wire        angle_valid,
    input  wire [11:0] echo_window,
    input  wire [5:0]  angle_out,

    // UART receive side
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,

    // UART transmit side (into the byte FIFO)
    input  wire        tx_fifo_full,
    output reg  [7:0]  tx_data,
    output reg         tx_push,

    // Control / status
    output reg         start_pulse,     // one clock high: fire a ping
    output wire        auto_mode,
    output reg         busy,            // measurement in progress
    output reg         result_ready     // sticky: an echo was reported since the last ping
);

    // ---------------------------------------------------------------- //
    // Command decode
    // ---------------------------------------------------------------- //
    wire cmd_auto_on  = rx_valid & (rx_data == "A");
    wire cmd_auto_off = rx_valid & (rx_data == "S");
    wire cmd_ping     = rx_valid & (rx_data == "P");
    wire cmd_query    = rx_valid & (rx_data == "?");

    // ---------------------------------------------------------------- //
    // The two control pins are asynchronous to clk (a button, a GPIO from
    // another MCU). Pass them through two flops before using them, the
    // same way uart_rx does, so a transition landing on a clock edge can
    // neither go metastable nor be half-seen by the edge detector.
    // ---------------------------------------------------------------- //
    reg ext_start_s1, ext_start_s2, ext_start_d;
    reg ext_auto_s1,  ext_auto_s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ext_start_s1 <= 1'b0; ext_start_s2 <= 1'b0;
            ext_auto_s1  <= 1'b0; ext_auto_s2  <= 1'b0;
        end
        else begin
            ext_start_s1 <= ext_start; ext_start_s2 <= ext_start_s1;
            ext_auto_s1  <= ext_auto;  ext_auto_s2  <= ext_auto_s1;
        end
    end

    reg uart_auto;
    assign auto_mode = uart_auto | ext_auto_s2;

    // Rising-edge detect on the synchronised start pin: a host that holds
    // the pin high gets exactly one ping, not one per clock.
    wire ext_rise = ext_start_s2 & ~ext_start_d;

    // ---------------------------------------------------------------- //
    // Timers (all in tick_4mhz units)
    // ---------------------------------------------------------------- //
    reg [21:0] since_ping;   // saturating; starts saturated so first ping is allowed
    reg [21:0] auto_cnt;
    reg        auto_fire;

    wire lockout_ok = (since_ping >= LOCKOUT_TICKS);
    wire can_ping   = mic_ready & lockout_ok;

    wire ping_req_manual = ext_rise | cmd_ping;
    wire ping_req        = ping_req_manual | auto_fire;
    wire do_ping         = ping_req & can_ping;

    reg detected;

    // ---------------------------------------------------------------- //
    // Message requests, latched until the message writer picks them up
    // ---------------------------------------------------------------- //
    reg pend_status, pend_detect, pend_noecho, pend_busy;
    reg [11:0] det_window;
    reg [5:0]  det_angle;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_auto    <= 1'b0;
            ext_start_d  <= 1'b0;
            since_ping   <= {22{1'b1}};
            auto_cnt     <= 22'd0;
            auto_fire    <= 1'b0;
            start_pulse  <= 1'b0;
            busy         <= 1'b0;
            result_ready <= 1'b0;
            detected     <= 1'b0;
            pend_status  <= 1'b0;
            pend_detect  <= 1'b0;
            pend_noecho  <= 1'b0;
            pend_busy    <= 1'b0;
            det_window   <= 12'd0;
            det_angle    <= 6'd0;
        end
        else begin
            start_pulse <= 1'b0;
            auto_fire   <= 1'b0;
            ext_start_d <= ext_start_s2;

            // --- commands ---
            if (cmd_auto_on)  uart_auto <= 1'b1;
            if (cmd_auto_off) uart_auto <= 1'b0;
            if (cmd_auto_on | cmd_auto_off | cmd_query)
                pend_status <= 1'b1;

            // --- timers ---
            if (tick_4mhz) begin
                if (since_ping != {22{1'b1}})
                    since_ping <= since_ping + 1'b1;

                if (auto_mode) begin
                    if (auto_cnt >= AUTO_PERIOD_TICKS - 1) begin
                        auto_cnt  <= 22'd0;
                        auto_fire <= 1'b1;
                    end
                    else begin
                        auto_cnt <= auto_cnt + 1'b1;
                    end
                end
                else begin
                    // Park just below the threshold so the first ping fires
                    // immediately when auto mode is switched on.
                    auto_cnt <= AUTO_PERIOD_TICKS - 1;
                end
            end

            // --- ping decision ---
            if (do_ping) begin
                start_pulse  <= 1'b1;
                since_ping   <= 22'd0;
                busy         <= 1'b1;
                result_ready <= 1'b0;
                detected     <= 1'b0;
            end
            else if (ping_req_manual) begin
                pend_busy <= 1'b1;      // refused: tell the host why nothing happened
            end

            // --- result from the detector ---
            if (angle_valid) begin
                result_ready <= 1'b1;
                detected     <= 1'b1;
                det_window   <= echo_window;
                det_angle    <= angle_out;
                pend_detect  <= 1'b1;
            end

            // --- end of the listening window ---
            if (busy && tick_4mhz && since_ping == MEAS_TICKS) begin
                busy <= 1'b0;
                if (!detected)
                    pend_noecho <= 1'b1;
            end

            // --- message writer clears its pending flag when it starts ---
            if (msg_take_status) pend_status <= 1'b0;
            if (msg_take_detect) pend_detect <= 1'b0;
            if (msg_take_noecho) pend_noecho <= 1'b0;
            if (msg_take_busy)   pend_busy   <= 1'b0;
        end
    end

    // ---------------------------------------------------------------- //
    // Message writer: pushes one byte per clock into the TX FIFO
    // ---------------------------------------------------------------- //
    localparam MSG_NONE   = 3'd0;
    localparam MSG_STATUS = 3'd1;
    localparam MSG_DETECT = 3'd2;
    localparam MSG_NOECHO = 3'd3;
    localparam MSG_BUSY   = 3'd4;

    reg [2:0] msg_kind;
    reg [2:0] msg_idx;

    wire msg_idle = (msg_kind == MSG_NONE);

    // Priority when several are pending: busy > status > detect > noecho
    wire msg_take_busy   = msg_idle & pend_busy;
    wire msg_take_status = msg_idle & ~pend_busy & pend_status;
    wire msg_take_detect = msg_idle & ~pend_busy & ~pend_status & pend_detect;
    wire msg_take_noecho = msg_idle & ~pend_busy & ~pend_status & ~pend_detect & pend_noecho;

    function [7:0] hex;
        input [3:0] n;
        begin
            hex = (n < 4'd10) ? (8'h30 + {4'd0, n}) : (8'h37 + {4'd0, n});
        end
    endfunction

    reg [7:0] msg_byte;

    always @(*) begin
        msg_byte = 8'h0A;
        case (msg_kind)
            MSG_STATUS: begin
                case (msg_idx)
                    3'd0:    msg_byte = auto_mode ? "A" : "S";
                    3'd1:    msg_byte = mic_ready ? "R" : "W";
                    default: msg_byte = 8'h0A;
                endcase
            end
            MSG_DETECT: begin
                case (msg_idx)
                    3'd0:    msg_byte = "D";
                    3'd1:    msg_byte = hex(det_window[11:8]);
                    3'd2:    msg_byte = hex(det_window[7:4]);
                    3'd3:    msg_byte = hex(det_window[3:0]);
                    3'd4:    msg_byte = " ";
                    3'd5:    msg_byte = hex({2'b00, det_angle[5:4]});
                    3'd6:    msg_byte = hex(det_angle[3:0]);
                    default: msg_byte = 8'h0A;
                endcase
            end
            MSG_NOECHO: msg_byte = (msg_idx == 3'd0) ? "N" : 8'h0A;
            MSG_BUSY:   msg_byte = (msg_idx == 3'd0) ? "B" : 8'h0A;
            default:    msg_byte = 8'h0A;
        endcase
    end

    // Last byte index of the current message (length - 1)
    wire [2:0] msg_len_last = (msg_kind == MSG_STATUS) ? 3'd2 :
                              (msg_kind == MSG_DETECT) ? 3'd7 :
                              3'd1;   // NOECHO and BUSY are "X\n"

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msg_kind <= MSG_NONE;
            msg_idx  <= 3'd0;
            tx_push  <= 1'b0;
            tx_data  <= 8'd0;
        end
        else begin
            tx_push <= 1'b0;

            if (msg_idle) begin
                msg_idx <= 3'd0;
                if      (msg_take_busy)   msg_kind <= MSG_BUSY;
                else if (msg_take_status) msg_kind <= MSG_STATUS;
                else if (msg_take_detect) msg_kind <= MSG_DETECT;
                else if (msg_take_noecho) msg_kind <= MSG_NOECHO;
            end
            else if (!tx_fifo_full) begin
                tx_push <= 1'b1;
                tx_data <= msg_byte;
                if (msg_idx == msg_len_last)
                    msg_kind <= MSG_NONE;
                else
                    msg_idx <= msg_idx + 1'b1;
            end
        end
    end

endmodule
