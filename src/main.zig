const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const fatal = std.process.fatal;
const Allocator = std.mem.Allocator;

const header_gen = @import("header_gen");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    if (args.len < 2) fatal("usage: {s} <file>", .{args[0]});

    const input_file_path = args[1];

    var stderr_buf: [1024]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &stderr_buf);

    const diagnostics: Io.Terminal = .{
        .writer = &stderr.interface,
        .mode = Io.Terminal.Mode.detect(io, stderr.file, false, false) catch .no_color,
    };

    const decls = try header_gen.generateDeclarations(
        gpa,
        arena,
        io,
        init.environ_map,
        diagnostics,
        input_file_path,
    );

    var stdout_buf: [1024]u8 = undefined;
    var stdout = Io.File.stdout().writer(io, &stdout_buf);

    try std.json.Stringify.value(
        decls,
        .{ .whitespace = .indent_2, .emit_null_optional_fields = false },
        &stdout.interface,
    );
    try stdout.interface.flush();
}
