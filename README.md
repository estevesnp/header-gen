# header-gen

generate C header bindings. uses [arocc](https://github.com/Vexu/arocc) for the backend

## usage

```
header-gen <file>
```

## build

`header-gen` needs aro's builtin headers, so the best way use it is to:

- clone and cd into the repo
- build the project
  - `zig build -Doptimize=ReleaseSafe`
- symlink the executable to somewhere in your path
  - `ln -rs zig-out/bin/header-gen /dir/in/path`
