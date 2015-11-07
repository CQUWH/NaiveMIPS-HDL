module uart_rx(/*autoport*/
//output
         data,
         data_available,
//input
         clk_bus,
         clk_uart,
         rst_n,
         clear,
         rxd);

parameter BAUD = 115200;
parameter UART_CLK = 11059200;
parameter COUNTER_PERIOD = UART_CLK/BAUD-1;
parameter SAMPLE_1 = UART_CLK/BAUD/4-1;
parameter SAMPLE_2 = UART_CLK/BAUD/2-1;
parameter SAMPLE_3 = UART_CLK/BAUD/4*3-1;

input wire clk_bus;
input wire clk_uart;
input wire rst_n;

input wire clear;
output reg[7:0] data;
output reg data_available;

reg[3:0] clear_request_reg;
reg rx_available_gated,rx_available_gated_last;
reg[7:0] rx_data_gated;

input wire rxd;

reg clear_request_gated;
reg[6:0] rx_available;
reg[8:0] rx_data;
reg[3:0] state, next_state;
reg[3:0] remain_bit;
reg[14:0] baud_cnt;
reg[2:0] samples;
wire sample_value;

assign sample_value = (samples[0] && samples[1] ||
    samples[2] && samples[1] ||
    samples[0] && samples[2] );

always @(posedge clk_bus or negedge rst_n) begin
    if (!rst_n) begin
        clear_request_reg <= 4'b0;
        rx_available_gated <= 1'b0;
        rx_available_gated_last <= 1'b0;
        data_available <= 1'b0;
    end
    else begin
        rx_data_gated <= rx_data;
        rx_available_gated <= (rx_available[6:2] != 5'b0);
        rx_available_gated_last <= rx_available_gated;
        clear_request_reg <= clear_request_reg<<1;
        if (clear && data_available) begin
            clear_request_reg <= 1'b1;
            data_available <= 1'b0;
        end else if(rx_available_gated_last && !rx_available_gated) begin
            data_available <= 1'b1;
            data <= rx_data_gated;
        end
    end
end

always @(posedge clk_uart or negedge rst_n) begin
    if (!rst_n) begin
        state <= 4'h0;
        next_state <= 4'h0;
        rx_available <= 7'b0;
        clear_request_gated <= 1'b0;
    end
    else begin
        clear_request_gated <= (clear_request_reg != 4'b0);
        rx_available = rx_available << 1;
        case(state)
        4'h0: begin
            next_state <= 4'h3;
            if(!rxd) begin
                state <= 4'h2;
                baud_cnt <= COUNTER_PERIOD;
            end
        end
        4'h1: begin
            rx_data <= {sample_value, rx_data[8:1]};
            next_state <= 4'h1;
            remain_bit <= remain_bit-4'd1;
            if(remain_bit!=4'd0) begin
                baud_cnt <= COUNTER_PERIOD;
                state <= 4'h2;
            end else begin
                state <= 4'h4;
            end
        end
        4'h2: begin
            baud_cnt <= baud_cnt - 1'b1;
            case (baud_cnt)
            0: begin
                state <= next_state;
            end
            SAMPLE_1,
            SAMPLE_2,
            SAMPLE_3: begin
                samples <= {samples[1:0], rxd};
            end
            endcase
        end
        4'h3: begin //checking START bit
            if(!sample_value) begin
                //valid
                state <= 4'h1;
                remain_bit <= 4'd9; //including STOP bit
            end else begin
                state <= 4'h0;
            end
        end
        4'h4: begin
            if(rx_data[8]) begin //checking STOP bit
                state <= 4'h5;
                rx_available <= 1'b1;
            end else begin
                state <= 4'h0;
            end
        end
        4'h5: begin
            if(clear_request_gated)
                state <= 4'h0;
        end
        endcase
    end
end
endmodule
