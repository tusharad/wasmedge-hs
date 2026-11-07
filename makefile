.PHONY: all build test bench lint format format-check docs clean

all: build test

## Build library and executables with Stack
build:
	stack build

## Run test suite with Stack
test:
	stack test

## Run benchmarks with Stack
bench:
	stack bench

## Run HLint linter
lint:
	hlint src/ test/ examples/

## Format source code with Fourmolu
format:
	fourmolu -i src/ test/ examples/

## Check code formatting with Fourmolu
format-check:
	fourmolu -m check src/ test/ examples/

## Build Haddock documentation
docs:
	stack haddock --no-haddock-deps

## Clean build artifacts
clean:
	stack clean
