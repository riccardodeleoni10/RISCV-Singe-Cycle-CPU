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
type data_mem_t is array (0 to DATA_MEM_DEPTH-1)  of std_logic_vector(31 downto 0);


signal reg_file : reg_t := (others => (others => '0'));
signal PC_s       : std_logic_vector(31 downto 0) := (others => '0');

----------------------------------------------------------------------------
-- Fibonacci Test Program (RV32I, offset di memoria multipli di 4)
----------------------------------------------------------------------------
signal instr_memory : istr_mem_t := (
    0  => x"00002083",   -- lw  x1,  0(x0)        ; x1 <- F(0) = 0
    1  => x"00402103",   -- lw  x2,  4(x0)        ; x2 <- F(1) = 1
    2  => x"00802183",   -- lw  x3,  8(x0)        ; x3 <- N
    3  => x"00C02203",   -- lw  x4, 12(x0)        ; x4 <- 1
    4  => x"00018C63",   -- beq x3, x0, done      ; se counter==0 -> done
    5  => x"002082B3",   -- add x5, x1, x2        ; x5 = x1 + x2
    6  => x"000160B3",   -- or  x1, x2, x0        ; x1 = x2
    7  => x"0002E133",   -- or  x2, x5, x0        ; x2 = x5
    8  => x"404181B3",   -- sub x3, x3, x4        ; x3 -= 1
    9  => x"FE0006E3",   -- beq x0, x0, loop      ; jump back
    10 => x"00102823",   -- sw  x1, 16(x0)        ; M[16] <- F(N)
    11 => x"00500f93",   -- addi x31 x0 5         ; x31 = x0 + x5
    12 => x"00000063",   -- beq x0, x0, halt      ; halt infinito
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
signal read_data1_s      : std_logic_vector(31 downto 0);
signal read_data2_s    : std_logic_vector(31 downto 0);
signal WB_data_s       : std_logic_vector(31 downto 0); -- Dato da scrivere nel Register File
signal ALU_result      : std_logic_vector(31 downto 0); -- Agisce anche da indirizzo di memoria dati
signal mem_read_data_s : std_logic_vector(31 downto 0); -- Dato letto dalla Data Memory
signal ALUsrc_out_s    : std_logic_vector(31 downto 0); -- Uscita dal mux gestito da ALUsrc_s
signal from_ImmGen     : std_logic_vector(31 downto 0); -- Uscita del generatore di Immediate
signal Zero_s          : std_logic;					  -- Flag di uscita dall'ALU
signal PC_next_s	   : std_logic_vector(31 downto 0); -- Prossimo program counter
signal PC_p4_s		   : std_logic_vector(31 downto 0); -- Program counter incrementato di 4, vedi anche logica di brench dell'architettura
signal PC_target_s     : std_logic_vector(31 downto 0); -- Program counter da calcolare per la brench e le jump
signal PC_src_s	       : std_logic;				      -- Mux per la logica del program counter
----------------------------------------------------------------------------
-- OPC_sodes
----------------------------------------------------------------------------
constant OP_IRRI     : std_logic_vector(6 downto 0) := "0110011";
constant OP_STORE    : std_logic_vector(6 downto 0) := "0100011";
constant OP_LOAD     : std_logic_vector(6 downto 0) := "0000011"; 
constant OP_BRANCH   : std_logic_vector(6 downto 0) := "1100011";
constant OP_IMM      : std_logic_vector(6 downto 0) := "0010011";
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
signal ALUOp_s     : std_logic_vector(1 downto 0);
signal ALU_ctrl_s  : std_logic_vector(3 downto 0);
							
begin
--------------------------------------------------------------------------------
-- ASSEGNAZIONE DELLE USCITE
--------------------------------------------------------------------------------

instr_obs <= instruction;
pc_obs    <= PC_s;
--------------------------------------------------------------------------------
-- LETTURA COMBINATORIA DELLE MEMORIE
--------------------------------------------------------------------------------
--  . LETTURA DELLA INSTRUCTION MEMORY
    instruction <= instr_memory(to_integer(unsigned(PC_s(31 downto 2))));

--  . LETTURA COMBINATORIA DELLA DATA MEMORY
    mem_read_data_s <= data_memory(to_integer(unsigned(ALU_result(31 downto 2)))) when MemRead_s = '1' else (others => '0');
    
--  . LETTURA COMBINATORIA DEL REGISTER FILE
    read_data1_s <= (others => '0') when rs1 = "00000" else reg_file(to_integer(unsigned(rs1)));
    read_data2_s <= (others => '0') when rs2 = "00000" else reg_file(to_integer(unsigned(rs2)));
    PC_p4_s <= std_logic_vector(unsigned(PC_s) + to_unsigned(4, 32));
--------------------------------------------------------------------------------
-- ASSEGNAZIONE DEI MUX
--------------------------------------------------------------------------------
--  . MUX PER IL 2° OPERANDO DELL'ALU
    ALUsrc_out_s <= from_ImmGen when ALUsrc_s = '1' else read_data2_s;
    Zero_s  <= '1' when ALU_result = x"00000000" else '0';
                                  -- Zero_s proveniente dall'ALU
--  . LOGICA PER IL NEXT PROGRAM COUNTER
    PC_target_s <= std_logic_vector(signed(PC_s)+signed(from_ImmGen));                  -- Program counter calcolato con l'immediata
    PC_src_s    <= Zero_s and Branch_s;                                                 -- Selettore per Mux per il next program counter
    PC_next_s   <= PC_target_s when PC_src_s = '1' else PC_p4_s;                        -- Mux per il next program counter
    
--  . LOGICA DI WRITEBACK NEL REGISTER FILE
    WB_data_s <= mem_read_data_s when MemtoReg_s = '1' else ALU_result; 

--------------------------------------------------------------------------------
-- PROCESSO COMBINATORIO PER IL CALCOLO DEI SEGNALI
--------------------------------------------------------------------------------
comb_proc: process(all)
begin
    MemtoReg_s  <= '0';
    RegWrite_s  <= '0';
    MemRead_s   <= '0';
    MemWrite_s  <= '0';
    Branch_s    <= '0';
    ALUOp_s     <= "00";
    ALU_ctrl_s  <= "0000";
    ALUsrc_s    <= '0';
    ALU_result  <= (others => '0');
    from_ImmGen <= (others => '0');
    
    --1. DECODE DELL'ISTRUZIONE
    case OPCODE is 
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
        when others    => NULL;
    end case;

    --2. CALCOLO DELL'IMMEDIATO
    case OPCODE is 
        when OP_LOAD   => from_ImmGen(11 downto 0)  <= instruction(31 downto 20);
                          from_ImmGen(31 downto 12) <= (others => instruction(31));
       
        when OP_STORE  => from_ImmGen(11 downto 5)  <= instruction(31 downto 25);
                          from_ImmGen(4 downto 0)   <= instruction(11 downto 7);
                          from_ImmGen(31 downto 12) <= (others => instruction(31));
    
        when OP_BRANCH => from_ImmGen(11)           <= instruction(7);
                          from_ImmGen(0)            <= '0';
                          from_ImmGen(10 downto 5)  <= instruction(30 downto 25);
                          from_ImmGen(4 downto 1)   <= instruction(11 downto 8);
                          from_ImmGen(31 downto 12) <= (others=>instruction(31));
        
        when others    => from_ImmGen <= (others => '0');
    end case;

    
    --3. LOGICA DI DECODING DELL'ALU
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

    --4. ALU
    case ALU_ctrl_s is 
        when "0000" => 
            -- AND logico
            ALU_result <= read_data1_s and ALUSrc_out_s;
            
        when "0001" => 
            -- OR logico
            ALU_result <= read_data1_s or ALUSrc_out_s;
            
        when "0010" => 
            -- ADD 
            ALU_result <= std_logic_vector(signed(read_data1_s) + signed(ALUSrc_out_s));
            
        when "0110" => 
            -- SUB 
            ALU_result <= std_logic_vector(signed(read_data1_s) - signed(ALUSrc_out_s));
            
        when others => 
            ALU_result <= (others => '0');
    end case;
    
    
end process comb_proc;


--------------------------------------------------------------------------------
-- PROCESSO SEQUENZIALE PER L'ASSEGNAZIONE DEI SEGNALI
--------------------------------------------------------------------------------

seq_proc : process(clk)
begin
    if (rising_edge(clk)) then
        if reset = '1' then
            reg_file <=(others => (others => '0'));
            PC_s       <=(others => '0');
        else
        -- 1. AGGIORNAMENTO DEL PC
            PC_s <= PC_next_s; 

        -- 2. SCRITTURA NEL REGISTER FILE
            if RegWrite_s = '1' and rd /= "00000" then
                reg_file(to_integer(unsigned(rd))) <= WB_data_s;
            end if;

        -- 3. SCRITTURA IN DATA MEMORY
            if MemWrite_s = '1' then
                data_memory(to_integer(unsigned(ALU_result(31 downto 2)))) <= read_data2_s;   -- Salto gli ultimi due bit dato che scrivo a multipli di 4
            end if;
        end if; 
    end if;
end process;
end Behavioral;
