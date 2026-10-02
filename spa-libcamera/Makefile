# PipeWire 1.6.2 spa/plugins/libcamera, plus the Surface NV12 mirror
# in libcamera-source.cpp. Build with this Makefile. PipeWire's meson
# file is not included; it only builds inside the PipeWire tree.
# https://github.com/PipeWire/pipewire/tree/1.6.2/spa/plugins/libcamera

CXX ?= g++
PKG_CFLAGS := $(shell pkg-config --cflags libpipewire-0.3 libcamera)
PKG_LIBS := $(shell pkg-config --libs libcamera)

CXXFLAGS ?= -O2 -fPIC -std=c++17 -Wall -Wno-unused-parameter
CPPFLAGS += $(PKG_CFLAGS)

SRCS = libcamera.c libcamera-manager.cpp libcamera-device.cpp libcamera-source.cpp
OBJS = $(SRCS:.cpp=.o)
OBJS := $(OBJS:.c=.o)

.PHONY: all clean
all: libspa-libcamera.so

libspa-libcamera.so: $(OBJS)
	$(CXX) -shared -o $@ $(OBJS) $(PKG_LIBS) -lpthread

%.o: %.cpp
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c -o $@ $<

%.o: %.c
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c -o $@ $<

clean:
	rm -f $(OBJS) libspa-libcamera.so
