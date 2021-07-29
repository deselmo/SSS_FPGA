.PHONY : default host device clean \
         run emulator dev rtl push pull finish report profile profile% cleanprofile clean% cleanall

# VARIABLES ####################################################################
INTELFPGAOCLSDKROOT ?= /opt/intelFPGA_pro/19.1/hld

# target directory
TARGET_DIR   ?= bin
# architecture     [device | emulator | ]
ARCH         ?= device
# debug flags      [  0 |   1]
DEBUG        ?= 0
PROFILE      ?= 0
FAST_COMPILE ?= 0
# verbose output   [  0 |   1]
V            ?= 0
# aoc target board
BOARD        ?= a10s_ddr
# extra CXX flags
CXXFLAGS     ?=
# extra ARMCXX flags
AOCFLAGS     ?=
# aoc output binary extension
AOC_EXT      ?= aocx
# extra environment variable
EXTRA_ENV    ?=

# COMMANDS #####################################################################
CXX    := g++ -std=c++11
ARMCXX := arm-linux-gnueabihf-g++ -std=c++11
AOC    := aoc
AOCL   := aocl
RM     := rm -fr
MKDIR  := mkdir -p

# COMPILATION ##################################################################
INC_DIRS_HOST :=
LIB_DIRS_HOST :=
INCS_HOST     :=
SRCS_HOST     :=
SRCS_AOC      :=
LIBS_HOST     :=

# PROJECT LOGIC ################################################################
PROJECT := $(notdir $(CURDIR))

TARGET_AOC  := $(PROJECT).$(AOC_EXT)
TARGET_HOST := host

