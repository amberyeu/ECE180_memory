// mem_pkg.sv -- shared parameters, types and address helpers for the memory subsystem
// rv32_ooo_pkg.sv must be compiled before this file.

package mem_pkg;

    import rv32_ooo_pkg::*;

    // -----------------------------------------------------------------------
    // Knobs: L1 1 KiB, L2 4 KiB, 4-way, 32-byte lines
    // -----------------------------------------------------------------------
    localparam int unsigned LINE_BYTES     = 32;
    localparam int unsigned WORD_BYTES     = XLEN / 8;          // 4

    localparam int unsigned L1_SIZE_BYTES  = 1024;
    localparam int unsigned L1_WAYS        = 4;

    localparam int unsigned L2_SIZE_BYTES  = 4096;
    localparam int unsigned L2_WAYS        = 4;

    // BIP: insert at MRU once every BIP_THROTTLE fills, otherwise at LRU
    localparam int unsigned BIP_THROTTLE   = 32;

    // -----------------------------------------------------------------------
    // do not edit, change the knobs instead
    // -----------------------------------------------------------------------
    localparam int unsigned WORDS_PER_LINE = LINE_BYTES / WORD_BYTES;           // 32 / 4 = 8

    localparam int unsigned BYTE_OFF_W     = $clog2(WORD_BYTES);                // $clog2(4) = 2
    localparam int unsigned WORD_OFF_W     = $clog2(WORDS_PER_LINE);            // 3
    localparam int unsigned LINE_OFF_W     = BYTE_OFF_W + WORD_OFF_W;           // 5

    localparam int unsigned L1_SETS        = L1_SIZE_BYTES / (LINE_BYTES * L1_WAYS);  // 8
    localparam int unsigned L1_INDEX_W     = $clog2(L1_SETS);                         // 3
    localparam int unsigned L1_TAG_W       = XLEN - L1_INDEX_W - LINE_OFF_W;          // 24
    localparam int unsigned L1_WAY_W       = $clog2(L1_WAYS);                         // 2

    localparam int unsigned L2_SETS        = L2_SIZE_BYTES / (LINE_BYTES * L2_WAYS);  // 32
    localparam int unsigned L2_INDEX_W     = $clog2(L2_SETS);                         // 5
    localparam int unsigned L2_TAG_W       = XLEN - L2_INDEX_W - LINE_OFF_W;          // 22
    localparam int unsigned L2_WAY_W       = $clog2(L2_WAYS);                         // 2

    localparam int unsigned PLRU_BITS      = L1_WAYS - 1;                             // 3
    localparam int unsigned BIP_CTR_W      = $clog2(BIP_THROTTLE);                    // 5


    // -----------------------------------------------------------------------
    // Basic types
    // -----------------------------------------------------------------------
    typedef logic [XLEN-1:0]                         addr_t;
    typedef logic [XLEN-1:0]                         word_t;
    typedef logic [WORD_BYTES-1:0]                   byte_en_t;
    typedef logic [WORDS_PER_LINE-1:0][XLEN-1:0]     line_data_t;   // [word][bit]

    typedef logic [BYTE_OFF_W-1:0]                   byte_off_t;
    typedef logic [WORD_OFF_W-1:0]                   word_off_t;

    typedef logic [L1_TAG_W-1:0]                     l1_tag_t;
    typedef logic [L1_INDEX_W-1:0]                   l1_index_t;
    typedef logic [L1_WAY_W-1:0]                     l1_way_t;

    typedef logic [L2_TAG_W-1:0]                     l2_tag_t;
    typedef logic [L2_INDEX_W-1:0]                   l2_index_t;
    typedef logic [L2_WAY_W-1:0]                     l2_way_t;

    // Replacement state
    typedef logic [PLRU_BITS-1:0]                    plru_bits_t;   // one per L1 set
    typedef logic [L2_WAY_W-1:0]                     lru_rank_t;    // 0 = MRU ... WAYS-1 = LRU (team to confirm)
    typedef logic [L2_WAYS-1:0][L2_WAY_W-1:0]        l2_set_ranks_t;// one rank per way, one per L2 set
    typedef logic [BIP_CTR_W-1:0]                    bip_ctr_t;


    // -----------------------------------------------------------------------
    // Per-line metadata (tag array entry)
    // -----------------------------------------------------------------------
    typedef struct packed {
        logic    valid;
        logic    dirty;
        l1_tag_t tag;
    } l1_meta_t;

    typedef struct packed {
        logic    valid;
        logic    dirty;
        l2_tag_t tag;
    } l2_meta_t;


    // -----------------------------------------------------------------------
    // A whole line moving between levels (promotion, demotion, refill,
    // writeback). The address is the line-aligned base address, so it is
    // level-independent: each level re-splits it with its own helpers below.
    // The dirty bit MUST travel with the line in the exclusive hierarchy.
    // -----------------------------------------------------------------------
    typedef struct packed {
        addr_t      base;
        logic       dirty;
        line_data_t data;
    } line_t;


    // -----------------------------------------------------------------------
    // L1 -> L2 command
    //   L2_CMD_FETCH  : L1 missed. L2 returns the line. On an L2 hit the L2
    //                   copy is invalidated (exclusive). On an L2 miss the
    //                   line is fetched from main memory and passed straight
    //                   to L1 without being installed in L2.
    //   L2_CMD_VICTIM : L1 evicted a valid line. L2 installs it (data + dirty),
    //                   evicting / writing back its own victim if needed.
    // -----------------------------------------------------------------------
    typedef enum logic [1:0] {
        L2_CMD_NONE,
        L2_CMD_FETCH,
        L2_CMD_VICTIM
    } l2_cmd_e;


    // -----------------------------------------------------------------------
    // Address helpers
    // -----------------------------------------------------------------------
    function automatic byte_off_t byte_offset(input addr_t a);
        return a[0 +: BYTE_OFF_W];
    endfunction

    function automatic word_off_t word_offset(input addr_t a);
        return a[BYTE_OFF_W +: WORD_OFF_W];
    endfunction

    // Clear the offset bits -> address of the first byte in the line
    function automatic addr_t line_base(input addr_t a);
        return {a[XLEN-1:LINE_OFF_W], {LINE_OFF_W{1'b0}}};
    endfunction

    // Byte address of word w inside the line starting at base
    // (used to step through the 8 beats of a refill / writeback)
    function automatic addr_t word_addr(input addr_t base, input word_off_t w);
        return {base[XLEN-1:LINE_OFF_W], w, {BYTE_OFF_W{1'b0}}};
    endfunction

    // ----- L1 split -----
    function automatic l1_index_t l1_index(input addr_t a);
        return a[LINE_OFF_W +: L1_INDEX_W];
    endfunction

    function automatic l1_tag_t l1_tag(input addr_t a);
        return a[XLEN-1 -: L1_TAG_W];
    endfunction

    // Rebuild a line base address from what the L1 tag array stores
    // (needed when an L1 victim is sent down to L2)
    function automatic addr_t l1_line_addr(input l1_tag_t t, input l1_index_t i);
        return {t, i, {LINE_OFF_W{1'b0}}};
    endfunction

    // ----- L2 split -----
    function automatic l2_index_t l2_index(input addr_t a);
        return a[LINE_OFF_W +: L2_INDEX_W];
    endfunction

    function automatic l2_tag_t l2_tag(input addr_t a);
        return a[XLEN-1 -: L2_TAG_W];
    endfunction

    // Rebuild a line base address from the L2 tag array
    // (when a dirty L2 victim is written back to main memory)
    function automatic addr_t l2_line_addr(input l2_tag_t t, input l2_index_t i);
        return {t, i, {LINE_OFF_W{1'b0}}};
    endfunction

endpackage
