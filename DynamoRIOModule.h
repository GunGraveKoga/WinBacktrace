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

WINBACKTRACE_EXPORT OFString *const kModuleName;
WINBACKTRACE_EXPORT OFString *const kModuleAddress;
WINBACKTRACE_EXPORT OFString *const kModulePath;
WINBACKTRACE_EXPORT OFString *const kMangledSymbolName;
WINBACKTRACE_EXPORT OFString *const kDemangledSymbolName;
WINBACKTRACE_EXPORT OFString *const kSourceFileName;
WINBACKTRACE_EXPORT OFString *const kSourceFilePath;
WINBACKTRACE_EXPORT OFString *const kLineNumber;
WINBACKTRACE_EXPORT OFString *const kStackAddress;
WINBACKTRACE_EXPORT OFString *const kModuleOffset;
WINBACKTRACE_EXPORT OFString *const kSymbolStartOffset;
WINBACKTRACE_EXPORT OFString *const kSymbolEndOffset;

@interface DynamoRIOModule: DrMinGWModule
{
	
	drsym_info_t _sym_info;
}

+ (instancetype)module;
+ (bool)loaded;

- (OFArray *)backtraceWithStack:(void *[])stack depth:(size_t)depth;
- (OFDictionary *)symbolInfoByName:(OFString *)name inModule:(OFString *)module;

@end