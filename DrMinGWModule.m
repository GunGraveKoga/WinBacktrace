#import <ObjFW/ObjFW.h>
#import "DrMinGWModule.h"
#import "DrMinGWModule+PRIVATE.h"

static HINSTANCE dllMgwhelp = NULL;
static HINSTANCE dllPsapi = NULL;

typedef BOOL (WINAPI* DrMinGwSymInitialize)(HANDLE hProcess, PCSTR UserSearchPath, BOOL fInvadeProcess);
typedef BOOL (WINAPI* DrMinGwSymCleanup)(HANDLE hProcess);
typedef BOOL (WINAPI* DrMinGwSymFromAddr)(HANDLE hProcess, DWORD64 Address, PDWORD64 Displacement, PSYMBOL_INFO Symbol);
typedef BOOL (WINAPI* DrMinGwStackWalk64)(DWORD MachineType, HANDLE hProcess, HANDLE hThread, LPSTACKFRAME64 StackFrame, PVOID ContextRecord, PREAD_PROCESS_MEMORY_ROUTINE64 ReadMemoryRoutine, PFUNCTION_TABLE_ACCESS_ROUTINE64 FunctionTableAccessRoutine, PGET_MODULE_BASE_ROUTINE64 GetModuleBaseRoutine, PTRANSLATE_ADDRESS_ROUTINE64 TranslateAddress);
typedef DWORD64 (WINAPI* DrMinGwSymGetModuleBase64)(HANDLE hProcess, DWORD64 dwAddress);
typedef DWORD64 (WINAPI* DrMinGwSymSetOptions)(DWORD SymOptions);
typedef PVOID (WINAPI* DrMinGwSymFunctionTableAccess64)(HANDLE hProcess, DWORD64 AddrBase);
typedef DWORD (WINAPI* DrMinGwUnDecorateSymbolName)(PCSTR DecoratedName, PSTR UnDecoratedName, DWORD UndecoratedLength, DWORD Flags);
typedef BOOL (WINAPI* DrMinGwSymGetLineFromAddr64)(HANDLE hProcess, DWORD64 dwAddr, PDWORD pdwDisplacement, PIMAGEHLP_LINE64 Line);
typedef DWORD (WINAPI* DrMinGwGetModuleFileNameExW)(HANDLE  hProcess, HMODULE hModule, LPWSTR  lpFilename, DWORD   nSize);

static DrMinGwSymInitialize DrMinGwSymInitializePtr = NULL;
static DrMinGwStackWalk64 DrMinGwStackWalk64Ptr = NULL;
static DrMinGwSymCleanup DrMinGwSymCleanupPtr = NULL;
static DrMinGwSymFromAddr DrMinGwSymFromAddrPtr = NULL;
static DrMinGwSymGetModuleBase64 DrMinGwSymGetModuleBase64Ptr = NULL;
static DrMinGwSymFunctionTableAccess64 DrMinGwSymFunctionTableAccess64Ptr = NULL;
static DrMinGwUnDecorateSymbolName DrMinGwUnDecorateSymbolNamePtr = NULL;
static DrMinGwSymGetLineFromAddr64 DrMinGwSymGetLineFromAddr64Ptr = NULL;
static DrMinGwSymSetOptions DrMinGwSymSetOptionsPtr = NULL;
static DrMinGwGetModuleFileNameExW DrMinGwGetModuleFileNameExPtr = NULL;

static int __drmingw_initialized = 0;
static bool __drmingw_module_loaded = false;


@implementation DrMinGWModule

