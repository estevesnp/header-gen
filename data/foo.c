struct Foo {
    const char *name;
    int age;
};

typedef struct Bar {
    int bariarity;
} Bar;

int calculate(int a, int b) {
    int c = a + b;
    int d = b * c;
    return a / d;
}
