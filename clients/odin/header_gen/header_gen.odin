package header_gen

import "core:encoding/json"
import "core:strings"

extract_tag_and_object :: proc(p: ^json.Parser) -> (tag, json_str: string, ok: bool) {
    json.allow_token(p, .Open_Brace) or_return
    json.allow_token(p, .String) or_return

    tag = strings.trim(p.prev_token.text, `"`)

    json.allow_token(p, .Colon) or_return

    start, end := find_json_object_boundaries(p) or_return

    json.allow_token(p, .Close_Brace) or_return

    json_str, ok = p.tok.data[start:end], true
    return
}

@(private)
find_json_object_boundaries :: proc(p: ^json.Parser) -> (start, end: int, ok: bool) {
    start = p.curr_token.offset
    json.allow_token(p, .Open_Brace) or_return

    depth := 1
    for depth > 0 {
        tok, err := json.advance_token(p)
        if err != nil {
            return
        }
        #partial switch tok.kind {
        case .EOF, .Invalid:
            return
        case .Open_Brace:
            depth += 1
        case .Close_Brace:
            depth -= 1
        }
    }

    end = p.curr_token.offset

    ok = true
    return
}
