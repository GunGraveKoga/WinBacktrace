#import <ObjFW/ObjFW.h>
#import "OFException+WinBacktrace.h"
#import "DrMinGWModule.h"
#import "DynamoRIOModule.h"
#import "WinCRTException.h"
#import "WinCRTException+PRIVATE.h"

#include <inttypes.h>

static bool __winbacktrace_postmortem_debug_enabled = false;
static bool __winbacktrace_print_full_call_stack = false;

@interface OFException(DebugPrint)

- (void)printDebugInfo:(OFDictionary *)info number:(size_t)number;

@end

/* We provide control over many aspects of callstack formatting (i#290)
 * encoded in print_flags.
 * We put file:line in [] and absaddr <mod!offs> in ()
 *
 Example:
 *  0  suppress.exe!do_uninit_read+0x27 [e:\derek\drmemory\git\src\tests\suppress.c @ 53] (0x004011d7 <suppress.exe+0x11d7>)
 *  1  suppress.exe!uninit_test1+0xb [e:\derek\drmemory\git\src\tests\suppress.c @ 59] (0x0040119c <suppress.exe+0x119c>)
 *  2  suppress.exe!test+0xf [e:\derek\drmemory\git\src\tests\suppress.c @ 213] (0x00401070 <suppress.exe+0x1070>)
 *  3  suppress.exe!main+0x31 [e:\derek\drmemory\git\src\tests\suppress.c @ 247] (0x00401042 <suppress.exe+0x1042>)
 *  4  suppress.exe!__tmainCRTStartup+0x15e [f:\sp\vctools\crt_bld\self_x86\crt\src\crt0.c @ 327] (0x00401d87 <suppress.exe+0x1d87>)
 *  5  KERNEL32.dll!BaseProcessStart+0x27 (0x7d4e9982 <KERNEL32.dll+0x29982>)
 */

LONG WINAPI __WinBacktrace_Exception_Filter(LPEXCEPTION_POINTERS info) {

	PEXCEPTION_RECORD ExceptionRecord = info->ExceptionRecord;
    PCONTEXT ContextRecord = info->ContextRecord;

    void* pool = objc_autoreleasePoolPush();

    WinCRTException* WinRTException = [WinCRTException exceptionWithExceptionRecord:ExceptionRecord];

    if ([DrMinGWModule loaded] && [DynamoRIOModule loaded]) {

    	DynamoRIOModule* module = [DynamoRIOModule moduleWithContext:ContextRecord];

    	if (__winbacktrace_postmortem_debug_enabled)
    		[module miniDump:info];

		OFArray* stack = [module callectStackWithDepth:OF_BACKTRACE_SIZE];

		size_t depth = [stack count];

    	void* _stack[depth];

    	memset(_stack, 0, (sizeof(void*) * depth));

    	for (size_t idx = 0; idx < depth; idx++) {

    		_stack[idx] = (void*)[[stack objectAtIndex:idx] uIntPtrValue];

    	}

    	[WinRTException setBackTrace:_stack count:depth];

    	[WinRTException retain];

    	objc_autoreleasePoolPop(pool);

    	@throw [WinRTException autorelease];


    } else if ([DrMinGWModule loaded]) {

    	DrMinGWModule* module = [DrMinGWModule moduleWithContext:ContextRecord];

    	if (__winbacktrace_postmortem_debug_enabled)
    		[module miniDump:info];

    	OFArray* stack = [module callectStackWithDepth:OF_BACKTRACE_SIZE];

		size_t depth = [stack count];

    	void* _stack[depth];

    	memset(_stack, 0, (sizeof(void*) * depth));

    	for (size_t idx = 0; idx < depth; idx++) {

    		_stack[idx] = (void*)[[stack objectAtIndex:idx] uIntPtrValue];

    	}

    	[WinRTException setBackTrace:_stack count:depth];

    	[WinRTException retain];

    	objc_autoreleasePoolPop(pool);

    	@throw [WinRTException autorelease];

    } else {

    	[of_stderr writeFormat:@"Runtime Error 0x%04x %@ was occured at address 0x%p\r\n", ExceptionRecord->ExceptionCode, WinExceptionDescription(ExceptionRecord->ExceptionCode), ExceptionRecord->ExceptionAddress];

    	if (ExceptionRecord->ExceptionCode == EXCEPTION_ACCESS_VIOLATION) {
    		if (ExceptionRecord->ExceptionInformation[0] == 0)
    			[of_stderr writeLine:@"Attempted to read the inaccessible data!"];
    		else if (ExceptionRecord->ExceptionInformation[0] == 1)
    			[of_stderr writeLine:@"Attempted to write to an inaccessible address!"];
    		else if (ExceptionRecord->ExceptionInformation[0] == 8)
    			[of_stderr writeLine:@"DEP violation!"];

    	} else if (ExceptionRecord->ExceptionCode == EXCEPTION_IN_PAGE_ERROR) {
    		if (ExceptionRecord->ExceptionInformation[0] == 0)
    			[of_stderr writeLine:@"Attempted to read the inaccessible data!"];
    		else if (ExceptionRecord->ExceptionInformation[0] == 1)
    			[of_stderr writeLine:@"Attempted to write to an inaccessible address!"];
    		else if (ExceptionRecord->ExceptionInformation[0] == 8)
    			[of_stderr writeLine:@"DEP violation!"];

    	}
    }

    objc_autoreleasePoolPop(pool);
    
    return 0x1;

}

