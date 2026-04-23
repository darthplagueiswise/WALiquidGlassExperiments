ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = WhatsApp
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WALiquidGlassExperiments

WALiquidGlassExperiments_FILES = Tweak.xm
WALiquidGlassExperiments_FRAMEWORKS = Foundation UIKit
WALiquidGlassExperiments_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
