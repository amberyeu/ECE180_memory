// ===========================================================================
// memory_subsystem_top.sv -- top level of the memory subsystem.
//
//   backend --(backend_memory_if)--> lsu --(data_memory_if)--> l1_cache
//        --(l2_* line ports)--> l2_cache --(xfer_* ports)--> line_transfer
//        --(data_memory_if)--> main memory
//
// The two external ports are the shared contract from common/ -- do not change
// ===========================================================================
module memory_subsystem_top
    import mem_pkg::*;
(
    input  logic             clk_i,
    input  logic             rst_ni,

    backend_memory_if.memory be,    // to / from the backend
    data_memory_if.client    mem    // to main memory
);

    // -----------------------------------------------------------------------
    // Elaboration-time sanity checks on the mem_pkg knobs
    // -----------------------------------------------------------------------
    if ((1 << LINE_OFF_W) != LINE_BYTES)
        $error("LINE_BYTES must be a power of two");
    if (L1_SETS * L1_WAYS * LINE_BYTES != L1_SIZE_BYTES)
        $error("L1 size is not SETS * WAYS * LINE_BYTES");
    if (L2_SETS * L2_WAYS * LINE_BYTES != L2_SIZE_BYTES)
        $error("L2 size is not SETS * WAYS * LINE_BYTES");
    if (L1_SETS < 2 || L2_SETS < 2 || L1_WAYS < 2 || L2_WAYS < 2)
        $error("Sets and ways must be >= 2 (index / way widths would be 0)");


    // -----------------------------------------------------------------------
    // LSU <-> L1 : word requests, reusing the shared data_memory_if
    // -----------------------------------------------------------------------
    data_memory_if lsu_l1_bus ();

    // -----------------------------------------------------------------------
    // L1 <-> L2 : line requests
    // -----------------------------------------------------------------------
    logic    l1_l2_req_valid, l1_l2_req_ready;
    l2_cmd_e l1_l2_req_cmd;
    line_t   l1_l2_req_line;
    logic    l2_l1_resp_valid, l2_l1_resp_ready;
    line_t   l2_l1_resp_line;
    logic    l2_l1_resp_error;

    // -----------------------------------------------------------------------
    // L2 <-> line_transfer
    // -----------------------------------------------------------------------
    logic       xfer_req_valid, xfer_req_ready, xfer_req_write;
    addr_t      xfer_req_base;
    line_data_t xfer_req_data;
    logic       xfer_resp_valid, xfer_resp_ready;
    line_data_t xfer_resp_data;
    logic       xfer_resp_error;


    // -----------------------------------------------------------------------
    // Instances
    // -----------------------------------------------------------------------
    lsu u_lsu (
        .clk_i  (clk_i),
        .rst_ni (rst_ni),
        .be     (be),
        .l1     (lsu_l1_bus)
    );

    l1_cache u_l1 (
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),
        .lsu             (lsu_l1_bus),
        .l2_req_valid_o  (l1_l2_req_valid),
        .l2_req_ready_i  (l1_l2_req_ready),
        .l2_req_cmd_o    (l1_l2_req_cmd),
        .l2_req_line_o   (l1_l2_req_line),
        .l2_resp_valid_i (l2_l1_resp_valid),
        .l2_resp_ready_o (l2_l1_resp_ready),
        .l2_resp_line_i  (l2_l1_resp_line),
        .l2_resp_error_i (l2_l1_resp_error)
    );

    l2_cache u_l2 (
        .clk_i             (clk_i),
        .rst_ni            (rst_ni),
        .l1_req_valid_i    (l1_l2_req_valid),
        .l1_req_ready_o    (l1_l2_req_ready),
        .l1_req_cmd_i      (l1_l2_req_cmd),
        .l1_req_line_i     (l1_l2_req_line),
        .l1_resp_valid_o   (l2_l1_resp_valid),
        .l1_resp_ready_i   (l2_l1_resp_ready),
        .l1_resp_line_o    (l2_l1_resp_line),
        .l1_resp_error_o   (l2_l1_resp_error),
        .xfer_req_valid_o  (xfer_req_valid),
        .xfer_req_ready_i  (xfer_req_ready),
        .xfer_req_write_o  (xfer_req_write),
        .xfer_req_base_o   (xfer_req_base),
        .xfer_req_data_o   (xfer_req_data),
        .xfer_resp_valid_i (xfer_resp_valid),
        .xfer_resp_ready_o (xfer_resp_ready),
        .xfer_resp_data_i  (xfer_resp_data),
        .xfer_resp_error_i (xfer_resp_error)
    );

    line_transfer u_xfer (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .req_valid_i  (xfer_req_valid),
        .req_ready_o  (xfer_req_ready),
        .req_write_i  (xfer_req_write),
        .req_base_i   (xfer_req_base),
        .req_data_i   (xfer_req_data),
        .resp_valid_o (xfer_resp_valid),
        .resp_ready_i (xfer_resp_ready),
        .resp_data_o  (xfer_resp_data),
        .resp_error_o (xfer_resp_error),
        .mem          (mem)
    );

endmodule