void __WinBacktrace_Uncaught_Exception_Handler(id exception) {

	wchar_t path[1024];
	OFConstantString* dateFormat = @"%A %d %B %Y %H:%M:%S";

	DWORD length = GetModuleFileNameW(NULL, path, 1024);
	OFString* executablePath = [OFString stringWithUTF16String:path length:(size_t)length];
	OFString* executableDir = [executablePath stringByDeletingLastPathComponent];
	OFString* executableName = [executablePath lastPathComponent];
	OFString* backtraceLogFile = [executableDir stringByAppendingPathComponent:[OFString stringWithFormat:@"%@_backtrace.log", [executableName stringByDeletingPathExtension]]];

	OFFile* backtrace = [OFFile fileWithPath:[backtraceLogFile stringByStandardizingPath] mode:@"a+"];

	[of_stderr writeLine:[exception description]];
	
	[backtrace writeFormat:@"%@ %@ GMT+0:\n\n", executableName, [[OFDate date] dateStringWithFormat:dateFormat]];
	[backtrace writeString:@"========================START=========================\n\n"];
	[backtrace writeFormat:@"PID %d TID 0x%llx <%@>\n\n", GetCurrentProcessId(), GetCurrentThreadId(), [[OFThread currentThread] name]];
	[backtrace writeLine:[exception description]];
	[backtrace writeString:@"\n\n"];
	[of_stderr writeString:@"\r\n\r\n"];
	OFArray* stackInfo = [exception backtraceInfo];

	size_t idx = 0;
	for (OFDictionary* info in stackInfo) {
		[exception printDebugInfo:info  number:idx];

		[backtrace writeFormat:@"%zu %@\n", idx, [exception stringFromDebugInfo:info]];

		idx++;
	}
	[of_stderr writeString:@"\r\n\r\n"];
	[backtrace writeString:@"\n\n"];

	if (__winbacktrace_print_full_call_stack) {
		if ([DrMinGWModule loaded]) {

			[backtrace writeString:@"Stack:\n\n"];

			OFArray* stack = nil;

			if ([DynamoRIOModule loaded]) {
				DynamoRIOModule* module = [DynamoRIOModule moduleWithContext:NULL];

				stack = [module backtraceStackWithDepth:256];

			} else {
				DrMinGWModule* module = [DrMinGWModule moduleWithContext:NULL];

				stack = [module backtraceStackWithDepth:256];
			}
			idx = 0;
			for (OFDictionary* i in stack){
				[backtrace writeLine:[OFString stringWithFormat:@"%zu %@", idx, [exception stringFromDebugInfo:i]]];
				idx++;
			}
		}
	}

	[backtrace writeString:@"========================END=========================\n\n"];
	[backtrace close];

	abort();
}

