#import <ObjFW/ObjFW.h>
#import "DynamoRIOModule.h"
#import "DrMinGWModule+PRIVATE.h"



typedef drsym_error_t (*drsym_lookup_symbol)(const char *modpath, const char *symbol, size_t *modoffs /*OUT*/, u_int flags);
typedef drsym_error_t (*drsym_lookup_address)(const char *modpath, size_t modoffs, drsym_info_t *info /*INOUT*/, u_int flags);
typedef drsym_error_t (*drsym_init)(const wchar_t * shmid);
typedef void* (*dr_standalone_init)(void);
typedef drsym_error_t (*drsym_exit)(void);

static HINSTANCE dllDrSyms = NULL;
static HINSTANCE dllDynamoRIO = NULL;

static drsym_init drsym_initPtr = NULL;
static dr_standalone_init dr_standalone_initPtr = NULL;
static drsym_exit drsym_exitPtr = NULL;
static drsym_lookup_symbol drsym_lookup_symbolPtr = NULL;
static drsym_lookup_address drsym_lookup_addressPtr = NULL;

static int __dynamorio_initialized = 0;
static bool __dynamorio_module_loaded = false;

@implementation DynamoRIOModule

+ (void)initialize
{
	if (self == [DynamoRIOModule class]) {
		if (of_atomic_int_cmpswap(&__dynamorio_initialized, 0, 1)) {

			if (NULL == dllDrSyms)
				dllDrSyms = LoadLibraryA("drsyms.dll");

			if (NULL == dllDrSyms) {
				of_log(@"Loading %s error", "drsyms.dll");
				return;
			}

			if (NULL == dllDynamoRIO)
				dllDynamoRIO = LoadLibraryA("dynamorio.dll");

			if (NULL == dllDrSyms) {
				of_log(@"Loading %s error", "dynamorio.dll");
				return;
			}

			dr_standalone_initPtr = (dr_standalone_init)GetProcAddress(dllDynamoRIO, "dr_standalone_init");
     		drsym_initPtr = (drsym_init)GetProcAddress(dllDrSyms, "drsym_init");
     		drsym_exitPtr = (drsym_exit)GetProcAddress(dllDrSyms, "drsym_exit");
     		drsym_lookup_symbolPtr = (drsym_lookup_symbol)GetProcAddress(dllDrSyms, "drsym_lookup_symbol");
     		drsym_lookup_addressPtr = (drsym_lookup_address)GetProcAddress(dllDrSyms, "drsym_lookup_address");

     		if (
     			!(
     				dr_standalone_initPtr != NULL
					&& drsym_initPtr != NULL
					&& drsym_exitPtr != NULL
					&& drsym_lookup_symbolPtr != NULL
					&& drsym_lookup_addressPtr != NULL
     				)
     			) {
     			@throw [OFInitializationFailedException exceptionWithClass:[DynamoRIOModule class]];
     		}

     		dr_standalone_initPtr();

     		__dynamorio_module_loaded = true;
		}
	}
}

- (void)dealloc
{
	if (_process != NULL)
		CloseHandle(_process);

	if (_thread != NULL)
		CloseHandle(_thread);

	[_backtrace release];

	[_mingwModule release];

	[super dealloc];
}

+ (void)unload
{
	FreeLibrary(dllDrSyms);
	FreeLibrary(dllDynamoRIO);
}

+ (instancetype)module
{
	return [[[self alloc] init] autorelease];
}

+ (bool)loaded
{
	return __dynamorio_module_loaded;
}

- (instancetype)init
{
	self = [super init];

	ZeroMemory(&_stackframe, sizeof(STACKFRAME64));

	_process = GetCurrentProcess();
	_thread = GetCurrentThread();

	_symbol = NULL;

	_backtrace = nil;

	memset(&_context, 0, sizeof(CONTEXT));
    _context.ContextFlags = CONTEXT_FULL;
    RtlCaptureContext(&_context);

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

    @try {
    	_mingwModule = [DrMinGWModule new];
    }@catch(id e) {
    	[self release];
    	@throw [OFInitializationFailedException exceptionWithClass:[DynamoRIOModule class]];
    }


    [_mingwModule setProcessHandle:_process];
    [_mingwModule setThreadHandle:_thread];

    [_mingwModule setContext:&_context];

	return self;
}

