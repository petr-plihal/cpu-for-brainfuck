-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2023 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Petr Plíhal <xpliha02 AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic;                      -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'

   -- stavove signaly
   READY    : out std_logic;                      -- hodnota 1 znamena, ze byl procesor inicializovan a zacina vykonavat program
   DONE     : out std_logic                       -- hodnota 1 znamena, ze procesor ukoncil vykonavani programu (narazil na instrukci halt)
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is
-- CNT
  signal CNT_INC : std_logic;
  signal CNT_DEC : std_logic;
  signal CNT_RESET     : std_logic;
  signal CNT_REGISTER  : std_logic_vector(12 downto 0);

-- COMPARATOR_CNT
  signal COMPARATOR_CNT_IS_ZERO : std_logic;

-- PTR
  signal PTR_INC : std_logic;
  signal PTR_DEC : std_logic;
  signal PTR_RESET     : std_logic;
  signal PTR_REGISTER  : std_logic_vector(12 downto 0);

-- PC
  signal PC_INC : std_logic;
  signal PC_DEC : std_logic;
  signal PC_RESET     : std_logic;
  signal PC_REGISTER  : std_logic_vector(12 downto 0);

-- MX1
  signal MX1_SELECT : std_logic;

-- MX2
  signal MX2_SELECT : std_logic_vector (1 downto 0);

-- DECODER
  type instruction_type is 
  (

    not_a_instruction,--pouze pro přehlednost v debuggingu

    inc_cell,
    dec_cell,
    inc_pointer,
    dec_pointer,
    print_cell,
    get_char,

    while_start,
    ptr_is_zero,

    while_end,
    break,
    end_of_program
  );
  signal DEC_OUT : instruction_type;


-- FSM
  type FSM_STATE is 
  ( -- Stavy pro inicializaci
    START, ENABLE_DATA, CHECK_FOR_RETURN, INIT_PTR_INC, RETURN_FOUND, INIT_DONE,
    -- Stavy pro načtení načtení instrukce
    FETCH, DECODE, SET_NEXT_COM,

    -- +
    CELL_INC_READ, CELL_INC_WAIT, CELL_INC,
    -- -
    CELL_DEC_READ, CELL_DEC_WAIT, CELL_DEC,
    
    -- >
    PTR_INC_READ,

    -- <
    PTR_DEC_READ,

    -- .
    PRINT_READ, PRINT_OUT_READY,

    -- ,
    GET_CHAR_READ, GET_CHAR_WRITE,

    -- [
    WHILE_START_READ,
    WHILE_START_CMP,
    WHILE_START_PC_WAIT,
    WHILE_START_INC,
    WHILE_CMP_END,

    -- ]
    WHILE_END_READ,
    WHILE_END_CMP,
    WHILE_END_PC_WAIT,
    WHILE_END_DEC,
    WHILE_CMP_START,
    WHILE_SET_TO_START,

    -- ~
    RETURN_READ,
    RETURN_LD_NEXT,
    RETURN_CMP,

    -- @
    END_OF_PROGRAM
  );
                                  -- Výchozí stav
  signal soucasny_stav    : FSM_STATE := START ;
  signal nasledujici_stav : FSM_STATE := START ;

