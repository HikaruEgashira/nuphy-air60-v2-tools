SWIFTC ?= swiftc
BINS := bin/ble-scan bin/nrf-dfu bin/via-raw
all: $(BINS)
bin/%: Sources/%.swift
	@mkdir -p bin
	$(SWIFTC) -O -o $@ $<
clean:
	rm -rf bin
.PHONY: all clean
