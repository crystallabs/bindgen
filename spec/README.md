# Test infrastructure

Invoke `crystal spec` from the project root directory to run the tests.

## Configuration

You can force a specific C++ compiler through the `CC` environment variable:
`$ CC=clang++ crystal spec`.  The default C++ compiler is used otherwise.

## Unit tests

Unit tests reside in `bindgen/`, mirroring the structure from `src/bindgen`:

The file `src/bindgen/graph/node.cr` has its unit test in
`spec/bindgen/graph/node_spec.cr` - And so on.

Apart from this, unit tests work like normal.

## Integration tests

Integration tests do a complete run of bindgen, testing the whole behaviour
going from the input files to the resulting crystal program a user would write
using the generated bindings.

Integration tests reside in `integration/`, each having three files:

* `NAME_spec.cr` is the Crystal spec
* `NAME.cpp` is the C++ source code for this spec
* `NAME.yml` is the configuration file

**To create a new integration test** the easiest route is to copy these three
files from another spec.

Where `NAME` is the name of your integration test.  It's important that you keep
this scheme.

Temporary files are stored in `integration/tmp/`.  These are generated when
running an integration test:

* `tmp/NAME.cpp` the generated C++ wrapper code
* `tmp/NAME.o` the compiled C++ wrapper
* `tmp/NAME.cr` the generated Crystal wrapper code
* `tmp/NAME_test.cr` the Crystal test code for those bindings

## Clang tool tests

Tests for behaviour of the clang tool are stored in `clang/`.  These mostly
concern the tool giving the expected output for a given input.

To force the clang tool path set the `BINDGEN_BIN` environment variable.
If not set, the default `clang/parser` will be used.

Set `VERBOSE=1` to print the command line of each clang tool invocation.  The
clang tool tests then also keep their temporary input file.

## Testing against a specific LLVM version

The tests use whatever `clang/parser` was built against.  To pick one of
several installed LLVM versions, rebuild the tool first:

```
git clean -fdX clang
cd clang && cmake -DLLVM_DIR=/usr/lib/llvm-18/lib/cmake/llvm . && make
```

This also regenerates `integration/spec_base.yml`, which holds the compiler
and include paths used by the integration tests.
