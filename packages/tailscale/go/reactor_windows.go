//go:build windows

package tailscale

import (
	"errors"
	"unsafe"
)

var errWindowsReactorUnsupported = errors.New(
	"shared fd reactor is not supported on Windows",
)

// ReactorCreate keeps the native export surface linkable on unsupported
// Windows builds. Android, Linux, and Darwin use reactor.go instead.
func ReactorCreate() (int64, error) {
	return -1, errWindowsReactorUnsupported
}

func ReactorClose(int64) error {
	return errWindowsReactorUnsupported
}

func ReactorWake(int64) error {
	return errWindowsReactorUnsupported
}

func ReactorRegister(int64, int, int64, int) error {
	return errWindowsReactorUnsupported
}

func ReactorUpdate(int64, int, int64, int) error {
	return errWindowsReactorUnsupported
}

func ReactorUnregister(int64, int) error {
	return errWindowsReactorUnsupported
}

func ReactorWait(int64, unsafe.Pointer, int, int) (int, error) {
	return -1, errWindowsReactorUnsupported
}
