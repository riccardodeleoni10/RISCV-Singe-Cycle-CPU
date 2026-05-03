--------------------------------------------------------------------------------
-- Title       : Risc-V Single Cycle CPU
-- Project     : 
--------------------------------------------------------------------------------
-- File        : riscv_sc_cpu.vhd
-- Author      : Riccardo De Leoni
-- Company     : User Company Name
-- Created     : Sun May  3 10:13:12 2026
-- Last update : Sun May  3 19:00:14 2026
-- Platform    : Default Part Number
-- Standard    : VHDL-2008 
--------------------------------------------------------------------------------
-- Copyright (c) 2026 User Company Name
-------------------------------------------------------------------------------
-- Description: 
--------------------------------------------------------------------------------
-- Revisions:  Revisions and documentation are controlled by
-- the revision control system (RCS).  The RCS should be consulted
-- on revision history.
-------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL; 
entity riscv_sc_cpu is
generic (
    INSTR_MEM_DEPTH : integer := 1024;
    DATA_MEM_DEPTH  : integer := 1024
);
Port ( 
    clk             : in std_logic;
    reset           : in std_logic;
    -- observability signals
    instr_obs       : out std_logic_vector(31 downto 0);
    pc_obs          : out std_logic_vector(31 downto 0)
);
end riscv_sc_cpu;

architecture Behavioral of riscv_sc_cpu is

type reg_t      is array (0 to 31) of std_logic_vector(31 downto 0);
type istr_mem_t is array (0 to INSTR_MEM_DEPTH-1) of std_logic_vector(31 downto 0);
type data_mem_t is array (0 to DATA_MEM_DEPTH-1) of std_logic_vector(31 downto 0);


signal reg_file : reg_t := (others => (others => '0'));
signal PC       : std_logic_vector(31 downto 0) := (others => '0');

