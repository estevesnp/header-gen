const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const fatal = std.process.fatal;
const Allocator = std.mem.Allocator;

const header_gen = @import("header_gen");

fn printUsage(out: *Io.Writer, exe_name: []const u8) Io.Writer.Error!void {
    const usage =
        \\usage: {s} [flags] <header file>
        \\
        \\flags:
        \\  -h, --help, help        print this message
        \\
    ;

    try out.print(usage, .{exe_name});
    try out.flush();
}

fn printErrorUsageAndExit(stderr: *Io.File.Writer, exe_name: []const u8, comptime fmt: []const u8, args: anytype) !noreturn {
    stderr.interface.print("header-gen: " ++ fmt ++ "\n", args) catch return stderr.err.?;
    printUsage(&stderr.interface, exe_name) catch return stderr.err.?;
    std.process.exit(1);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    var stdout_buf: [1024]u8 = undefined;
    var stdout = Io.File.stdout().writer(io, &stdout_buf);

    var stderr_buf: [1024]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &stderr_buf);

    switch (parseArgs(args)) {
        .help => printUsage(&stdout.interface, args[0]) catch return stdout.err.?,
        .file => |f| try printDeclarations(gpa, arena, io, init.environ_map, &stdout, &stderr, f),

        .unknown_flag => |f| try printErrorUsageAndExit(&stderr, args[0], "unkown flag: {s}", .{f}),
        .missing_file => try printErrorUsageAndExit(&stderr, args[0], "no filename provided", .{}),
        .multiple_files => try printErrorUsageAndExit(&stderr, args[0], "multiple filenames provided", .{}),
    }
}

fn printDeclarations(
    gpa: Allocator,
    arena: Allocator,
    io: Io,
    environ_map: *const std.process.Environ.Map,
    stdout: *Io.File.Writer,
    stderr: *Io.File.Writer,
    filename: []const u8,
) !void {
    const diagnostics: Io.Terminal = .{
        .writer = &stderr.interface,
        .mode = Io.Terminal.Mode.detect(io, stderr.file, false, false) catch .no_color,
    };

    const decls = header_gen.generateDeclarations(
        gpa,
        arena,
        io,
        environ_map,
        diagnostics,
        filename,
    ) catch |err| switch (err) {
        error.WriteFailed => return stderr.err.?,
        else => |e| return e,
    };

    std.json.Stringify.value(
        decls,
        .{ .whitespace = .indent_2, .emit_null_optional_fields = false },
        &stdout.interface,
    ) catch return stdout.err.?;
    stdout.interface.flush() catch return stdout.err.?;
}

const Cmd = union(enum) {
    file: []const u8,
    help,

    // errors
    unknown_flag: []const u8,
    missing_file,
    multiple_files,
};

fn eqlAny(needle: []const u8, haystack: []const []const u8) bool {
    for (haystack) |item| {
        if (std.mem.eql(u8, needle, item)) return true;
    }
    return false;
}

fn parseArgs(args: []const []const u8) Cmd {
    var parsing_flags = true;
    var file: ?[]const u8 = null;

    for (args[1..]) |arg| {
        if (parsing_flags) {
            if (std.mem.eql(u8, arg, "--")) {
                parsing_flags = false;
                continue;
            }

            if (eqlAny(arg, &.{ "help", "--help", "-h" })) return .help;

            if (std.mem.startsWith(u8, arg, "-")) return .{ .unknown_flag = arg };
        }

        if (file != null) return .multiple_files;
        file = arg;
    }

    if (file == null) return .missing_file;

    return .{ .file = file.? };
}
