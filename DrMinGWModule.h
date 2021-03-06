#import <ObjFW/OFObject.h>
#import "macros.h"

#include <windows.h>
#include <WinNT.h>
#include <dbghelp.h>

@class OFString;
@class OFArray;

WINBACKTRACE_EXPORT OFString *const kModuleName;
WINBACKTRACE_EXPORT OFString *const kModuleAddress;
WINBACKTRACE_EXPORT OFString *const kModulePath;
WINBACKTRACE_EXPORT OFString *const kMangledSymbolName;
WINBACKTRACE_EXPORT OFString *const kDemangledSymbolName;
WINBACKTRACE_EXPORT OFString *const kSourceFileName;
WINBACKTRACE_EXPORT OFString *const kSourceFilePath;
WINBACKTRACE_EXPORT OFString *const kLineNumber;
WINBACKTRACE_EXPORT OFString *const kLineOffset;
WINBACKTRACE_EXPORT OFString *const kStackAddress;
WINBACKTRACE_EXPORT OFString *const kModuleOffset;
WINBACKTRACE_EXPORT OFString *const kSymbolStartOffset;
WINBACKTRACE_EXPORT OFString *const kSymbolEndOffset;

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
+ (instancetype)moduleWithContext:(PCONTEXT)ctx;
+ (bool)loaded;

- (instancetype)initWithContext:(PCONTEXT)ctx;
- (void)setContext:(PCONTEXT)ctx;
- (OFString *)symbolNameFromAddress:(DWORD64)Address;
- (OFString *)moduleFileNameFromHandle:(HMODULE)moduleHandle;
- (HMODULE)moduleHandleFromAddress:(DWORD64)address;
- (OFArray *)backtraceStackWithDepth:(size_t)depth;
- (OFArray *)backtraceWithStack:(void *[])stack depth:(size_t)depth;
- (OFArray *)callectStackWithDepth:(size_t)depth;
- (bool)stackWalk;
- (void)miniDump:(PEXCEPTION_POINTERS)exInfo;

@end