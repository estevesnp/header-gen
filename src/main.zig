const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const fatal = std.process.fatal;
const Allocator = std.mem.Allocator;

const aro = @import("aro");

const fff_h = "data/fff.h";

const Kind = enum {
    scalar,
    @"struct",
    @"enum",
    @"union",
    pointer,
    array,
    function,
};

const Type = union(Kind) {
    scalar: []const u8,
    @"struct": []const u8,
    @"enum": []const u8,
    @"union": []const u8,

    pointer: *Property,
    array: *Array,

    function: *Function,
};

const Schema = struct {
    structs: []const Struct,
    enums: []const Enum,
    unions: []const Union,
    functions: []const Function,
};

const Struct = struct {
    name: []const u8,
    properties: []const Property,
};

const Enum = struct {
    name: []const u8,
    backing_type: []const u8,
    values: []const Value,

    const Value = struct {
        name: []const u8,
        value: i64,
    };
};

const Union = struct {
    name: []const u8,
    variants: []const Property,
};

const Function = struct {
    name: ?[]const u8,
    parameters: []const Property,
    return_type: Type,
};

const Array = struct {
    len: u64,
    kind: Kind,
    type: Type,

    fn init(t: Type, len: u64) Array {
        return .{
            .len = len,
            .kind = t,
            .type = t,
        };
    }
};

const Property = struct {
    name: ?[]const u8,
    @"const": bool,
    kind: Kind,
    type: Type,

    fn init(t: Type, is_const: bool, name: ?[]const u8) Property {
        return .{
            .name = name,
            .@"const" = is_const,
            .kind = t,
            .type = t,
        };
    }
};

fn parseTree(arena: Allocator, tree: *aro.Tree) Allocator.Error!Schema {
    const comp = tree.comp;

    var functions: std.ArrayList(Function) = .empty;
    defer functions.deinit(arena);

    var structs: std.ArrayList(Struct) = .empty;
    defer structs.deinit(arena);

    var enums: std.ArrayList(Enum) = .empty;
    defer enums.deinit(arena);

    var unions: std.ArrayList(Union) = .empty;
    defer unions.deinit(arena);

    for (tree.root_decls.items) |node_idx| {
        const node = node_idx.get(tree);
        const node_qt = node_idx.qtOrNull(tree) orelse continue;

        // strip attributes (e.g. deprecated)
        const node_type = s: switch (node_qt.type(comp)) {
            .attributed => |a| continue :s a.base.type(comp),
            else => |e| e,
        };

        switch (node) {
            .function => |function| {
                const func_type = switch (node_type) {
                    .func => |f| f,
                    else => |e| {
                        std.debug.print("unexpected type for function: {t}\n", .{e});
                        continue;
                    },
                };

                const func: Function = .{
                    .name = tree.tokSlice(function.name_tok),
                    .parameters = try extractFuncParams(arena, comp, func_type),
                    .return_type = try resolveType(arena, comp, func_type.return_type),
                };
                try functions.append(arena, func);
            },
            .struct_decl => |struct_decl| {
                _ = struct_decl;
                const struct_type = switch (node_type) {
                    .@"struct" => |s| s,
                    else => |e| {
                        std.debug.print("unexpected type for struct_decl: {t}\n", .{e});
                        continue;
                    },
                };

                if (struct_type.isAnonymous(comp)) continue;

                const record = try extractRecord(arena, comp, struct_type);

                const st: Struct = .{
                    .name = record.name,
                    .properties = record.properties,
                };

                try structs.append(arena, st);
            },
            .enum_decl => |enum_decl| {
                // maybe use node_qt.get(.@"enum") orelse continue
                const enum_type = switch (node_type) {
                    .@"enum" => |e| e,
                    else => |e| {
                        std.debug.print("unexpected type for enum_decl: {t}\n", .{e});
                        continue;
                    },
                };

                if (enum_type.isAnonymous(comp) or enum_type.incomplete) continue;

                const tag_type = try resolveType(arena, comp, enum_type.tag orelse continue);

                var fields: std.ArrayList(Enum.Value) = .empty;
                defer fields.deinit(arena);

                for (enum_type.fields, enum_decl.fields) |type_field, decl_field| {
                    try fields.append(arena, .{
                        .name = type_field.name.lookup(comp),
                        .value = tree.value_map.get(decl_field).?.toInt(i64, comp).?,
                    });
                }

                const en: Enum = .{
                    .name = enum_type.name.lookup(comp),
                    .backing_type = tag_type.scalar, // should always be an int
                    .values = try fields.toOwnedSlice(arena),
                };

                try enums.append(arena, en);
            },
            .union_decl => |union_decl| {
                _ = union_decl;
                const union_type = switch (node_type) {
                    .@"union" => |u| u,
                    else => |e| {
                        std.debug.print("unexpected type for union_decl: {t}\n", .{e});
                        continue;
                    },
                };

                if (union_type.isAnonymous(comp)) continue;

                const record = try extractRecord(arena, comp, union_type);

                const un: Union = .{
                    .name = record.name,
                    .variants = record.properties,
                };

                try unions.append(arena, un);
            },
            .typedef => {
                // do we want to just silently ignore?
            },
            else => std.debug.print("skipping node {t}\n", .{node}),
        }
    }

    return .{
        .functions = try functions.toOwnedSlice(arena),
        .structs = try structs.toOwnedSlice(arena),
        .enums = try enums.toOwnedSlice(arena),
        .unions = try unions.toOwnedSlice(arena),
    };
}

