Good course teaching high-speed timing optimizations. Nonsense PYNQ workflow though..

Board: Pynq-Z1 (Zynq-7000 architecture)

Main vhd files are in exponentiation/source
- Exponentiation.vhd -- main file
- montgomery_mult -- entity used in exponentiation.vhd two times


To synthesize: (To run .tcl: tools-> run tcl script)
1. run cleanup.tcl
2. run regenerate_projects.tcl
3. run synthesize.tcl
