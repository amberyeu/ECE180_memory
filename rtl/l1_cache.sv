
module l1_cache
    import rv32_ooo_pkg::*;
    import mem_pkg::*;
(
    input logic clk_i,
    input logic rst_ni,

    data_memory_if.server lsu_if,

    output logic        l2_req_valid_o,
    input  logic        l2_req_ready_i,
    output l1_l2_req_t  l2_req_o,
    input  logic        l2_resp_valid_i,
    output logic        l2_resp_ready_o,
    input  l2_l1_resp_t l2_resp_i
);

    typedef enum logic [2:0] {
        S_IDLE, S_LOOKUP, S_MISS_REQ, S_MISS_WAIT, S_RESP
    } l1_state_e;

    l1_tag_t            tag_q   [L1_SETS][L1_WAYS];
    logic [L1_WAYS-1:0] valid_q [L1_SETS];
    logic [L1_WAYS-1:0] dirty_q [L1_SETS];
    line_data_t         data_q  [L1_SETS][L1_WAYS];
    logic [2:0]         plru_q  [L1_SETS];

    l1_state_e state_q;
    word_t     req_addr_q;
    logic      req_write_q;
    word_t     req_wdata_q;
    byte_en_t  req_be_q;

    word_t      resp_data_q;
    logic       resp_err_q;
    way_t       victim_way_q;
    l1_l2_req_t l2_req_q;

    line_addr_t req_line;
    l1_index_t  set;
    l1_tag_t    tag;
    word_off_t  woff;

    logic [L1_WAYS-1:0] way_hit;
    logic               cache_hit;
    way_t               hit_way;

    way_t       plru_access_way;
    logic [2:0] plru_next;
    way_t       plru_victim;
    way_t       victim_way;

    logic       data_we;
    way_t       data_wway;
    line_data_t data_wline;

    assign req_line = line_of(req_addr_q);
    assign set      = l1_index(req_line);
    assign tag      = l1_tag(req_line);
    assign woff     = word_of(req_addr_q);

    always_comb begin
        way_hit   = '0;
        hit_way   = '0;
        cache_hit = 1'b0;
    end

    assign plru_access_way = hit_way;

    l1_tree_plru u_plru (
        .plru_bits    (plru_q[set]),
        .accessed_way (plru_access_way),
        .updated_bits (plru_next),
        .victim_way   (plru_victim)
    );

    always_comb begin
        victim_way = plru_victim;
    end

    always_comb begin
        data_we    = 1'b0;
        data_wway  = '0;
        data_wline = '0;
    end

    always_ff @(posedge clk_i) begin
        if (data_we) data_q[set][data_wway] <= data_wline;
    end

    assign lsu_if.request_ready  = 1'b0;
    assign lsu_if.response_valid = 1'b0;
    assign lsu_if.read_data      = resp_data_q;
    assign lsu_if.error          = resp_err_q;

    assign l2_req_valid_o  = 1'b0;
    assign l2_req_o        = l2_req_q;
    assign l2_resp_ready_o = 1'b0;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q      <= S_IDLE;
            req_addr_q   <= '0;
            req_write_q  <= 1'b0;
            req_wdata_q  <= '0;
            req_be_q     <= '0;
            resp_data_q  <= '0;
            resp_err_q   <= 1'b0;
            victim_way_q <= '0;
            l2_req_q     <= '0;
            for (int s = 0; s < L1_SETS; s++) begin
                valid_q[s] <= '0;
                dirty_q[s] <= '0;
                plru_q[s]  <= '0;
                for (int w = 0; w < L1_WAYS; w++) tag_q[s][w] <= '0;
            end
        end else begin
            case (state_q)
                S_IDLE: 
                S_LOOKUP: 
                S_MISS_REQ:
                S_MISS_WAIT:
                S_RESP: 
                default: state_q <= S_IDLE;
            endcase
        end
    end

endmodule
