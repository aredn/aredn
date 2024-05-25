include config.mk
include openwrt.mk

# get main- and subtarget name from TARGET
MAINTARGET=$(word 1, $(subst -, ,$(TARGET)))
SUBTARGET=$(word 2, $(subst -, ,$(TARGET)))
ALTTARGET=$(word 3, $(subst -, ,$(TARGET)))

GIT_BRANCH=$(shell git symbolic-ref HEAD | sed -e 's,.*/\(.*\),\1,')
GIT_COMMIT=$(shell git rev-parse --short HEAD)

# set dir and file names
TOP_DIR=$(shell pwd)
OPENWRT_DIR=$(TOP_DIR)/openwrt
TARGET_CONFIG=$(TOP_DIR)/configs/common.config $(TOP_DIR)/configs/$(MAINTARGET)-$(SUBTARGET)$(patsubst %,-%,$(ALTTARGET)).config
UMASK=umask 022

# set variables based on private or CircleCI build
ifeq ($(CIRCLECI),true)
$(info CircleCI build ...)
FW_VERSION=$(PRIVATE_BUILD_VERSION)-$(GIT_COMMIT)
else
FW_VERSION=$(PRIVATE_BUILD_VERSION)-$(GIT_BRANCH)-$(GIT_COMMIT)
endif

# test for existing $TARGET-config or abort
ifeq ($(wildcard $(TOP_DIR)/configs/$(TARGET).config),)
$(error config for $(TARGET) not defined)
endif

default: compile

# clone openwrt
$(OPENWRT_DIR): .stamp-openwrt-removed
	git clone $(OPENWRT_SRC) $(OPENWRT_DIR)
	cd $(OPENWRT_DIR); git checkout $(OPENWRT_COMMIT)
	ln -sf $(TOP_DIR)/patches $(OPENWRT_DIR)/
	ln -sf $(TOP_DIR)/files   $(OPENWRT_DIR)/
	touch .stamp-openwrt-cleaned
	rm -f .stamp-unpatched

# when updating openwrt.mk to point to another repo
.stamp-openwrt-removed: openwrt.mk
	rm -rf $(OPENWRT_DIR)
	rm -f .stamp*
	touch $@

# clean up openwrt working copy
openwrt-clean: stamp-clean-openwrt-cleaned .stamp-openwrt-cleaned
.stamp-openwrt-cleaned: | $(OPENWRT_DIR)
	cd $(OPENWRT_DIR); \
	  ./scripts/feeds clean && \
	  git clean -dff && git fetch && git reset --hard HEAD && \
	  rm -rf .config feeds.conf build_dir/target-* logs/
	rm -rf $(TOP_DIR)/results
	rm -rf $(TOP_DIR)/.pc
	rm -f .stamp-unpatched
	ln -sf $(TOP_DIR)/patches $(OPENWRT_DIR)/
	ln -sf $(TOP_DIR)/files   $(OPENWRT_DIR)/
	sed -i "s/^.*freifunk.*$$//" $(OPENWRT_DIR)/feeds.conf.default
	sed -i "s/luci.git$$/luci.git;openwrt-22.03/" $(OPENWRT_DIR)/feeds.conf.default
	touch $@

# update openwrt and checkout specified commit
openwrt-update: .stamp-openwrt-updated .stamp-unpatched
.stamp-openwrt-updated: stamp-clean-openwrt-updated .stamp-openwrt-cleaned
	cd $(OPENWRT_DIR); git checkout --detach $(OPENWRT_COMMIT)
	rm -f .stamp-unpatched
	touch $@

# feeds
$(OPENWRT_DIR)/feeds.conf: feeds.conf
	cp $(TOP_DIR)/feeds.conf $@
	cat $(OPENWRT_DIR)/feeds.conf.default >> $@

