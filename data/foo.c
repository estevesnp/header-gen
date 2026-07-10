#include <stdbool.h>
#include <stdint.h>

struct Foo {
    bool is_foo;
    uint8_t *name;
};

typedef struct Bar {
    struct Foo foo;
} Bar;

enum Baz {
    tree,
    book
};

union FooBarBazNum {
    struct Foo foo;
    Bar *bar;
    enum Baz baz;
    int64_t num;
};

enum Backed : uint8_t {
    zero,
    um,
    dois
};

int8_t *const *calculate(struct Foo *foo, double mult);
