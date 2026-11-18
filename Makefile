SWIFTC ?= swiftc
BINS := bin/ble-scan bin/nrf-dfu bin/via-raw bin/ddc bin/kvm-switch bin/input-source bin/snap
all: $(BINS)
bin/%: Sources/%.swift
	@mkdir -p bin
	$(SWIFTC) -O -o $@ $<
bin/ddc: Sources/ddc/main.swift Sources/shared/DDC.swift
	@mkdir -p bin
	$(SWIFTC) -O -o $@ $^
bin/kvm-switch: Sources/kvm-switch/main.swift Sources/shared/DDC.swift
	@mkdir -p bin
	$(SWIFTC) -O -o $@ $^
bin/snap: Sources/snap/main.swift Sources/shared/Landing.swift
	@mkdir -p bin
	$(SWIFTC) -O -o $@ $^
bin/landing-test: tests/landing-test/main.swift Sources/shared/Landing.swift
	@mkdir -p bin
	$(SWIFTC) -o $@ $^
test: bin/landing-test
	bin/landing-test tests/landing-cases.txt
clean:
	rm -rf bin
.PHONY: all clean test
