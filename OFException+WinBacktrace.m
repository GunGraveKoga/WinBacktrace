#import <ObjFW/ObjFW.h>
#import "OFException+WinBacktrace.h"
#import "DrMinGWModule.h"
#import "DynamoRIOModule.h"

@implementation OFException(WinBacktrace)

- (OFArray *)debugBacktrace
{
	if (![DrMinGWModule loaded] || ![DynamoRIOModule loaded])
		return [self backtrace];

	OFArray* arr = nil;

	void* pool = objc_autoreleasePoolPush();

	DynamoRIOModule* module = [DynamoRIOModule module];

	arr = [module backtraceWithStack:_backtrace depth:OF_BACKTRACE_SIZE];

	[arr retain];

	objc_autoreleasePoolPop(pool);

	return [arr autorelease];
}

@end