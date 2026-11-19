// Only the shared interfaces cross the subsystem boundary. The two extra outputs are sticky debug/status flags and need no other team's signals.

module memory_subsystem_top
    import rv32_ooo_pkg::*;
    import mem_pkg::*;
#(
    parameter bit STORE_AT_ROB_HEAD = 1'b1,
    parameter bit ENABLE_FORWARDING = 1'b1
) (
    input logic clk_i,
    input logic rst_ni,

    backend_memory_if.memory backend_if,
    data_memory_if.client    main_mem_if,

    output logic misaligned_o, // sticky: misaligned access seen
    output logic mem_error_o   // sticky: main-memory error seen
);

    // LSU <-> L1 uses the shared word-level interface type.
    data_memory_if lsu_l1_if ();

    // L1 <-> L2 line port
    logic        l2_req_valid, l2_req_ready, l2_resp_valid, l2_resp_ready;
    l1_l2_req_t  l2_req;
    l2_l1_resp_t l2_resp;

    lsu #(
        .STORE_AT_ROB_HEAD (STORE_AT_ROB_HEAD),
        .ENABLE_FORWARDING (ENABLE_FORWARDING)
    ) u_lsu (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .be_if        (backend_if),
        .dmem_if      (lsu_l1_if),
        .misaligned_o (misaligned_o)
    );

    l1_cache u_l1 (
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),
        .lsu_if          (lsu_l1_if),
        .l2_req_valid_o  (l2_req_valid),
        .l2_req_ready_i  (l2_req_ready),
        .l2_req_o        (l2_req),
        .l2_resp_valid_i (l2_resp_valid),
        .l2_resp_ready_o (l2_resp_ready),
        .l2_resp_i       (l2_resp)
    );

    l2_cache u_l2 (
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),
        .l1_req_valid_i  (l2_req_valid),
        .l1_req_ready_o  (l2_req_ready),
        .l1_req_i        (l2_req),
        .l1_resp_valid_o (l2_resp_valid),
        .l1_resp_ready_i (l2_resp_ready),
        .l1_resp_o       (l2_resp),
        .mem_if          (main_mem_if),
        .mem_error_o     (mem_error_o)
    );

endmodule
