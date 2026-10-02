.PHONY: plugin modules clean

plugin:
	$(MAKE) -C spa-libcamera

modules:
	$(MAKE) -C dkms/dw9719-ipu3

clean:
	$(MAKE) -C spa-libcamera clean
	$(MAKE) -C dkms/dw9719-ipu3 clean