----------------------------------------------------------------------------
-- Fibonacci Test Program (RV32I, offset di memoria multipli di 4)
----------------------------------------------------------------------------
--signal instr_memory : istr_mem_t := (
  --  0  => x"00002083",   -- lw  x1,  0(x0)        ; x1 <- F(0) = 0
    --1  => x"00402103",   -- lw  x2,  4(x0)        ; x2 <- F(1) = 1
    --2  => x"00802183",   -- lw  x3,  8(x0)        ; x3 <- N
    --3  => x"00C02203",   -- lw  x4, 12(x0)        ; x4 <- 1
    --4  => x"00018C63",   -- beq x3, x0, done      ; se counter==0 -> done
    --5  => x"002082B3",   -- add x5, x1, x2        ; x5 = x1 + x2
    --6  => x"000160B3",   -- or  x1, x2, x0        ; x1 = x2
    --7  => x"0002E133",   -- or  x2, x5, x0        ; x2 = x5
    --8  => x"404181B3",   -- sub x3, x3, x4        ; x3 -= 1
    --9  => x"FE0006E3",   -- beq x0, x0, loop      ; jump back
    --10 => x"00102823",   -- sw  x1, 16(x0)        ; M[16] <- F(N)
    --11 => x"00500f93",   -- addi x31 x0 5         ; x31 = x0 + x5
    --12 => x"00000063",   -- beq x0, x0, halt      ; halt infinito
    --others => x"00000000"
--);
--------------------------------------------------------------------------------
-- TEST ROM PER LA JAL
--------------------------------------------------------------------------------
signal instr_memory : istr_mem_t := (
    -- 1. TEST ALU (R-Type e I-Type)
    0  => x"00F00093",   -- [PC=0]  addi x1, x0, 15   ; x1 = 15
    1  => x"00A00113",   -- [PC=4]  addi x2, x0, 10   ; x2 = 10
    2  => x"002081B3",   -- [PC=8]  add  x3, x1, x2   ; x3 = 25 (0x19)
    3  => x"40208233",   -- [PC=12] sub  x4, x1, x2   ; x4 = 5  (0x05)
    4  => x"0020F2B3",   -- [PC=16] and  x5, x1, x2   ; x5 = 10 (0x0A)
    5  => x"0020E333",   -- [PC=20] or   x6, x1, x2   ; x6 = 15 (0x0F)

    -- 2. TEST MEMORY (Load e Store)
    6  => x"00302223",   -- [PC=24] sw   x3, 4(x0)    ; Salva 25 in Memoria Dati[4]
    7  => x"00402383",   -- [PC=28] lw   x7, 4(x0)    ; x7 legge 25 dalla memoria

    -- 3. TEST BRANCHING
    8  => x"00208463",   -- [PC=32] beq  x1, x2, 8    ; 15 == 10? FALSO. Non salta.
    9  => x"00608463",   -- [PC=36] beq  x1, x6, 8    ; 15 == 15? VERO! Salta di 8 byte (2 instr)
    10 => x"3E700413",   -- [PC=40] addi x8, x0, 999  ; DEVE ESSERE SALTATA (x8 resterà 0)

    -- 4. TEST JAL e JALR
    11 => x"00C004EF",   -- [PC=44] jal  x9, 12       ; Salta a PC=56. Salva PC+4 (48) in x9
    12 => x"02A00513",   -- [PC=48] addi x10, x0, 42  ; <--- PUNTO DI RITORNO DALLA JALR
    13 => x"00000863",   -- [PC=52] beq  x0, x0, 16   ; Salta a PC=68 (Halt) per finire il programma
    14 => x"04D00593",   -- [PC=56] addi x11, x0, 77  ; <--- TARGET DELLA JAL (x11 = 77)
    15 => x"00048667",   -- [PC=60] jalr x12, 0(x9)   ; Torna all'indirizzo in x9 (48). Salva 64 in x12
    16 => x"00100693",   -- [PC=64] addi x13, x0, 1   ; DEVE ESSERE SALTATA (x13 resterà 0)
    
    -- 5. HALT
    17 => x"00000063",   -- [PC=68] beq  x0, x0, 0    ; Halt infinito
    
    others => x"00000000"
);
signal data_memory : data_mem_t := (
    0      => x"00000000",   -- F(0)        = 0errors
    1      => x"00000001",   -- F(1)        = 1
    2      => x"0000000A",   -- N           = 14
    3      => x"00000001",   -- decremento  = 1
    others => x"00000000"    -- slot 4 riceve il risultato F(N)
);

----------------------------------------------------------------------------
-- Campi dell'istruzione
----------------------------------------------------------------------------
signal instruction : std_logic_vector(31 downto 0);
alias  opcode      : std_logic_vector(6 downto 0) is instruction(6 downto 0);
alias  rd          : std_logic_vector(4 downto 0) is instruction(11 downto 7);
alias  funct3      : std_logic_vector(2 downto 0) is instruction(14 downto 12);
alias  rs1         : std_logic_vector(4 downto 0) is instruction(19 downto 15);
alias  rs2         : std_logic_vector(4 downto 0) is instruction(24 downto 20);
alias  funct7_b5   : std_logic                    is instruction(30);

