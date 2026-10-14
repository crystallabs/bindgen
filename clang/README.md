# Clang tool

This directory contains the `clang` based C++ parser.  Its job is to parse the
wanted files, and returning the found information as JSON formatted data.

This tool is executed by `Bindgen::Parser::Runner`.  Basically, runner passes a ton
of arguments to this tool, and captures its standard output.

**Note**: If `clang++` is not in your `PATH`, provide the path to it through the
`CLANG` environment variable: `CLANG=/my/custom/clang++ cmake .`

## Supported Clang versions

All versions from **14** on.  Please file a ticket if it fails with a supported
version at
https://github.com/Papierkorb/bindgen/issues

## Build system

This tool uses `cmake`. Just run `cmake .` to build the usual `Makefile`. From
there you can run `make -j` to build. If you need to rebuild the `Makefile`
later, you might want to delete `CMakeCache.txt` first, to remove cmake's cache.

The static LLVM and Clang libraries are linked if they're installed, the shared
ones (`libclang-cpp` and `libLLVM`) otherwise.  Set the environment variable
`BINDGEN_DYNAMIC` to `1` or `0` to force shared or static linking:

```
BINDGEN_DYNAMIC=1 cmake . && make
```

The C++ standard library headers are those `clang++` uses by default.  To use
another one, pass the flag selecting it in `BINDGEN_CLANG_FLAGS`:

```
BINDGEN_CLANG_FLAGS=-stdlib=libc++ cmake . && make
```

### On Clang

The tool has one big flaw: It uses clang.  While clang is a good tool for this
job (I never tried the GCC equivalent for this), linking a tool using it isn't
much fun.  Second, we have to manually provide it with the system include paths.

For all of this, there's `find_clang.cr`.  It's a Crystal script figuring all of
this out.  It's used by build system, and is supposed to be portable.

## Tips for direct usage

The tool takes the file to parse, what to look for, and after `--` the
compiler flags:

```
clang/parser my_lib.h -c MyClass -e MyEnum -f 'my_func_.*' -m 'MY_MACRO_.*' -- -x c++ -std=c++17 -Iinclude
```

`-c` and `-e` name a class or enumeration and can be repeated, `-f` and `-m`
take a regular expression matching functions or macros.  Only what was asked
for ends up in the output.  If macros were found, the file is parsed a second
time to evaluate them.

You can see the whole command line by setting `VERBOSE=1` before calling
bindgen: `$ VERBOSE=1 lib/bindgen/tool.sh my-config.yml`.

This will output a large JSON document without any spaces.  To format the
output, you can use the [jq tool](https://stedolan.github.io/jq/), like this:
`$ clang/parser ... | jq . > output.json` The "output.json" will now be
formatted.  If you want to use the less program instead of your editor, you can
get it to show formatting with highlighting:
`$ clang/parser ... | jq . -C | less -R`
