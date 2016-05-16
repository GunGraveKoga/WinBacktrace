#import <ObjFW/OFObject.h>

#include <windows.h>
#include <WinNT.h>
#include <dbghelp.h>

@class OFString;
@class OFArray;

@interface DrMinGWModule: OFObject
{
	DWORD _image;
  	STACKFRAME64 _stackframe;
  	CONTEXT _context;
  	HANDLE _process;
	HANDLE _thread;
	PSYMBOL_INFO _symbol;
	OFArray* _backtrace;
}

+ (instancetype)module;
+ (bool)loaded;

- (instancetype)initWithContext:(PCONTEXT)ctx;
- (void)setContext:(PCONTEXT)ctx;
- (OFString *)symbolFromAddress:(DWORD64)Address;
- (OFArray *)backtraceStackWithDepth:(size_t)depth;
- (bool)stackWalk;

@end