+ (void)initialize
{
	if (self == [DrMinGWModule class]) {
		if (of_atomic_int_cmpswap(&__drmingw_initialized, 0, 1)) {
			if (NULL == dllMgwhelp)
				dllMgwhelp = LoadLibraryA("mgwhelp.dll");

			if (NULL == dllMgwhelp) {
				of_log(@"Loading %s error", "mgwhelp.dll");
				return;
			}

			if (NULL == dllPsapi)
				dllPsapi = LoadLibraryA("psapi.dll");

			if (NULL == dllPsapi) {
				of_log(@"Loading %s error", "psapi.dll");
				return;
			}

			DrMinGwSymInitializePtr = (DrMinGwSymInitialize)GetProcAddress(dllMgwhelp, "SymInitialize");
			DrMinGwStackWalk64Ptr = (DrMinGwStackWalk64)GetProcAddress(dllMgwhelp, "StackWalk64");
			DrMinGwSymCleanupPtr = (DrMinGwSymCleanup)GetProcAddress(dllMgwhelp, "SymCleanup");
			DrMinGwSymFromAddrPtr = (DrMinGwSymFromAddr)GetProcAddress(dllMgwhelp, "SymFromAddr");
			DrMinGwSymGetModuleBase64Ptr = (DrMinGwSymGetModuleBase64)GetProcAddress(dllMgwhelp, "SymGetModuleBase64");
			DrMinGwSymFunctionTableAccess64Ptr = (DrMinGwSymFunctionTableAccess64)GetProcAddress(dllMgwhelp, "SymFunctionTableAccess64");
			DrMinGwUnDecorateSymbolNamePtr = (DrMinGwUnDecorateSymbolName)GetProcAddress(dllMgwhelp, "UnDecorateSymbolName");
			DrMinGwSymGetLineFromAddr64Ptr = (DrMinGwSymGetLineFromAddr64)GetProcAddress(dllMgwhelp, "SymGetLineFromAddr64");
			DrMinGwSymSetOptionsPtr = (DrMinGwSymSetOptions)GetProcAddress(dllMgwhelp, "SymSetOptions");
			DrMinGwGetModuleFileNameExPtr = (DrMinGwGetModuleFileNameExW)GetProcAddress(dllPsapi, "GetModuleFileNameExW");

			if (
				!(DrMinGwSymInitializePtr != NULL
				&& DrMinGwStackWalk64Ptr != NULL
				&& DrMinGwSymCleanupPtr != NULL
				&& DrMinGwSymFromAddrPtr != NULL
				&& DrMinGwSymGetModuleBase64Ptr != NULL
				&& DrMinGwSymFunctionTableAccess64Ptr != NULL
				&& DrMinGwUnDecorateSymbolNamePtr != NULL
				&& DrMinGwSymGetLineFromAddr64Ptr != NULL
				&& DrMinGwSymSetOptionsPtr != NULL
				&& DrMinGwGetModuleFileNameExPtr != NULL)
				) {
				@throw [OFInitializationFailedException exceptionWithClass:[DrMinGWModule class]];
			}


			__drmingw_module_loaded = true;
		}
	}
}

- (instancetype)init
{
	self = [super init];

	ZeroMemory(&_stackframe, sizeof(STACKFRAME64));

	_process = GetCurrentProcess();
	_thread = GetCurrentThread();

	_symbol = NULL;

	_backtrace = nil;

	return self;
}

- (void)dealloc
{
	DrMinGwSymCleanupPtr(_process);

	if (_process != NULL)
		CloseHandle(_process);

	if (_thread != NULL)
		CloseHandle(_thread);

	[_backtrace release];

	[super dealloc];
}

+ (void)unload
{
	FreeLibrary(dllMgwhelp);
	FreeLibrary(dllPsapi);
}

- (instancetype)initWithContext:(PCONTEXT)ctx
{
	self = [self init];

	[self setContext:ctx];

	return self;
}

- (void)setContext:(PCONTEXT)ctx
{
	if (ctx == NULL) {
    	memset(&_context, 0, sizeof(CONTEXT));
    	_context.ContextFlags = CONTEXT_FULL;
    	RtlCaptureContext(&_context);
  	} else {
    	memcpy(&_context, ctx, sizeof(CONTEXT));
  	}

  	DrMinGwSymInitializePtr(_process, NULL, TRUE);

#ifdef _M_IX86
  	_image = IMAGE_FILE_MACHINE_I386;
  	_stackframe.AddrPC.Offset = _context.Eip;
  	_stackframe.AddrPC.Mode = AddrModeFlat;
  	_stackframe.AddrFrame.Offset = _context.Ebp;
  	_stackframe.AddrFrame.Mode = AddrModeFlat;
  	_stackframe.AddrStack.Offset = _context.Esp;
  	_stackframe.AddrStack.Mode = AddrModeFlat;
#elif _M_X64
  	//#error !x86
  	_image = IMAGE_FILE_MACHINE_AMD64;
  	_stackframe.AddrPC.Offset = _context.Rip;
  	_stackframe.AddrPC.Mode = AddrModeFlat;
  	_stackframe.AddrFrame.Offset = _context.Rsp;
  	_stackframe.AddrFrame.Mode = AddrModeFlat;
  	_stackframe.AddrStack.Offset = _context.Rsp;
  	_stackframe.AddrStack.Mode = AddrModeFlat;
#elif _M_IA64
  	//#error !x86
  	_image = IMAGE_FILE_MACHINE_IA64;
  	_stackframe.AddrPC.Offset = _context.StIIP;
  	_stackframe.AddrPC.Mode = AddrModeFlat;
  	_stackframe.AddrFrame.Offset = _context.IntSp;
  	_stackframe.AddrFrame.Mode = AddrModeFlat;
  	_stackframe.AddrBStore.Offset = _context.RsBSP;
  	_stackframe.AddrBStore.Mode = AddrModeFlat;
  	_stackframe.AddrStack.Offset = _context.IntSp;
  	_stackframe.AddrStack.Mode = AddrModeFlat;
#endif
}

