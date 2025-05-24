ifneq (,$(wildcard .env))
	include .env
	export
endif

.PHONY: format
format:
	forge fmt

.PHONY: format-check
format-check:
	forge fmt --check

.PHONY: test
test:
	forge test

.PHONY: build
build:
	forge build

	