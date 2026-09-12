.PHONY: lint format format-check docs  clean

## Run HLint linter
lint:
	hlint src/ test/

## Format source code with Fourmolu
format:
	fourmolu -i src/ test/

## Check code formatting with Fourmolu
format-check:
	fourmolu -m check src/ test/

## Build Haddock documentation
docs:
	stack haddock --no-haddock-deps

## Clean build artifacts
clean:
	stack clean