----------------------------------------------------------------------------
-- Segnali aggiuntivi per il Datapath
----------------------------------------------------------------------------
signal read_data1    : std_logic_vector(31 downto 0);
signal read_data2    : std_logic_vector(31 downto 0);
signal write_data    : std_logic_vector(31 downto 0); -- Dato da scrivere nel Register File
signal ALU_result    : std_logic_vector(31 downto 0); -- Agisce anche da indirizzo di memoria dati
signal mem_read_data : std_logic_vector(31 downto 0); -- Dato letto dalla Data Memory
signal ALUsrc_out_s  : std_logic_vector(31 downto 0); -- Uscita dal mux gestito da ALUsrc_s
signal from_ImmGen   : std_logic_vector(31 downto 0); -- Uscita del generatore di Immediate
signal Zero_s        : std_logic;					  -- Flag di uscita dall'ALU
signal PC_next		 : std_logic_vector(31 downto 0); -- Prossimo program counter
signal PC_p4		 : std_logic_vector(31 downto 0); -- Program counter incrementato di 4, vedi anche logica di brench dell'architettura
signal PC_target     : std_logic_vector(31 downto 0); -- Program counter da calcolare per la brench e le jump
signal PCsrc_s	     : std_logic;				      -- Mux per la logica del program counter
signal PC_ret        : std_logic_vector(31 downto 0); -- Segnale di appoggio per la JALR, gli viene assegnato ALU_result, x il Debug
----------------------------------------------------------------------------
-- OPCodes
----------------------------------------------------------------------------
constant OP_IRRI  : std_logic_vector(6 downto 0) := "0110011";
constant OP_STORE : std_logic_vector(6 downto 0) := "0100011";
constant OP_LOAD  : std_logic_vector(6 downto 0) := "0000011"; 
constant OP_BRANCH: std_logic_vector(6 downto 0) := "1100011";
constant OP_IMM   : std_logic_vector(6 downto 0) := "0010011";
constant OP_JAL   : std_logic_vector(6 downto 0) := "1101111";
constant OP_JALR  : std_logic_vector(6 downto 0) := "1100111";
----------------------------------------------------------------------------
-- funct3 & funct7
----------------------------------------------------------------------------
constant F3_ADD    : std_logic_vector(2 downto 0) := "000";
constant F3_SUB    : std_logic_vector(2 downto 0) := "000";
constant F3_AND    : std_logic_vector(2 downto 0) := "111";
constant F3_OR     : std_logic_vector(2 downto 0) := "110";
constant F7_b5_SUB : std_logic :='1';

----------------------------------------------------------------------------
-- Segnali di controllo
----------------------------------------------------------------------------
signal ALUsrc_s    : std_logic;
signal MemtoReg_s  : std_logic;
signal RegWrite_s  : std_logic;
signal MemRead_s   : std_logic;
signal MemWrite_s  : std_logic;
signal Branch_s    : std_logic;
signal Jal_s       : std_logic;
signal JalR_s      : std_logic;
signal ALUOp_s     : std_logic_vector(1 downto 0);
signal ALU_ctrl_s  : std_logic_vector(3 downto 0);
							
begin

-- Assegnazione segnali di osservabilità
instr_obs <= instruction;
pc_obs    <= PC;

----------------------------------------------------------------------------
-- 1. INSTRUCTION MEMORY 
----------------------------------------------------------------------------
instruction <= instr_memory(to_integer(unsigned(PC(31 downto 2))));
----------------------------------------------------------------------------
-- 2. REGISTER FILE
----------------------------------------------------------------------------

read_data1 <= (others => '0') when rs1 = "00000" else reg_file(to_integer(unsigned(rs1)));
read_data2 <= (others => '0') when rs2 = "00000" else reg_file(to_integer(unsigned(rs2)));

process(clk)
begin
    if rising_edge(clk) then
        if reset = '1' then
        elsif RegWrite_s = '1' and rd /= "00000" then 
            reg_file(to_integer(unsigned(rd))) <= write_data;
        end if;
    end if;
end process;

----------------------------------------------------------------------------
-- 3. DATA MEMORY
----------------------------------------------------------------------------
-- Lettura Combinatoria
mem_read_data <= data_memory(to_integer(unsigned(ALU_result(31 downto 2)))) when MemRead_s = '1' else (others => '0');

-- Scrittura Sincrona
process(clk)
begin
    if rising_edge(clk) then
        if MemWrite_s = '1' then
            data_memory(to_integer(unsigned(ALU_result(31 downto 2)))) <= read_data2;
        end if;
    end if;
end process;