# update feeds
feeds-update: stamp-clean-feeds-updated .stamp-feeds-updated
.stamp-feeds-updated: $(OPENWRT_DIR)/feeds.conf
	cd $(OPENWRT_DIR); ./scripts/feeds uninstall -a
	cd $(OPENWRT_DIR); ./scripts/feeds update -a
	cd $(OPENWRT_DIR); ./scripts/feeds install libpam
	cd $(OPENWRT_DIR); ./scripts/feeds install libcap
	cd $(OPENWRT_DIR); ./scripts/feeds install jansson
	cd $(OPENWRT_DIR); ./scripts/feeds install libidn2
	cd $(OPENWRT_DIR); ./scripts/feeds install liblzma
	cd $(OPENWRT_DIR); ./scripts/feeds install libssh2
	cd $(OPENWRT_DIR); ./scripts/feeds install libidn
	cd $(OPENWRT_DIR); ./scripts/feeds install libopenldap
	cd $(OPENWRT_DIR); ./scripts/feeds install libgnutls
	cd $(OPENWRT_DIR); ./scripts/feeds install libnetsnmp
	cd $(OPENWRT_DIR); ./scripts/feeds install -p arednpackages olsrd
	cd $(OPENWRT_DIR); ./scripts/feeds install -p arednpackages vtun
	cd $(OPENWRT_DIR); ./scripts/feeds install -p arednpackages dd-wrt-ath10k-firmware
	cd $(OPENWRT_DIR); ./scripts/feeds install -p arednpackages prometheus-exporter
	cd $(OPENWRT_DIR); ./scripts/feeds install snmpd
	cd $(OPENWRT_DIR); ./scripts/feeds install curl
	cd $(OPENWRT_DIR); ./scripts/feeds install ntpclient
	cd $(OPENWRT_DIR); ./scripts/feeds install socat
	cd $(OPENWRT_DIR); ./scripts/feeds install luci-lib-base
	cd $(OPENWRT_DIR); ./scripts/feeds install luci-lib-nixio
	cd $(OPENWRT_DIR); ./scripts/feeds install luci-lib-ip
	cd $(OPENWRT_DIR); ./scripts/feeds install luci-lib-jsonc
	cd $(OPENWRT_DIR); ./scripts/feeds install luasocket
	cd $(OPENWRT_DIR); ./scripts/feeds install iperf3
	cd $(OPENWRT_DIR); ./scripts/feeds install micrond
	cd $(OPENWRT_DIR); ./scripts/feeds install mii-tool
	cd $(OPENWRT_DIR); ./scripts/feeds install mmc-utils
	cd $(OPENWRT_DIR); ./scripts/feeds install mtr
	touch $@

# prepare patch
pre-patch: stamp-clean-pre-patch .stamp-pre-patch
.stamp-pre-patch: $(wildcard $(TOP_DIR)/patches/*) | $(OPENWRT_DIR)
	rm -f .stamp-unpatched
	touch $@

# patch openwrt working copy
patch: stamp-clean-patched .stamp-patched
.stamp-patched: .stamp-pre-patch  .stamp-unpatched .stamp-feeds-updated
	cd $(OPENWRT_DIR); quilt push -a || [ $$? = 2 ] && true
	rm -rf $(OPENWRT_DIR)/tmp
	touch $@

.stamp-build_rev: .FORCE
ifneq (,$(wildcard .stamp-build_rev))
ifneq ($(shell cat .stamp-build_rev),$(FW_VERSION))
	echo $(FW_VERSION) | diff >/dev/null -q $@ - || echo -n $(FW_VERSION) >$@
endif
else
	echo -n $(FW_VERSION) >$@
endif

# openwrt config
$(OPENWRT_DIR)/.config: .stamp-feeds-updated $(TARGET_CONFIG) .stamp-build_rev always
	cat $(TARGET_CONFIG) >$(OPENWRT_DIR)/.config
	echo "CONFIG_VERSION_NUMBER=\"$(FW_VERSION)\"" >>$(OPENWRT_DIR)/.config
	echo "$(FW_VERSION)" >$(TOP_DIR)/files/etc/mesh-release
	echo "CONFIG_VERSION_REPO=\"$(PRIVATE_BUILD_PACKAGES)\"" >>$(OPENWRT_DIR)/.config
	$(UMASK); \
	  $(MAKE) -C $(OPENWRT_DIR) defconfig

# prepare openwrt .config
prepare: stamp-clean-prepared .stamp-prepared
.stamp-prepared: .stamp-patched .stamp-feeds-updated $(OPENWRT_DIR)/.config
	touch $@

# compile
compile: stamp-clean-compiled .stamp-compiled
.stamp-compiled: .stamp-prepared .stamp-feeds-updated | $(TOP_DIR)/firmware
	$(TOP_DIR)/scripts/tests-prebuild.sh
	$(UMASK); \
	  $(MAKE) -C $(OPENWRT_DIR) $(MAKE_ARGS)
	for FILE in `find $(TOP_DIR)/firmware/targets/$(MAINTARGET)/$(SUBTARGET) -path "*packages" -prune -o \( -type f -a \
	  ! \( -name "*factory.bin" -o -name "*sysupgrade.bin" -o -name "*x86*" -o -name "*initramfs*" -o -name sha256sums -o -name "*.buildinfo" -o -name "*.json" \) \
	  -print \)`; do rm $$FILE; \
	done;
	$(TOP_DIR)/scripts/tests-postbuild.sh

$(TOP_DIR)/firmware:
	ln -sf $(OPENWRT_DIR)/bin/ $(TOP_DIR)/firmware

stamp-clean-%:
	rm -f .stamp-$*

stamp-clean:
	rm -f .stamp-*

# unpatch needs "patches/" in openwrt
.stamp-unpatched:
# RC = 2 of quilt --> nothing to be done
	cd $(OPENWRT_DIR); quilt pop -a -f || [ $$? = 2 ] && true
	rm -rf $(OPENWRT_DIR)/tmp
	rm -f .stamp-patched
	touch $@

clean: stamp-clean .stamp-openwrt-cleaned

.PHONY: openwrt-clean openwrt-update patch feeds-update prepare compile stamp-clean clean always
.NOTPARALLEL:
.FORCE:
