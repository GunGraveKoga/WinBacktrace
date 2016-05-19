#import <ObjFW/ObjFW.h>
#import "WinBacktrace.h"

extern void objc_unregister_class(Class);

static bool __winbacktrace_postmortem_debug_enabled = false;
static bool __winbacktrace_print_full_call_stack = false;

static int __winbacktrace_print_full_call_stack_lock = 0;
static int __winbacktrace_postmortem_debug_enabled_lock = 0;

static void __attribute__((destructor))
unload(void)
{
	objc_unregister_class(objc_getClass("WinBacktrace"));
	objc_unregister_class(objc_getClass("DynamoRIOModule"));
	objc_unregister_class(objc_getClass("DrMinGWModule"));
	objc_unregister_class(objc_getClass("WinCRTException"));
}

@implementation WinBacktrace

- (void)enablePostmortemDebug:(bool)yes_no
{
	if (of_atomic_int_cmpswap(&__winbacktrace_postmortem_debug_enabled_lock, 0, 1)) {
		__winbacktrace_postmortem_debug_enabled = yes_no;
		__winbacktrace_postmortem_debug_enabled_lock = 0;
	}
}

- (void)printFullCallStack:(bool)yes_no
{
	if (of_atomic_int_cmpswap(&__winbacktrace_print_full_call_stack_lock, 0, 1)) {
		__winbacktrace_print_full_call_stack = yes_no;
		__winbacktrace_print_full_call_stack_lock = 0;
	}
}

+ (bool)postmortemDebug
{
	return __winbacktrace_postmortem_debug_enabled;
}

+ (bool)isPrintCallStack
{
	return __winbacktrace_print_full_call_stack;
}

@end

id init_plugin(void)
{
	return [[[WinBacktrace alloc] init] autorelease];
}