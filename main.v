module main

import os
import ysc_interpreter

fn main() {

	f := os.read_file("main.ysc") or {
		return
	}

	ysc_interpreter.parse(f)
}
