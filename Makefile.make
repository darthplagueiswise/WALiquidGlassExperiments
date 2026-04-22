export THEOS := /home/ubuntu/theos
export THEOS_MAKE_PATH = $(THEOS)/makefiles

# Build no Linux (Ubuntu) — mesma config que funcionou na v5.8
export TARGET_LD = /usr/bin/clang -fuse-ld=lld
TARGET := iphone:clang:14.5:14.0
SDKVERSION = 14.5
ARCHS := arm64

include $(THEOS_MAKE_PATH)/common.mk

LIBRARY_NAME = InstagramTweaks

InstagramTweaks_FILES = Tweak.x fishhook.c
InstagramTweaks_CFLAGS = -fobjc-arc -fvisibility=hidden -Wno-deprecated-declarations -Wno-unused-function
InstagramTweaks_LDFLAGS = -framework Foundation -framework UIKit -framework CoreGraphics
InstagramTweaks_USE_MODULES = 0

include $(THEOS_MAKE_PATH)/library.mk
