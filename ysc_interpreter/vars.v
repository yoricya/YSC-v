module ysc_interpreter

enum VarType {
	int
	double
	string
	context
}

struct YscVariable {
	mut:
	data voidptr
	var_type VarType
}

pub fn (this YscVariable) to_string() !string {
	if this.var_type != VarType.string {
		return error("Var is not a string")
	}

	return (*(&string(this.data))).str()
}

pub fn (this YscVariable) to_int() !i64 {
	if this.var_type != VarType.int {
		return error("Var is not a int")
	}

	return i64(this.data)
}

pub fn (this YscVariable) to_float() !f64 {
	if this.var_type != VarType.int {
		return error("Var is not a float")
	}

	return i64(this.data)
}

pub fn (this YscVariable) to_context() !Context {
	if this.var_type != VarType.context {
		return error("Var is not a context")
	}

	return unsafe { *(&Context(this.data)) }
}

pub fn (this YscVariable) to_type_name() string {
	return match this.var_type {
		.context {
			"context_space"
		}
		.double {
			"double"
		}
		.int {
			"integer"
		}
		.string {
			"string"
		}
		// else {
		// 	"unknown"
		// }
	}
}
