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
    wire [63:0] txdata, valid_mask;
    wire phase_active, phase_start_pulse, sequence_active, busy, done;
    wire [7:0] phase_offset, current_state;
    realtime half_period=3.103;
    integer errors=0, expected_bits=0;
    reg exp_data[0:399999];
    reg exp_valid[0:399999];

    always #(half_period) clk=~clk;
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
      .txdata(txdata),.valid_mask(valid_mask),
      .phase_active(phase_active),.phase_start_pulse(phase_start_pulse),
      .sequence_active(sequence_active),.busy(busy),.done(done),
      .phase_offset(phase_offset),.current_state(current_state));

    task automatic fail(input string s); begin
      $display("ERROR @%0t %s",$time,s); errors++;
    end endtask
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
    task automatic arm_and_start(input string name); integer timeout; begin
      timeout=0;
      while(!engine_start_accept_pulse && timeout<5000) begin
        @(posedge clk); #0.05; timeout++;
      end
      if(!engine_start_accept_pulse) fail({name," no accept"});
      @(negedge clk);
      eom_geometry_armed=1;
      eom_tx_start_level=1;
      @(posedge clk); #0.05;
      @(negedge clk);
      eom_tx_start_level=0;
    end endtask
    task automatic run_case(input string name); integer w,l,pos,words,timeout; begin
      build_expected(); eom_geometry_armed=0; pulse_start();
      arm_and_start(name);
      words=(expected_bits+63)/64;
      for(w=0;w<words;w++) begin
        @(posedge clk); #0.05;
        for(l=0;l<64;l++) begin
          pos=w*64+l;
          if(valid_mask[l] !== ((pos<expected_bits)?exp_valid[pos]:1'b0))
            fail($sformatf("%s mask w=%0d l=%0d",name,w,l));
          if(txdata[l] !== ((pos<expected_bits)?exp_data[pos]:1'b0))
            fail($sformatf("%s data w=%0d l=%0d",name,w,l));
        end
      end
      timeout=0;
      while(!done && timeout<8) begin @(posedge clk); #0.05; timeout++; end
      if(!done) fail({name," no done"});
      $display("PASS %s bits=%0d words=%0d",name,expected_bits,words);
      repeat(2) @(posedge clk);
    end endtask
    task automatic set_gap(input integer idx,input integer value);
      gap_len_bits[idx*8 +:8]=value[7:0];
    endtask
    task automatic run_loop_one_accept_case; integer cycles,accepts; begin
      pattern_len=63;repeat_cycles=2;head_delay_bits=0;gap_len_bits=0;
      set_gap(0,1);phase_shift_en=0;loop_en=1;
      eom_geometry_armed=0; pulse_start(); accepts=0;
      while(!engine_start_accept_pulse) begin @(posedge clk);#0.05;end
      accepts++;
      @(negedge clk);eom_geometry_armed=1;eom_tx_start_level=1;
      @(posedge clk);#0.05;@(negedge clk);eom_tx_start_level=0;
      for(cycles=0;cycles<12;cycles++) begin
        @(posedge clk);#0.05;if(engine_start_accept_pulse)accepts++;
      end
      if(accepts!=1||!busy||done)
        fail($sformatf("loop one-accept semantics accepts=%0d busy=%0b done=%0b",
                       accepts,busy,done));
      enable=0;repeat(2)@(posedge clk);#0.05;
      if(busy||valid_mask!=0)fail("loop disable did not quiesce");
      enable=1;loop_en=0;eom_geometry_armed=0;repeat(2)@(posedge clk);
      pulse_start();arm_and_start("new accepted task");
      $display("PASS loop boundary does not reaccept; new task does");
      while(!done)@(posedge clk);repeat(2)@(posedge clk);
    end endtask

    initial begin
      base_pattern=127'h52A55AA5765432100123456789ABCDEF;
      pattern_len=63; repeat_cycles=1; head_delay_bits=0; gap_len_bits=0;
      phase_shift_en=0; loop_en=0;
      repeat(4) @(posedge clk); rst=0;
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
      if(errors==0)
        $display("PATTERN_TX_ENGINE_TIMING_REGRESSION_PASS");
      else
        $display("PATTERN_TX_ENGINE_TIMING_REGRESSION_FAIL errors=%0d",errors);
      $finish;
    end
endmodule
