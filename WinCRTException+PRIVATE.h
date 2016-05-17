#import "WinCRTException.h"

@interface WinCRTException(PRIVATE)

- (void)setBackTrace:(void* [])backtrace count:(size_t)count;

@end