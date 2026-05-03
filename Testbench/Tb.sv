`timescale 1ns / 1ps

module tb_riscv_sc_cpu();

// Segnali di test
logic clk;
logic reset;
logic [31:0] instr_obs;
logic [31:0] pc_obs;

// Variabili di conteggio
integer i;
int cycle_count = 0;


riscv_sc_cpu dut (
    .clk(clk),
    .reset(reset),
    .instr_obs(instr_obs),
    .pc_obs(pc_obs)
); 


initial begin
    clk = 0;
    forever #5 clk = ~clk;
end


always @(posedge clk) begin
    if (!reset) begin
        cycle_count++;
    end
end


initial begin
    $monitor("Tempo: %0t ns | Ciclo: %0d | PC: %0d (0x%0h) | Instr: 0x%08h", 
             $time, cycle_count, pc_obs, pc_obs, instr_obs);
end


initial begin
    $display("==================================================");
    $display(" INIZIO SIMULAZIONE CPU RISC-V");
    $display("==================================================");
    
    
    reset = 1;
    #50;  
    
    reset = 0; 
    $display("--> Reset rilasciato. Inizio esecuzione istruzioni...");
    
        begin
            wait(cycle_count == 100);
            $display("\n[TIMEOUT] - Terminazione forzata dopo 100 cicli di clock.");
        end
    //        forever begin
     //           @(posedge clk);
                // Controllo se il PC è 44 in decimale (0x2C in esadecimale) 
                // per due cicli di fila.
       //         if (pc_obs == 32'd1024) begin
         //           $display("\n[SUCCESSO] - Rilevato stato di HALT all'indirizzo PC = 44.");
        //            break; // Esco dal loop forever
        //        end
         //   end
        //end
    //join_any
    //disable fork; // Disabilita l'altro thread in background

    $display("==================================================");
    $display(" SIMULAZIONE COMPLETATA                           ");
    $display("==================================================");
    $display("Apri la finestra delle Waveform (GTKWave/Vivado) ");
    $display("per verificare che il risultato F(10) sia stato ");
    $display("correttamente salvato all'indirizzo 16 della Memoria Dati.");
    
    $finish;
end

endmodule
