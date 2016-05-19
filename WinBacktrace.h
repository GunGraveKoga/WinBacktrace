#import <ObjFW/OFObject.h>
#import <ObjFW/OFPlugin.h>
#import "OFException+WinBacktrace.h"
#import "WinCRTException.h"
#import "DrMinGWModule.h"
#import "DynamoRIOModule.h"
#import "macros.h"


@interface WinBacktrace: OFPlugin

- (void)enablePostmortemDebug:(bool)yes_no;
- (void)printFullCallStack:(bool)yes_no;

+ (bool)postmortemDebug;
+ (bool)isPrintCallStack;

@end
