# synth.tcl — AES crypto top-level synthesis for area estimation
# Run from repo root: yosys synth/synth.tcl
# Output: cell count + FF count + estimated area against sky130_fd_sc_hd

set src_files {
    src/project.v
    src/ack_bus_arbiter.v
    src/ack_bus_module_interface.v
    src/aes_fsm.v
    src/bus_arbiter.v
    src/comp_queue.v
    src/control_top.v
    src/data_bus_ctrl.v
    src/data_bus_module_interface.v
    src/deserializer.v
    src/global_arbiter.v
    src/interconnect.v
    src/mem_command_port.v
    src/mem_spi_controller.v
    src/mem_top.v
    src/mem_txn_fsm.v
    src/req_queue.v
    src/serializer.v
    src/mix_columns.v
    src/aes_core_rs.v
    src/AES.v
    src/roundkey_gen.v
    src/sbox.v
    src/sub_bytes.v
}

foreach f $src_files {
    read_verilog -sv $f
}

# Synthesize to generic gates + flatten for accurate counts
synth -top tt_um_uwasic_crypto -flatten -noabc

# Report FF count before technology mapping
# (DFF count is accurate here; cell names are generic)
stat

# Technology map to sky130_fd_sc_hd if liberty available
set liberty_path "synth/sky130_fd_sc_hd__tt_025C_1v80.lib"
if {[file exists $liberty_path]} {
    dfflibmap -liberty $liberty_path
    abc -liberty $liberty_path
    stat -liberty $liberty_path
} else {
    puts "\n[WARNING] Liberty file not found at $liberty_path"
    puts "Run synth/get_liberty.sh to download it, or copy it manually."
    puts "FF count above is still accurate for area estimation."
}
