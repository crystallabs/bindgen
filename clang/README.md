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

If on SuSE or Fedora `find_clang.cr` can't find it, run it as:

```
BINDGEN_DYNAMIC=1 crystal clang/find_clang.cr
```

### On Clang

The tool has one big flaw: It uses clang.  While clang is a good tool for this
job (I never tried the GCC equivalent for this), linking a tool using it isn't
much fun.  Second, we have to manually provide it with the system include paths.

For all of this, there's `find_clang.cr`.  It's a Crystal script figuring all of
this out.  It's used by build system, and is supposed to be portable.

## Tips for direct usage

You can see the whole command line by setting `VERBOSE=1` before calling
bindgen: `$ VERBOSE=1 lib/bindgen/tool.sh my-config.yml`.

This will output a large JSON document without any spaces.  To format the
output, you can use the [jq tool](https://stedolan.github.io/jq/), like this:
`$ clang/parser ... | jq . > output.json` The "output.json" will now be
formatted.  If you want to use the less program instead of your editor, you can
get it to show formatting with highlighting:
`$ clang/parser ... | jq . -C | less -R`
