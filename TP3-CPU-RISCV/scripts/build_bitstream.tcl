# ---------------------------------------------------------------------------
# build_bitstream.tcl
#
# Sintesis + implementacion + bitstream, sin abrir la GUI.
#   vivado -mode batch -source scripts/build_bitstream.tcl
#
# Ejecutar create_project.tcl antes.
# El bitstream queda en build/riscv_pipeline.runs/impl_1/top.bit
# ---------------------------------------------------------------------------

set proj_name "riscv_pipeline"
set proj_dir  "build"
set jobs      4

set repo_dir [file normalize [file dirname [info script]]/..]
cd $repo_dir

open_project $proj_dir/$proj_name.xpr

reset_run synth_1
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: fallo la sintesis"
    exit 1
}

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: fallo la implementacion"
    exit 1
}

open_run impl_1

# ---- Reportes de timing: guardarlos SIEMPRE, son material del informe ----
file mkdir reports
report_timing_summary -file reports/timing_summary.rpt
report_utilization    -file reports/utilization.rpt
report_clock_networks -file reports/clock_networks.rpt

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts ""
puts "=========================================="
puts " WNS (worst negative slack): $wns ns"
if {$wns < 0} {
    puts " >>> NO CIERRA TIMING. Bajar la frecuencia del Clock Wizard"
    puts " >>> o acortar el camino critico. Ver reports/timing_summary.rpt"
} else {
    puts " >>> Timing OK"
}
puts "=========================================="
