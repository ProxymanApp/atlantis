TARGET := iphone:clang:latest:11.0
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = atlantis

atlantis_FILES = Tweak.xm \
	../Sources/Atlantis+Manual.swift \
	../Sources/DispatchQueue+Once.swift \
	../Sources/NetworkInjector.swift \
	../Sources/Transporter.swift \
	../Sources/Atlantis.swift \
	../Sources/Message.swift \
	../Sources/PackageIdentifier.swift \
	../Sources/Configuration.swift \
	../Sources/NetworkInjector+URLConnection.swift \
	../Sources/Packages.swift \
	../Sources/DataCompression.swift \
	../Sources/NetworkInjector+URLSession.swift \
	../Sources/Runtime.swift
atlantis_CFLAGS = -fobjc-arc
atlantis_LIBRARIES = applist

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	# Respring the device
	install.exec "killall -9 SpringBoard"
