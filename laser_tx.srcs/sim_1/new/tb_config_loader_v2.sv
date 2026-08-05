`timescale 1ns/1ps
module tb_config_loader_v2;
  logic clk=0,rstn=0;logic[7:0]config_index=0;logic apply_toggle=0;wire bram_en;wire[31:0]bram_addr;logic[31:0]bram_dout;
  wire cfg_valid,cfg_error;wire[7:0]error_code;wire cfg_update_toggle;wire[4:0]repeat_cycles;wire[7:0]head_delay_bits;wire[119:0]gap_len_bits;wire eom_enable;wire[10:0]eom_global_pattern_index;wire[15:0]eom_lead_ticks,eom_trail_ticks;wire phase_shift_en,loop_en;wire[7:0]pattern_len;wire[126:0]configured_pattern;
  reg[31:0]mem[0:31];integer errors=0,i;
  always #5 clk=~clk;always@(posedge clk)if(bram_en)bram_dout<=mem[bram_addr>>2];
  config_loader dut(.*);
  function automatic[31:0]crcword(input[31:0]cin,input[31:0]v);integer b;reg[31:0]c,x;begin c=cin;x=v;for(b=0;b<32;b++)begin c=(c[0]^x[0])?((c>>1)^32'hEDB88320):(c>>1);x=x>>1;end crcword=c;end endfunction
  task automatic build(input[7:0]seq);reg[31:0]c;begin for(i=0;i<32;i++)mem[i]=0;mem[0]={16'h5458,4'd2,1'b1,3'b0,seq};mem[1]=32'h12345678;mem[2]=5'd5|(8'd7<<5)|(1<<13)|(1<<15)|(1<<16)|(1<<17)|(11'd17<<18);mem[3]=8'd65;mem[4]=32'h403f0201;mem[5]=32'h000000ff;mem[8]={16'd3,16'd2};mem[9]=32'h89abcdef;mem[10]=32'h01234567;mem[11]=32'h76543210;mem[12]=32'h02a55aa5;mem[13]=seq|(16<<8)|(16<<16)|(8<<24);mem[14]=0;c=32'hffffffff;for(i=1;i<=14;i++)c=crcword(c,mem[i]);mem[15]=~c;end endtask
  task automatic refresh_crc; reg[31:0] c; begin c=32'hffffffff;for(i=1;i<=14;i++)c=crcword(c,mem[i]);mem[15]=~c;end endtask
  task automatic apply_wait; integer t; begin @(negedge clk); apply_toggle=~apply_toggle; t=0; while(dut.apply_seen!=apply_toggle && t<200) begin @(posedge clk); #0.1; t++; end while(dut.state!=0 && t<300) begin @(posedge clk); #0.1; t++; end repeat(2)@(posedge clk); end endtask
  task automatic report_error(input string s); begin
    $display("ERROR %s",s); errors = errors + 1;
  end endtask
  initial begin build(8'h21);repeat(3)@(posedge clk);rstn=1;apply_wait();if(!cfg_valid||cfg_error||repeat_cycles!=5||head_delay_bits!=65||gap_len_bits[7:0]!=1||!eom_enable||eom_global_pattern_index!=17||pattern_len!=127||configured_pattern!=127'h2a55aa5765432100123456789abcdef)report_error("valid configured-pattern record decode");else $display("PASS valid configured-pattern record");
    build(8'h22);mem[15]^=1;apply_wait();if(!cfg_error||error_code!=8'h13||configured_pattern!=127'h2a55aa5765432100123456789abcdef)report_error("CRC failure did not preserve active pattern");else $display("PASS CRC preserves active pattern");
    build(8'h23);fork begin wait(dut.word_index==5);mem[0][7:0]=8'h24;end begin apply_wait();end join;if(!cfg_error||error_code!=8'h14||configured_pattern!=127'h2a55aa5765432100123456789abcdef)report_error("double header atomic failure");else $display("PASS double-header preserves active pattern");
    build(8'h25);mem[0][11]=0;apply_wait();if(!cfg_error||error_code!=8'h11||configured_pattern!=127'h2a55aa5765432100123456789abcdef)report_error("invalid commit header");else $display("PASS commit_valid/half-write guard");
    build(8'h26);mem[0][31:16]=16'h0000;apply_wait();if(!cfg_error||error_code!=8'h11||configured_pattern!=127'h2a55aa5765432100123456789abcdef)report_error("bad magic");else $display("PASS bad magic preserves active");
    build(8'h27);mem[0][15:12]=4'd1;apply_wait();if(!cfg_error||error_code!=8'h11||configured_pattern!=127'h2a55aa5765432100123456789abcdef)report_error("bad version");else $display("PASS bad version preserves active");
    build(8'h28);mem[13][15:8]=8'd15;refresh_crc();apply_wait();if(!cfg_error||error_code!=8'h12||configured_pattern!=127'h2a55aa5765432100123456789abcdef)report_error("bad metadata");else $display("PASS bad metadata preserves active");
    build(8'h29);mem[13][7:0]=8'h2a;refresh_crc();apply_wait();if(!cfg_error||error_code!=8'h12||configured_pattern!=127'h2a55aa5765432100123456789abcdef)report_error("sequence mirror mismatch");else $display("PASS sequence mirror mismatch preserves active");
    build(8'h2b);mem[14]=32'h1;refresh_crc();apply_wait();if(!cfg_error||error_code!=8'h12||configured_pattern!=127'h2a55aa5765432100123456789abcdef)report_error("reserved word nonzero");else $display("PASS reserved word guard");
    build(8'h2d);mem[1]=32'hdeadc0de;mem[2][12:5]=8'hff;mem[2][15]=1'b0;refresh_crc();apply_wait();if(!cfg_valid||cfg_error||pattern_len!=127||configured_pattern!=127'h2a55aa5765432100123456789abcdef)report_error("legacy PRBS/source fields were not ignored");else $display("PASS seed/prbs/source fields reserved and ignored");
    build(8'h2c);config_index=8'd128;apply_wait();if(!cfg_error||error_code!=8'h10||configured_pattern!=127'h2a55aa5765432100123456789abcdef)report_error("index range guard");else $display("PASS index range guard");config_index=0;
    if(errors==0)$display("CONFIG_LOADER_V2_REGRESSION_PASS");else $display("CONFIG_LOADER_V2_REGRESSION_FAIL errors=%0d",errors);$finish;end
endmodule