INC_DIRS_HOST += ../common/inc
SRCS_HOST     += $(wildcard host/src/*.cpp) \
                 $(wildcard ../common/src/AOCLUtils/*.cpp)
INCS_HOST     += $(wildcard ../common/inc/AOCLUtils/*.h) \
                 $(wildcard ../common/inc/acl/*.hpp)
LIBS_HOST     += rt pthread

SRCS_AOC      += $(wildcard device/*.cl)
INC_DIRS_AOC  += ../common/inc_aoc
INCS_AOC      += $(wildcard ../common/inc_aoc/*.cl)

_CXXFLAGS      += $(CXXFLAGS) -Wall -fPIC \
                 -DBINARY_FILE_NAME=\"$(PROJECT)\"
_AOCFLAGS      += $(AOCFLAGS) -board=$(BOARD) \
                  -report
_EXTRA_ENV     += $(EXTRA_ENV)

ifeq ($(DEBUG),1)
_CXXFLAGS += -DDEBUG -g
_AOCFLAGS += -DDEBUG -g
else
_CXXFLAGS += -O3
endif

ifeq ($(PROFILE),1)
_AOCFLAGS += -profile=all
endif

ifeq ($(FAST_COMPILE),1)
_AOCFLAGS += -fast-compile
endif

ifeq ($(ARCH),device)
CXX := $(ARMCXX)
_CXXFLAGS += -DARCH_DEVICE
_AOCFLAGS += -DARCH_DEVICE  -W
UNLINK := ACL_BOARD_VENDOR_PATH=
else
_CXXFLAGS += -Wno-ignored-attributes
ifeq ($(ARCH), simulator)
_CXXFLAGS += -DARCH_SIMULATOR
_AOCFLAGS += -DARCH_SIMULATOR -march=simulator -W
else
ifeq ($(ARCH), emulator)
_CXXFLAGS  += -DARCH_EMULATOR
_AOCFLAGS  += -DARCH_EMULATOR -march=emulator -emulator-channel-depth-model=strict -W
else
_CXXFLAGS  += -DARCH_EMULATOR -DARCH_FAST_EMULATOR
_CXXFLAGS  += -DPLATFORM="\"Intel(R) FPGA Emulation Platform for OpenCL(TM)\""
_AOCFLAGS  += -DARCH_EMULATOR -march=emulator -fast-emulator
_EXTRA_ENV += CL_CONTEXT_EMULATOR_DEVICE_INTELFPGA=1 CL_CONFIG_CHANNEL_DEPTH_EMULATION_MODE=strict
endif
endif
endif

AOCL_COMPILE_CONFIG := $(shell $(UNLINK) $(AOCL) compile-config)
AOCL_LINK_CONFIG    := $(shell $(UNLINK) $(AOCL) link-config) -lacl_emulator_kernel_rt

ifeq ($(V),1)
ECHO :=
else
ECHO := @
endif

# RULES ########################################################################
default : host device

host   : $(TARGET_DIR)/$(TARGET_HOST)
device : $(TARGET_DIR)/$(TARGET_AOC)

clean :
	$(ECHO)$(RM) $(TARGET_DIR)

$(TARGET_DIR)/$(TARGET_HOST) : $(SRCS_HOST) $(INCS_HOST)
	$(ECHO)$(MKDIR) $(TARGET_DIR)
	$(ECHO) $(_EXTRA_ENV) $(CXX) $(_CXXFLAGS) $(SRCS_HOST) \
    $(AOCL_COMPILE_CONFIG) \
    $(AOCL_LINK_CONFIG) \
    $(foreach D,$(INC_DIRS_HOST),-I$D) \
    $(foreach D,$(LIB_DIRS_HOST),-L$D) \
    $(foreach L,$(LIBS_HOST),-l$L) \
    -o $(TARGET_DIR)/$(TARGET_HOST)

$(TARGET_DIR)/$(TARGET_AOC) : $(SRCS_AOC) $(INCS_AOC)
	$(ECHO) $(_EXTRA_ENV) $(AOC) $(_AOCFLAGS) $(SRCS_AOC) -o $(TARGET_DIR)/$(TARGET_AOC) \
		$(foreach D,$(INC_DIRS_AOC),-I$D)
	$(ECHO)$(RM) $(TARGET_DIR)/*.temp


################################################################################
# EXTRA ########################################################################
# VARIABLES ####################################################################
ARGS        ?=
VIRT_DEVS   ?= 1
PRERUN_EMU  ?= env CL_CONTEXT_EMULATOR_DEVICE_INTELFPGA=$(VIRT_DEVS)
PRERUN_FEMU ?= env CL_CONFIG_CPU_EMULATE_DEVICES=$(VIRT_DEVS)
PRERUN_SIM  ?= env CL_CONTEXT_MPSIM_DEVICE_INTELFPGA=$(VIRT_DEVS)
PROFILE_EXT ?=

# COMMANDS #####################################################################
MAKE  := $(MAKE) --no-print-directory
OPEN  := xdg-open
CP    := rsync -azur
TESTF := test -f
FPGA  := socfpga:

# RULES ########################################################################
run : LD_LIBRARY_PATH := $(INTELFPGAOCLSDKROOT)/host/linux64/lib:$(LD_LIBRARY_PATH)
run : emu
	$(ECHO)$(PRERUN_EMU) bin_emu/$(TARGET_HOST) $(ARGS)

runfemu : LD_LIBRARY_PATH := $(INTELFPGAOCLSDKROOT)/host/linux64/lib:$(LD_LIBRARY_PATH)
runfemu : femu
	$(ECHO)$(PRERUN_FEMU) bin_femu/$(TARGET_HOST) $(ARGS)


runsim : LD_LIBRARY_PATH := $(INTELFPGAOCLSDKROOT)/host/linux64/lib:$(LD_LIBRARY_PATH)
runsim : sim
	$(ECHO)$(PRERUN_SIM) bin_sim/$(TARGET_HOST) $(ARGS)

emu :
	$(ECHO)$(MAKE) TARGET_DIR=bin_emu ARCH=emulator DEBUG=1
emu% :
	$(ECHO)$(MAKE) TARGET_DIR=bin_emu ARCH=emulator DEBUG=1 $*

femu :
	$(ECHO)$(MAKE) TARGET_DIR=bin_femu ARCH=fastemulator DEBUG=1
femu% :
	$(ECHO)$(MAKE) TARGET_DIR=bin_femu ARCH=fastemulator DEBUG=1 $*

sim :
	$(ECHO)$(MAKE) ARCH=simulator DEBUG=1 TARGET_DIR=bin_sim
sim% :
	$(ECHO)$(MAKE) ARCH=simulator DEBUG=1 TARGET_DIR=bin_sim $*

dev :
	$(ECHO)$(MAKE) TARGET_DIR=bin_dev ARCH=device DEBUG=1 PROFILE=1
dev% :
	$(ECHO)$(MAKE) TARGET_DIR=bin_dev ARCH=device DEBUG=1 PROFILE=1 $*

obj :
	$(MAKE) device DEBUG=0 AOC_EXT="aoco" AOCFLAGS="-c -g"
rtl :
	$(MAKE) device DEBUG=0 AOC_EXT="aocr" AOCFLAGS="-rtl -report -g"

push : default
	$(ECHO)$(CP) $(TARGET_DIR)/host $(TARGET_DIR)/$(TARGET_AOC) $(FPGA)$(PROJECT)/

pull :
	$(ECHO)$(MKDIR) $(TARGET_DIR)
	$(ECHO)$(CP) $(FPGA)$(PROJECT)/$* $(TARGET_DIR)/$*


%/report.html : $(SRCS_AOC)
	$(ECHO)$(MAKE) rtl -B

$(TARGET_DIR)/%.mon:
	$(ECHO)$(MAKE) pull
	$(ECHO)$(TESTF) $@


report : bin/$(PROJECT)/reports/report.html
	$(ECHO)$(OPEN) "bin/$(PROJECT)/reports/report.html"

profile : $(TARGET_DIR)/profile$(PROFILE_EXT).mon
	$(ECHO)$(AOCL) report $(TARGET_DIR)/$(PROJECT).aocx \
                        $(TARGET_DIR)/profile$(PROFILE_EXT).mon \
                        $(TARGET_DIR)/$(PROJECT).source &
profile% : 
	$(ECHO)$(MAKE) profile PROFILE_EXT=$*


cleanprofile :
	$(ECHO)$(RM) $(TARGET_DIR)/profile*

cleanall :
	$(ECHO)$(RM) bin bin_dev bin_emu bin_femu bin_sim aocl_program_library
