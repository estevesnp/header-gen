package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import hg "header_gen"

fatal :: proc(format: string, args: ..any) -> ! {
	fmt.eprintf(format, ..args)
	os.exit(1)
}

main :: proc() {
	json.set_user_unmarshalers(new(map[typeid]json.User_Unmarshaler))
	reg_err := json.register_user_unmarshaler(hg.Type, hg.type_unmarshaler)
	if reg_err != nil {
		fatal("error registering unmarshaler: %s", reg_err)
	}

	data, read_err := os.read_entire_file("/Users/ctw03759/tmp/schema.json", context.allocator)
	if read_err != nil {
		fatal("error reading file: %s", read_err)
	}

	decls: hg.Declarations
	if json_err := json.unmarshal(data, &decls); json_err != nil {
		fatal("error unmarshaling json: %v", json_err.(json.Unsupported_Type_Error))
	}

	fmt.printfln("%#v", decls)
}
