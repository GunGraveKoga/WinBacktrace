#import <ObjFW/ObjFW.h>
#import "OFException+WinBacktrace.h"
#import "DrMinGWModule.h"
#import "DynamoRIOModule.h"

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