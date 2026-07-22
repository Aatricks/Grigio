#ifndef CPrivateAPIs_h
#define CPrivateAPIs_h

#include <stdbool.h>
#include <stdint.h>
#include <CoreFoundation/CoreFoundation.h>

bool GrayscaleGlobalAPIAvailable(void);
void GrayscaleForceToGray(bool enabled);
bool GrayscaleUsesForceToGray(void);
void GrayscaleInstallCleanupHandlers(void);

bool GrayscaleManagedSpacesAPIAvailable(void);
CFArrayRef GrayscaleCopyManagedDisplaySpaces(void) CF_RETURNS_RETAINED;
CFStringRef GrayscaleCopyDisplayUUID(uint32_t display_id) CF_RETURNS_RETAINED;
uint64_t GrayscaleCurrentSpaceForDisplay(uint32_t display_id);
void GrayscaleAddWindowToSpace(uint32_t window_id, uint64_t space_id);
void GrayscaleRemoveWindowFromSpace(uint32_t window_id, uint64_t space_id);
CFArrayRef GrayscaleCopySpacesForWindow(uint32_t window_id) CF_RETURNS_RETAINED;

#endif
