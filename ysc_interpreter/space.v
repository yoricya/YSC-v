module ysc_interpreter

import sokol.f

struct YscFunc {
	name string
	body string
	start_line int

	internal bool
	internal_method fn (ct Context, args[] YscVariable) ?Result
}

struct Result {
	use_origin_layer bool = false
}

struct Context {
pub:
	context_space Space
pub mut:
	local_vars map[string]YscVariable
}

struct Space {
pub:
	is_module bool
	module_name string

pub mut:
	functions map[string]YscFunc
	glob_vars map[string]YscVariable
}

pub fn parse(s string) int {
	mut space := space_parse(s)

	space.functions["println"] = YscFunc{
		name: 'println'
		internal: true
		internal_method: fn (ct Context, args []YscVariable) ?Result {
			if args.len > 0 {
				if args[0].var_type == VarType.int {
					println(args[0].to_int() or {0})
				}else if args[0].var_type == VarType.double {
					println(args[0].to_float() or {0.0})
				}else if args[0].var_type == VarType.string {
					println(args[0].to_string() or {panic(err)})
				}
			}else{
				print("\n")
			}

			return Result{}
		}
	}

	main := space.functions["main"] or {
		panic("[ERR] func main{} - entry point not found!")
	}

	main.run(mut Context{
		context_space: space
	}, []YscVariable{})

	return 0
}

pub fn (func YscFunc) run(mut ct Context, args[] YscVariable) ?Result {
	if func.internal {
		return func.internal_method(ct, args)
	}

	mut code := func.body.trim_space().trim_left("{").trim_right("}").trim_space()

	mut line := 0

	for i := 0; i < code.len; i++ {
		if code[i] == ` ` {continue}
		if code[i] == `\n` {line++}
		s, o := read_next_tosym(code, i, `;`)
		i += o

		mut nct := Context{ct.context_space, ct.local_vars}

		mut args_ctx := Context{}
		args_ctx.local_vars["len"] = YscVariable{
			data: voidptr(args.len)
			var_type: .int
		}

		for iarg, var in args {
			args_ctx.local_vars[iarg.str()] = var
		}

		nct.local_vars["args"] = YscVariable{
			data: voidptr(&args_ctx)
			var_type: .context
		}

		result := fn_command_parse(s, mut nct)
		if result or {Result{false}}.use_origin_layer {
			ct = nct
		}
	}

	return none
}

pub fn fn_command_parse(s string, mut ct Context) ?Result {
	cmd := s.trim_space()

	mut cmd_args := []string{}

	mut is_open_str := false
	mut queries := 0

	mut start_pos := 0

	for i := 0; i < cmd.len; i++{
		if cmd[i] == `"` {
			is_open_str = !is_open_str
		}

		if is_open_str {continue}

		if cmd[i] == `{`{
			queries++
			continue
		}

		if cmd[i] == `}`{
			queries--
		}

		if (cmd[i] == ` ` || i == cmd.len-1) && queries == 0 {
			fstr := cmd[start_pos..i+1].trim_space()
			if fstr != "" {
				cmd_args << fstr
			}

			start_pos = i
			continue
		}
	}

	if cmd_args[0].starts_with("#"){
		return none
	}

	//Set variable
	if cmd_args.len > 2 {
		if cmd_args[1] == ":=" {
			a := parse_var(mut ct, cmd_args[2])
			ct.local_vars[cmd_args[0]] = a
			return Result{true}
		}

		if cmd_args[1] == "+=" || cmd_args[1] == "-=" || cmd_args[1] == "*=" || cmd_args[1] == "/="{
			i1 := parse_var(mut ct, cmd_args[0])
			i2 := parse_var(mut ct, cmd_args[2])

			if i1.var_type == .string{
				mut st := i1.to_string() or {""}
				st += i2.to_string() or {
					mut er := false
					mut ret := i2.to_int() or {
						er = true
						0
					}.str()

					if er {
						er = false
						ret = i2.to_int() or {
							er = true
							0
						}.str()
						if er {
							ret = ""
						}
					}

					ret
				}

				ct.local_vars[cmd_args[0]] = YscVariable{
					data: voidptr(&st.str)
					var_type: .string
				}

				return Result{true}
			}

			if i1.var_type != .int && i1.var_type != .double {
				panic("i1 Not A Number")
			}
			if i2.var_type != .int && i2.var_type != .double {
				panic("i2 Not A Number")
			}

			int1 := i1.to_float() or {i1.to_int() or {0}}
			int2 := i2.to_float() or {i2.to_int() or {0}}

			int3 := if cmd_args[1] == "+=" {
				int1 + int2
			}else if cmd_args[1] == "-=" {
				int1 - int2
			}else if cmd_args[1] == "*=" {
				int1 * int2
			}else if cmd_args[1] == "/=" {
				int1 / int2
			}else {0}

			ct.local_vars[cmd_args[0]] = YscVariable{
				data: if i1.var_type == .int {
					i64(int3)
				}else{
					i64(int3)
				}

				var_type: i1.var_type
			}

			return Result{true}
		}
	}

	func := ct.context_space.functions[cmd_args[0]] or {
		panic("[ERR] ${cmd_args[0]} - function not defined!")
	}

	mut vars := []YscVariable{}

	for arg in cmd_args[1..] {
		vars << parse_var(mut ct, arg)
	}

	return func.run(mut ct, vars)
}

pub fn parse_var(mut ct Context, s string) YscVariable {
	arg := s.trim_space()

	// println("PV: ${s} - ${unsafe{voidptr(&ct.local_vars)}} - ${ct.local_vars}")

	// strings
	if arg.starts_with("\"") && arg.ends_with("\"") {
		str := arg.trim_right("\"").trim_left("\"")
		return YscVariable{data: voidptr(&str.str), var_type: .string}
	}

	//ints
	if arg.is_int() {
		return YscVariable{data: voidptr(arg.i64()), var_type: .int}
	}

	// //floats
	// if s.f64() != 0 {
	// 	return true
	// }
	//

	//vars
	spl := s.split(".")

	mut layer := ct
	for i, st in spl {
		var := layer.local_vars[st.trim_space()] or {
			panic("[ERR] Unknown variable \'$arg\'")
		}

		if i == spl.len-2 && spl.len > 1 && spl[i+1] == "*type" {
			typ := var.to_type_name()
			return YscVariable{data: voidptr(&typ.str), var_type: .string}
		} else if i != spl.len-1 && spl.len > 1 {
			layer = var.to_context() or {
				panic("[ERR] Variable is not a context \'$arg\'")
			}
		}

		if i == spl.len - 1 {
			return var
		}
	}

	return YscVariable{}
}

pub fn space_parse(s string) Space {
	mut code := s.trim_space()

	mut line := 0

	mut is_module := false
	mut module_name := "unnamed"
	if code.starts_with("module") {
		is_module = true
		module_name, _ = read_next_q(code, "module".len)
		line++
	}

	mut fn_map := map[string]YscFunc{}

	for i := 0; i < code.len; i++ {
		if code[i] == ` ` {continue}
		if code[i] == `\n` {line++}

		if i+4 < code.len && code[i..][..4] == "func" {
			i += 4

			fn_name, o := read_next_tosym(code, i, `{`)
			if fn_name == "" {
				panic("[SYNTAX_ERR] line:$line - fn_name cannot be empty!")
			}
			i += o

			fn_body, o1 := read_next_block(code, i)
			i += o1

			fn_map[fn_name] = YscFunc{
				name: fn_name
				body: fn_body
				start_line: line
			}
		}
	}

	return Space{
		glob_vars: {}
		functions: fn_map
		is_module: is_module
		module_name: module_name
	}
}

pub fn read_next_q(code string, pos int) (string, int) {
	mut i := pos

	mut is_open_str := false

	for i < code.len {
		i++

		if code[i] == `"`{
			is_open_str = !is_open_str
		}

		if is_open_str {
			continue
		}

		if !is_open_str && code[i] == `;` {
			return code[pos..i].trim_space(), i-pos
		}
	}

	if i > code.len {
		return code[pos..(i-1)].trim_space(), i-pos
	}

	return "", 0
}

pub fn read_next_block(code string, pos int) (string, int) {
	mut queries := 0
	mut is_open_str := false
	for i := pos; i < code.len; i++ {
		if code[i] == ` `{continue}

		if code[i] == `"`{
			is_open_str = !is_open_str
		}

		if is_open_str {continue}

		if code[i] == `{`{
			queries++
			continue
		}

		if code[i] == `}`{
			queries--

			if queries == 0 && i != pos {
				return code[pos..i+1].trim_space(), i - pos
			}

			continue
		}
	}

	return "_", 0
}

pub fn read_next_tosym(code string, pos int, sym u8) (string, int){
	mut is_open_str := false
	for i := pos; i < code.len; i++ {
		if code[i] == ` `{continue}

		if code[i] == `"`{
			is_open_str = !is_open_str
		}

		if is_open_str {continue}

		if code[i] == sym {
			return code[pos..i].trim_space(), i - pos
		}
	}

	return "_", 0
}