begin

 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --      - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
 --      - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly. 


  -- -----------------CNT------------------
  -- Popis: Počítá vnoření cyklů
    CNT: process(CLK, RESET, CNT_RESET)
    begin

      -- Asynchronní reset
      if (RESET = '1') then
        CNT_REGISTER <= ( others => '0' );

      elsif ( CLK'event ) and ( CLK = '1' ) then
        -- Inkrementace
        if ( CNT_INC = '1' ) then
          CNT_REGISTER <= CNT_REGISTER + 1;
        -- Dekrementace
        elsif ( CNT_DEC = '1' ) then
          CNT_REGISTER <= CNT_REGISTER - 1;
        elsif ( CNT_RESET = '1' ) then
          CNT_REGISTER <= ( others => '0' );
        end if;

      end if;

    end process CNT;

  -- -----------COMPARATOR_CNT-------------
  -- Popis: Porovnává hodnotu registru CNT na nulu
    COMPARATOR_CNT: process(CNT_REGISTER)
    begin
      if ( CNT_REGISTER = 0 ) then
        COMPARATOR_CNT_IS_ZERO <= '1';
      else
        COMPARATOR_CNT_IS_ZERO <= '0';
      end if;
    end process COMPARATOR_CNT;

  -- --------------------------------------
  -- -----------------PTR------------------
  -- Popis: Udržuje ukazatel na aktuální pozici v paměti RAM(?)
    PTR: process(CLK, RESET)
    begin

      -- Asynchronní reset
      if (RESET = '1') then
        PTR_REGISTER <= ( others => '0' );

      elsif ( CLK'event ) and ( CLK = '1' ) then
        -- Inkrementace
        if ( PTR_INC = '1' ) then
          PTR_REGISTER <= (PTR_REGISTER + 1);
        -- Dekrementace
        elsif ( PTR_DEC = '1' ) then
          PTR_REGISTER <= (PTR_REGISTER - 1);
        elsif ( PTR_RESET = '1' ) then
          PTR_REGISTER <= ( others => '0' );
        end if;

      end if;

    end process PTR;

  -- --------------------------------------
  -- ------------------PC------------------
  -- Popis: Ukazatel na aktuální(další?) instrukci
    PC: process(CLK, RESET)
    begin

      -- Asynchronní reset
      if (RESET = '1') then
        PC_REGISTER <= ( others => '0' );

      elsif ( CLK'event ) and ( CLK = '1' ) then
        -- Inkrementace
        if ( PC_INC = '1' ) then
          PC_REGISTER <= PC_REGISTER + 1;
        -- Dekrementace
        elsif ( PC_DEC = '1' ) then
          PC_REGISTER <= PC_REGISTER - 1;
        elsif ( PC_RESET = '1' ) then
          PC_REGISTER <= ( others => '0' );
        end if;

      end if;

    end process PC;

  -- --------------------------------------
  -- -----------------MX1------------------
  -- Popis: Multiplexor pro určení, jestli se data čtou jako instrukce nebo jako data
    MX1: process(MX1_SELECT, PTR_REGISTER, PC_REGISTER)
    begin

      if MX1_SELECT = '0' then
        DATA_ADDR <= PTR_REGISTER;

      else
        DATA_ADDR <= PC_REGISTER;

      end if;

    end process MX1;

  -- --------------------------------------
  -- -----------------MX2------------------
  -- Popis: Multiplexor pro určení, která data se do paměti zapisují, jestli ze [vstupu/DATA_RDATA+1/-1]
    MX2: process(MX2_SELECT, IN_DATA)
    begin

      case MX2_SELECT is
        when "00" => DATA_WDATA <= IN_DATA;
        when "01" => DATA_WDATA <= DATA_RDATA - 1;
        when "10" => DATA_WDATA <= DATA_RDATA + 1;
        when others => null;
      end case;

    end process MX2;

  -- --------------------------------------
  -- ---------------DECODER----------------
  -- Popis: Dekóduje instrukce pro FSM ze vstupu DATA_RDATA
    DECODER: process(DATA_RDATA)
    begin

      case DATA_RDATA is
        when X"3E" => DEC_OUT <= inc_pointer;
        when X"3C" => DEC_OUT <= dec_pointer;
        when X"2B" => DEC_OUT <= inc_cell;
        when X"2D" => DEC_OUT <= dec_cell;
        when X"2E" => DEC_OUT <= print_cell;
        when X"2C" => DEC_OUT <= get_char;
        when X"5B" => DEC_OUT <= while_start;
        when X"5D" => DEC_OUT <= while_end;
        when X"7E" => DEC_OUT <= break;
        when X"40" => DEC_OUT <= end_of_program;

        when X"00" => DEC_OUT <= ptr_is_zero;

        when others => DEC_OUT <= not_a_instruction;
      end case;

    end process DECODER;

  -- ---PŘIPOJENÍ VÝSTUPU PAMĚTI K IO----
  OUT_DATA <= DATA_RDATA;
-- --------------------------------------
-- -----------------FSM------------------
-- Popis: Řídí komponenty procesoru, aby vykonávaly instrukce

  asynchroni_reset_a_nasledujici_stav: process ( RESET, CLK, EN )
  begin
      if ( RESET = '1' ) then
          soucasny_stav <= START;
      elsif ( CLK='1' and CLK'event ) then
        if ( EN = '1' ) then
          soucasny_stav <= nasledujici_stav;
        end if ;
      end if;
  end process;

-- PRAVIDLA PRO PŘECHODY MEZI STAVY
  nasledujici_stav_logic: process ( soucasny_stav, COMPARATOR_CNT_IS_ZERO, DEC_OUT, OUT_BUSY, IN_VLD, CLK, RESET, EN )
  begin
    case soucasny_stav is 
  -------------------------------Inicializace-------------------------------
      when START =>
        -- Kvůli asynchroni_reset_a_nasledujici_stav by tahle podmínka měla být zbytečná
        if ( RESET = '0' and EN = '1' ) then
          nasledujici_stav <= ENABLE_DATA;
        else
          nasledujici_stav <= START;
        end if;	
    --------------------------------------------------------------------------
      when ENABLE_DATA =>
        nasledujici_stav <= CHECK_FOR_RETURN;
    --------------------------------------------------------------------------
      when CHECK_FOR_RETURN =>
          if ( DEC_OUT = end_of_program ) then
            nasledujici_stav <= RETURN_FOUND;
          else
            nasledujici_stav <= INIT_PTR_INC;
          end if;
    --------------------------------------------------------------------------
      when INIT_PTR_INC =>
        nasledujici_stav <= ENABLE_DATA;
    --------------------------------------------------------------------------
      when RETURN_FOUND =>
        nasledujici_stav <= INIT_DONE;
    --------------------------------------------------------------------------
      when INIT_DONE =>
        nasledujici_stav <= FETCH;
  --------------------------------------------------------------------------
      when FETCH =>
        nasledujici_stav <= DECODE;
    --------------------------------------------------------------------------
      when DECODE =>
        case( DEC_OUT ) is

          when inc_cell =>
            nasledujici_stav <= CELL_INC_READ;

          when dec_cell =>
            nasledujici_stav <= CELL_DEC_READ;

          when inc_pointer =>
            nasledujici_stav <= PTR_INC_READ;

          when dec_pointer =>
            nasledujici_stav <= PTR_DEC_READ;

          when print_cell =>
            nasledujici_stav <= PRINT_READ;

          when get_char =>
            nasledujici_stav <= GET_CHAR_READ;


          when while_start =>
            nasledujici_stav <= WHILE_START_READ;

          when while_end =>
            nasledujici_stav <= WHILE_END_READ;

          when break =>
            nasledujici_stav <= RETURN_READ;


          when end_of_program =>
            nasledujici_stav <= END_OF_PROGRAM;

          when others =>-- šlo by i doplnit not_a_instruction
            nasledujici_stav <= SET_NEXT_COM;
        end case ;
    --------------------------------------------------------------------------
      when END_OF_PROGRAM =>
        nasledujici_stav <= END_OF_PROGRAM;
    --------------------------------------------------------------------------
      when SET_NEXT_COM =>
        nasledujici_stav <= FETCH;
  --------------------------------------------------------------------------
  ----------------------------------- + ------------------------------------
      when CELL_INC_READ =>
        nasledujici_stav <= CELL_INC_WAIT;
    --------------------------------------------------------------------------
      when CELL_INC_WAIT =>
        nasledujici_stav <= CELL_INC;
    --------------------------------------------------------------------------
      when CELL_INC =>
        nasledujici_stav <= SET_NEXT_COM;
  --------------------------------------------------------------------------
  ----------------------------------- - ------------------------------------
      when CELL_DEC_READ =>
        nasledujici_stav <= CELL_DEC_WAIT;
    --------------------------------------------------------------------------
      when CELL_DEC_WAIT =>
        nasledujici_stav <= CELL_DEC;
    --------------------------------------------------------------------------
      when CELL_DEC =>
        nasledujici_stav <= SET_NEXT_COM;
  --------------------------------------------------------------------------
  ----------------------------------- > ------------------------------------
      when PTR_INC_READ =>--TODO: loop around the momory
        nasledujici_stav <= SET_NEXT_COM;
  --------------------------------------------------------------------------
  ----------------------------------- < ------------------------------------
      when PTR_DEC_READ =>--TODO: loop around the momory
        nasledujici_stav <= SET_NEXT_COM;
  --------------------------------------------------------------------------
  ----------------------------------- . ------------------------------------
      when PRINT_READ =>
        if ( OUT_BUSY = '0' ) then
          nasledujici_stav <= PRINT_OUT_READY;
        else
          nasledujici_stav <= PRINT_READ;
        end if ;
    ------------------------------------------------------------------------
      when PRINT_OUT_READY =>
        nasledujici_stav <= SET_NEXT_COM;
  --------------------------------------------------------------------------
  ----------------------------------- , ------------------------------------
      when GET_CHAR_READ =>
        if ( IN_VLD = '1' ) then
          nasledujici_stav <= GET_CHAR_WRITE;
        else
          nasledujici_stav <= GET_CHAR_READ;
        end if ;
    ------------------------------------------------------------------------
      when GET_CHAR_WRITE =>
          nasledujici_stav <= SET_NEXT_COM;
  --------------------------------------------------------------------------
  ----------------------------------- [ ------------------------------------
      when WHILE_START_READ =>
          nasledujici_stav <= WHILE_START_CMP;
    ------------------------------------------------------------------------
      when WHILE_START_CMP =>
        if ( DEC_OUT = ptr_is_zero ) then
          nasledujici_stav <= WHILE_START_PC_WAIT;
        else
          nasledujici_stav <= SET_NEXT_COM;
        end if ;
    ------------------------------------------------------------------------
      when WHILE_START_PC_WAIT =>
          nasledujici_stav <= WHILE_START_INC;
    ------------------------------------------------------------------------
      when WHILE_START_INC =>
          nasledujici_stav <= WHILE_CMP_END;
    ------------------------------------------------------------------------
      when WHILE_CMP_END =>
          if ( DEC_OUT = while_end ) then
            nasledujici_stav <= SET_NEXT_COM;
          else
            nasledujici_stav <= WHILE_START_PC_WAIT;
          end if ;
  --------------------------------------------------------------------------
  ----------------------------------- ] ------------------------------------
      when WHILE_END_READ =>
        nasledujici_stav <= WHILE_END_CMP;
    ------------------------------------------------------------------------
      when WHILE_END_CMP =>
        if ( DEC_OUT = ptr_is_zero ) then
          nasledujici_stav <= SET_NEXT_COM;
        else
          nasledujici_stav <= WHILE_END_PC_WAIT;
        end if ;
    ------------------------------------------------------------------------
      when WHILE_END_PC_WAIT =>
        nasledujici_stav <= WHILE_END_DEC;
    ------------------------------------------------------------------------
      when WHILE_END_DEC =>
        nasledujici_stav <= WHILE_CMP_START;
    ------------------------------------------------------------------------
      when WHILE_CMP_START =>
        if ( DEC_OUT = while_start ) then
          nasledujici_stav <= WHILE_SET_TO_START;
        else
          nasledujici_stav <= WHILE_END_PC_WAIT;
        end if ;
    ------------------------------------------------------------------------
      when WHILE_SET_TO_START =>
        nasledujici_stav <= SET_NEXT_COM;
  --------------------------------------------------------------------------
  ----------------------------------- ~ ------------------------------------
      when RETURN_READ =>
        nasledujici_stav <= RETURN_LD_NEXT;
    ------------------------------------------------------------------------
      when RETURN_LD_NEXT =>
        nasledujici_stav <= RETURN_CMP;
    ------------------------------------------------------------------------
      when RETURN_CMP =>
        if ( DEC_OUT = while_end ) then
          nasledujici_stav <= SET_NEXT_COM;
        else
          nasledujici_stav <= RETURN_READ;
        end if ;

      when others => null;
    end case;
  end process;

-- VÝSTUPY STAVŮ
  vystupy_stavu: process( soucasny_stav )
  begin

    -- Defaultní hodnoty
      PC_RESET <= '0';
        PC_INC <= '0';
        PC_DEC <= '0';
      
      PTR_RESET <= '0';
        PTR_INC <= '0';
        PTR_DEC <= '0';

      CNT_RESET <= '0';
        CNT_INC <= '0';
        CNT_DEC <= '0';

      DONE <= '0';

      MX1_SELECT <= '0';
      MX2_SELECT <= "11";

      DATA_EN <= '0';
      DATA_RDWR <= '0';

      OUT_WE <= '0';

      IN_REQ <= '0';

    case soucasny_stav is 
    -------Inicializace-------
      when START =>
        PC_RESET <= '1';
    
        PTR_RESET <= '1';

        CNT_RESET <= '1';

        READY <= '0';
      -------------------------
      when ENABLE_DATA =>
        DATA_EN <= '1';

      when CHECK_FOR_RETURN =>

      when INIT_PTR_INC =>
        PTR_INC <= '1';

      when RETURN_FOUND =>
        PTR_INC <= '1';

      when INIT_DONE =>
        READY <= '1';
    ----Načtení instrukce-----
      when FETCH =>
        DATA_EN <= '1';
        MX1_SELECT <= '1';

      when DECODE =>
        -- žádné outputy

      when SET_NEXT_COM =>
        PC_INC <= '1';
    -------------------------
    ---------- + ------------
      when CELL_INC_READ =>
        DATA_EN <= '1';
      -------------------------
      when CELL_INC_WAIT =>
        -- Čeká na výsledek z paměti na adrese PTR
      -------------------------
      when CELL_INC =>
        DATA_EN <= '1';
        DATA_RDWR <= '1';
        MX2_SELECT <= "10";
    -------------------------
    ---------- - ------------
      when CELL_DEC_READ =>
        DATA_EN <= '1';
      -----------------------
      when CELL_DEC_WAIT =>
      -----------------------
      when CELL_DEC =>
        DATA_EN <= '1';
        DATA_RDWR <= '1';
        MX2_SELECT <= "01";
    -------------------------
    ---------- > ------------
      when PTR_INC_READ =>
        PTR_INC <= '1';
    -------------------------
    ---------- < ------------
      when PTR_DEC_READ =>
        PTR_DEC <= '1';
    -------------------------
    ---------- . ------------
      when PRINT_READ =>
        DATA_EN <= '1';
      -----------------------
      when PRINT_OUT_READY =>
        OUT_WE <= '1';
    -------------------------
    ---------- . ------------
      when GET_CHAR_READ =>
        IN_REQ <= '1';
      -----------------------
      when GET_CHAR_WRITE =>
        DATA_EN <= '1';
        DATA_RDWR <= '1';
        MX2_SELECT <= "00";
    -------------------------
    ---------- [ ------------
      when WHILE_START_READ =>
        DATA_EN <= '1';
      -----------------------
      when WHILE_START_CMP =>
        -- Čekalo se na validní data z adresy PTR, v tomto stavu se pouze rozhoduje o přechodu
      -----------------------
      when WHILE_START_PC_WAIT =>
        PC_INC <= '1';
      -----------------------
      when WHILE_START_INC =>
        DATA_EN <= '1';
        MX1_SELECT <= '1';
      -----------------------
      when WHILE_CMP_END =>
        -- Čekalo se na validní data z adresy PC, v tomto stavu se pouze rozhoduje o přechodu
    -------------------------
    ---------- ] ------------
      when WHILE_END_READ =>
        DATA_EN <= '1';
      -----------------------
      when WHILE_END_CMP =>
        -- Čekalo se na validní data z adresy PTR, v tomto stavu se pouze rozhoduje o přechodu
      -----------------------
      when WHILE_END_PC_WAIT =>
        PC_DEC <= '1';
      -----------------------
      when WHILE_END_DEC =>
        DATA_EN <= '1';
        MX1_SELECT <= '1';
      -----------------------
      when WHILE_CMP_START =>
        -- Čekalo se na validní data z adresy PC, v tomto stavu se pouze rozhoduje o přechodu
      -----------------------
      when WHILE_SET_TO_START =>
        PC_DEC <= '1';
    -------------------------
    ---------- ~ ------------
      when RETURN_READ =>
        PC_INC <= '1';
      -----------------------
      when RETURN_LD_NEXT =>
        DATA_EN <= '1';
        MX1_SELECT <= '1';
      -----------------------
      when RETURN_CMP =>
        -- Čekalo se na validní data z adresy PC, v tomto stavu se pouze rozhoduje o přechodu
    -------------------------
    ---------- @ ------------
      when END_OF_PROGRAM =>
        DONE <= '1';
    -------------------------
      when others => null;
    end case;
  end process;





end behavioral;

