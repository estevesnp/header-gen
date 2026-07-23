# header-gen

generate C header bindings. uses [arocc](https://github.com/Vexu/arocc) for the backend

## usage

```
header-gen <file>
```

## build

`header-gen` needs aro's builtin headers at runtime, which are created next to the executable, so the best way use it is to:

- clone and cd into the repo
- build the project
  - `zig build -Doptimize=ReleaseSafe`
- symlink the executable to somewhere in your path
  - `ln -s $(pwd)/zig-out/bin/header-gen /dir/in/path`

## dependency

to use the project as a dependency, you will need to first fetch it as a dependency:

```sh
zig fetch --save git+https://github.com/estevesnp.header-gen.git
```

then include it in the build system:

```zig
// build.zig
const header_gen = b.dependency("header_gen", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("header_gen", header_gen.module("header_gen"));
```

and install aro's builtin headers:

```zig
// build.zig
@import("header_gen").installBuiltinHeaders(b);
```

note that your program will also need aro's builtin headers at runtime, so see the steps in the [build](#build) section