@implementation OFException (WinBacktrace)

+ (void)enablePostmortemDebug:(bool)yes_no
{
	__winbacktrace_postmortem_debug_enabled = yes_no;
}

+ (void)printFullCallStack:(bool)yes_no
{
	__winbacktrace_print_full_call_stack = yes_no;
}

- (void)printDebugBacktrace
{
	void* pool_ = objc_autoreleasePoolPush();

	OFArray* backtrace_ = nil;

	size_t idx = 0;

	if ((backtrace_ = [self backtraceInfo]) == nil) {
		backtrace_ = [self backtrace];

		[of_stderr writeFormat:@"\r\n\r\n"];

		for (OFString* stackAddress in backtrace_) {
			[of_stderr writeFormat:@"%zu %@\r\n", idx, stackAddress];
			idx++;
		}

		[of_stderr writeFormat:@"\r\n\r\n"];

		objc_autoreleasePoolPop(pool_);
		return;
	}

	OFAutoreleasePool* pool = [OFAutoreleasePool new];

	[of_stderr writeFormat:@"\r\n\r\n"];
	for (OFDictionary* info in backtrace_) {
		
		[self printDebugInfo:info number:idx];

		[pool releaseObjects];
		idx++;
	}

	[pool release];

	[of_stderr writeFormat:@"\r\n\r\n"];

	objc_autoreleasePoolPop(pool_);
	return;
}

- (OFArray *)backtraceInfo
{
	OFArray* info = nil;

	void* pool = objc_autoreleasePoolPush();

	if (![DynamoRIOModule loaded]) {
		if (![DrMinGWModule loaded])
			return nil;

		DrMinGWModule* module = [DrMinGWModule moduleWithContext:NULL];

    	info = [module backtraceWithStack:_backtrace depth:OF_BACKTRACE_SIZE];

		[info retain];

		objc_autoreleasePoolPop(pool);

		return [info autorelease];

	}

	

	DynamoRIOModule* module = [DynamoRIOModule module];

	info = [module backtraceWithStack:_backtrace depth:OF_BACKTRACE_SIZE];

	[info retain];

	objc_autoreleasePoolPop(pool);

	return [info autorelease];
}

- (void)printDebugInfo:(OFDictionary *)info  number:(size_t)number
{
	[of_stderr writeFormat:@"%zu %@\r\n", 
		number,
		[self stringFromDebugInfo:info]
	];
}

- (OFString *)stringFromDebugInfo:(OFDictionary *)info
{
	return [OFString stringWithFormat:@"%@!%@+0x%x  [%@ @ %llu]  (0x%p <%@+0x%p>)", 
		[[info objectForKey:kModuleName] isEqual:@"Unknown"] ? @"????" : [info objectForKey:kModuleName],
		([info objectForKey:kDemangledSymbolName] != nil) ? [info objectForKey:kDemangledSymbolName] : ([info objectForKey:kMangledSymbolName] != nil) ? [info objectForKey:kMangledSymbolName] : @"???",
		(ptrdiff_t)([[info objectForKey:kStackAddress] uIntPtrValue] - [[info objectForKey:kModuleAddress] uIntPtrValue] - [[info objectForKey:kModuleOffset] uIntPtrValue]),
		([info objectForKey:kSourceFilePath] != nil) ? [info objectForKey:kSourceFilePath] : @"???",
		([info objectForKey:kLineNumber] != nil) ? [[info objectForKey:kLineNumber] uInt64Value] : 0,
		[[info objectForKey:kStackAddress] uIntPtrValue],
		[[info objectForKey:kModuleName] isEqual:@"Unknown"] ? @"????" : [info objectForKey:kModuleName],
		(ptrdiff_t)([[info objectForKey:kStackAddress] uIntPtrValue] - [[info objectForKey:kModuleAddress] uIntPtrValue])
	];
}


@end