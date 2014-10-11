
NAME := $(shell git config --get remote.origin.url | sed -e 's/^.*github\.com.//' -e 's/\.git$$//')

all: clean
	$(MAKE) build

clean:
	$(RM) *.asc

build: rubygems.yml
	rultor encrypt -p "$(NAME)" $<