fn resolveType(arena: Allocator, comp: *const aro.Compilation, qt: aro.QualType) Allocator.Error!Type {
    const t = qt.type(comp);
    return switch (t) {
        .@"struct" => |s| .{ .@"struct" = s.name.lookup(comp) },
        .@"enum" => |s| .{ .@"enum" = s.name.lookup(comp) },
        .@"union" => |s| .{ .@"union" = s.name.lookup(comp) },
        .pointer => |p| {
            const prop = try arena.create(Property);
            prop.* = .init(try resolveType(arena, comp, p.child), p.child.@"const", null);
            return .{ .pointer = prop };
        },
        .array => |a| {
            const len = switch (a.len) {
                .fixed, .static => |l| l,
                .incomplete, .variable, .unspecified_variable => blk: {
                    std.debug.print("unsupported array type: {t}\n", .{a.len});
                    break :blk 0;
                },
            };

            const arr = try arena.create(Array);
            arr.* = .init(try resolveType(arena, comp, a.elem), len);
            return .{ .array = arr };
        },
        .typedef => resolveType(arena, comp, qt.base(comp).qt),
        .void, .bool => .{ .scalar = @tagName(t) },

        .int => |i| .{ .scalar = resolveIntName(comp, i) },
        .float => |f| .{ .scalar = resolveFloatName(comp, f) },

        .func => |f| {
            const func = try arena.create(Function);
            func.* = .{
                .name = null,
                .parameters = try extractFuncParams(arena, comp, f),
                .return_type = try resolveType(arena, comp, f.return_type),
            };
            return .{ .function = func };
        },

        else => |e| {
            std.debug.print("defaulting to tagname: {t}\n", .{e});
            return .{ .scalar = @tagName(e) };
        },
    };
}

fn resolveIntName(comp: *const aro.Compilation, int: aro.Type.Int) []const u8 {
    if (int == .char) return "char";
    const unsigned = @tagName(int)[0] == 'u';
    return switch (int.bits(comp)) {
        8 => if (unsigned) "u8" else "i8",
        16 => if (unsigned) "u16" else "i16",
        32 => if (unsigned) "u32" else "i32",
        64 => if (unsigned) "u64" else "i64",
        128 => if (unsigned) "u128" else "i128",
        else => unreachable,
    };
}

