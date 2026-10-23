Good course teaching high-speed timing optimizations. Nonsense PYNQ workflow though..

Board: Pynq-Z1 (Zynq-7000 architecture)

Main vhd files are in exponentiation/source
- Exponentiation.vhd -- main file
- montgomery_mult -- entity used in exponentiation.vhd two times


To synthesize, use synthesize.tcl; not the synthesize button inside vivado as we need to synthesize 3 projects.
Might need to run cleanup.tcl and regenerate_projects.tcl first.
