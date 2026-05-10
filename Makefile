.PHONY: test format format-check ci

ci: format-check test

test:
	busted

format:
	stylua .

format-check:
	stylua --check .
