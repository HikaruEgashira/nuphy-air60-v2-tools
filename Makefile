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
test: Tests/snap/main.swift Sources/snap.swift
	@mkdir -p bin/test
	sed -n '/^\/\/ BEGIN pickLanding/,/^\/\/ END pickLanding/p' Sources/snap.swift | (echo 'import Foundation'; cat) > bin/test/pickLanding.swift
	$(SWIFTC) -o bin/test/snap-tests Tests/snap/main.swift bin/test/pickLanding.swift
	bin/test/snap-tests
clean:
	rm -rf bin
.PHONY: all clean test
