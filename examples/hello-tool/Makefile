ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TOOL_NAME = ios-build-lab-hello

ios-build-lab-hello_FILES = main.m
ios-build-lab-hello_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tool.mk
