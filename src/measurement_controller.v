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
//   'V'  dump the tuning registers reply: config line
//   'Cnvv' write tuning register n with hex value vv, reply: config line
//         n=0 threshold, 1 min_width (windows), 2 blank (windows),
//         n=3 ping half periods (16 = the default 8-period burst)
//         Anything that is not a hex digit aborts the command. Values stay
//         until rst_n, which restores the defaults below.
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
//   "Vttmmbbpp\n"  tuning registers: threshold, min_width, blank, ping
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

    // Tuning registers, settable over UART
    output reg  [7:0]  cfg_threshold,
    output reg  [7:0]  cfg_min_width,
    output reg  [7:0]  cfg_blank,
    output reg  [4:0]  cfg_halfcycles,

    // Control / status
    output reg         start_pulse,     // one clock high: fire a ping
    output wire        auto_mode,
    output reg         busy,            // measurement in progress
    output reg         result_ready     // sticky: an echo was reported since the last ping
);

    // ---------------------------------------------------------------- //
    // Command decode
    // ---------------------------------------------------------------- //
    // Bytes 2..4 of a "Cnvv" command must not be decoded as commands.
    reg [1:0] cfg_phase;
    reg [2:0] cfg_addr;
    reg [3:0] cfg_hi;
    wire top_level    = rx_valid & (cfg_phase == 2'd0);

    wire cmd_auto_on  = top_level & (rx_data == "A");
    wire cmd_auto_off = top_level & (rx_data == "S");
    wire cmd_ping     = top_level & (rx_data == "P");
    wire cmd_query    = top_level & (rx_data == "?");
    wire cmd_dump     = top_level & (rx_data == "V");
    wire cmd_config   = top_level & (rx_data == "C");

    wire [3:0] rx_nib   = rx_data[3:0] + ((rx_data > 8'h39) ? 4'd9 : 4'd0);
    wire       rx_is_hex = (rx_data >= "0" && rx_data <= "9")
                         | (rx_data >= "A" && rx_data <= "F");

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
    reg pend_status, pend_detect, pend_noecho, pend_busy, pend_config;
    reg [11:0] det_window;
    reg [5:0]  det_angle;

    localparam MSG_NONE   = 3'd0;
    localparam MSG_STATUS = 3'd1;
    localparam MSG_DETECT = 3'd2;
    localparam MSG_NOECHO = 3'd3;
    localparam MSG_BUSY   = 3'd4;
    localparam MSG_CONFIG = 3'd5;

    reg [2:0] msg_kind;
    reg [3:0] msg_idx;

    wire msg_idle = (msg_kind == MSG_NONE);

    // Priority when several are pending: busy > config > status > detect > noecho
    wire msg_take_busy   = msg_idle & pend_busy;
    wire msg_take_config = msg_idle & ~pend_busy & pend_config;
    wire msg_take_status = msg_idle & ~pend_busy & ~pend_config & pend_status;
    wire msg_take_detect = msg_idle & ~pend_busy & ~pend_config & ~pend_status & pend_detect;
    wire msg_take_noecho = msg_idle & ~pend_busy & ~pend_config & ~pend_status & ~pend_detect & pend_noecho;

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
            pend_config  <= 1'b0;
            cfg_phase    <= 2'd0;
            cfg_addr     <= 3'd0;
            cfg_hi       <= 4'd0;
            cfg_threshold  <= 8'd7;
            cfg_min_width  <= 8'd5;
            cfg_blank      <= 8'd64;
            cfg_halfcycles <= 5'd16;
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
            if (cmd_dump) pend_config <= 1'b1;

            // --- "Cnvv": collect the register index and the two hex digits ---
            if (cmd_config) cfg_phase <= 2'd1;
            else if (rx_valid && cfg_phase != 2'd0) begin
                if (!rx_is_hex) cfg_phase <= 2'd0;      // give up on a bad digit
                else case (cfg_phase)
                    2'd1: begin cfg_addr <= rx_nib[2:0]; cfg_phase <= 2'd2; end
                    2'd2: begin cfg_hi   <= rx_nib;      cfg_phase <= 2'd3; end
                    default: begin
                        case (cfg_addr)
                            3'd0: cfg_threshold <= {cfg_hi, rx_nib};
                            3'd1: cfg_min_width <= {cfg_hi, rx_nib};
                            3'd2: cfg_blank     <= {cfg_hi, rx_nib};
                            default: cfg_halfcycles <= {cfg_hi[0], rx_nib};
                        endcase
                        cfg_phase   <= 2'd0;
                        pend_config <= 1'b1;
                    end
                endcase
            end

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
            if (msg_take_config) pend_config <= 1'b0;
        end
    end

    // ---------------------------------------------------------------- //
    // Message writer: pushes one byte per clock into the TX FIFO
    // ---------------------------------------------------------------- //
    function [7:0] hex;
        input [3:0] n;
        begin
            hex = (n < 4'd10) ? (8'h30 + {4'd0, n}) : (8'h37 + {4'd0, n});
        end
    endfunction

    // Snapshot taken when the message starts: a second echo may overwrite
    // det_window/det_angle while this line is still being sent.
    reg [11:0] msg_window;
    reg [5:0]  msg_angle;

    // One hex converter shared by every message: the case below picks either a
    // literal character or the nibble to print.
    reg [7:0] msg_lit;
    reg [3:0] msg_nib;
    reg       msg_hex;

    always @(*) begin
        msg_lit = 8'h0A;
        msg_nib = 4'd0;
        msg_hex = 1'b0;
        case (msg_kind)
            MSG_STATUS:
                case (msg_idx)
                    4'd0: msg_lit = auto_mode ? "A" : "S";
                    4'd1: msg_lit = mic_ready ? "R" : "W";
                    default: ;
                endcase
            MSG_DETECT:
                case (msg_idx)
                    4'd0: msg_lit = "D";
                    4'd1: begin msg_hex = 1'b1; msg_nib = msg_window[11:8]; end
                    4'd2: begin msg_hex = 1'b1; msg_nib = msg_window[7:4];  end
                    4'd3: begin msg_hex = 1'b1; msg_nib = msg_window[3:0];  end
                    4'd4: msg_lit = " ";
                    4'd5: begin msg_hex = 1'b1; msg_nib = {2'b00, msg_angle[5:4]}; end
                    4'd6: begin msg_hex = 1'b1; msg_nib = msg_angle[3:0];   end
                    default: ;
                endcase
            MSG_CONFIG:
                case (msg_idx)
                    4'd0: msg_lit = "V";
                    4'd1: begin msg_hex = 1'b1; msg_nib = cfg_threshold[7:4]; end
                    4'd2: begin msg_hex = 1'b1; msg_nib = cfg_threshold[3:0]; end
                    4'd3: begin msg_hex = 1'b1; msg_nib = cfg_min_width[7:4]; end
                    4'd4: begin msg_hex = 1'b1; msg_nib = cfg_min_width[3:0]; end
                    4'd5: begin msg_hex = 1'b1; msg_nib = cfg_blank[7:4];     end
                    4'd6: begin msg_hex = 1'b1; msg_nib = cfg_blank[3:0];     end
                    4'd7: begin msg_hex = 1'b1; msg_nib = {3'b000, cfg_halfcycles[4]}; end
                    4'd8: begin msg_hex = 1'b1; msg_nib = cfg_halfcycles[3:0]; end
                    default: ;
                endcase
            MSG_NOECHO: if (msg_idx == 4'd0) msg_lit = "N";
            MSG_BUSY:   if (msg_idx == 4'd0) msg_lit = "B";
            default: ;
        endcase
    end

    wire [7:0] msg_byte = msg_hex ? hex(msg_nib) : msg_lit;

    // Last byte index of the current message (length - 1)
    wire [3:0] msg_len_last = (msg_kind == MSG_STATUS) ? 4'd2  :
                              (msg_kind == MSG_DETECT) ? 4'd7  :
                              (msg_kind == MSG_CONFIG) ? 4'd9  :
                              4'd1;   // NOECHO and BUSY are "X\n"

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msg_kind   <= MSG_NONE;
            msg_idx    <= 4'd0;
            tx_push    <= 1'b0;
            tx_data    <= 8'd0;
            msg_window <= 12'd0;
            msg_angle  <= 6'd0;
        end
        else begin
            tx_push <= 1'b0;

            if (msg_idle) begin
                msg_idx    <= 4'd0;
                msg_window <= det_window;
                msg_angle  <= det_angle;
                if      (msg_take_busy)   msg_kind <= MSG_BUSY;
                else if (msg_take_config) msg_kind <= MSG_CONFIG;
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
