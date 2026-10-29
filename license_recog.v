`timescale 1ns/1ps
// license_recog_led - BRAM-friendly edge scan + host-controlled progress LEDs
// Arty A7-35T, 100 MHz, UART 115200 baud.
// PC status packet: C3 3C stage (0..3); candidate packet: C3 3C 10 + ASCII text + LF; frame: A5 5A + grayscale.
// FPGA returns: BOX:XX,YY,XX,YY\n (hex coordinates).
// LED stages: 0=off, 1=0001, 2=0011, 3=0111; parser acceptance drives 1111.
// This is a coarse global edge bounding box, NOT final plate localization or OCR.

module license_recog #(
    parameter integer FRAME_W = 160,
    parameter integer FRAME_H = 120,
    parameter integer CLKS_PER_BIT = 868,
    parameter [7:0] EDGE_THRESHOLD = 8'd42,
    parameter integer MIN_EDGE_COUNT = 20
)(
    input wire CLK100MHZ,
    input wire uart_rxd,
    output wire uart_txd,
    input wire [3:0] sw,
    input wire [3:0] btn,
    output reg [3:0] led
);
    localparam integer FRAME_PIXELS = FRAME_W * FRAME_H;
    localparam integer XW = (FRAME_W <= 2) ? 1 : $clog2(FRAME_W);
    localparam integer YW = (FRAME_H <= 2) ? 1 : $clog2(FRAME_H);

    // Synchronous single-port inferred block RAM:
    // one write during frame reception, one registered read during scan.
    (* ram_style = "block" *) reg [7:0] frame_mem [0:FRAME_PIXELS-1];

    // Small one-line delay memory: one byte per x coordinate.
    reg [7:0] line_buf [0:FRAME_W-1];

    wire [7:0] rx_data;
    wire rx_valid;
    reg [7:0] tx_data = 8'h00;
    reg tx_start = 1'b0;
    wire tx_busy, tx_done;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(CLK100MHZ), .rst(btn[0]), .rx(uart_rxd),
        .data(rx_data), .valid(rx_valid)
    );
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(CLK100MHZ), .rst(btn[0]), .data(tx_data),
        .start(tx_start), .tx(uart_txd), .busy(tx_busy), .done(tx_done)
    );

    // ASCII registration parser: receives host-sent OCR text after the C3 3C 10 command.
    wire parser_byte_valid = rx_valid && (state == WAIT_TEXT) && (rx_data != 8'h0A);
    wire parser_plate_valid;
    wire [79:0] parser_plate_ascii;
    wire [15:0] parser_state_code, parser_district_code, parser_series_code;
    wire [31:0] parser_registration_no;
    plate_ascii_parser u_plate_parser (
        .clk(CLK100MHZ), .rst(btn[0]),
        .byte_valid(parser_byte_valid), .byte_in(rx_data),
        .plate_valid(parser_plate_valid), .plate_ascii(parser_plate_ascii),
        .state_code(parser_state_code), .district_code(parser_district_code),
        .series_code(parser_series_code), .registration_no(parser_registration_no)
    );

    localparam [3:0] WAIT_A5=4'd0, WAIT_5A=4'd1, RECEIVE=4'd2,
                     SCAN_REQ=4'd3, SCAN_PROC=4'd4, SEND=4'd5, WAIT_TX=4'd6,
                     WAIT_CTL_3C=4'd7, WAIT_CTL_STAGE=4'd8, WAIT_TEXT=4'd9;
    reg [3:0] state = WAIT_A5;

    reg [31:0] pixel_addr = 0;
    reg [31:0] scan_addr = 0;
    reg [7:0] scan_pixel = 0;
    reg [XW-1:0] scan_x = 0;
    reg [YW-1:0] scan_y = 0;
    reg [7:0] prev_pixel = 0;
    reg [7:0] above_pixel = 0;
    reg [8:0] diff_left = 0, diff_above = 0;
    reg edge_hit = 0;

    reg [31:0] edge_count = 0;
    reg [7:0] xmin = 8'hFF, ymin = 8'hFF, xmax = 0, ymax = 0;
    reg [4:0] report_index = 0;
    reg [7:0] report_char;
    reg [7:0] out_xmin, out_ymin, out_xmax, out_ymax;
    reg found_box;

    function [7:0] hex_ascii;
        input [3:0] nib;
        begin
            if (nib < 10) hex_ascii = 8'h30 + nib;
            else hex_ascii = 8'h41 + (nib - 10);
        end
    endfunction

    // Stable after scan completes; response is "BOX:XX,YY,XX,YY\n".
    always @* begin
        found_box = (edge_count >= MIN_EDGE_COUNT) && (xmin != 8'hFF);
        if (found_box) begin
            out_xmin = xmin; out_ymin = ymin; out_xmax = xmax; out_ymax = ymax;
        end else begin
            out_xmin = 0; out_ymin = 0; out_xmax = 0; out_ymax = 0;
        end
        case (report_index)
            0: report_char = "B";
            1: report_char = "O";
            2: report_char = "X";
            3: report_char = ":";
            4: report_char = hex_ascii(out_xmin[7:4]);
            5: report_char = hex_ascii(out_xmin[3:0]);
            6: report_char = ",";
            7: report_char = hex_ascii(out_ymin[7:4]);
            8: report_char = hex_ascii(out_ymin[3:0]);
            9: report_char = ",";
            10: report_char = hex_ascii(out_xmax[7:4]);
            11: report_char = hex_ascii(out_xmax[3:0]);
            12: report_char = ",";
            13: report_char = hex_ascii(out_ymax[7:4]);
            14: report_char = hex_ascii(out_ymax[3:0]);
            default: report_char = 8'h0A;
        endcase
    end

    // Synchronous scan: memory output is registered in SCAN_REQ.
    // SCAN_PROC compares current pixel with left neighbor and previous row.
    always @(posedge CLK100MHZ) begin
        tx_start <= 1'b0;
        if (btn[0]) begin
            state <= WAIT_A5;
            pixel_addr <= 0; scan_addr <= 0;
            scan_pixel <= 0; scan_x <= 0; scan_y <= 0; prev_pixel <= 0;
            edge_count <= 0;
            xmin <= 8'hFF; ymin <= 8'hFF; xmax <= 0; ymax <= 0;
            report_index <= 0;
            led <= 4'b0000;
        end else begin
            case (state)
                WAIT_A5: begin
                    if (rx_valid) begin
                        if (rx_data == 8'hA5) state <= WAIT_5A;
                        else if (rx_data == 8'hC3) state <= WAIT_CTL_3C;
                    end
                end
                WAIT_CTL_3C: begin
                    if (rx_valid) begin
                        if (rx_data == 8'h3C) state <= WAIT_CTL_STAGE;
                        else state <= WAIT_A5;
                    end
                end
                WAIT_CTL_STAGE: begin
                    if (rx_valid) begin
                        case (rx_data)
                            8'd0: led <= 4'b0000;
                            8'd1: led <= 4'b0001;
                            8'd2: led <= 4'b0011;
                            8'd3: led <= 4'b0111;
                            8'h10: state <= WAIT_TEXT;
                            default: led <= 4'b0000;
                        endcase
                        if (rx_data != 8'h10) state <= WAIT_A5;
                    end
                end
                WAIT_TEXT: begin
                    // Host sends OCR candidate text followed by LF (0x0A).
                    if (rx_valid && rx_data == 8'h0A) state <= WAIT_A5;
                end
                WAIT_5A: begin
                    if (rx_valid) begin
                        if (rx_data == 8'h5A) begin
                            pixel_addr <= 0;
                            state <= RECEIVE;
                        end else if (rx_data != 8'hA5) state <= WAIT_A5;
                    end
                end
                RECEIVE: begin
                    if (rx_valid) begin
                        frame_mem[pixel_addr] <= rx_data;
                        if (pixel_addr == FRAME_PIXELS-1) begin
                            pixel_addr <= 0;
                            scan_addr <= 0;
                            edge_count <= 0;
                            xmin <= 8'hFF; ymin <= 8'hFF; xmax <= 0; ymax <= 0;
                            prev_pixel <= 0;
                                    state <= SCAN_REQ;
                        end else pixel_addr <= pixel_addr + 1'b1;
                    end
                end
                SCAN_REQ: begin
                    // Synchronous BRAM read. Coordinates travel with registered pixel.
                    scan_pixel <= frame_mem[scan_addr];
                    scan_x <= scan_addr % FRAME_W;
                    scan_y <= scan_addr / FRAME_W;
                    state <= SCAN_PROC;
                end
                SCAN_PROC: begin
                    above_pixel = line_buf[scan_x];
                    diff_left = (scan_pixel >= prev_pixel) ?
                                (scan_pixel - prev_pixel) : (prev_pixel - scan_pixel);
                    diff_above = (scan_pixel >= above_pixel) ?
                                 (scan_pixel - above_pixel) : (above_pixel - scan_pixel);
                    edge_hit = 1'b0;
                    if (scan_x != 0 && diff_left >= EDGE_THRESHOLD) edge_hit = 1'b1;
                    if (scan_y != 0 && diff_above >= EDGE_THRESHOLD) edge_hit = 1'b1;

                    line_buf[scan_x] <= scan_pixel;
                    if (scan_x == 0) prev_pixel <= scan_pixel;
                    else prev_pixel <= scan_pixel;

                    if (edge_hit) begin
                        edge_count <= edge_count + 1'b1;
                        if (scan_x < xmin) xmin <= scan_x;
                        if (scan_y < ymin) ymin <= scan_y;
                        if (scan_x > xmax) xmax <= scan_x;
                        if (scan_y > ymax) ymax <= scan_y;
                    end

                    if (scan_addr == FRAME_PIXELS-1) begin
                        report_index <= 0;
                        state <= SEND;
                    end else begin
                        scan_addr <= scan_addr + 1'b1;
                        state <= SCAN_REQ;
                    end
                end
                SEND: begin
                    if (!tx_busy) begin
                        tx_data <= report_char;
                        tx_start <= 1'b1;
                        state <= WAIT_TX;
                    end
                end
                WAIT_TX: begin
                    if (tx_done) begin
                        if (report_index == 15) begin
                            state <= WAIT_A5;
                                end else begin
                            report_index <= report_index + 1'b1;
                            state <= SEND;
                        end
                    end
                end
                default: state <= WAIT_A5;
            endcase
        end
    end
endmodule

module uart_rx #(
    parameter integer CLKS_PER_BIT = 868
)(
    input wire clk, input wire rst, input wire rx,
    output reg [7:0] data, output reg valid
);
    localparam [1:0] IDLE=2'd0, START=2'd1, DATA=2'd2, STOP=2'd3;
    reg [1:0] state = IDLE;
    reg [31:0] count = 0;
    reg [2:0] bit_index = 0;
    reg [7:0] shift = 0;
    reg rx_meta = 1'b1, rx_sync = 1'b1;
    always @(posedge clk) begin
        rx_meta <= rx;
        rx_sync <= rx_meta;
        valid <= 1'b0;
        if (rst) begin
            state <= IDLE; count <= 0; bit_index <= 0; shift <= 0;
            data <= 0; valid <= 0; rx_meta <= 1'b1; rx_sync <= 1'b1;
        end else begin
            case (state)
                IDLE: if (!rx_sync) begin state <= START; count <= 0; end
                START: begin
                    if (count == (CLKS_PER_BIT/2)) begin
                        if (!rx_sync) begin count <= 0; bit_index <= 0; state <= DATA; end
                        else state <= IDLE;
                    end else count <= count + 1;
                end
                DATA: begin
                    if (count == CLKS_PER_BIT-1) begin
                        count <= 0; shift[bit_index] <= rx_sync;
                        if (bit_index == 7) begin bit_index <= 0; state <= STOP; end
                        else bit_index <= bit_index + 1;
                    end else count <= count + 1;
                end
                STOP: begin
                    if (count == CLKS_PER_BIT-1) begin
                        count <= 0; data <= shift; valid <= 1'b1; state <= IDLE;
                    end else count <= count + 1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

module uart_tx #(
    parameter integer CLKS_PER_BIT = 868
)(
    input wire clk, input wire rst, input wire [7:0] data,
    input wire start, output reg tx, output reg busy, output reg done
);
    localparam [2:0] IDLE=3'd0, START=3'd1, DATA=3'd2, STOP=3'd3;
    reg [2:0] state = IDLE;
    reg [31:0] count = 0;
    reg [2:0] bit_index = 0;
    reg [7:0] shift = 0;
    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            state <= IDLE; count <= 0; bit_index <= 0;
            shift <= 0; tx <= 1'b1; busy <= 1'b0; done <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1'b1; busy <= 1'b0; count <= 0;
                    if (start) begin shift <= data; busy <= 1'b1; state <= START; end
                end
                START: begin
                    tx <= 1'b0;
                    if (count == CLKS_PER_BIT-1) begin count <= 0; bit_index <= 0; state <= DATA; end
                    else count <= count + 1;
                end
                DATA: begin
                    tx <= shift[bit_index];
                    if (count == CLKS_PER_BIT-1) begin
                        count <= 0;
                        if (bit_index == 7) state <= STOP;
                        else bit_index <= bit_index + 1;
                    end else count <= count + 1;
                end
                STOP: begin
                    tx <= 1'b1;
                    if (count == CLKS_PER_BIT-1) begin
                        count <= 0; state <= IDLE; busy <= 1'b0; done <= 1'b1;
                    end else count <= count + 1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule


// Sliding 10-byte ASCII window for the standard AA00AA0000 registration pattern.
// The host-side Python model still performs YOLO and OCR; this module validates format only.
module plate_ascii_parser (
    input wire clk, input wire rst, input wire byte_valid, input wire [7:0] byte_in,
    output reg plate_valid, output reg [79:0] plate_ascii,
    output reg [15:0] state_code, output reg [15:0] district_code,
    output reg [15:0] series_code, output reg [31:0] registration_no
);
    reg [79:0] window;
    wire [79:0] next_window = {window[71:0], byte_in};
    function is_letter; input [7:0] c; begin is_letter=(c>=8'h41 && c<=8'h5A); end endfunction
    function is_digit; input [7:0] c; begin is_digit=(c>=8'h30 && c<=8'h39); end endfunction
    wire pattern_ok = is_letter(next_window[79:72]) && is_letter(next_window[71:64]) &&
      is_digit(next_window[63:56]) && is_digit(next_window[55:48]) &&
      is_letter(next_window[47:40]) && is_letter(next_window[39:32]) &&
      is_digit(next_window[31:24]) && is_digit(next_window[23:16]) &&
      is_digit(next_window[15:8]) && is_digit(next_window[7:0]);
    always @(posedge clk) begin
      if (rst) begin
        window<=0; plate_valid<=0; plate_ascii<=0; state_code<=0;
        district_code<=0; series_code<=0; registration_no<=0;
      end else begin
        plate_valid<=0;
        if (byte_valid) begin
          window<=next_window;
          if (pattern_ok) begin
            plate_valid<=1; plate_ascii<=next_window;
            state_code<={next_window[79:72],next_window[71:64]};
            district_code<={next_window[63:56],next_window[55:48]};
            series_code<={next_window[47:40],next_window[39:32]};
            registration_no<={next_window[31:24],next_window[23:16],next_window[15:8],next_window[7:0]};
          end
        end
      end
    end
endmodule
