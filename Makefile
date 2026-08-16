# tmux-cockpit — dev tasks.
.PHONY: install test

# Symlink the command-line-facing scripts (tmsg, wt-*) onto $PATH.
# Override the bin dir: `make install BIN=~/bin`.
install:
	scripts/link.sh $(BIN)

# Run the bats suite (unit + isolated-socket integration).
test:
	bats tests/
