#import <ObjFW/OFObject.h>
#import <ObjFW/OFException.h>


@class OFArray;
@class OFString;

@protocol WinBacktrace

+ (void)enablePostmortemDebug:(bool)yes_no;
+ (void)printFullCallStack:(bool)yes_no;

- (void)printDebugBacktrace;
- (OFArray *)backtraceInfo;
- (OFString *)stringFromDebugInfo:(OFDictionary *)info;

@end

LONG WINAPI __WinBacktrace_Exception_Filter(LPEXCEPTION_POINTERS info);
void __WinBacktrace_Uncaught_Exception_Handler(id exception);

@interface OFException (WinBacktrace) <WinBacktrace>



@end