#!/bin/sh

# Paths, names and functions definitions
NSSDB="/etc/pki/nssdb/"
COOLKEY_NAME="CoolKey PKCS #11 Module"
COOLKEY_LIBRARY="libcoolkeypk11.so"
OPENSC_NAME="OpenSC PKCS #11 Module"
OPENSC_LIBRARY="opensc-pkcs11.so"

add_module() {
	NAME="$1"
	LIBRARY="$2"
	modutil -add "$NAME" -dbdir "$NSSDB" -libfile "$LIBRARY"
}
remove_module() {
	NAME="$1"
	modutil -delete "$NAME" -dbdir "$NSSDB" -force
}

# Parse arguments. If wrong, print usage
TARGET="$1"
if [ "$TARGET" = "" ]; then
	# Print currently installed module
	PRINT_CURRENT="1"
elif [ "$TARGET" = "opensc" ] || [ "$TARGET" = "coolkey" ]; then
	: # Correct arguments
else
	echo "Simple tool to switch between OpenSC and Coolkey PKCS#11 modules in main NSS DB."
	echo "Usage: $0 [coolkey|opensc]"
	echo "    [coolkey|opensc]   says which of the modules should be used."
	echo "                       The other one will be removed from database."
	echo
	echo "    If there is no argument specified, prints the current module in NSS DB"
	exit 255
fi

if [ ! -x /usr/bin/modutil ]; then
	echo "The modutil is not installed. Please install package nss-util"
	exit 255
fi

# Find the current library in NSS DB
CURRENT="" # none
LIBS=$(modutil -rawlist -dbdir "$NSSDB" | grep "^library=")
if echo "$LIBS" | grep "$COOLKEY_NAME" > /dev/null; then
	CURRENT="coolkey"
fi
if echo "$LIBS" | grep "$OPENSC_NAME" > /dev/null; then
	if [ -n "$CURRENT" ]; then
		CURRENT="opensc coolkey"
		echo "There are both modules in NSS DB, which is not recommended."
		echo "I will remove the other."
	else
		CURRENT="opensc"
	fi
fi

if [ "$PRINT_CURRENT" = "1" ]; then
	echo "$CURRENT"
	exit 0
fi

# Do we need to change something?
if [ "$CURRENT" = "$TARGET" ]; then
	echo "The requested module is already in the NSS DB"
	exit 0
fi

# Do the actual change
if [ "$TARGET" = "opensc" ]; then
	add_module "$OPENSC_NAME" "$OPENSC_LIBRARY"
	remove_module "$COOLKEY_NAME"
fi
if [ "$TARGET" = "coolkey" ]; then
	add_module "$COOLKEY_NAME" "$COOLKEY_LIBRARY"
	remove_module "$OPENSC_NAME"
fi
