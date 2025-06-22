library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cpu_tb is
end cpu_tb;


architecture sim of cpu_tb is
    -- Signály podle entity cpu
    signal clk        : std_logic := '0';
    signal reset      : std_logic := '1';
    signal en         : std_logic := '0';

    -- RAM signály
    signal data_addr  : std_logic_vector(12 downto 0);
    signal data_wdata : std_logic_vector(7 downto 0);
    signal data_rdata : std_logic_vector(7 downto 0);
    signal data_rdwr  : std_logic;
    signal data_en    : std_logic;

    -- Vstupní port
    signal in_data    : std_logic_vector(7 downto 0) := (others => '0');
    signal in_vld     : std_logic := '0';
    signal in_req     : std_logic;

    -- Výstupní port
    signal out_data   : std_logic_vector(7 downto 0);
    signal out_busy   : std_logic := '0';
    signal out_we     : std_logic;

    -- Stavové signály
    signal ready      : std_logic;
    signal done       : std_logic;

    -- Jednoduchá RAM (8bit, 2^13 adres)
    type ram_type is array (0 to 8191) of std_logic_vector(7 downto 0);
    signal ram : ram_type := (others => (others => '0'));

begin
    -- Generátor hodin
    clk <= not clk after 10 ns;

    -- Reset a enable
    process
    begin
        reset <= '1';
        en    <= '0';
        wait for 50 ns;
        reset <= '0';
        en    <= '1';
        wait;
    end process;

    -- Simulace RAM
    process(clk)
    begin
        if rising_edge(clk) then
            if data_en = '1' then
                if data_rdwr = '1' then
                    ram(to_integer(unsigned(data_addr))) <= data_wdata;
                end if;
                data_rdata <= ram(to_integer(unsigned(data_addr)));
            end if;
        end if;
    end process;

    -- Jednoduchý program v RAM
    ram(0) <= x"2B"; -- '+'
    ram(1) <= x"2B"; -- '+'
    ram(2) <= x"2B"; -- '+'
    ram(3) <= x"2E"; -- '.' (print)
    ram(4) <= x"40"; -- '@' (end)

    -- Instance CPU
    uut: entity work.cpu
        port map (
            CLK        => clk,
            RESET      => reset,
            EN         => en,
            DATA_ADDR  => data_addr,
            DATA_WDATA => data_wdata,
            DATA_RDATA => data_rdata,
            DATA_RDWR  => data_rdwr,
            DATA_EN    => data_en,
            IN_DATA    => in_data,
            IN_VLD     => in_vld,
            IN_REQ     => in_req,
            OUT_DATA   => out_data,
            OUT_BUSY   => out_busy,
            OUT_WE     => out_we,
            READY      => ready,
            DONE       => done
        );

    -- Příklad: Simulace vstupu z klávesnice (IN_DATA)
    -- process
    -- begin
    --     wait for 200 ns;
    --     in_data <= x"31"; -- ASCII '1'
    --     in_vld  <= '1';
    --     wait for 20 ns;
    --     in_vld  <= '0';
    --     wait;
    -- end process;

    -- Výpis výstupu (OUT_DATA) do konzole
    process(clk)
    begin
        if rising_edge(clk) then
            if out_we = '1' then
                report "OUT_DATA: " & integer'image(to_integer(unsigned(out_data))) severity note;
            end if;
        end if;
    end process;


    -- Omezení délky simulace, TODO: oddělat později
    process
    begin
        wait for 200 us; -- nebo kratší čas podle potřeby
        report "SIMULATION END" severity failure;
    end process;

end sim;