package header_gen

import "core:encoding/json"
import "core:reflect"
type_unmarshaler :: proc(p: ^json.Parser, v: any) -> json.Unmarshal_Error {
    tag_str, json_str, ok := extract_tag_and_object(p)
    if !ok {
        return .Unexpected_Token
    }

    tag, t_ok := reflect.enum_from_name(Kind, tag_str)
    if !t_ok {
        return .Invalid_Data
    }

    t := cast(^Type)v.data

    switch tag {
    case .k_struct, .k_enum, .k_union:
        ident: Identifier
        json.unmarshal_string(json_str, &ident) or_return
        t^ = ident
    case .k_scalar:
        scalar: Scalar
        json.unmarshal_string(json_str, &scalar) or_return
        t^ = scalar
    case .k_pointer:
        ptr := new(Property)
        json.unmarshal_string(json_str, ptr) or_return
        t^ = ptr
    case .k_array:
        arr := new(Array)
        json.unmarshal_string(json_str, arr) or_return
        t^ = arr
    case .k_function:
        func := new(Function)
        json.unmarshal_string(json_str, func) or_return
        t^ = func
    }

    return nil
}
