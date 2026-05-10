# synth_quick.tcl — FF + cell count, no liberty file needed
# Run: yosys synth/synth_quick.tcl
# This gives an accurate DFF count and generic gate estimate

foreach f {
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
} {
    read_verilog $f
}

# Synthesize to internal gate library
synth -top tt_um_uwasic_crypto -flatten

# Report: the "Flip-Flops" line is the DFF count.
# "Number of cells" gives total gate count (mix of _DFF_, $_AND_, $_OR_, etc.)
stat
