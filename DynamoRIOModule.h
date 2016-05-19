#import <ObjFW/OFObject.h>
#import "DrMinGWModule.h"
#import "macros.h"

#include <windows.h>
#include <WinNT.h>
#include <dbghelp.h>
#include "dynamorio_types.h"

@class OFString;
@class OFArray;
@class OFDictionary;

@interface DynamoRIOModule: DrMinGWModule
{
	
	drsym_info_t _sym_info;
}

+ (instancetype)module;
+ (bool)loaded;

- (OFDictionary *)symbolInfoByName:(OFString *)name inModule:(OFString *)module;
- (OFDictionary *)symbolInfoAtAddress:(ptrdiff_t)offset inModule:(OFString *)module;

@end