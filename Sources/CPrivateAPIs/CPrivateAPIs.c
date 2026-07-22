#include "CPrivateAPIs.h"

#include <signal.h>
#include <stdlib.h>
#include <unistd.h>

extern void CGDisplayForceToGray(bool enabled) __attribute__((weak_import));
extern bool CGDisplayUsesForceToGray(void) __attribute__((weak_import));

typedef uint32_t CGSConnectionID;
extern CGSConnectionID CGSMainConnectionID(void) __attribute__((weak_import));
extern CFArrayRef CGSCopyManagedDisplaySpaces(CGSConnectionID connection) __attribute__((weak_import));
extern void CGSAddWindowsToSpaces(CGSConnectionID connection, CFArrayRef windows, CFArrayRef spaces) __attribute__((weak_import));
extern void CGSRemoveWindowsFromSpaces(CGSConnectionID connection, CFArrayRef windows, CFArrayRef spaces) __attribute__((weak_import));
extern CFArrayRef CGSCopySpacesForWindows(CGSConnectionID connection, int mask, CFArrayRef windows) __attribute__((weak_import));
extern CFUUIDRef CGDisplayCreateUUIDFromDisplayID(uint32_t display_id) __attribute__((weak_import));
extern uint64_t CGSManagedDisplayGetCurrentSpace(CGSConnectionID connection, CFStringRef display) __attribute__((weak_import));

bool GrayscaleGlobalAPIAvailable(void) {
    return CGDisplayForceToGray != NULL && CGDisplayUsesForceToGray != NULL;
}

void GrayscaleForceToGray(bool enabled) {
    if (CGDisplayForceToGray != NULL) {
        CGDisplayForceToGray(enabled);
    }
}

bool GrayscaleUsesForceToGray(void) {
    if (CGDisplayUsesForceToGray == NULL) {
        return false;
    }
    return CGDisplayUsesForceToGray();
}

static void restore_color(void) {
    GrayscaleForceToGray(false);
}

static void handle_signal(int signal_number) {
    restore_color();
    _exit(128 + signal_number);
}

void GrayscaleInstallCleanupHandlers(void) {
    atexit(restore_color);
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);
    signal(SIGHUP, handle_signal);
}

bool GrayscaleManagedSpacesAPIAvailable(void) {
    return CGSMainConnectionID != NULL
        && CGSCopyManagedDisplaySpaces != NULL
        && CGSAddWindowsToSpaces != NULL
        && CGSRemoveWindowsFromSpaces != NULL
        && CGSCopySpacesForWindows != NULL
        && CGDisplayCreateUUIDFromDisplayID != NULL
        && CGSManagedDisplayGetCurrentSpace != NULL;
}

CFArrayRef GrayscaleCopyManagedDisplaySpaces(void) {
    if (!GrayscaleManagedSpacesAPIAvailable()) {
        return NULL;
    }
    return CGSCopyManagedDisplaySpaces(CGSMainConnectionID());
}

CFStringRef GrayscaleCopyDisplayUUID(uint32_t display_id) {
    if (CGDisplayCreateUUIDFromDisplayID == NULL) {
        return NULL;
    }
    CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(display_id);
    if (uuid == NULL) {
        return NULL;
    }
    CFStringRef uuid_string = CFUUIDCreateString(kCFAllocatorDefault, uuid);
    CFRelease(uuid);
    return uuid_string;
}

uint64_t GrayscaleCurrentSpaceForDisplay(uint32_t display_id) {
    if (!GrayscaleManagedSpacesAPIAvailable()) {
        return 0;
    }
    CFStringRef display_uuid = GrayscaleCopyDisplayUUID(display_id);
    if (display_uuid == NULL) {
        return 0;
    }
    uint64_t space_id = CGSManagedDisplayGetCurrentSpace(CGSMainConnectionID(), display_uuid);
    CFRelease(display_uuid);
    return space_id;
}

static CFArrayRef single_number_array(CFNumberType type, const void *value) {
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, type, value);
    const void *values[] = { number };
    CFArrayRef array = CFArrayCreate(kCFAllocatorDefault, values, 1, &kCFTypeArrayCallBacks);
    CFRelease(number);
    return array;
}

static void mutate_window_space(uint32_t window_id, uint64_t space_id, bool add) {
    if (!GrayscaleManagedSpacesAPIAvailable()) {
        return;
    }
    CFArrayRef windows = single_number_array(kCFNumberSInt32Type, &window_id);
    CFArrayRef spaces = single_number_array(kCFNumberSInt64Type, &space_id);
    if (add) {
        CGSAddWindowsToSpaces(CGSMainConnectionID(), windows, spaces);
    } else {
        CGSRemoveWindowsFromSpaces(CGSMainConnectionID(), windows, spaces);
    }
    CFRelease(windows);
    CFRelease(spaces);
}

void GrayscaleAddWindowToSpace(uint32_t window_id, uint64_t space_id) {
    mutate_window_space(window_id, space_id, true);
}

void GrayscaleRemoveWindowFromSpace(uint32_t window_id, uint64_t space_id) {
    mutate_window_space(window_id, space_id, false);
}

CFArrayRef GrayscaleCopySpacesForWindow(uint32_t window_id) {
    if (!GrayscaleManagedSpacesAPIAvailable()) {
        return NULL;
    }
    CFArrayRef windows = single_number_array(kCFNumberSInt32Type, &window_id);
    CFArrayRef spaces = CGSCopySpacesForWindows(CGSMainConnectionID(), 7, windows);
    CFRelease(windows);
    return spaces;
}