- (OFArray *)backtraceWithStack:(void *[])stack depth:(size_t)depth
{
	if (_backtrace != nil)
		return [[_backtrace retain] autorelease];

	OFMutableArray* array = [OFMutableArray arrayWithCapacity:depth];

	OFAutoreleasePool* pool = [OFAutoreleasePool new];

	size_t symbolSize = sizeof(SYMBOL_INFO) + (MAX_SYM_NAME * sizeof(char));
	char buffer[symbolSize];
	char nameBuffer[MAX_PATH];
    char fileBuffer[MAX_PATH];

	memset(buffer, 0, symbolSize);
	memset(&_sym_info, 0, sizeof(_sym_info));
	memset(nameBuffer, 0, MAX_PATH * sizeof(char));
	memset(fileBuffer, 0, MAX_PATH * sizeof(char));

	size_t modOffs = 0;

	for (size_t idx = 0; idx < depth; idx++) {

		_sym_info.struct_size = sizeof(_sym_info);
    	_sym_info.name = nameBuffer;
    	_sym_info.name_size = MAX_PATH * sizeof(char);
    	_sym_info.file = fileBuffer;
    	_sym_info.file_size = MAX_PATH * sizeof(char);

		HMODULE hModule = [_mingwModule moduleHandleFromAddress:(DWORD64)stack[idx]];
		OFString* moduleName = [_mingwModule moduleFileNameFromHandle:hModule];


		[_mingwModule setSymbol:(PSYMBOL_INFO)buffer];

		OFString* symbolName = [_mingwModule symbolNameFromAddress:(DWORD64)stack[idx]];

		if (symbolName != nil && ![moduleName isEqual:[OFString stringWithUTF8String:"Unknown"]]) {

			OFMutableString* description = [OFMutableString stringWithFormat:@"%zu %@ %p %@", idx, [moduleName lastPathComponent], stack[idx], symbolName];
			
			if (drsym_initPtr(NULL) == DRSYM_SUCCESS) {
				of_log(@"Desc %@ %@", moduleName, description);
				if (drsym_lookup_symbolPtr([moduleName UTF8String], [symbolName UTF8String], &modOffs, DRSYM_DEFAULT_FLAGS) == DRSYM_SUCCESS) {
					of_log(@"Desc %@ %@", moduleName, description);
					drsym_error_t ret = drsym_lookup_addressPtr([moduleName UTF8String], modOffs, &_sym_info, DRSYM_DEFAULT_FLAGS);

					if (ret == DRSYM_SUCCESS)
						[description appendFormat:@" +0x%p [%s : %llu]", modOffs, _sym_info.file, _sym_info.line];
					else if (ret == DRSYM_ERROR_LINE_NOT_AVAILABLE)
						[description appendFormat:@" +0x%p [%d : %d]", modOffs, _sym_info.start_offs, _sym_info.end_offs];
				}

				drsym_exitPtr();

			}

			[description makeImmutable];

			[array addObject:description];

		} else {
			if (![moduleName isEqual:[OFString stringWithUTF8String:"Unknown"]])
				[array addObject:[OFString stringWithFormat:@"%zu %@ %p %@", idx, [moduleName lastPathComponent], stack[idx], (symbolName != nil) ? symbolName : @"???"]];
			else
				[array addObject:[OFString stringWithFormat:@"%zu %@ %p %@", idx, moduleName, stack[idx], (symbolName != nil) ? symbolName : @"???"]];
		}


		[pool releaseObjects];

    	memset(buffer, 0, symbolSize);
		memset(&_sym_info, 0, sizeof(_sym_info));
		memset(nameBuffer, 0, MAX_PATH * sizeof(char));
		memset(fileBuffer, 0, MAX_PATH * sizeof(char));
		modOffs = 0;

	}

	[pool release];

	[array makeImmutable];

	_backtrace = array;

	return [[_backtrace retain] autorelease];
}


@end