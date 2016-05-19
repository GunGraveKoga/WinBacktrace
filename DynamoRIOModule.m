#import <ObjFW/ObjFW.h>
#import "DynamoRIOModule.h"
#import "DrMinGWModule+PRIVATE.h"
#import "objc_demangle.h"

typedef drsym_error_t (*drsym_lookup_symbol)(const char *modpath, const char *symbol, size_t *modoffs /*OUT*/, u_int flags);
typedef drsym_error_t (*drsym_lookup_address)(const char *modpath, size_t modoffs, drsym_info_t *info /*INOUT*/, u_int flags);
typedef size_t (*drsym_demangle_symbol)(char *dst, size_t dst_sz, const char *mangled, u_int flags);
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
static drsym_demangle_symbol drsym_demangle_symbolPtr = NULL;

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
     		drsym_demangle_symbolPtr = (drsym_demangle_symbol)GetProcAddress(dllDrSyms, "drsym_demangle_symbol");

     		if (
     			!(
     				dr_standalone_initPtr != NULL
					&& drsym_initPtr != NULL
					&& drsym_exitPtr != NULL
					&& drsym_lookup_symbolPtr != NULL
					&& drsym_lookup_addressPtr != NULL
					&& drsym_demangle_symbolPtr != NULL
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

	[self setContext:NULL];

	return self;
}

- (instancetype)initWithContext:(PCONTEXT)ctx
{
	self = [super init];

	[self setContext:ctx];

	return self;
}

+ (instancetype)moduleWithContext:(PCONTEXT)ctx
{
	return [[[self alloc] initWithContext:ctx] autorelease];
}

- (OFArray *)backtraceWithStack:(void *[])stack depth:(size_t)depth
{
	if (_backtrace != nil)
		return [[_backtrace retain] autorelease];

	OFMutableArray* array = [[OFMutableArray alloc] initWithCapacity:depth];

	OFAutoreleasePool* pool = [OFAutoreleasePool new];

	size_t symbolSize = sizeof(SYMBOL_INFO) + (MAX_SYM_NAME * sizeof(char));
	char buffer[symbolSize];

	memset(buffer, 0, symbolSize);

	OFMutableDictionary* addressInfo = nil;

	for (size_t idx = 0; idx < depth; idx++) {

		if (stack[idx] == NULL)
			break;

		addressInfo = [OFMutableDictionary dictionary];

		HMODULE hModule = [self moduleHandleFromAddress:(DWORD64)stack[idx]];
		OFString* moduleName = [self moduleFileNameFromHandle:hModule];

		if (![moduleName isEqual:[OFString stringWithUTF8String:"Unknown"]]) {

			

			[addressInfo setObject:moduleName forKey:kModulePath];
			[addressInfo setObject:[moduleName lastPathComponent] forKey:kModuleName];

			[addressInfo setObject:[OFNumber numberWithUIntPtr:(uintptr_t)stack[idx]] forKey:kStackAddress];
			[addressInfo setObject:[OFNumber numberWithUIntPtr:(uintptr_t)hModule] forKey:kModuleAddress];

			ptrdiff_t offset = ((uintptr_t)stack[idx] - (uintptr_t)hModule);

			OFDictionary* stackInfo = [self symbolInfoAtAddress:offset inModule:moduleName];

			if (stackInfo != nil) {

				for (OFString* key in [stackInfo allKeys]) {

					[addressInfo setObject:[stackInfo objectForKey:key] forKey:key];

				}
			}

			[addressInfo makeImmutable];

			[array addObject:addressInfo];

		}

		addressInfo = [OFMutableDictionary dictionary];

		[addressInfo setObject:[OFNumber numberWithUIntPtr:(uintptr_t)hModule] forKey:kModuleAddress];
		

		[self setSymbol:(PSYMBOL_INFO)buffer];

		OFString* symbolName = [self symbolNameFromAddress:(DWORD64)stack[idx]];
		
		if (![moduleName isEqual:[OFString stringWithUTF8String:"Unknown"]]) {

			[addressInfo setObject:moduleName forKey:kModulePath];
			[addressInfo setObject:[moduleName lastPathComponent] forKey:kModuleName];

		} else {

			[addressInfo setObject:moduleName forKey:kModuleName];
		}

		[addressInfo setObject:[OFNumber numberWithUIntPtr:(uintptr_t)stack[idx]] forKey:kStackAddress];

		if (symbolName != nil && ![moduleName isEqual:[OFString stringWithUTF8String:"Unknown"]]) {

			OFDictionary* symbolInfo = [self symbolInfoByName:symbolName inModule:moduleName];

			if (symbolInfo != nil) {

				for (OFString* key in [symbolInfo allKeys]) {
					[addressInfo setObject:[symbolInfo objectForKey:key] forKey:key];
				}
			} else {

				[addressInfo setObject:symbolName forKey:kMangledSymbolName];
				[addressInfo setObject:objc_demangle(symbolName) forKey:kDemangledSymbolName];
			}

		} else {
			if (symbolName != nil) {
				[addressInfo setObject:symbolName forKey:kMangledSymbolName];
				[addressInfo setObject:objc_demangle(symbolName) forKey:kDemangledSymbolName];
			}
		}

		[addressInfo makeImmutable];

		[array addObject:addressInfo];


		[pool releaseObjects];

    	memset(buffer, 0, symbolSize);

	}

	[pool release];

	[array makeImmutable];

	_backtrace = array;

	return [[_backtrace retain] autorelease];
}

- (OFDictionary *)symbolInfoByName:(OFString *)name inModule:(OFString *)module
{
	if (module == nil || [module length] == 0)
		return nil;

	OFMutableDictionary* result = [OFMutableDictionary dictionary];

	OFAutoreleasePool* pool = [OFAutoreleasePool new];

	if (drsym_initPtr(NULL) == DRSYM_SUCCESS) {
		size_t modOffs = 0;
		char* nameBuffer = (char*)__builtin_alloca(sizeof(char) * (MAX_PATH * 4));
    	char* fileBuffer = (char*)__builtin_alloca(sizeof(char) * (MAX_PATH * 4));

		memset(&_sym_info, 0, sizeof(_sym_info));
		memset(nameBuffer, 0, (MAX_PATH * 4) * sizeof(char));
		memset(fileBuffer, 0, (MAX_PATH * 4) * sizeof(char));

		if (drsym_lookup_symbolPtr([module UTF8String], [name UTF8String], &modOffs, DRSYM_DEFAULT_FLAGS) == DRSYM_SUCCESS) {

			_sym_info.struct_size = sizeof(_sym_info);
    		_sym_info.name = nameBuffer;
    		_sym_info.name_size = (MAX_PATH * 4) * sizeof(char);
    		_sym_info.file = fileBuffer;
    		_sym_info.file_size = (MAX_PATH * 4) * sizeof(char);

    		drsym_error_t ret = drsym_lookup_addressPtr([module UTF8String], modOffs, &_sym_info, DRSYM_DEFAULT_FLAGS);

    		[result setObject:[OFNumber numberWithUIntPtr:(uintptr_t)modOffs] forKey:kModuleOffset];
    		[result setObject:[OFNumber numberWithSize:_sym_info.start_offs] forKey:kSymbolStartOffset];
    		[result setObject:[OFNumber numberWithSize:_sym_info.end_offs] forKey:kSymbolEndOffset];
    		
    		if (ret == DRSYM_SUCCESS) {

    			[result setObject:[OFNumber numberWithUInt64:(uint64_t)_sym_info.line] forKey:kLineNumber];
    			OFString* file = [OFString stringWithUTF8String:_sym_info.file length:_sym_info.file_available_size];
    			[result setObject:file forKey:kSourceFilePath];
    			[result setObject:[file lastPathComponent] forKey:kSourceFileName];
    			[result setObject:[OFNumber numberWithSize:_sym_info.line_offs] forKey:kLineOffset];

    		} else if (ret == DRSYM_ERROR_LINE_NOT_AVAILABLE) {

    			if (_sym_info.file_available_size > 0) {

    				[result setObject:[OFString stringWithUTF8String:_sym_info.file length:_sym_info.file_available_size] forKey:kSourceFilePath];
    				[result setObject:[[result objectForKey:kSourceFileName] lastPathComponent] forKey:kSourceFileName];

    			}

    		}

    		OFString* demangledSymbolName = objc_demangle(name);

    		if (demangledSymbolName == nil) {
    			char* demangledBuffer = (char*)__builtin_alloca(sizeof(char) * (MAX_PATH * 4));

    			size_t demangleSize = drsym_demangle_symbolPtr(demangledBuffer, (sizeof(char) * (MAX_PATH * 4)), _sym_info.name, DRSYM_DEFAULT_FLAGS);

    			demangledSymbolName = [OFString stringWithUTF8String:demangledBuffer length:demangleSize];

    		}

    		[result setObject:demangledSymbolName forKey:kDemangledSymbolName];
    		[result setObject:name forKey:kMangledSymbolName];

    		[pool release];

    		[result makeImmutable];

    		drsym_exitPtr();

    		return result;

		}

		[pool release];

		drsym_exitPtr();

		return nil;
	}

	[pool release];

	return nil;
}

- (OFDictionary *)symbolInfoAtAddress:(ptrdiff_t)offset inModule:(OFString *)module
{
	if (module == nil || [module length] == 0)
		return nil;

	OFMutableDictionary* result = [OFMutableDictionary dictionary];

	OFAutoreleasePool* pool = [OFAutoreleasePool new];


	if (drsym_initPtr(NULL) == DRSYM_SUCCESS) {

		char* nameBuffer = (char*)__builtin_alloca(sizeof(char) * (MAX_PATH * 4));
    	char* fileBuffer = (char*)__builtin_alloca(sizeof(char) * (MAX_PATH * 4));

		memset(&_sym_info, 0, sizeof(_sym_info));
		memset(nameBuffer, 0, (MAX_PATH * 4) * sizeof(char));
		memset(fileBuffer, 0, (MAX_PATH * 4) * sizeof(char));

		_sym_info.struct_size = sizeof(_sym_info);
    	_sym_info.name = nameBuffer;
    	_sym_info.name_size = (MAX_PATH * 4) * sizeof(char);
    	_sym_info.file = fileBuffer;
    	_sym_info.file_size = (MAX_PATH * 4) * sizeof(char);

    	drsym_error_t ret = drsym_lookup_addressPtr([module UTF8String], offset, &_sym_info, DRSYM_DEFAULT_FLAGS);

    	if (ret == DRSYM_SUCCESS) {

    		OFString* filePath = [OFString stringWithUTF8String:_sym_info.file length:_sym_info.file_available_size];
			OFString* fileName = [filePath lastPathComponent];

			[result setObject:filePath forKey:kSourceFilePath];
			[result setObject:fileName forKey:kSourceFileName];

			[result setObject:[OFNumber numberWithSize:_sym_info.line_offs] forKey:kLineOffset];
			[result setObject:[OFNumber numberWithSize:_sym_info.line] forKey:kLineNumber];

    	} 
    	else if (ret == DRSYM_ERROR_LINE_NOT_AVAILABLE) {

    		if (_sym_info.file_available_size > 0) {
    			OFString* filePath = [OFString stringWithUTF8String:_sym_info.file length:_sym_info.file_available_size];
    			OFString* fileName = [filePath lastPathComponent];

    			[result setObject:filePath forKey:kSourceFilePath];
    			[result setObject:fileName forKey:kSourceFileName];
    		}

    	} else {

    		[pool release];

    		drsym_exitPtr();

    		return nil;
    	}

    	[result setObject:[OFNumber numberWithUIntPtr:(uintptr_t)offset] forKey:kModuleOffset];
    	[result setObject:[OFNumber numberWithSize:_sym_info.start_offs] forKey:kSymbolStartOffset];
    	[result setObject:[OFNumber numberWithSize:_sym_info.end_offs] forKey:kSymbolEndOffset];

    	if (_sym_info.name_available_size > 0) {
    		OFString* mangledName = [OFString stringWithUTF8String:_sym_info.name];

    		OFString* demangledName = nil;

    		if ((demangledName = objc_demangle(mangledName)) == nil) {

    			char* demangledBuffer = (char*)__builtin_alloca(sizeof(char) * (MAX_PATH * 4));

    			size_t demangleSize = drsym_demangle_symbolPtr(demangledBuffer, (sizeof(char) * (MAX_PATH * 4)), _sym_info.name, DRSYM_DEFAULT_FLAGS);

    			demangledName = [OFString stringWithUTF8String:demangledBuffer length:demangleSize];
    		}


    		[result setObject:mangledName forKey:kMangledSymbolName];
    		[result setObject:demangledName forKey:kDemangledSymbolName];
    	}

    	[pool release];

    	[result makeImmutable];

    	drsym_exitPtr();

    	return result;
    	
	}

	return nil;

}

@end