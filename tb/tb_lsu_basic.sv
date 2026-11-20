// tb for LSU

module tb_lsu_basic;
    import rv32_ooo_pkg::*;
    import mem_pkg::*;

    logic clk = 0;
    logic rst_n = 0;
    logic misaligned;

    always #5 clk = ~clk;

    backend_memory_if be_if();
    data_memory_if mem_bus();

    // LSU connected directly to test memory
    lsu dut (
        .clk_i(clk),
        .rst_ni(rst_n),
        .be_if(be_if),
        .dmem_if(mem_bus),
        .misaligned_o(misaligned)
    );

    mem_model #(
        .READY_PCT(100),
        .MAX_LATENCY(0)
    ) mem (
        .clk_i(clk),
        .rst_ni(rst_n),
        .bus(mem_bus)
    );

    // Send one instruction and check its result
    task automatic test_op(
        input bit store,
        input mem_size_e size,
        input bit uns,
        input logic [31:0] addr,
        input logic [31:0] data,
        input logic [31:0] expected,
        input rob_tag_t tag
    );
        renamed_uop_t u;
        int timeout_count;

        u = '0;
        u.decoded.mem_cmd = store ? MEM_STORE : MEM_LOAD;
        u.decoded.mem_size = size;
        u.decoded.load_unsigned = uns;
        u.decoded.immediate = 0;
        u.has_destination = !store;
        u.rob_tag = tag;
        u.pdst = phys_reg_t'(1);

        @(negedge clk);
        be_if.rob_head_tag = tag;
        be_if.issue_uop = u;
        be_if.source_1 = addr;
        be_if.source_2 = data;
        be_if.issue_valid = 1;

        // Wait until LSU accepts the instruction
        timeout_count = 0;
        do begin
            @(posedge clk);
            timeout_count++;
            if (timeout_count > 100)
                $fatal(1, "Issue timeout");
        end while (!be_if.issue_ready);

        @(negedge clk);
        be_if.issue_valid = 0;

        // Wait for completion
        timeout_count = 0;
        do begin
            @(posedge clk);
            timeout_count++;
            if (timeout_count > 100)
                $fatal(1, "Result timeout");
        end while (!be_if.result_valid);

        if (be_if.result.rob_tag !== tag)
            $fatal(1, "Wrong ROB tag");

        if (be_if.result.writeback_valid !== !store)
            $fatal(1, "Wrong writeback valid");

        if (!store && be_if.result.value !== expected)
            $fatal(1, "Expected %h, got %h",
                   expected, be_if.result.value);

        $display("PASS: %s at address %h",
                 store ? "STORE" : "LOAD", addr);

        @(negedge clk);
    endtask

    initial begin
        be_if.issue_valid = 0;
        be_if.result_ready = 1;
        be_if.issue_uop = '0;
        be_if.source_1 = 0;
        be_if.source_2 = 0;
        be_if.rob_head_tag = '0;

        repeat (3) @(negedge clk);
        rst_n = 1;

        // Store 32-bit word
        test_op(1, MEM_WORD, 0,
                32'h100, 32'h8012_3456, 0,
                rob_tag_t'(0));

        // Load the same word
        test_op(0, MEM_WORD, 0,
                32'h100, 0, 32'h8012_3456,
                rob_tag_t'(1));

        // Signed byte load from byte offset 3
        test_op(0, MEM_BYTE, 0,
                32'h103, 0, 32'hFFFF_FF80,
                rob_tag_t'(2));

        if (misaligned)
            $fatal(1, "Unexpected misalignment");

        $display("TB_LSU_BASIC PASS");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Testbench timeout");
    end

endmodule