----------------------------------------------------------------------------
-- 4. CONTROL UNIT
----------------------------------------------------------------------------
control_unit_process: process(opcode)
begin
    ALUsrc_s    <= '0';
    MemtoReg_s  <= '0';
    RegWrite_s  <= '0';
    MemRead_s   <= '0';
    MemWrite_s  <= '0';
    Branch_s    <= '0';
    Jal_s       <= '0';
    ALUOp_s     <= "00";

    case opcode is 
        when OP_IRRI   => ALUsrc_s    <= '0';
                          MemtoReg_s  <= '0';
                          RegWrite_s  <= '1';
                          ALUOp_s     <= "10";

        when OP_LOAD   => ALUsrc_s    <= '1';
                          MemtoReg_s  <= '1';
                          RegWrite_s  <= '1';
                          MemRead_s   <= '1';
                          ALUOp_s     <= "00";

        when OP_STORE  => ALUsrc_s    <= '1';
                          MemWrite_s  <= '1';
                          ALUOp_s     <= "00";

        when OP_BRANCH => Branch_s    <= '1';
                          ALUOp_s     <= "01";
        
        when OP_IMM    => ALUsrc_s    <= '1';
                          MemtoReg_s  <= '0';
                          RegWrite_s  <= '1';  
                          ALUOp_s     <= "11"; 
        
        when OP_JAL    => ALUsrc_s    <= '0';       -- in realtà questo è don't care
                          MemtoReg_s  <= '0';
                          RegWrite_s  <= '1'; 
                          ALUOp_s     <= "00";      -- Pure questo
                          Jal_s       <= '1';
        
        when OP_JALR   => ALUsrc_s    <= '1';
                          MemtoReg_s  <= '0';
                          RegWrite_s  <= '1';
                          ALUOp_s     <= "00";
                          Jal_s       <= '1';       -- Questo lo uso per pilotare il mux del Writeback
                          JalR_s      <= '1';       -- Questo il mux per PC_next       
        
        when others    => NULL;
    end case;
end process;

-----------------------------------------------------------------------------
-- 5. ASSEGNAZIONE DEI MUX NEL DATAPATH
-----------------------------------------------------------------------------
PCsrc_s      <= Branch_s and Zero_s;									    -- Mux per program counter;
ALUSrc_out_s <= read_data2 when ALUsrc_s = '0' else from_ImmGen;			-- Assegnazione del mux per 2° ingresso dell'ALU

-- mux per Writeback nel register file
result_mux_process: process(ALU_result,mem_read_data,PC_p4,MemtoReg_s,Jal_s)
variable sel : std_logic_vector(1 downto 0);
begin
    sel := (Jal_s,MemtoReg_s);
    case sel is 
        when "00"   => write_data <= ALU_result;      -- IMM | IRRI

        when "01"   => write_data <= mem_read_data;   -- LOAD

        when others => write_data <= PC_p4;           -- JAL | JALR
    end case;
end process;
----------------------------------------------------------------------------
-- 6. ALU CONTROL UNIT
----------------------------------------------------------------------------
ALU_control_unit_process: process(ALUOp_s, funct3, funct7_b5)
begin
    ALU_ctrl_s <= "0000";
    case ALUOp_s is 
        when "00" => ALU_ctrl_s <= "0010";
       
        when "01" => ALU_ctrl_s <= "0110";
       
        when "10" => 
            case funct3 is 
                when F3_ADD  => 
                    if funct7_b5 = '1' then 
                        ALU_ctrl_s <= "0110";
                    else 
                        ALU_ctrl_s <= "0010";
                    end if; 
                
                when F3_AND     => ALU_ctrl_s <= "0000";
                
                when F3_OR      => ALU_ctrl_s <= "0001";
                
                when others     => NULL;
            end case;
        when "11" =>
            case funct3 is
                when F3_ADD     => ALU_ctrl_s <= "0010";
                    
                when F3_AND     => ALU_ctrl_s <= "0000";
                
                when F3_OR      => ALU_ctrl_s <= "0001";

                when others     => NULL;
            end case;
        when others => NULL;
    end case;
