
ALL := \
	rubygems.yml.asc \
	$(NULL)

NAME := $(shell git config --get remote.origin.url | sed -e 's/^.*github\.com.//' -e 's/\.git$$//')

.SUFFIXES: .yml.asc .yml

all: $(ALL)
	rultor encrypt -p "$(NAME)" $<
