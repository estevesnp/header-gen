const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const fatal = std.process.fatal;

const aro = @import("aro");

const fff_h = "data/fff.h";

const Kind = enum {
    scalar,
    @"struct",
    @"enum",
    @"union",
    pointer,
    // TODO: function? for function pointers (callbacks, etc)
};

const Type = union(Kind) {
    scalar: []const u8,
    @"struct": []const u8,
    @"enum": []const u8,
    @"union": []const u8,

    pointer: *Property,
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
        value: u32,
    };
};

const Union = struct {
    name: []const u8,
    variants: []const Property,
};

const Function = struct {
    name: []const u8,
    parameters: []const Property,
    return_type: Property,
};

const Property = struct {
    name: ?[]const u8 = null,
    @"const": bool = false,
    kind: Kind,
    type: Type,
};

fn parseTree(arena: std.mem.Allocator, tree: *aro.Tree) !Schema {
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

        switch (node) {
            .function => |function| {
                // TODO - properly parse function
                const func: Function = .{
                    .name = tree.tokSlice(function.name_tok),
                    .parameters = &.{},
                    .return_type = .{ .name = "void", .kind = .scalar, .type = .{ .scalar = "void" } },
                };
                try functions.append(arena, func);
            },
            .struct_decl => |struct_decl| {
                _ = struct_decl;
                const struct_type = switch (node_qt.type(comp)) {
                    .@"struct" => |s| s,
                    else => |e| {
                        std.debug.print("unexpected type for struct_decl: {t}\n", .{e});
                        continue;
                    },
                };

                var properties: std.ArrayList(Property) = .empty;
                defer properties.deinit(arena);

                for (struct_type.fields) |field| {
                    // TODO - properly parse fields
                    const prop: Property = .{
                        .name = field.name.lookup(comp),
                        .kind = .scalar,
                        .type = .{ .scalar = "void" },
                    };
                    try properties.append(arena, prop);
                }

                const st: Struct = .{
                    .name = struct_type.name.lookup(comp),
                    .properties = try properties.toOwnedSlice(arena),
                };

                try structs.append(arena, st);
            },
            .enum_decl => |enum_decl| {
                std.debug.print("TODO: enum_decl={any}\n", .{enum_decl});
            },
            .union_decl => |union_decl| {
                std.debug.print("TODO: union_decl={any}\n", .{union_decl});
            },
            else => {
                std.debug.print("skipping node {t}\n", .{node});
                continue;
            },
        }
    }

    return .{
        .functions = try functions.toOwnedSlice(arena),
        .structs = try structs.toOwnedSlice(arena),
        .enums = try enums.toOwnedSlice(arena),
        .unions = try unions.toOwnedSlice(arena),
    };
}

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
