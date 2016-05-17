#import <ObjFW/OFObject.h>
#import <ObjFW/OFException.h>

@class OFArray;

@interface OFException(WinBacktrace)

- (void)printDebugBacktrace;
- (OFArray *)backtraceInfo;

@end