# Load RUCKUS environment and library
source -quiet $::env(RUCKUS_DIR)/vivado_proc.tcl

# Load local Source Code and Constraints
loadSource      -dir "$::DIR_PATH/rtl"
loadConstraints -dir "$::DIR_PATH/rtl"

# loadIpCore -path "$::DIR_PATH/ip/AxisPgpGthCore.xci"
loadSource   -path "$::DIR_PATH/ip/AxisPgpGthCore.dcp"
