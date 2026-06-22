const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;

const aro = @import("aro");

const fff_h = "data/fff.h";

fn handleTree(io: Io, tree: *aro.Tree) !void {
    var stdout_buf: [1024]u8 = undefined;
    var stdout = Io.File.stdout().writer(io, &stdout_buf);
    const term: Io.Terminal = .{ .mode = .escape_codes, .writer = &stdout.interface };

    try tree.dump(term);
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

    try handleTree(io, &tree);
}
