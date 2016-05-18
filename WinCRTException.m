#import <ObjFW/ObjFW.h>
#import "DrMinGWModule.h"
#import "DrMinGWModule+PRIVATE.h"
#import "DynamoRIOModule.h"
#import "WinCRTException.h"
#import "OFException+WinBacktrace.h"
#import "WinCRTException+PRIVATE.h"

OFString* WinExceptionDescription(DWORD _exception_code) {
  switch(_exception_code) {
    case EXCEPTION_ACCESS_VIOLATION:
      return [OFString stringWithUTF8String:"Access Violation"];
    case EXCEPTION_ARRAY_BOUNDS_EXCEEDED:
      return [OFString stringWithUTF8String:"Requested array element is out of bounds"];
    case EXCEPTION_BREAKPOINT:
      return [OFString stringWithUTF8String:"A breakpoint was encountered"];
    case EXCEPTION_DATATYPE_MISALIGNMENT:
      return [OFString stringWithUTF8String:"Data is misaligned"];
    case EXCEPTION_FLT_DENORMAL_OPERAND:
      return [OFString stringWithUTF8String:"One of the operands in a floating-point operation is denormal"];
    case EXCEPTION_FLT_DIVIDE_BY_ZERO:
      return [OFString stringWithUTF8String:"Floating-point value divided by a floating-point divisor of zero"];
    case EXCEPTION_FLT_INEXACT_RESULT:
      return [OFString stringWithUTF8String:"The result of a floating-point operation cannot be represented exactly as a decimal fraction"];
    case EXCEPTION_FLT_INVALID_OPERATION:
      return [OFString stringWithUTF8String:"Floating-point operation exception"];
    case EXCEPTION_FLT_OVERFLOW:
      return [OFString stringWithUTF8String:"The exponent of a floating-point operation is greater than the magnitude allowed by the corresponding type"];
    case EXCEPTION_FLT_STACK_CHECK:
      return [OFString stringWithUTF8String:"The stack overflowed or underflowed as the result of a floating-point operation"];
    case EXCEPTION_FLT_UNDERFLOW:
      return [OFString stringWithUTF8String:"The exponent of a floating-point operation is less than the magnitude allowed by the corresponding type"];
    case EXCEPTION_ILLEGAL_INSTRUCTION:
      return [OFString stringWithUTF8String:"Invalid instruction execution"];
    case EXCEPTION_IN_PAGE_ERROR:
      return [OFString stringWithUTF8String:"System was unable to load the page"];
    case EXCEPTION_INT_DIVIDE_BY_ZERO:
      return [OFString stringWithUTF8String:"Integer value divided by an integer divisor of zero"];
    case EXCEPTION_INT_OVERFLOW:
      return [OFString stringWithUTF8String:"The result of an integer operation caused a carry out of the most significant bit of the result"];
    case EXCEPTION_INVALID_DISPOSITION:
      return [OFString stringWithUTF8String:"An exception handler returned an invalid disposition to the exception dispatcher"];
    case EXCEPTION_NONCONTINUABLE_EXCEPTION:
      return [OFString stringWithUTF8String:"Continue execution after a noncontinuable exception occurred"];
    case EXCEPTION_PRIV_INSTRUCTION:
      return [OFString stringWithUTF8String:"Instruction is not allowed in the current machine mode"];
    case EXCEPTION_SINGLE_STEP:
      return [OFString stringWithUTF8String:"A trace trap or other single-instruction mechanism signaled that one instruction has been executed"];
    case EXCEPTION_STACK_OVERFLOW:
      return [OFString stringWithUTF8String:"Stack overflowed"];
    default:
      return [OFString stringWithUTF8String:"UNKNOWN"];
  }

  return nil;
}

@implementation WinCRTException

+ (void)load
{
  SetUnhandledExceptionFilter(__WinBacktrace_Exception_Filter);
  objc_setUncaughtExceptionHandler(__WinBacktrace_Uncaught_Exception_Handler);
}

- (instancetype)initWithExceptionRecord:(PEXCEPTION_RECORD)record
{
	self = [super init];

	_record = (PEXCEPTION_RECORD)malloc(sizeof(EXCEPTION_RECORD));

	if (_record == NULL) {
		[self release];

		@throw [OFInitializationFailedException exceptionWithClass:[WinCRTException class]];
	}

	memset(_record, 0, sizeof(EXCEPTION_RECORD));

	memcpy(_record, record, sizeof(EXCEPTION_RECORD));

	return self;
}

- (void)dealloc
{
	if (_record != NULL)
		free(_record);

	[super dealloc];
}

+ (instancetype)exceptionWithExceptionRecord:(PEXCEPTION_RECORD)record
{
	return [[[self alloc] initWithExceptionRecord:record] autorelease];
}

- (void)setBackTrace:(void* [])backtrace count:(size_t)count
{
	memset(_backtrace, 0, (sizeof(void*) * OF_BACKTRACE_SIZE));

	for (size_t idx = 0; idx < count; idx++) {
		_backtrace[idx] = backtrace[idx];
	}
}

- (OFString *)description
{
	OFMutableString* desc = [OFMutableString stringWithFormat:@"WinRuntime Error 0x%04x occured at address 0x%p!", _record->ExceptionCode, _record->ExceptionAddress];
  [desc appendFormat:@"\n%@.", WinExceptionDescription(_record->ExceptionCode)];

  if (_record->ExceptionCode == EXCEPTION_ACCESS_VIOLATION) {
        if (_record->ExceptionInformation[0] == 0)
          [desc appendString:@"\nAttempted to read the inaccessible data!"];
        else if (_record->ExceptionInformation[0] == 1)
          [desc appendString:@"\nAttempted to write to an inaccessible address!"];
        else if (_record->ExceptionInformation[0] == 8)
          [desc appendString:@"\nDEP violation!"];

      } else if (_record->ExceptionCode == EXCEPTION_IN_PAGE_ERROR) {
        if (_record->ExceptionInformation[0] == 0)
          [desc appendString:@"\nAttempted to read the inaccessible data!"];
        else if (_record->ExceptionInformation[0] == 1)
          [desc appendString:@"\nAttempted to write to an inaccessible address!"];
        else if (_record->ExceptionInformation[0] == 8)
          [desc appendString:@"\nDEP violation!"];

      }

      [desc makeImmutable];

      return desc;

}

@end