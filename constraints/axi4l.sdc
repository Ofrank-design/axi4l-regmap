# Starting-point timing constraint. Change the period to your real clock.
create_clock -name aclk -period 10.0 [get_ports aclk]

# The slave is fully registered on its outputs, so a modest I/O budget is
# usually enough; tighten these once the real interconnect is known.
set_input_delay  -clock aclk 2.0 [remove_from_collection [all_inputs] [get_ports aclk]]
set_output_delay -clock aclk 2.0 [all_outputs]
