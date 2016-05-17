#import <ObjFW/OFObject.h>
#import <ObjFW/OFException.h>


@interface WinCRTException: OFException
{
	PEXCEPTION_RECORD _record;
}

- (instancetype)initWithExceptionRecord:(PEXCEPTION_RECORD)record;
+ (instancetype)exceptionWithExceptionRecord:(PEXCEPTION_RECORD)record;

@end