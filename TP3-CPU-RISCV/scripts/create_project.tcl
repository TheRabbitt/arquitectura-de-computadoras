# ---------------------------------------------------------------------------
# create_project.tcl
#
# Regenera el proyecto de Vivado desde cero a partir de los fuentes del repo.
# El .xpr NO se commitea: este script es la fuente de verdad.
#
#   vivado -mode batch -source scripts/create_project.tcl
#   vivado -mode gui   -source scripts/create_project.tcl   (abre la GUI)
#
# Para agregar un modulo nuevo NO hay que tocar este archivo: basta con
# dejar el .v dentro de rtl/ o tb/, se levantan recursivamente.
# ---------------------------------------------------------------------------

set proj_name  "riscv_pipeline"
set proj_dir   "build"
# xc7a100tcsg324-1 sirve para Nexys 4, Nexys 4 DDR y Nexys A7-100T.
set part_name  "xc7a100tcsg324-1"
set top_module "top"
set tb_module  "top_tb"

set repo_dir [file normalize [file dirname [info script]]/..]
cd $repo_dir

if {[file exists $proj_dir]} {
    puts "INFO: borrando proyecto anterior en $proj_dir"
    file delete -force $proj_dir
}

create_project $proj_name $proj_dir -part $part_name -force

# ---- Fuentes de sintesis (todo rtl/, recursivo) ----
set rtl_files [glob -nocomplain -directory rtl -types f *.v rtl/*/*.v]
set rtl_files [concat $rtl_files [glob -nocomplain rtl/*/*.v]]
set rtl_files [lsort -unique $rtl_files]
if {[llength $rtl_files] == 0} {
    puts "ERROR: no se encontro ningun .v en rtl/"
    exit 1
}
add_files -fileset sources_1 $rtl_files
set_property top $top_module [get_filesets sources_1]
puts "INFO: [llength $rtl_files] archivo(s) de RTL agregados"

# ---- Testbenches ----
set tb_files [glob -nocomplain tb/*.v]
if {[llength $tb_files] > 0} {
    add_files -fileset sim_1 $tb_files
    set_property top $tb_module [get_filesets sim_1]
    puts "INFO: [llength $tb_files] testbench(es) agregados"
}

# ---- Constraints ----
set xdc_files [glob -nocomplain constraints/*.xdc]
if {[llength $xdc_files] > 0} {
    add_files -fileset constrs_1 $xdc_files
}

# Verilog 2001 clasico para todo el proyecto (consistencia entre Vivado e Icarus)
set_property file_type {Verilog} [get_files -filter {FILE_TYPE == Verilog}]

update_compile_order -fileset sources_1

puts ""
puts "=========================================="
puts " Proyecto '$proj_name' creado en $proj_dir"
puts " Parte: $part_name"
puts " Top:   $top_module"
puts "=========================================="
