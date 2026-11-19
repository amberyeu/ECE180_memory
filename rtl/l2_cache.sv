module l2_cache
    import rv32_ooo_pkg::*;
    import mem_pkg::*;
(
    input logic clk_i,
    input logic rst_ni,

    input  logic        l1_req_valid_i,
    output logic        l1_req_ready_o,
    input  l1_l2_req_t  l1_req_i,
    output logic        l1_resp_valid_o,
    input  logic        l1_resp_ready_i,
    output l2_l1_resp_t l1_resp_o,

    data_memory_if.client mem_if,

    output logic mem_error_o
);

    typedef enum logic [2:0] {
        S_IDLE, S_LOOKUP, S_REFILL, S_RESP, S_VICTIM_SEL, S_WB, S_INSTALL
    } l2_state_e;

    l2_tag_t              tag_q   [L2_SETS][L2_WAYS];
    logic [L2_WAYS-1:0]   valid_q [L2_SETS];
    logic [L2_WAYS-1:0]   dirty_q [L2_SETS];
    line_data_t           data_q  [L2_SETS][L2_WAYS];
    lru_ranks_t           rank_q  [L2_SETS];
    logic [BIP_CNT_W-1:0] bip_cnt_q;

    l2_state_e   state_q;
    l1_l2_req_t  req_q;
    l2_l1_resp_t resp_q;
    way_t        ins_way_q;
    logic        mem_error_q;

    l2_index_t f_set, v_set;
    l2_tag_t   f_tag, v_tag;

    logic [L2_WAYS-1:0] way_hit;
    logic               f_hit;
    way_t               f_way;

    logic       insert_mru;
    way_t       bip_victim;
    lru_ranks_t bip_ranks_next;

    logic       xfer_start, xfer_write, xfer_busy, xfer_done, xfer_err;
    line_addr_t xfer_line;
    line_data_t xfer_wdata, xfer_rdata;
    logic       victim_needs_wb;

    assign f_set = l2_index(req_q.fetch_line);
    assign f_tag = l2_tag(req_q.fetch_line);
    assign v_set = l2_index(req_q.victim_line);
    assign v_tag = l2_tag(req_q.victim_line);

    always_comb begin
        way_hit = '0;
        f_way   = '0;
        f_hit   = 1'b0;
    end

    assign insert_mru = 1'b0;

    l2_bip_lru u_bip (
        .ranks_i      (rank_q[v_set]),
        .valid_i      (valid_q[v_set]),
        .way_i        (ins_way_q),
        .insert_mru_i (insert_mru),
        .victim_o     (bip_victim),
        .ranks_o      (bip_ranks_next)
    );

    assign victim_needs_wb = 1'b0;

    always_comb begin
        xfer_start = 1'b0;
        xfer_write = 1'b0;
        xfer_line  = '0;
        xfer_wdata = '0;
    end

    line_transfer u_xfer (
        .clk_i   (clk_i),
        .rst_ni  (rst_ni),
        .start_i (xfer_start),
        .write_i (xfer_write),
        .line_i  (xfer_line),
        .wdata_i (xfer_wdata),
        .busy_o  (xfer_busy),
        .done_o  (xfer_done),
        .rdata_o (xfer_rdata),
        .error_o (xfer_err),
        .mem_if  (mem_if)
    );

    assign l1_req_ready_o  = 1'b0;
    assign l1_resp_valid_o = 1'b0;
    assign l1_resp_o       = resp_q;
    assign mem_error_o     = mem_error_q;

    always_ff @(posedge clk_i) begin
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q     <= S_IDLE;
            req_q       <= '0;
            resp_q      <= '0;
            ins_way_q   <= '0;
            bip_cnt_q   <= '0;
            mem_error_q <= 1'b0;
            for (int s = 0; s < L2_SETS; s++) begin
                valid_q[s] <= '0;
                dirty_q[s] <= '0;
                rank_q[s]  <= lru_reset_ranks();
                for (int w = 0; w < L2_WAYS; w++) tag_q[s][w] <= '0;
            end
        end else begin
            case (state_q)
                S_IDLE: 
                S_LOOKUP: 
                S_REFILL: 
                S_RESP: 
                S_VICTIM_SEL: 
                S_WB: 
                S_INSTALL: 
                default: state_q <= S_IDLE;
            endcase
        end
    end

endmodule
