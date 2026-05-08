.PHONY: test format format-check

test:
	busted

format:
	stylua .

format-check:
	stylua --check .
