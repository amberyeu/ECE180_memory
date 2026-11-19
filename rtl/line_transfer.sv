module line_transfer
    import rv32_ooo_pkg::*;
    import mem_pkg::*;
(
    input logic clk_i,
    input logic rst_ni,

    input logic       start_i,
    input logic       write_i,
    input line_addr_t line_i,
    input line_data_t wdata_i,

    output logic       busy_o,
    output logic       done_o,
    output line_data_t rdata_o,
    output logic       error_o,

    data_memory_if.client mem_if
);

    typedef enum logic [1:0] {X_IDLE, X_REQ, X_RESP, X_DONE} xfer_state_e;

    xfer_state_e state_q;
    logic        write_q;
    line_addr_t  line_q;
    line_data_t  wdata_q;
    line_data_t  rdata_q;
    word_off_t   beat_q;
    logic        err_q;

    assign mem_if.request_valid  = 1'b0;
    assign mem_if.write          = 1'b0;
    assign mem_if.address        = '0;
    assign mem_if.write_data     = '0;
    assign mem_if.byte_enable    = '0;
    assign mem_if.response_ready = 1'b0;

    assign busy_o  = 1'b0;
    assign done_o  = 1'b0;
    assign rdata_o = rdata_q;
    assign error_o = err_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= X_IDLE;
            write_q <= 1'b0;
            line_q  <= '0;
            beat_q  <= '0;
            err_q   <= 1'b0;
        end else begin
            case (state_q)
                X_IDLE: begin
                end
                X_REQ: begin
                end
                X_RESP: begin
                end
                X_DONE: begin
                end
                default: state_q <= X_IDLE;
            endcase
        end
    end

    always_ff @(posedge clk_i) begin
    end

endmodule
