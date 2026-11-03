transcript on
if {[file exists rtl_work]} {
vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vsim -t 1ps  -voptargs=+acc work.tb_single_file
add wave *
view structure
view signals
run -all
