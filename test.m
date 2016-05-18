#import <ObjFW/ObjFW.h>
#import "WinBacktrace.h"


@interface OFObject(TEST)

- (void)__test;
- (void)setInt:(int)a forFloat:(float)b;
- (void)OF__internalMethod;
+ (void)classMethod;
- (void)incorrectMethodDemangle__;
- (void)CRTException;

@end

@implementation OFObject(TEST)

- (void)__test
{
	@throw [OFException exception];
}

- (void)setInt:(int)a forFloat:(float)b
{
	@throw [OFException exception];
}

- (void)OF__internalMethod
{
	@throw [OFException exception];
}

+ (void)classMethod
{
	@throw [OFException exception];
}

- (void)incorrectMethodDemangle__
{
	@throw [OFException exception];
}

- (void)CRTException
{
	int i = 1;
  	i = i / 0;
}

@end;


int main(int argc, char const *argv[])
{
	//[OFException(WinBacktrace) enablePostmortemDebug:true];
	//[OFException printFullCallStack:true];

	WinBacktrace* plugin = [OFPlugin pluginFromFile:@"WinBacktrace"];

	
	OFObject* obj = [OFObject new];

	@try {
		[OFObject classMethod];

	}@catch(OFException* e) {
		[e printDebugBacktrace];
	}

	@try {
		[obj setInt:1 forFloat:5.0];

	}@catch(OFException* e) {
		[e printDebugBacktrace];
	}

	@try {
		[obj __test];

	} @catch(OFException* e) {
		[e printDebugBacktrace];
	}

	@try {
		[obj OF__internalMethod];

	}@catch(OFException* e) {
		[e printDebugBacktrace];
	}

	@try {
		[obj incorrectMethodDemangle__];
	}@catch(OFException* e) {
		[e printDebugBacktrace];
	}

	@try {
		[OFString stringWithArray:nil];
	}@catch(OFException* e) {
		[e printDebugBacktrace];
	}

	//[obj CRTException];

	//of_log(@"After exception");

	@throw [OFException exception];


	return 0;
}