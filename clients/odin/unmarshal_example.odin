package main

import "core:encoding/json"
import hg "header_gen"


Foo :: struct {
	name: string,
}

Bar :: struct {
	age: int,
}

Foo_Bar :: union {
	Foo,
	Bar,
}

Container :: struct {
	foo_bar: Foo_Bar,
	counter: int,
}

foobar_unmarshaler :: proc(p: ^json.Parser, v: any) -> json.Unmarshal_Error {
	tag, json_str, ok := hg.extract_tag_and_object(p)
	if !ok {
		return .Unexpected_Token
	}

	foo_bar := cast(^Foo_Bar)v.data

	switch tag {
	case "foo":
		f: Foo
		json.unmarshal_string(json_str, &f) or_return
		foo_bar^ = f
	case "bar":
		b: Bar
		json.unmarshal_string(json_str, &b) or_return
		foo_bar^ = b
	case:
		return .Invalid_Data
	}

	return nil
}

main :: proc() {
	str := `
        {
          "foo_bar": {
            "bar": {
              "age": 2
            }
          },
          "counter": 5
        }`

	json.set_user_unmarshalers(new(map[typeid]json.User_Unmarshaler))

	reg_err := json.register_user_unmarshaler(Foo_Bar, foobar_unmarshaler)
	assert(reg_err == nil)

	c: Container
	parse_err := json.unmarshal_string(str, &c)
	assert(parse_err == nil)

	assert(c.counter == 5)
	assert(c.foo_bar.(Bar).age == 2)
}
