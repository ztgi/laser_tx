`timescale 1ns/1ps

module tb_tx_scope_debug_outputs;
    logic txusrclk2 = 1'b0;
    logic reset_async = 1'b1;
    logic sequence_word_fire = 1'b0;
    wire gt_sequence_sync_out;
    wire txusrclk2_monitor_out;
    integer errors = 0;
    integer high_cycles = 0;
    integer monitor_edges = 0;

    always #4 txusrclk2 = ~txusrclk2;
    always @(txusrclk2_monitor_out)
        if (!reset_async)
            monitor_edges++;

    tx_scope_debug_outputs #(
        .SYNC_WIDTH_CYCLES(16)
    ) dut (
        .txusrclk2(txusrclk2),
        .reset_tx(reset_async),
        .sequence_word_fire(sequence_word_fire),
        .gt_sequence_sync_out(gt_sequence_sync_out),
        .txusrclk2_monitor_out(txusrclk2_monitor_out)
    );

    task automatic fail(input string text);
      begin
        $display("ERROR @%0t %s", $time, text);
        errors++;
      end
    endtask

    initial begin
        repeat (3) @(posedge txusrclk2);
        if (gt_sequence_sync_out !== 1'b0 ||
            txusrclk2_monitor_out !== 1'b0)
            fail("outputs not low during reset");

        @(negedge txusrclk2);
        reset_async = 1'b0;
        // The UNISIM global set/reset remains asserted for the first 100 ns.
        // Wait beyond it before checking normal ODDR edge forwarding.
        repeat (16) @(posedge txusrclk2);
        if (monitor_edges < 6)
            fail("ODDR monitor did not toggle on both clock edges");

        @(negedge txusrclk2);
        sequence_word_fire = 1'b1;
        @(posedge txusrclk2);
        #0.05;
        if (!gt_sequence_sync_out)
            fail("widened output did not rise with raw event");
        sequence_word_fire = 1'b0;

        high_cycles = 1;
        while (gt_sequence_sync_out && high_cycles < 32) begin
            @(posedge txusrclk2);
            #0.05;
            if (gt_sequence_sync_out)
                high_cycles++;
        end
        if (high_cycles != 16)
            fail($sformatf("pulse width=%0d expected=16", high_cycles));

        @(negedge txusrclk2);
        sequence_word_fire = 1'b1;
        @(posedge txusrclk2);
        #0.05;
        sequence_word_fire = 1'b0;
        repeat (3) @(posedge txusrclk2);
        #0.05;
        reset_async = 1'b1;
        @(posedge txusrclk2);
        #0.05;
        if (gt_sequence_sync_out !== 1'b0 ||
            txusrclk2_monitor_out !== 1'b0)
            fail("TX-synchronous abort did not force outputs low");

        if (errors == 0)
            $display("TX_SCOPE_DEBUG_OUTPUTS_REGRESSION_PASS");
        else
            $display("TX_SCOPE_DEBUG_OUTPUTS_REGRESSION_FAIL errors=%0d",
                     errors);
        $finish;
    end
endmodule
