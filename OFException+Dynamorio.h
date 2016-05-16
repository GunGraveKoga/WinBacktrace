#import <ObjFW/ObjFW.h>


@class OFException;
@class OFArray;

@interface OFException(DEBUG)
- (OFArray *)debugBacktrace;
@end

LONG WINAPI dbg_exception_filter(LPEXCEPTION_POINTERS info);
void DynamorioUncaughtExceptionHandler(id exception);

#define SET_DEBUG_INFO_IN_EXCEPTION_HANDLERS objc_setUncaughtExceptionHandler(DynamorioUncaughtExceptionHandler); \
                                              SetUnhandledExceptionFilter(dbg_exception_filter);
