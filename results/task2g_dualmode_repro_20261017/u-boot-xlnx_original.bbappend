FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " file://platform-top.h file://bsp.cfg"

# Task 2g signed FIT verification prototype
SRC_URI:append = " file://task2g-verified-boot.cfg"
