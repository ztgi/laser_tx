`timescale 1ns/1ps
module tb_tx_eom_v2;
  logic eom_clk=0;
  logic tx_clk_div=0;
  logic rst=1, clock_safe=0, enable=0;
  logic engine_start=0;
  logic eom_enable=1, phase_shift_en=0, loop_en=0;
  logic [10:0] global_pattern_index=0;
  logic [15:0] lead_ticks=0,trail_ticks=0;
  logic [4:0] repeat_cycles=1;
  logic [7:0] pattern_len=63,head_delay_bits=0;
  logic [119:0] gaps=0;
  logic [2:0] eom_subdiv_log2=4;
  logic [126:0] base_pattern=127'h52A55AA5765432100123456789ABCDEF;
  logic [4:0] tx_div_phase=0;

  wire tx_clk=(eom_subdiv_log2==0)?eom_clk:tx_clk_div;
  wire engine_accept;
  wire first_sequence_word_fire;
  wire task_request_pulse=engine_accept;
  wire geometry_armed_tx,tx_start_level,request_valid_tx,request_busy_tx;
  wire eom_out,eom_active,eom_fired,done_toggle;
  wire geometry_valid_eom,eom_armed,alignment_valid_eom;
  wire task_zero_pulse_eom;
  wire [23:0] task_tick_counter_eom,start_tick_local_eom,end_tick_local_eom;
  wire [7:0] selected_phase_eom;
  wire [3:0] selected_repeat_eom;
  wire [63:0] txdata,valid_mask;
  wire phase_active,phase_start_pulse,sequence_active,busy,done;
  wire [7:0] phase_offset,current_state;
  logic done_meta=0,done_sync=0,done_seen=0;
  wire eom_done_pulse=done_sync^done_seen;

  integer errors=0;
  integer gap_ref[0:14];
  integer eom_rise_count=0;
  integer task_zero_count=0,tx_first_word_count=0;
  realtime zero_time,first_word_time;
  realtime last_task_zero_time,last_tx_first_word_time;
  logic engine_running_seen=0;
  logic tx_first_word_pending=0;

  always #4 eom_clk=~eom_clk;

  // Simulation model of zero-phase integer-related MMCM outputs. TX rising
  // edges coincide with EOM rising edges for K=16/8/4.
  always @(posedge eom_clk or negedge clock_safe) begin
    if(!clock_safe) begin
      tx_div_phase<=0;
      tx_clk_div<=0;
    end else if(eom_subdiv_log2!=0) begin
      if(tx_div_phase==0)
        tx_clk_div<=1;
      else if(tx_div_phase==(1<<(eom_subdiv_log2-1)))
        tx_clk_div<=0;
      if(tx_div_phase==((1<<eom_subdiv_log2)-1))
        tx_div_phase<=0;
      else
        tx_div_phase<=tx_div_phase+1'b1;
    end
  end

  always @(posedge tx_clk) begin
    if(rst||!clock_safe) begin
      done_meta<=0;done_sync<=0;done_seen<=0;
    end else begin
      done_meta<=done_toggle;
      done_sync<=done_meta;
      done_seen<=done_sync;
    end
  end

  always @(posedge eom_out) eom_rise_count=eom_rise_count+1;
  always @(posedge task_zero_pulse_eom) begin
    task_zero_count=task_zero_count+1;
    last_task_zero_time=$realtime;
    $display("TRACE EOM_TASK_ZERO time=%0.3f",$realtime);
  end

  // running changes on B1. The first word is registered on B2.
  always @(posedge tx_clk) begin
    #0.02;
    if(tx_first_word_pending)begin
      tx_first_word_count=tx_first_word_count+1;
      last_tx_first_word_time=$realtime-0.02;
      tx_first_word_pending=0;
      $display("TRACE TX_FIRST_WORD time=%0.3f",$realtime);
    end
    if(engine.output_running&&!engine_running_seen)begin
      engine_running_seen=1;
      tx_first_word_pending=1;
    end else if(!engine.output_running)begin
      engine_running_seen=0;
    end
  end

  tx_eom_window_generator dut(
    .tx_clk(tx_clk),.tx_abort(rst||!enable||!clock_safe),
    .task_request_pulse_tx(task_request_pulse),
    .eom_enable_tx(eom_enable),
    .global_pattern_index_tx(global_pattern_index),
    .lead_ticks_tx(lead_ticks),.trail_ticks_tx(trail_ticks),
    .repeat_cycles_tx(repeat_cycles),.pattern_len_tx(pattern_len),
    .phase_shift_en_tx(phase_shift_en),
    .head_delay_bits_tx(head_delay_bits),.gap_len_bits_tx(gaps),
    .eom_subdiv_log2_tx(eom_subdiv_log2),
    .eom_clk(eom_clk),.clock_safe(clock_safe&&enable&&!rst),
    .async_output_safe(clock_safe&&enable&&!rst),
    .geometry_armed_tx(geometry_armed_tx),
    .tx_start_level(tx_start_level),
    .request_valid_tx(request_valid_tx),
    .request_busy_tx(request_busy_tx),
    .eom_out(eom_out),.eom_active(eom_active),.eom_fired(eom_fired),
    .done_toggle(done_toggle),
    .geometry_valid_eom(geometry_valid_eom),.eom_armed(eom_armed),
    .alignment_valid_eom(alignment_valid_eom),
    .task_zero_pulse_eom(task_zero_pulse_eom),
    .task_tick_counter_eom(task_tick_counter_eom),
    .start_tick_local_eom(start_tick_local_eom),
    .end_tick_local_eom(end_tick_local_eom),
    .selected_phase_eom(selected_phase_eom),
    .selected_repeat_eom(selected_repeat_eom));

  pattern_tx_engine engine(
    .clk(tx_clk),.rst(rst||!clock_safe),.start(engine_start),.enable(enable),
    .pattern_valid(1'b1),.base_pattern(base_pattern),
    .pattern_len(pattern_len),.repeat_cycles(repeat_cycles),
    .head_delay_bits(head_delay_bits),.gap_len_bits(gaps),
    .phase_shift_en(phase_shift_en),.loop_en(loop_en),
    .eom_geometry_armed(geometry_armed_tx),
    .eom_tx_start_level(tx_start_level),
    .eom_request_valid(request_valid_tx),
    .eom_done_pulse(eom_done_pulse),
    .engine_start_accept_pulse(engine_accept),
    .first_sequence_word_fire(first_sequence_word_fire),
    .txdata(txdata),.valid_mask(valid_mask),
    .phase_active(phase_active),.phase_start_pulse(phase_start_pulse),
    .sequence_active(sequence_active),.busy(busy),.done(done),
    .phase_offset(phase_offset),.current_state(current_state));

  task automatic fail(input string s); begin
    $display("ERROR @%0t %s",$time,s);errors++;
  end endtask
  task automatic set_gap(input integer i,input integer v); begin
    gaps[i*8 +:8]=v[7:0];gap_ref[i]=v;
  end endtask
  task automatic clear_gaps; integer i; begin
    gaps=0;for(i=0;i<15;i++)gap_ref[i]=0;
  end endtask
  function automatic integer gap_at(input integer i);
    gap_at=gap_ref[i];
  endfunction

  task automatic select_k(input integer klog2); begin
    enable=0;clock_safe=0;rst=1;
    repeat(4)@(posedge eom_clk);
    eom_subdiv_log2=klog2[2:0];
    repeat(2)@(posedge eom_clk);
    // Restart the related clocks while TX remains held in reset/not-ready.
    clock_safe=1;
    repeat((1<<klog2)+2)@(posedge eom_clk);
    rst=0;enable=1;
    repeat(6)@(posedge eom_clk);
  end endtask

  task automatic pulse_engine_start(input integer phase_delay); begin
    repeat(phase_delay)@(posedge eom_clk);
    @(negedge tx_clk);engine_start=1;
    @(negedge tx_clk);engine_start=0;
  end endtask

  task automatic expected_geometry(
    output integer ep,output integer er,output integer estart,
    output integer eend);
    integer i,frame,prefix,bpt,sbit,ebit;
    begin
      ep=global_pattern_index/repeat_cycles;
      er=global_pattern_index%repeat_cycles;
      frame=head_delay_bits;
      for(i=0;i<repeat_cycles;i++)frame=frame+pattern_len;
      for(i=0;i<repeat_cycles-1;i++)frame=frame+gap_at(i);
      prefix=0;for(i=0;i<er;i++)prefix=prefix+gap_at(i);
      bpt=64/(1<<eom_subdiv_log2);
      sbit=ep*frame+head_delay_bits+er*pattern_len+prefix;
      ebit=sbit+pattern_len;
      estart=(sbit/bpt>lead_ticks)?sbit/bpt-lead_ticks:0;
      eend=(ebit+bpt-1)/bpt+trail_ticks;
    end
  endtask

  task automatic run_valid_task(
    input string name,input integer phase_delay,input bit mutate_while_busy);
    integer ep,er,estart,eend,timeout,rises_before,zero_before,word_before;
    reg [10:0] original_index;
    reg [119:0] original_gaps;
    begin
      expected_geometry(ep,er,estart,eend);
      original_index=global_pattern_index;
      original_gaps=gaps;
      rises_before=eom_rise_count;
      zero_before=task_zero_count;
      word_before=tx_first_word_count;
      pulse_engine_start(phase_delay);
      timeout=0;
      while(!request_busy_tx&&timeout<50)begin @(posedge tx_clk);#0.05;timeout++;end
      if(!request_busy_tx)fail({name," request was not accepted"});

      if(mutate_while_busy)begin
        // Changing the source bundle while busy must not alter the held
        // snapshot captured before the request toggle.
        global_pattern_index=11'd2047;gaps={15{8'hff}};
      end

      // A new acknowledge is the authoritative transaction boundary. The
      // prior geometry_valid level may remain high until EOM captures this
      // request, so it is not used as a new-transaction event.
      timeout=0;
      while(geometry_armed_tx&&timeout<1000)
        begin @(posedge tx_clk);#0.05;timeout++;end
      while(!geometry_armed_tx&&timeout<10000)
        begin @(posedge tx_clk);#0.05;timeout++;end
      if(!geometry_armed_tx)fail({name," armed ack timeout"});
      if(!geometry_valid_eom)fail({name," geometry not valid at ack"});
      if(!request_valid_tx)fail({name," unexpectedly invalid geometry"});
      if(selected_phase_eom!=ep||selected_repeat_eom!=er||
         start_tick_local_eom!=estart||end_tick_local_eom!=eend)
        fail($sformatf("%s geometry got p%0d/r%0d/%0d..%0d exp p%0d/r%0d/%0d..%0d",
          name,selected_phase_eom,selected_repeat_eom,
          start_tick_local_eom,end_tick_local_eom,ep,er,estart,eend));

      global_pattern_index=original_index;gaps=original_gaps;
      timeout=0;
      while((task_zero_count==zero_before||tx_first_word_count==word_before)&&
            timeout<10000)begin @(posedge eom_clk);#0.05;timeout++;end
      if(task_zero_count==zero_before||tx_first_word_count==word_before)begin
        $display("ALIGN_DEBUG state=%0d align=%0b phase=%0d terminal=%0d start_req=%0b start_level=%0b armed_tx=%0b armed_seen=%0b",
          dut.eom_state,alignment_valid_eom,dut.boundary_phase_eom,
          dut.boundary_terminal_eom,dut.tx_start_level_request_eom,
          tx_start_level,geometry_armed_tx,dut.armed_seen_eom);
        fail({name," aligned launch timeout"});
        $finish;
      end
      zero_time=last_task_zero_time;
      first_word_time=last_tx_first_word_time;
      if(zero_time!=first_word_time)
        fail($sformatf("%s first-word/tick-zero mismatch %0.3f/%0.3f",
                       name,first_word_time,zero_time));

      timeout=0;
      while(!done&&timeout<200000)begin @(posedge tx_clk);#0.05;timeout++;end
      if(!done)fail({name," completion timeout"});
      if(eom_rise_count-rises_before!=1)
        fail($sformatf("%s EOM pulses=%0d expected=1",
                       name,eom_rise_count-rises_before));
      if(eom_out||eom_active||!eom_fired)
        fail({name," EOM completion state"});
      else
        $display("PASS %s K=%0d geometry=%0d..%0d boundary=%0.3f",
          name,1<<eom_subdiv_log2,estart,eend,zero_time);
      repeat(2)@(posedge tx_clk);
    end
  endtask

  task automatic run_invalid_or_disabled(input string name);
    integer timeout,rises_before;
    begin
      rises_before=eom_rise_count;
      pulse_engine_start(1);
      timeout=0;
      while(geometry_armed_tx&&timeout<1000)
        begin @(posedge tx_clk);#0.05;timeout++;end
      while(!geometry_armed_tx&&timeout<10000)
        begin @(posedge tx_clk);#0.05;timeout++;end
      if(!geometry_armed_tx||!geometry_valid_eom)
        fail({name," geometry ack timeout"});
      timeout=0;
      while(!done&&timeout<200000)begin @(posedge tx_clk);#0.05;timeout++;end
      if(!done)fail({name," no TX completion"});
      if(request_valid_tx||eom_rise_count!=rises_before||eom_fired)
        fail({name," unexpectedly generated EOM"});
      else $display("PASS %s suppressed",name);
      repeat(2)@(posedge tx_clk);
    end
  endtask

  task automatic run_abort_case;
    integer timeout,rises_before;
    begin
      repeat_cycles=1;pattern_len=127;head_delay_bits=0;phase_shift_en=0;
      global_pattern_index=0;lead_ticks=0;trail_ticks=100;
      eom_enable=1;loop_en=0;clear_gaps();
      rises_before=eom_rise_count;
      pulse_engine_start(3);
      timeout=0;
      while(!eom_out&&timeout<10000)begin @(posedge eom_clk);#0.05;timeout++;end
      if(!eom_out)fail("abort setup never raised EOM");
      #1 clock_safe=0;#0.05;
      if(eom_out)
        fail("clock unsafe did not asynchronously close EOM output");
      // Internal geometry/config/state intentionally use the local
      // asynchronous-assert/synchronous-release reset.  They clear on the
      // next available EOM clock edge rather than through raw clock_safe CLR.
      repeat(3)@(posedge eom_clk);
      #0.05;
      if(eom_active||eom_armed||geometry_valid_eom)
        fail("local EOM reset did not synchronously clear internal state");
      // Keep TX reset/not-ready while the related clocks restart.
      enable=0;rst=1;clock_safe=1;
      repeat(18)@(posedge eom_clk);
      rst=0;enable=1;
      repeat(20)begin @(posedge eom_clk);#0.05;
        if(eom_out)fail("stale EOM reopened after recovery");
      end
      if(eom_rise_count-rises_before!=1)
        fail("abort pulse accounting");
      else $display("PASS abort immediate-low/no-stale-reopen");
      repeat(2)@(posedge tx_clk);
    end
  endtask

  task automatic run_loop_one_shot;
    integer rises_before,timeout;
    begin
      repeat_cycles=2;pattern_len=63;head_delay_bits=0;phase_shift_en=0;
      global_pattern_index=0;lead_ticks=0;trail_ticks=0;eom_enable=1;
      loop_en=1;clear_gaps();set_gap(0,1);
      rises_before=eom_rise_count;
      pulse_engine_start(2);
      timeout=0;
      while(eom_rise_count==rises_before&&timeout<10000)begin
        @(posedge eom_clk);#0.05;timeout++;
      end
      repeat(30)@(posedge tx_clk);
      if(eom_rise_count-rises_before!=1||!busy||done)
        fail("loop emitted more than one EOM or stopped");
      else $display("PASS loop emits one EOM for one accepted task");
      enable=0;repeat(2)@(posedge tx_clk);enable=1;
      // The production EOM handshake state now uses a TX-domain local reset
      // synchronizer.  Wait in that domain before issuing the next task.
      loop_en=0;repeat(4)@(posedge tx_clk);
    end
  endtask

  initial begin
    clear_gaps();

    select_k(4);
    repeat_cycles=5;pattern_len=63;head_delay_bits=3;phase_shift_en=1;
    global_pattern_index=17;lead_ticks=100;trail_ticks=3;eom_enable=1;
    set_gap(0,1);set_gap(1,64);set_gap(2,3);set_gap(3,255);
    run_valid_task("K16_repeat5_mixed_middle_lead_clamp",3,1);

    repeat_cycles=1;pattern_len=63;head_delay_bits=0;phase_shift_en=0;
    global_pattern_index=0;lead_ticks=0;trail_ticks=2;clear_gaps();
    run_valid_task("K16_back_to_back_repeat1_first",7,0);
    run_loop_one_shot();
    run_abort_case();

    repeat_cycles=2;pattern_len=63;head_delay_bits=1;phase_shift_en=0;
    global_pattern_index=1;lead_ticks=0;trail_ticks=1;clear_gaps();set_gap(0,2);
    run_valid_task("K16_recovery_fresh_snapshot",5,0);

    select_k(3);clear_gaps();set_gap(0,7);
    repeat_cycles=2;pattern_len=127;head_delay_bits=5;phase_shift_en=0;
    global_pattern_index=1;lead_ticks=1;trail_ticks=4;eom_enable=1;
    run_valid_task("K8_repeat2_127_last",2,0);

    select_k(2);clear_gaps();set_gap(0,1);set_gap(1,2);set_gap(2,3);
    repeat_cycles=16;pattern_len=63;head_delay_bits=2;phase_shift_en=0;
    global_pattern_index=15;lead_ticks=0;trail_ticks=5;eom_enable=1;
    run_valid_task("K4_repeat16_last",1,0);

    select_k(0);clear_gaps();set_gap(0,3);
    repeat_cycles=2;pattern_len=127;head_delay_bits=4;phase_shift_en=1;
    global_pattern_index=127;lead_ticks=2;trail_ticks=2;eom_enable=1;
    run_valid_task("K1_127_phase_middle",4,0);

    repeat_cycles=2;pattern_len=63;head_delay_bits=0;phase_shift_en=0;
    global_pattern_index=2;lead_ticks=0;trail_ticks=0;eom_enable=1;
    clear_gaps();run_invalid_or_disabled("invalid_global_index");
    global_pattern_index=0;eom_enable=0;
    run_invalid_or_disabled("eom_disabled");

    if(errors==0)$display("TX_EOM_V2_REGRESSION_PASS");
    else $display("TX_EOM_V2_REGRESSION_FAIL errors=%0d",errors);
    $finish;
  end
endmodule