fn resolveFloatName(comp: *const aro.Compilation, float: aro.Type.Float) []const u8 {
    return switch (float.bits(comp)) {
        16 => "f16",
        32 => "f32",
        64 => "f64",
        128 => "f128",
        else => unreachable,
    };
}

fn extractRecord(arena: Allocator, comp: *const aro.Compilation, record: aro.Type.Record) Allocator.Error!Record {
    var properties: std.ArrayList(Property) = .empty;
    defer properties.deinit(arena);

    for (record.fields) |field| {
        const field_type = try resolveType(arena, comp, field.qt);
        const prop: Property = .init(field_type, field.qt.@"const", field.name.lookup(comp));
        try properties.append(arena, prop);
    }

    return .{
        .name = record.name.lookup(comp),
        .properties = try properties.toOwnedSlice(arena),
    };
}

fn extractFuncParams(arena: Allocator, comp: *const aro.Compilation, func: aro.Type.Func) Allocator.Error![]const Property {
    var params: std.ArrayList(Property) = .empty;
    defer params.deinit(arena);

    for (func.params) |param| {
        const param_name = param.name.lookup(comp);
        try params.append(arena, .init(
            try resolveType(arena, comp, param.qt),
            param.qt.@"const",
            if (param_name.len != 0) param_name else null,
        ));
    }

    return params.toOwnedSlice(arena);
}

const Record = struct {
    name: []const u8,
    properties: []const Property,
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    const input_file_path = if (args.len > 1) args[1] else fff_h;

    var stderr_buf: [1024]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &stderr_buf);
    var diagnostics: aro.Diagnostics = .{
        .output = .{ .to_writer = .{
            .mode = std.Io.Terminal.Mode.detect(io, stderr.file, false, false) catch .no_color,
            .writer = &stderr.interface,
        } },
    };

    var comp = try aro.Compilation.init(.{
        .gpa = gpa,
        .arena = arena,
        .io = io,
        .diagnostics = &diagnostics,
        .environ_map = init.environ_map,
    });
    defer comp.deinit();

    var driver: aro.Driver = .{
        .comp = &comp,
        .aro_name = args[0],
        .diagnostics = &diagnostics,
    };
    defer driver.deinit();

    var toolchain: aro.Toolchain = .{ .driver = &driver };
    defer toolchain.deinit();

    var macro_buf: std.ArrayList(u8) = .empty;
    defer macro_buf.deinit(gpa);

    var discard_buf: [256]u8 = undefined;
    var discarding: Io.Writer.Discarding = .init(&discard_buf);
    assert(!try driver.parseArgs(&discarding.writer, &macro_buf, &.{ args[0], input_file_path }));
    if (macro_buf.items.len > std.math.maxInt(u32)) {
        return driver.fatal("user provided macro source exceeded max size", .{});
    }

    const content = try macro_buf.toOwnedSlice(gpa);
    defer gpa.free(content);
    const user_macros = try driver.comp.addSourceFromOwnedBuffer("<command line>", content, .user);

    const source = driver.inputs.items[0];

    try toolchain.discover();
    try toolchain.defineSystemIncludes();
    try driver.comp.initSearchPath(driver.includes.items, driver.verbose_search_path);

    const builtin_macros = try driver.comp.generateBuiltinMacros(driver.system_defines);

    var pp = try aro.Preprocessor.init(driver.comp, .{ .base_file = source.id });
    defer pp.deinit();

    try pp.preprocessSources(.{
        .main = source,
        .builtin = builtin_macros,
        .command_line = user_macros,
        .imacros = driver.imacros.items,
        .implicit_includes = driver.implicit_includes.items,
    });

    var tree = try pp.parse();
    defer tree.deinit();

    const decls = try parseTree(arena, &tree);
    var stdout_buf: [1024]u8 = undefined;
    var stdout = Io.File.stdout().writer(io, &stdout_buf);

    try stdout.interface.print("{f}\n", .{
        std.json.fmt(decls, .{
            .whitespace = .indent_2,
            .emit_null_optional_fields = false,
        }),
    });
    try stdout.interface.flush();
}
