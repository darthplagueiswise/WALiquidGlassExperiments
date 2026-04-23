TARGET := iphone:clang:16.2
INSTALL_TARGET_PROCESSES = WhatsApp
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WALiquidGlassExperiments

WALiquidGlassExperiments_FILES = Tweak.xm
WALiquidGlassExperiments_FRAMEWORKS = UIKit Foundation
WALiquidGlassExperiments_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk
