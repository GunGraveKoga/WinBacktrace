#import <ObjFW/ObjFW.h>
#import "OFException+WinBacktrace.h"
#import "DrMinGWModule.h"
#import "DynamoRIOModule.h"

static OFString* WinExceptionCodeToString(DWORD _exception_code) {
  switch(_exception_code) {
    case EXCEPTION_ACCESS_VIOLATION:
      return [OFString stringWithUTF8String:"EXCEPTION_ACCESS_VIOLATION"];
    case EXCEPTION_ARRAY_BOUNDS_EXCEEDED:
      return [OFString stringWithUTF8String:"EXCEPTION_ARRAY_BOUNDS_EXCEEDED"];
    case EXCEPTION_BREAKPOINT:
      return [OFString stringWithUTF8String:"EXCEPTION_BREAKPOINT"];
    case EXCEPTION_DATATYPE_MISALIGNMENT:
      return [OFString stringWithUTF8String:"EXCEPTION_DATATYPE_MISALIGNMENT"];
    case EXCEPTION_FLT_DENORMAL_OPERAND:
      return [OFString stringWithUTF8String:"EXCEPTION_FLT_DENORMAL_OPERAND"];
    case EXCEPTION_FLT_DIVIDE_BY_ZERO:
      return [OFString stringWithUTF8String:"EXCEPTION_FLT_DIVIDE_BY_ZERO"];
    case EXCEPTION_FLT_INEXACT_RESULT:
      return [OFString stringWithUTF8String:"EXCEPTION_FLT_INEXACT_RESULT"];
    case EXCEPTION_FLT_INVALID_OPERATION:
      return [OFString stringWithUTF8String:"EXCEPTION_FLT_INVALID_OPERATION"];
    case EXCEPTION_FLT_OVERFLOW:
      return [OFString stringWithUTF8String:"EXCEPTION_FLT_OVERFLOW"];
    case EXCEPTION_FLT_STACK_CHECK:
      return [OFString stringWithUTF8String:"EXCEPTION_FLT_STACK_CHECK"];
    case EXCEPTION_FLT_UNDERFLOW:
      return [OFString stringWithUTF8String:"EXCEPTION_FLT_UNDERFLOW"];
    case EXCEPTION_ILLEGAL_INSTRUCTION:
      return [OFString stringWithUTF8String:"EXCEPTION_ILLEGAL_INSTRUCTION"];
    case EXCEPTION_IN_PAGE_ERROR:
      return [OFString stringWithUTF8String:"EXCEPTION_IN_PAGE_ERROR"];
    case EXCEPTION_INT_DIVIDE_BY_ZERO:
      return [OFString stringWithUTF8String:"EXCEPTION_INT_DIVIDE_BY_ZERO"];
    case EXCEPTION_INT_OVERFLOW:
      return [OFString stringWithUTF8String:"EXCEPTION_INT_OVERFLOW"];
    case EXCEPTION_INVALID_DISPOSITION:
      return [OFString stringWithUTF8String:"EXCEPTION_INVALID_DISPOSITION"];
    case EXCEPTION_NONCONTINUABLE_EXCEPTION:
      return [OFString stringWithUTF8String:"EXCEPTION_NONCONTINUABLE_EXCEPTION"];
    case EXCEPTION_PRIV_INSTRUCTION:
      return [OFString stringWithUTF8String:"EXCEPTION_PRIV_INSTRUCTION"];
    case EXCEPTION_SINGLE_STEP:
      return [OFString stringWithUTF8String:"EXCEPTION_SINGLE_STEP"];
    case EXCEPTION_STACK_OVERFLOW:
      return [OFString stringWithUTF8String:"EXCEPTION_STACK_OVERFLOW"];
    default:
      return [OFString stringWithUTF8String:"UNKNOWN"];
  }

  return nil;
}

LONG WINAPI __WinBacktrace_Exception_Filter(LPEXCEPTION_POINTERS info) {

	PEXCEPTION_RECORD ExceptionRecord = info->ExceptionRecord;
    PCONTEXT ContextRecord = info->ContextRecord;

    void* pool = objc_autoreleasePoolPush();

    OFException* WinRTException = [OFException exception];

    if ([DrMinGWModule loaded] && [DynamoRIOModule loaded]) {

    	DynamoRIOModule* module = [DynamoRIOModule moduleWithContext:ContextRecord];

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

    	[of_stderr writeFormat:@"Runtime Error %@ was occured at address 0x%p\r\n", WinExceptionCodeToString(ExceptionRecord->ExceptionCode), ExceptionRecord->ExceptionAddress];

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

	of_log(@"%@", exception);
	[exception printDebugBacktrace];

	exit(1);
}

@implementation OFException(WinBacktrace)

- (void)printDebugBacktrace
{
	void* pool_ = objc_autoreleasePoolPush();

	OFArray* backtrace_ = nil;

	size_t idx = 0;

	if ((backtrace_ = [self backtraceInfo]) == nil) {
		backtrace_ = [self backtrace];

		

		for (OFString* stackAddress in backtrace_) {
			[of_stderr writeFormat:@"[%zu]:%@\r\n", idx, stackAddress];
			idx++;
		}

		objc_autoreleasePoolPop(pool_);
		return;
	}

	OFAutoreleasePool* pool = [OFAutoreleasePool new];
	OFMutableString* line = nil;

	[of_stderr writeFormat:@"\r\n\r\n"];
	for (OFDictionary* info in backtrace_) {
		line = [OFMutableString stringWithFormat:@"[%zu]:0x%p ", idx, [[info objectForKey:kStackAddress] uIntPtrValue]];

		if (![[info objectForKey:kModuleName] isEqual:@"Unknown"])
			[line appendString:[info objectForKey:kModuleName]];
		else
			[line appendUTF8String:"????"];

		[line appendFormat:@"(0x%p)", [[info objectForKey:kModuleAddress] uIntPtrValue]];

		[line appendUTF8String:" "];

		if ([info objectForKey:kDemangledSymbolName])
			[line appendString:[info objectForKey:kDemangledSymbolName]];
		else
			[line appendString:[info objectForKey:kMangledSymbolName]];

		[line appendFormat:@" +0x%p", [[info objectForKey:kModuleOffset] uIntPtrValue]];

		[line appendUTF8String:" "];

		if ([info objectForKey:kSourceFileName]) {

			[line appendUTF8String:"at "];

			[line appendString:[info objectForKey:kSourceFileName]];

			if ([info objectForKey:kLineNumber])
				[line appendFormat:@":%@", [info objectForKey:kLineNumber]];

		} else if ([info objectForKey:kSourceFilePath]) {

			[line appendUTF8String:"at "];

			[line appendString:[info objectForKey:kSourceFilePath]];

			if ([info objectForKey:kLineNumber])
				[line appendFormat:@":%@", [info objectForKey:kLineNumber]];

		}

		[of_stderr writeLine:line];

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
	if (![DrMinGWModule loaded] || ![DynamoRIOModule loaded])
		return nil;

	OFArray* info = nil;

	void* pool = objc_autoreleasePoolPush();

	DynamoRIOModule* module = [DynamoRIOModule module];

	info = [module backtraceWithStack:_backtrace depth:OF_BACKTRACE_SIZE];

	[info retain];

	objc_autoreleasePoolPop(pool);

	return [info autorelease];
}


@end