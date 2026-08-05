`timescale 1ns/1ps
module tb_pattern_tx_engine_timing;
    logic clk=0, rst=1, start=0, enable=1, pattern_valid=1;
    logic [126:0] base_pattern;
    logic [7:0] pattern_len, head_delay_bits;
    logic [4:0] repeat_cycles;
    logic [119:0] gap_len_bits;
    logic phase_shift_en, loop_en;
    logic eom_geometry_armed=0, eom_tx_start_level=0;
    logic eom_request_valid=0, eom_done_pulse=0;
    wire engine_start_accept_pulse;
    wire first_sequence_word_fire;
    wire [63:0] txdata, valid_mask;
    wire phase_active, phase_start_pulse, sequence_active, busy, done;
    wire [7:0] phase_offset, current_state;
    realtime half_period=3.103;
    integer errors=0, expected_bits=0;
    integer append_count0_seen=0, append_count1_seen=0;
    integer append_count63_seen=0;
    reg exp_data[0:399999];
    reg exp_valid[0:399999];
    localparam [126:0] LEGACY_PRBS6_SEED_5A_GOLDEN =
      127'h0000000000000000376938bca3083f56;
    localparam [126:0] LEGACY_PRBS7_SEED_5A_GOLDEN =
      127'h491c2f95cd13c50c103faa6774b1bdad;

    always #(half_period) clk=~clk;
    always @(posedge clk) begin
      if(!rst && dut.planner_step) begin
        if(dut.append_count_calc==0) append_count0_seen++;
        if(dut.append_count_calc==1) append_count1_seen++;
        if(dut.append_count_calc==63) append_count63_seen++;
      end
    end
    pattern_tx_engine dut(
      .clk(clk),.rst(rst),.start(start),.enable(enable),.pattern_valid(pattern_valid),
      .base_pattern(base_pattern),.pattern_len(pattern_len),.repeat_cycles(repeat_cycles),
      .head_delay_bits(head_delay_bits),.gap_len_bits(gap_len_bits),
      .phase_shift_en(phase_shift_en),.loop_en(loop_en),
      .eom_geometry_armed(eom_geometry_armed),
      .eom_tx_start_level(eom_tx_start_level),
      .eom_request_valid(eom_request_valid),
      .eom_done_pulse(eom_done_pulse),
      .engine_start_accept_pulse(engine_start_accept_pulse),
      .first_sequence_word_fire(first_sequence_word_fire),
      .txdata(txdata),.valid_mask(valid_mask),
      .phase_active(phase_active),.phase_start_pulse(phase_start_pulse),
      .sequence_active(sequence_active),.busy(busy),.done(done),
      .phase_offset(phase_offset),.current_state(current_state));

    task automatic fail(input string s); begin
      $display("ERROR @%0t %s",$time,s); errors++;
    end endtask
    function automatic [126:0] legacy_prbs_period(
      input integer order,input [31:0] seed);
      integer i;
      reg [5:0] lfsr6;
      reg [6:0] lfsr7;
      reg [126:0] period;
    begin
      period=0;
      lfsr6=(seed[5:0]==0)?6'h3f:seed[5:0];
      lfsr7=(seed[6:0]==0)?7'h7f:seed[6:0];
      if(order==6) begin
        for(i=0;i<63;i++) begin
          period[i]=lfsr6[5];
          lfsr6={lfsr6[4:0],lfsr6[5]^lfsr6[4]};
        end
      end else begin
        for(i=0;i<127;i++) begin
          period[i]=lfsr7[6];
          lfsr7={lfsr7[5:0],lfsr7[6]^lfsr7[5]};
        end
      end
      legacy_prbs_period=period;
    end endfunction
    function automatic [7:0] gap_at(input integer i);
      gap_at=gap_len_bits[i*8 +: 8];
    endfunction
    task automatic append_delay(input integer n); integer i; begin
      for(i=0;i<n;i++) begin
        exp_data[expected_bits]=0; exp_valid[expected_bits]=0; expected_bits++;
      end
    end endtask
    task automatic append_pattern(input integer phase); integer i,idx; begin
      for(i=0;i<pattern_len;i++) begin
        idx=phase_shift_en?((i+phase)%pattern_len):i;
        exp_data[expected_bits]=base_pattern[idx];
        exp_valid[expected_bits]=1;
        expected_bits++;
      end
    end endtask
    task automatic build_expected; integer p,r,pc; begin
      expected_bits=0; pc=phase_shift_en?pattern_len:1;
      for(p=0;p<pc;p++) begin
        append_delay(head_delay_bits);
        for(r=0;r<repeat_cycles;r++) begin
          append_pattern(p);
          if(r+1<repeat_cycles) append_delay(gap_at(r));
        end
      end
    end endtask
    task automatic pulse_start; begin
      @(negedge clk); start=1; @(negedge clk); start=0;
    end endtask
    task automatic wait_current_plan(input string name);
      integer timeout;
    begin
      timeout=0;
      while(!dut.current_append_plan_valid_q && timeout<5000) begin
        @(posedge clk); #0.05; timeout++;
      end
      if(!dut.current_append_plan_valid_q)
        fail({name," current plan timeout"});
    end endtask
    task automatic arm_and_start(input string name); integer timeout; begin
      timeout=0;
      while(!engine_start_accept_pulse && timeout<5000) begin
        @(posedge clk); #0.05; timeout++;
      end
      if(!engine_start_accept_pulse) fail({name," no accept"});
      wait_current_plan(name);
      @(negedge clk);
      eom_geometry_armed=1;
      eom_tx_start_level=1;
      @(posedge clk); #0.05;
      @(negedge clk);
      eom_tx_start_level=0;
    end endtask
    task automatic run_case(input string name);
      integer w,l,pos,words,timeout,sequence_fires,seen_valid;
    begin
      build_expected(); eom_geometry_armed=0; pulse_start();
      arm_and_start(name);
      words=(expected_bits+63)/64; sequence_fires=0; seen_valid=0;
      for(w=0;w<words;w++) begin
        @(posedge clk); #0.05;
        if(first_sequence_word_fire) begin
          sequence_fires++;
          if(seen_valid || valid_mask==0)
            fail($sformatf("%s sequence fire misaligned w=%0d mask=%h",
                           name,w,valid_mask));
        end
        if(valid_mask!=0)
          seen_valid=1;
        for(l=0;l<64;l++) begin
          pos=w*64+l;
          if(valid_mask[l] !== ((pos<expected_bits)?exp_valid[pos]:1'b0))
            fail($sformatf("%s mask w=%0d l=%0d",name,w,l));
          if(txdata[l] !== ((pos<expected_bits)?exp_data[pos]:1'b0))
            fail($sformatf("%s data w=%0d l=%0d",name,w,l));
        end
      end
      if(sequence_fires!=1)
        fail($sformatf("%s sequence fire count=%0d",name,sequence_fires));
      timeout=0;
      while(!done && timeout<8) begin @(posedge clk); #0.05; timeout++; end
      if(!done) fail({name," no done"});
      $display("PASS %s bits=%0d words=%0d",name,expected_bits,words);
      repeat(2) @(posedge clk);
    end endtask
    task automatic run_active_snapshot_case;
      integer w,l,pos,words,timeout;
      reg [126:0] replacement_pattern;
    begin
      build_expected();
      replacement_pattern=~base_pattern;
      eom_geometry_armed=0;
      pulse_start();
      timeout=0;
      while(!engine_start_accept_pulse && timeout<5000) begin
        @(posedge clk); #0.05; timeout++;
      end
      if(!engine_start_accept_pulse)
        fail("active snapshot no accept");
      // This emulates a changed BRAM/config shadow after the task is accepted.
      // The running task must retain the pattern captured on its start edge.
      @(negedge clk);
      base_pattern=replacement_pattern;
      wait_current_plan("active snapshot");
      eom_geometry_armed=1;
      eom_tx_start_level=1;
      @(posedge clk); #0.05;
      @(negedge clk);
      eom_tx_start_level=0;
      words=(expected_bits+63)/64;
      for(w=0;w<words;w++) begin
        @(posedge clk); #0.05;
        for(l=0;l<64;l++) begin
          pos=w*64+l;
          if(valid_mask[l] !== ((pos<expected_bits)?exp_valid[pos]:1'b0))
            fail($sformatf("active snapshot mask w=%0d l=%0d",w,l));
          if(txdata[l] !== ((pos<expected_bits)?exp_data[pos]:1'b0))
            fail($sformatf("active snapshot polluted w=%0d l=%0d",w,l));
        end
      end
      timeout=0;
      while(!done && timeout<8) begin @(posedge clk); #0.05; timeout++; end
      if(!done) fail("active snapshot no done");
      $display("PASS active task pattern snapshot is isolated from shadow");
      repeat(2) @(posedge clk);
    end endtask
    task automatic set_gap(input integer idx,input integer value);
      gap_len_bits[idx*8 +:8]=value[7:0];
    endtask
    task automatic run_loop_one_accept_case;
      integer cycles,accepts,sequence_fires;
    begin
      pattern_len=63;repeat_cycles=2;head_delay_bits=0;gap_len_bits=0;
      set_gap(0,1);phase_shift_en=0;loop_en=1;
      eom_geometry_armed=0; pulse_start(); accepts=0; sequence_fires=0;
      while(!engine_start_accept_pulse) begin @(posedge clk);#0.05;end
      accepts++;
      wait_current_plan("loop plan");
      @(negedge clk);eom_geometry_armed=1;eom_tx_start_level=1;
      @(posedge clk);#0.05;@(negedge clk);eom_tx_start_level=0;
      for(cycles=0;cycles<12;cycles++) begin
        @(posedge clk);#0.05;
        if(engine_start_accept_pulse)accepts++;
        if(first_sequence_word_fire)sequence_fires++;
      end
      if(accepts!=1||!busy||done)
        fail($sformatf("loop one-accept semantics accepts=%0d busy=%0b done=%0b",
                       accepts,busy,done));
      if(sequence_fires<2)
        fail($sformatf("loop sequence boundary fires=%0d",sequence_fires));
      enable=0;repeat(2)@(posedge clk);#0.05;
      if(busy||valid_mask!=0)fail("loop disable did not quiesce");
      enable=1;loop_en=0;eom_geometry_armed=0;repeat(2)@(posedge clk);
      pulse_start();arm_and_start("new accepted task");
      $display("PASS loop boundary does not reaccept; new task does");
      while(!done)@(posedge clk);repeat(2)@(posedge clk);
    end endtask

    task automatic run_pipeline_abort_case(input bit abort_at_plan);
      integer timeout;
    begin
      pattern_len=63;repeat_cycles=6;head_delay_bits=1;
      gap_len_bits=0;phase_shift_en=0;loop_en=0;
      eom_geometry_armed=0;
      pulse_start();
      timeout=0;
      if(abort_at_plan) begin
        while(!dut.next_append_plan_valid_q && timeout<5000) begin
          @(posedge clk);#0.05;timeout++;
        end
      end else begin
        while(!dut.append_meta_valid_q && timeout<5000) begin
          @(posedge clk);#0.05;timeout++;
        end
      end
      if(timeout>=5000)
        fail(abort_at_plan?"abort plan stage timeout":
                           "abort metadata stage timeout");
      @(negedge clk);enable=0;
      @(posedge clk);#0.05;
      if(busy || valid_mask!=0 || dut.append_meta_valid_q ||
         dut.next_append_plan_valid_q ||
         dut.current_append_plan_valid_q)
        fail(abort_at_plan?"abort did not flush plan pipeline":
                           "abort did not flush metadata pipeline");
      @(negedge clk);enable=1;
      repeat(2)@(posedge clk);
      $display("PASS abort flushes %s stage",
               abort_at_plan?"plan":"metadata");
    end endtask

    initial begin
      base_pattern=127'h52A55AA5765432100123456789ABCDEF;
      pattern_len=63; repeat_cycles=1; head_delay_bits=0; gap_len_bits=0;
      phase_shift_en=0; loop_en=0;
      repeat(4) @(posedge clk); rst=0;
      if(first_sequence_word_fire)
        fail("sequence fire asserted after reset");
      if(legacy_prbs_period(6,32'h0000005a) !==
         LEGACY_PRBS6_SEED_5A_GOLDEN)
        fail("legacy PRBS6 golden vector mismatch");
      if(legacy_prbs_period(7,32'h0000005a) !==
         LEGACY_PRBS7_SEED_5A_GOLDEN)
        fail("legacy PRBS7 golden vector mismatch");
      base_pattern=LEGACY_PRBS6_SEED_5A_GOLDEN;
      pattern_len=63;
      run_case("configured_prbs6_golden_lane_equivalence");
      base_pattern=LEGACY_PRBS7_SEED_5A_GOLDEN;
      pattern_len=127;
      run_case("configured_prbs7_golden_lane_equivalence");
      base_pattern=127'h52A55AA5765432100123456789ABCDEF;
      pattern_len=127;
      run_active_snapshot_case();
      // The following task must observe the newly configured replacement.
      run_case("next_task_uses_updated_configured_pattern");
      base_pattern=127'h52A55AA5765432100123456789ABCDEF;
      pattern_len=63;
      run_pipeline_abort_case(0);
      run_pipeline_abort_case(1);
      pattern_len=63;repeat_cycles=1;head_delay_bits=0;
      gap_len_bits=0;phase_shift_en=0;loop_en=0;
      run_case("repeat1_head0");
      head_delay_bits=64;run_case("repeat1_head64");head_delay_bits=0;
      repeat_cycles=2; set_gap(0,1); run_case("repeat2_gap1");
      // Directed descriptor-boundary coverage: a 63-bit pattern with zero
      // gaps alternates between partial and whole-pattern append cases.
      pattern_len=63;repeat_cycles=6;head_delay_bits=0;gap_len_bits=0;
      run_case("append63_zero_gap_boundary_chain");
      // A one-bit head offset exercises a different append alignment while
      // retaining back-to-back descriptor consumption.
      repeat_cycles=6;head_delay_bits=1;gap_len_bits=0;
      run_case("append63_head1_zero_gap_chain");
      // A two-bit head leaves one source bit for the second word; the next
      // zero-gap descriptor then fills the remaining 63 lanes.
      repeat_cycles=2;head_delay_bits=2;gap_len_bits=0;
      run_case("append63_count63_boundary");
      // 127-bit patterns cover the partial append followed by the remaining
      // 64/63-bit stream split.
      pattern_len=127;repeat_cycles=4;head_delay_bits=0;gap_len_bits=0;
      run_case("append127_zero_gap_boundary_chain");
      pattern_len=63;
      repeat_cycles=5; gap_len_bits=0; set_gap(0,0);set_gap(1,2);
      set_gap(2,63);set_gap(3,65);head_delay_bits=1;
      run_case("repeat5_mixed_gaps");
      repeat_cycles=16;gap_len_bits=0;set_gap(0,3);set_gap(1,64);
      set_gap(2,127);set_gap(3,128);set_gap(4,255);head_delay_bits=255;
      run_case("repeat16_boundaries");
      pattern_len=63;repeat_cycles=3;gap_len_bits=0;set_gap(0,0);
      set_gap(1,1);head_delay_bits=0;phase_shift_en=1;
      run_case("phase_precompute_repeat_reuse_63");
      repeat_cycles=2;gap_len_bits=0;set_gap(0,0);head_delay_bits=63;
      phase_shift_en=1;run_case("direct63_all_phases_same_repeat");
      pattern_len=127;repeat_cycles=2;head_delay_bits=65;set_gap(0,3);
      phase_shift_en=1;run_case("direct127_all_phases");
      phase_shift_en=0;repeat_cycles=1;head_delay_bits=127;gap_len_bits=0;
      half_period=1.5515;run_case("runtime_clock_change");
      half_period=3.103;run_loop_one_accept_case();
      if(append_count0_seen==0 || append_count1_seen==0 ||
         append_count63_seen==0)
        fail($sformatf("append count coverage 0=%0d 1=%0d 63=%0d",
             append_count0_seen,append_count1_seen,append_count63_seen));
      else
        $display("PASS append count coverage 0=%0d 1=%0d 63=%0d",
                 append_count0_seen,append_count1_seen,
                 append_count63_seen);
      if(errors==0)
        $display("PATTERN_TX_ENGINE_TIMING_REGRESSION_PASS");
      else
        $display("PATTERN_TX_ENGINE_TIMING_REGRESSION_FAIL errors=%0d",errors);
      $finish;
    end
endmodule
