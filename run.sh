ghdl -a -fsynopsys src/cpu.vhd src/cpu_test_bench.vhd
ghdl -e -fsynopsys cpu_tb
ghdl -r -fsynopsys cpu_tb --vcd=cpu_test_bench.vcd
gtkwave cpu_test_bench.vcd cpu_gtkwave_settings.gtkw