+ (instancetype)module
{
	return [[[self alloc] init] autorelease];
}

+ (instancetype)moduleWithContext:(PCONTEXT)ctx
{
	return [[[self alloc] initWithContext:ctx] autorelease];
}

+ (bool)loaded
{
	return __drmingw_module_loaded;
}

- (OFString *)symbolNameFromAddress:(DWORD64)Address
{

	DWORD64 displacement = 0;

	if (DrMinGwSymFromAddrPtr(_process, Address, &displacement, _symbol)) {
		return [OFString stringWithUTF8String:_symbol->Name];
	}

	return nil;

}

- (OFArray *)backtraceStackWithDepth:(size_t)depth
{
	if (_backtrace != nil)
		return [[_backtrace retain] autorelease];

	OFMutableArray* array = [[OFMutableArray alloc] initWithCapacity:depth];

	OFAutoreleasePool* pool = [OFAutoreleasePool new];

	
	size_t symbolSize = sizeof(SYMBOL_INFO) + (MAX_SYM_NAME * sizeof(char));
	char buffer[symbolSize];

	memset(buffer, 0, symbolSize);
	size_t idx = 0;

	while([self stackWalk]) {

		[self setSymbol:(PSYMBOL_INFO)buffer];

    	OFString* symbolName = [self symbolNameFromAddress:_stackframe.AddrPC.Offset];

    	[array addObject:[OFString stringWithFormat:@"[%i] %@ [0x%0llX]", idx, (symbolName != nil) ? symbolName : @"???", _stackframe.AddrPC.Offset]];

    	[pool releaseObjects];

    	depth--;

    	if (depth <= 0)
    		break;

    	memset(buffer, 0, symbolSize);
    	idx++;
	}

	[pool release];

	[array makeImmutable];

	_backtrace = array;

	return [[_backtrace retain] autorelease];
}

- (bool)stackWalk
{
	BOOL ret = DrMinGwStackWalk64Ptr(_image, _process, _thread, &_stackframe, &_context, NULL, DrMinGwSymFunctionTableAccess64Ptr, DrMinGwSymGetModuleBase64Ptr, NULL);

	return ret ? true : false;
}

- (OFString *)moduleFileNameFromHandle:(HMODULE)moduleHandle
{
	wchar_t buffer[MAX_PATH];
	size_t bufferSize = MAX_PATH * sizeof(wchar_t);

	DWORD ret = DrMinGwGetModuleFileNameExPtr(_process, moduleHandle, buffer, bufferSize);

	if (ret > 0)
		return [OFString stringWithUTF16String:(const of_char16_t *)buffer length:(size_t)ret];
	
	
	return [OFString stringWithUTF8String:"Unknown"];
}

- (HMODULE)moduleHandleFromAddress:(DWORD64)address
{
	return (HMODULE)(INT_PTR)DrMinGwSymGetModuleBase64Ptr(_process, address);
}

- (void)setProcessHandle:(HANDLE)process
{
	if (_process != NULL)
		CloseHandle(_process);

	_process = process;
}

- (void)setThreadHandle:(HANDLE)thread
{
	if (_thread != NULL)
		CloseHandle(_thread);

	_thread = thread;
}

- (void)setSymbol:(PSYMBOL_INFO)symbol
{
	_symbol = symbol;
	_symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
    _symbol->MaxNameLen = MAX_SYM_NAME;
}

@end