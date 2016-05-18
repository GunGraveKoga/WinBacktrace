#import <ObjFW/OFObject.h>
#import "WinCRTException.h"

@class OFString;

OFString* WinExceptionDescription(DWORD _exception_code);

@interface WinCRTException(PRIVATE)

- (void)setBackTrace:(void* [])backtrace count:(size_t)count;

@end