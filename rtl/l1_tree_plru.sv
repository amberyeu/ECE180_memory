module l1_tree_plru (
    input  logic [2:0] plru_bits,
    input  logic [1:0] accessed_way,
    output logic [2:0] updated_bits,
    output logic [1:0] victim_way
);

    always_comb begin
        updated_bits = plru_bits;
        victim_way   = 2'd0;
    end

endmodule