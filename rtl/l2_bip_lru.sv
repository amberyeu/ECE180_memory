module l2_bip_lru
    import mem_pkg::*;
(
    input  lru_ranks_t         ranks_i,
    input  logic [L2_WAYS-1:0] valid_i,
    input  way_t               way_i,
    input  logic               insert_mru_i,
    output way_t               victim_o,
    output lru_ranks_t         ranks_o
);

    always_comb begin
        victim_o = '0;
        ranks_o  = ranks_i;
    end

endmodule
