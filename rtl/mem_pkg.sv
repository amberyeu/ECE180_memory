package mem_pkg;

    import rv32_ooo_pkg::*;

    // Cache geometry
    localparam int unsigned WORD_BYTES     = 4;
    localparam int unsigned LINE_BYTES     = 32;
    localparam int unsigned WORDS_PER_LINE = LINE_BYTES / WORD_BYTES; // 8 words
    localparam int unsigned BYTE_OFF_W     = 2;
    localparam int unsigned WORD_OFF_W     = 3;                       // log2(8)
    localparam int unsigned LINE_OFF_W     = BYTE_OFF_W + WORD_OFF_W; // 5
    localparam int unsigned LINE_ADDR_W    = XLEN - LINE_OFF_W;       // 27 bit line address

    // L1: 1 KiB, 32 B, 4 ways
    localparam int unsigned L1_BYTES   = 1024;
    localparam int unsigned L1_WAYS    = 4;
    localparam int unsigned L1_SETS    = 8;
    localparam int unsigned L1_INDEX_W = 3;
    localparam int unsigned L1_TAG_W   = LINE_ADDR_W - L1_INDEX_W; // 24 bit tag

    // L2: 4 KiB, 32 B, 4 ways
    localparam int unsigned L2_BYTES   = 4096;
    localparam int unsigned L2_WAYS    = 4;
    localparam int unsigned L2_SETS    = 32;
    localparam int unsigned L2_INDEX_W = 5;
    localparam int unsigned L2_TAG_W   = LINE_ADDR_W - L2_INDEX_W; // 22 bit tag
    localparam int unsigned WAY_W      = 2; //2 bits to select 1 of 4 ways

    // LSQ
    localparam int unsigned LSQ_DEPTH  = 8; // 8-entry
    localparam int unsigned LSQ_IDX_W  = 3; // eight queue entry index, 0-7
    localparam int unsigned LSQ_CNT_W  = 4; // occupancy ranges from 0-8

    // BIP
    localparam int unsigned BIP_PERIOD = 32; // one-in-32 MRU insertion policy
    localparam int unsigned BIP_CNT_W  = 5;  // 32 counter states

    // Data types
    typedef logic [XLEN-1:0]                     word_t;
    typedef logic [WORD_BYTES-1:0]               byte_en_t;
    typedef logic [LINE_ADDR_W-1:0]              line_addr_t; // addr[31:5], removes line offset
    typedef logic [WORDS_PER_LINE-1:0][XLEN-1:0] line_data_t; // [word][bit]
    typedef logic [WORD_OFF_W-1:0]               word_off_t; // selects word, 0-7
    typedef logic [WAY_W-1:0]                    way_t; // selects way, 0-3

    typedef logic [L1_INDEX_W-1:0]               l1_index_t;
    typedef logic [L1_TAG_W-1:0]                 l1_tag_t;
    typedef logic [L2_INDEX_W-1:0]               l2_index_t;
    typedef logic [L2_TAG_W-1:0]                 l2_tag_t;

    // L2 replacement metadata: one 2-bit rank per way, ranks 0, 1 , 2 ,3 where 0 = MRU, 3 = LRU
    typedef logic [1:0]                          lru_rank_t; // rank of 1 way
    typedef logic [L2_WAYS-1:0][1:0]             lru_ranks_t; // all 4 ranks

    // L1 <-> L2 line-transfer protocol
    typedef struct packed {
        line_addr_t fetch_line; 
        logic       victim_valid; 
        logic       victim_dirty; 
        line_addr_t victim_line; 
        line_data_t victim_data; 
    } l1_l2_req_t;

    typedef struct packed {
        line_data_t data; // line returned from L2
        logic       dirty; // preserve dirty status during promotion
        logic       error; // any main-memory error seen during the refill (transfer error)
    } l2_l1_resp_t;


    // Address helpers
    // remove lower 5 offset bits to get cache line addr
    function automatic line_addr_t line_of(input word_t addr);
        return addr[XLEN-1:LINE_OFF_W];
    endfunction

    // select 1 of 8 words within a cache line
    function automatic word_off_t word_of(input word_t addr);
        return addr[LINE_OFF_W-1:BYTE_OFF_W];
    endfunction

    // convert line addr back to byte addr
    function automatic word_t line_base(input line_addr_t line);
        return {line, {LINE_OFF_W{1'b0}}};
    endfunction

    // extract L1 set index and tag
    function automatic l1_index_t l1_index(input line_addr_t line);
        return line[L1_INDEX_W-1:0];
    endfunction

    function automatic l1_tag_t l1_tag(input line_addr_t line);
        return line[LINE_ADDR_W-1:L1_INDEX_W];
    endfunction

    // extract L2 set index and tag
    function automatic l2_index_t l2_index(input line_addr_t line);
        return line[L2_INDEX_W-1:0];
    endfunction

    function automatic l2_tag_t l2_tag(input line_addr_t line);
        return line[LINE_ADDR_W-1:L2_INDEX_W];
    endfunction

    // merge store data with old word, only update enabled bytes 
    function automatic word_t merge_bytes(input word_t    old_word,
                                          input word_t    new_word,
                                          input byte_en_t be);
        word_t r;
        for (int b = 0; b < WORD_BYTES; b++)
            r[8*b +: 8] = be[b] ? new_word[8*b +: 8] : old_word[8*b +: 8];
        return r;
    endfunction


    // LSU helpers
    // generate 4-bit byte mask based on access size and offset
    function automatic byte_en_t make_byte_enable(input mem_size_e  size,
                                                  input logic [1:0] off);
        case (size)
            MEM_BYTE: return byte_en_t'(4'b0001 << off);
            MEM_HALF: return byte_en_t'(4'b0011 << off);
            default:  return 4'b1111;
        endcase
    endfunction

    // replicate store data across the 32 bit word, byte enable determines which bytes are actually written
    function automatic word_t align_store_data(input mem_size_e size,
                                               input word_t     rs2);
        case (size)
            MEM_BYTE: return {4{rs2[7:0]}};  // repeat 8 bit value 4 tiems
            MEM_HALF: return {2{rs2[15:0]}}; // repeat 16-bit value twice
            default:  return rs2;            // full 32-bit word
        endcase
    endfunction

    // extract requested load bytes and sign/zero extend to 32 bits
    function automatic word_t extract_load(input word_t      raw,
                                           input mem_size_e  size,
                                           input logic [1:0] off,
                                           input logic       is_unsigned);
        word_t sh;
        sh = raw >> (8 * off);
        case (size)
            MEM_BYTE: return is_unsigned ? {24'b0, sh[7:0]}
                                         : {{24{sh[7]}}, sh[7:0]};
            MEM_HALF: return is_unsigned ? {16'b0, sh[15:0]}
                                         : {{16{sh[15]}}, sh[15:0]};
            default:  return raw;
        endcase
    endfunction

    // check whether halfword/word access is misaligned
    function automatic logic is_misaligned(input mem_size_e  size,
                                           input logic [1:0] off);
        case (size)
            MEM_HALF: return off[0];         // halfword needs even address
            MEM_WORD: return (off != 2'b00); // word needs 4-byte alignment
            default:  return 1'b0;           // byte can use any offset
        endcase
    endfunction


    // L2 BIP / LRU rank helpers  (0 = MRU, 3 = LRU)
    function automatic lru_ranks_t lru_reset_ranks();
        lru_ranks_t r;
        for (int i = 0; i < L2_WAYS; i++) r[i] = lru_rank_t'(i);
        return r;
    endfunction

    // move selected way to MRU (rank 0), other more-recent ways shift one rank toward LRU
    function automatic lru_ranks_t lru_touch_mru(input lru_ranks_t r,
                                                 input way_t       w);
        lru_ranks_t n;
        lru_rank_t  old;
        old = r[w];
        for (int i = 0; i < L2_WAYS; i++) begin
            if (way_t'(i) == w)  n[i] = 2'd0;
            else if (r[i] < old) n[i] = r[i] + 2'd1;
            else                 n[i] = r[i];
        end
        return n;
    endfunction

    // insert selected way at LRU (rank 3), more-recent ranks shift toward MRU
    function automatic lru_ranks_t lru_insert_lru(input lru_ranks_t r,
                                                  input way_t       w);
        lru_ranks_t n;
        lru_rank_t  old;
        old = r[w];
        for (int i = 0; i < L2_WAYS; i++) begin
            if (way_t'(i) == w)  n[i] = 2'd3;
            else if (r[i] > old) n[i] = r[i] - 2'd1;
            else                 n[i] = r[i];
        end
        return n;
    endfunction

    // choose invalid way first, otherwise evict rank 3 (LRU)
    function automatic way_t lru_victim(input lru_ranks_t           r,
                                        input logic [L2_WAYS-1:0]   valid);
        way_t w;
        logic found;
        w     = '0;
        found = 1'b0;
        for (int i = 0; i < L2_WAYS; i++) begin
            if (!valid[i] && !found) begin
                w     = way_t'(i);
                found = 1'b1;
            end
        end
        if (!found) begin
            for (int i = 0; i < L2_WAYS; i++)
                if (r[i] == 2'd3) w = way_t'(i);
        end
        return w;
    endfunction

endpackage
