#import <ObjFW/ObjFW.h>
#import "WinBacktrace.h"

extern void objc_unregister_class(Class);

static void __attribute__((destructor))
unload(void)
{
	objc_unregister_class(objc_getClass("WinBacktrace"));
}

@implementation WinBacktrace

@end

id init_plugin(void)
{
	return [[[WinBacktrace alloc] init] autorelease];
}