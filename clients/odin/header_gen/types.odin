package header_gen

Declarations :: struct {
    structs:   []Struct,
    enums:     []Enum,
    unions:    []Union,
    functions: []Function,
    opaques:   []Opaque,
}

Kind :: enum {
    k_scalar,
    k_struct,
    k_enum,
    k_union,
    k_pointer,
    k_array,
    k_function,
}

Type :: union {
    Identifier,
    Scalar,
    ^Property,
    ^Array,
    ^Function,
}

Identifier :: struct {
    name: string,
    kind: Kind,
}

ScalarKind :: enum {
    s_void,
    s_bool,
    s_char,
    s_u8,
    s_u16,
    s_u32,
    s_u64,
    s_u128,
    s_i8,
    s_i16,
    s_i32,
    s_i64,
    s_i128,
    s_f16,
    s_f32,
    s_f64,
    s_f128,
}

Scalar :: struct {
    scalar: ScalarKind,
}

Struct :: struct {
    name:       string,
    properties: []Property,
}

Value :: struct {
    name:  string,
    value: i64,
}

Enum :: struct {
    name:         string,
    backing_type: string,
    values:       []Value,
}

Union :: struct {
    name:     string,
    variants: []Property,
}

Function :: struct {
    name:        Maybe(string),
    parameters:  []Property,
    return_type: Type,
}

Array :: struct {
    len:  u64,
    kind: Kind,
    type: Type,
}

Property :: struct {
    name:     Maybe(string),
    is_const: bool,
    kind:     Kind,
    type:     Type,
}

Opaque_Kind :: enum {
    k_struct,
    k_enum,
    k_union,
}

Opaque :: struct {
    name: string,
    kind: Opaque_Kind,
}
