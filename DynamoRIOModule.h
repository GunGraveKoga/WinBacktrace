#import <ObjFW/OFObject.h>

#include <windows.h>
#include <WinNT.h>
#include <dbghelp.h>
#include "dynamorio_types.h"

@class OFString;
@class OFArray;
@class DrMinGWModule;

@interface DynamoRIOModule: OFObject
{
	DrMinGWModule* _mingwModule;
	DWORD _image;
  	STACKFRAME64 _stackframe;
  	CONTEXT _context;
  	HANDLE _process;
	HANDLE _thread;
	PSYMBOL_INFO _symbol;
	OFArray* _backtrace;
	drsym_info_t _sym_info;
}

+ (instancetype)module;
+ (bool)loaded;

- (OFArray *)backtraceWithStack:(void *[])stack depth:(size_t)depth;

@end