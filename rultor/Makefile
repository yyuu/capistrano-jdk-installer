
ALL := \
	rubygems.yml.asc \
	$(NULL)

.SUFFIXES: .yml.asc .yml

all: $(ALL)

.yml.yml.asc:
	gpg --trust-model always --armor --encrypt --recipient 9AF0FA4C $<
