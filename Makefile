REBAR := $(shell which rebar3 2>/dev/null || which ./rebar3)
SUBMODULES = build_utils
SUBTARGETS = $(patsubst %,%/.git,$(SUBMODULES))

UTILS_PATH := build_utils
TEMPLATES_PATH := .

# Name of the service (I don't know why is needed by build_utils!)
SERVICE_NAME := payproc-errors-erlang

# Build image tag to be used
BUILD_IMAGE_TAG := 07d3946f8f005782697de20270ac58cdcd18b011

CALL_ANYWHERE := all submodules rebar-update compile xref lint dialyze clean distclean

CALL_W_CONTAINER := $(CALL_ANYWHERE) test

all: compile

-include $(UTILS_PATH)/make_lib/utils_container.mk

.PHONY: $(CALL_W_CONTAINER)

# CALL_ANYWHERE
$(SUBTARGETS): %/.git: %
	git submodule update --init $<
	touch $@

submodules: $(SUBTARGETS)

rebar-update:
	$(REBAR) update

compile: submodules rebar-update
	$(REBAR) compile

xref: submodules
	$(REBAR) xref

lint:
	elvis rock

dialyze: submodules
	$(REBAR) dialyzer

clean:
	$(REBAR) clean

distclean:
	$(REBAR) clean -a
	rm -rf _build

# CALL_W_CONTAINER
test: submodules
	$(REBAR) ct