end process;
----------------------------------------------------------------------------
-- 7. ALU 
----------------------------------------------------------------------------
alu_process: process(read_data1, ALUSrc_out_s, ALU_ctrl_s)
begin
    ALU_result <= (others => '0');

    case ALU_ctrl_s is 
        when "0000" => 
            -- AND logico
            ALU_result <= read_data1 and ALUSrc_out_s;
            
        when "0001" => 
            -- OR logico
            ALU_result <= read_data1 or ALUSrc_out_s;
            
        when "0010" => 
            -- ADD 
            ALU_result <= std_logic_vector(signed(read_data1) + signed(ALUSrc_out_s));
            
        when "0110" => 
            -- SUB 
            ALU_result <= std_logic_vector(signed(read_data1) - signed(ALUSrc_out_s));
            
        when others => 
            ALU_result <= (others => '0');
    end case;
end process;
Zero_s  <= '1' when ALU_result = x"00000000" else '0';
----------------------------------------------------------------------------
-- 8. PC 
----------------------------------------------------------------------------
pc_process:process(clk)
begin
	if rising_edge(clk) then 
		if reset = '1' then
			PC <= (others => '0');
		else 
			PC <= PC_next;
		end if;
	end if;
end process;
PC_p4     <= std_logic_vector(unsigned(PC) + to_unsigned(4, 32));

--PC_next   <= PC_target when (PCsrc_s = '1' or Jal_s = '1') else PC_p4;
PC_next_process: process(PC_p4,PC_target,PC_ret,Jal_s,JalR_s,PCsrc_s)
begin
    if PCsrc_s = '1' then 
        PC_next <= PC_target;
    elsif (Jal_s = '1') then
        if (JalR_s = '1') then
            PC_next <= PC_ret;
        else 
            PC_next <= PC_target;
        end if;
    else 
        PC_next <= PC_p4;
    end if;
end process;
-----------------------------------------------------------------------------
-- 9. BRENCH | JAL | JALR LOGIC
-----------------------------------------------------------------------------
PC_target <= std_logic_vector(signed(PC)+signed(from_ImmGen));
PC_ret    <= (ALU_result(31 downto 1) & '0');
-- MA QUINDI BISOGNA SHIFTARE ???
-----------------------------------------------------------------------------
-- 10. IMMEDIATE GENERATE
-----------------------------------------------------------------------------
imm_gen_process: process(instruction, opcode)
begin
    from_ImmGen <= (others => '0');
    case opcode is 
        when OP_LOAD | OP_IMM | OP_JALR  => from_ImmGen(11 downto 0)  <= instruction(31 downto 20);
            			                    from_ImmGen(31 downto 12) <= (others => instruction(31));
       
        when OP_STORE           => from_ImmGen(11 downto 5)  <= instruction(31 downto 25);
        			               from_ImmGen(4 downto 0)   <= instruction(11 downto 7);
        			               from_ImmGen(31 downto 12) <= (others => instruction(31));
            
        when OP_BRANCH          => from_ImmGen(11)           <= instruction(7);
                                   from_ImmGen(0)            <= '0';
                                   from_ImmGen(10 downto 5)  <= instruction(30 downto 25);
                                   from_ImmGen(4 downto 1)   <= instruction(11 downto 8);
                                   from_ImmGen(31 downto 12) <= (others=>instruction(31));

        when OP_JAL             => from_ImmGen(0)            <= '0';
                                   from_ImmGen(19 downto 12) <= instruction(19 downto 12);
                                   from_ImmGen(11)           <= instruction(20);
                                   from_ImmGen(10 downto 1)  <= instruction(30 downto 21);
                                   from_ImmGen(31 downto 20) <= (others => instruction(31));
        
        when others             => from_ImmGen <= (others => '0');
            
    end case;
end process;

end Behavioral;
