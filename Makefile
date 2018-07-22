ISO=NetBoot

# iPXE
.PHONY: ipxe-build
ipxe-build:
	make --makefile="./Makefile.ipxe" build

ipxe-clean:
	make --makefile="./Makefile.ipxe" clean

# VM
.PHONY: vm-clean
vm-clean:
	make --makefile="./Makefile.vm" clean

.PHONY: vm-ui
vm-ui:
	make --makefile="./Makefile.vm" ui

.PHONY: vm-create
vm-create:
	ISO=${ISO} make --makefile="./Makefile.vm" create

.PHONY: vm-destroy
vm-destroy:
	make --makefile="./Makefile.vm" destroy

.PHONY: vm-start
vm-start:
	ISO=${ISO} make --makefile="./Makefile.vm" start

.PHONY: vm-build
vm-build:
	ISO=${ISO} make --makefile="./Makefile.vm" build

# NetBoot
netboot-xyz-build:
	make --makefile="./Makefile.netboot-xyz" build

# All
.PHONY: clean
clean: ipxe-clean vm-clean

.PHONY: build
build: ipxe-build vm-build

.PHONY: help
help:
	grep -E "^\.PHONY:" "./Makefile" | cut -d" " -f2 | sort
