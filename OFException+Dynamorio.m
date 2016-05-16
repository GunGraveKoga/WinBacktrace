#import "OFException+Dynamorio.h"
#include "dbghelp.h"
#include <WinNT.h>

typedef BOOL (WINAPI* DwSymInitialize)(HANDLE hProcess, PCSTR UserSearchPath, BOOL fInvadeProcess);
typedef BOOL (WINAPI* DwSymCleanup)(HANDLE hProcess);
typedef BOOL (WINAPI* DwSymFromAddr)(HANDLE hProcess, DWORD64 Address, PDWORD64 Displacement, PSYMBOL_INFO Symbol);
typedef BOOL (WINAPI* DwStackWalk64)(DWORD MachineType, HANDLE hProcess, HANDLE hThread, LPSTACKFRAME64 StackFrame, PVOID ContextRecord, PREAD_PROCESS_MEMORY_ROUTINE64 ReadMemoryRoutine, PFUNCTION_TABLE_ACCESS_ROUTINE64 FunctionTableAccessRoutine, PGET_MODULE_BASE_ROUTINE64 GetModuleBaseRoutine, PTRANSLATE_ADDRESS_ROUTINE64 TranslateAddress);
typedef DWORD64 (WINAPI* DwSymGetModuleBase64)(HANDLE hProcess, DWORD64 dwAddress);
typedef DWORD64 (WINAPI* DwSymSetOptions)(DWORD SymOptions);
typedef PVOID (WINAPI* DwSymFunctionTableAccess64)(HANDLE hProcess, DWORD64 AddrBase);
typedef DWORD (WINAPI* DwUnDecorateSymbolName)(PCSTR DecoratedName, PSTR UnDecoratedName, DWORD UndecoratedLength, DWORD Flags);
typedef BOOL (WINAPI* DwSymGetLineFromAddr64)(HANDLE hProcess, DWORD64 dwAddr, PDWORD pdwDisplacement, PIMAGEHLP_LINE64 Line);
typedef DWORD (WINAPI* DwGetModuleFileNameEx)(HANDLE  hProcess, HMODULE hModule, LPTSTR  lpFilename, DWORD   nSize);

typedef enum {
    DRSYM_SUCCESS,                  /**< Operation succeeded. */
    DRSYM_ERROR,                    /**< Operation failed. */
    DRSYM_ERROR_INVALID_PARAMETER,  /**< Operation failed: invalid parameter */
    DRSYM_ERROR_INVALID_SIZE,       /**< Operation failed: invalid size */
    DRSYM_ERROR_LOAD_FAILED,        /**< Operation failed: unable to load symbols */
    DRSYM_ERROR_SYMBOL_NOT_FOUND,   /**< Operation failed: symbol not found */
    DRSYM_ERROR_LINE_NOT_AVAILABLE, /**< Operation failed: line info not available */
    DRSYM_ERROR_NOT_IMPLEMENTED,    /**< Operation failed: not yet implemented */
    DRSYM_ERROR_FEATURE_NOT_AVAILABLE, /**< Operation failed: not available */
    DRSYM_ERROR_NOMEM,              /**< Operation failed: not enough memory */
    DRSYM_ERROR_RECURSIVE,          /**< Operation failed: unavailable when recursive */
} drsym_error_t;

typedef enum {
    /**
     * Do not demangle C++ symbols.  This option is not available for
     * Windows PDB symbols.
     */
    DRSYM_LEAVE_MANGLED = 0x00,
    /**
     * Demangle C++ symbols, omitting templates and parameter types.
     * For all symbol types, templates are collapsed to <> while function
     * parameters are omitted entirely (without any parentheses).
     */
    DRSYM_DEMANGLE      = 0x01,
    /**
     * Demangle template arguments and parameter types.  This option is not
     * available for Windows PDB symbols (except in drsym_demangle_symbol()).
     */
    DRSYM_DEMANGLE_FULL = 0x02,
    /** For Windows PDB, do not collapse templates to <>. */
    DRSYM_DEMANGLE_PDB_TEMPLATES = 0x04,
    /**
     * Windows-only, for drsym_search_symbols_ex().
     * Requests a full search for all symbols and not just functions.
     * This adds overhead: see drsym_search_symbols_ex() for details.
     */
    DRSYM_FULL_SEARCH   = 0x08,
    DRSYM_DEFAULT_FLAGS = DRSYM_DEMANGLE,   /**< Default flags. */
} drsym_flags_t;

/**
 * Bitfield indicating the availability of different kinds of debugging
 * information for a module.  The first 8 bits are reserved for platform
 * independent qualities of the debug info, while the rest indicate exactly
 * which kind of debug information is present.
 */
typedef enum {
    DRSYM_SYMBOLS    = (1 <<  0), /**< Any symbol information beyond exports. */
    DRSYM_LINE_NUMS  = (1 <<  1), /**< Any line number info. */
    /* Platform-dependent types. */
    DRSYM_ELF_SYMTAB = (1 <<  8), /**< ELF .symtab symbol names. */
    DRSYM_DWARF_LINE = (1 <<  9), /**< DWARF line info. */
    DRSYM_PDB        = (1 << 10), /**< Windows PDB files. */
    DRSYM_PECOFF_SYMTAB = (1 <<  11), /**< PE COFF (Cygwin or MinGW) symbol table names.*/
    DRSYM_MACHO_SYMTAB =  (1 <<  12), /**< Mach-O symbol table names. */
} drsym_debug_kind_t;

/** Data structure that holds symbol information */
typedef struct _drsym_info_t {
    /* INPUTS */
    /** Input: should be set by caller to sizeof(drsym_info_t) */
    size_t struct_size;
    /** Input: should be set by caller to the size of the name buffer, in bytes */
    size_t name_size;
    /** Input: should be set by caller to the size of the file buffer, in bytes */
    size_t file_size;

    /* OUTPUTS */
    /**
     * Output: size of data available for file (not including terminating null).
     * Only file_size bytes will be copied to file.
     */
    size_t file_available_size;
    /**
     * Output: file name (storage allocated by caller, of size file_size).
     * Guaranteed to be null-terminated.
     * Optional: can be set to NULL.
     */
    char *file;
    /** Output: line number */
    u_int64 line;
    /** Output: offset from address that starts at line */
    size_t line_offs;

    /**
     * Output: offset from module base of start of symbol.
     * For Mach-O executables, the module base is after any __PAGEZERO segment.
     */
    size_t start_offs;
    /**
     * Output: offset from module base of end of symbol.
     * \note For DRSYM_PECOFF_SYMTAB (Cygwin or MinGW) or DRSYM_MACHO_SYMTAB (MacOS)
     * symbols, the end offset is not known precisely.
     * The start address of the subsequent symbol will be stored here.
     **/
    size_t end_offs;

    /** Output: type of the debug info available for this module */
    drsym_debug_kind_t debug_kind;
    /** Output: type id for passing to drsym_expand_type() */
    u_int type_id;

    /**
     * Output: size of data available for name (not including terminating null).
     * Only name_size bytes will be copied to name.
     */
    size_t name_available_size;
    /**
     * Output: symbol name (storage allocated by caller, of size name_size).
     * Guaranteed to be null-terminated.
     * Optional: can be set to NULL.
     */
    char *name;

    /** Output: the demangling status of the symbol, as drsym_flags_t values. */
    u_int flags;
} drsym_info_t;

typedef drsym_error_t (*drsym_lookup_symbol)(const char *modpath, const char *symbol, size_t *modoffs /*OUT*/, u_int flags);
typedef drsym_error_t (*drsym_lookup_address)(const char *modpath, size_t modoffs, drsym_info_t *info /*INOUT*/, u_int flags);

#define TESTALL(mask, var) (((mask) & (var)) == (mask))
/* check if any bit in mask is set in var */
#define TESTANY(mask, var) (((mask) & (var)) != 0)

# define FULL_PDB_DEBUG_KIND \
        (DRSYM_SYMBOLS | DRSYM_LINE_NUMS | DRSYM_PDB)
# define FULL_PECOFF_DEBUG_KIND \
        (DRSYM_SYMBOLS | DRSYM_LINE_NUMS | \
         DRSYM_PECOFF_SYMTAB | DRSYM_DWARF_LINE)

typedef drsym_error_t (*drsym_init)(const wchar_t * shmid);
typedef void* (*dr_standalone_init)(void);
typedef drsym_error_t (*drsym_exit)(void);

const char* formatedName(const char* name) {
  char* symbolString = NULL;


  const char* methodType;

  char* spacePos = NULL;
  char* mthName = NULL;
  int pos = 0;
  char* className = NULL;
  char* methodName = NULL;

  if ((strncmp(name, "_i_", 3)) == 0) {
    methodType = "-";
  } else if ((strncmp(name, "_c_", 3)) == 0) {
    methodType = "+";
  } else {
    return name;
  }

  mthName = (char*)(name + 3);

  spacePos = strchr(mthName, '_');
  if (spacePos == NULL) {
    return name;
  }
  pos = spacePos - mthName;

  if (mthName[pos + 1] == '_') {
    methodName = mthName + (pos + 2);
  } else {
    for (size_t i = (size_t)(pos + 1); i < strlen(mthName); i++) {
      if (mthName[i] == '_') {
        if (mthName[i + 1] == '_') {
          methodName = mthName + (i + 2);
          pos = i;
          break;
        }
      }
    }

  }


  className = (char*)malloc((pos + 1) * sizeof(char));
  if (className == NULL) {
    return name;
  }
  memset(className, 0, (pos + 1) * sizeof(char));
  strncpy(className, mthName, pos);

  if (className[0] == 0) {
    return name;
  }

  size_t cp = snprintf(NULL, 0, "%s[%s %s]", methodType, className, methodName);

  if (cp <= 0) {
    return name;
  }

  symbolString = (char *)calloc(cp + 1, sizeof(char));
  if (symbolString == NULL) {
    return name;
  }
  memset(symbolString, 0, cp + 1);
  snprintf(symbolString, cp, "%s[%s %s]", methodType, className, methodName);

  symbolString[cp+1] = 0;

  return symbolString;
}

const char* exceptionCodeToString(DWORD _exception_code) {
  switch(_exception_code) {
    case EXCEPTION_ACCESS_VIOLATION:
      return "EXCEPTION_ACCESS_VIOLATION";
    case EXCEPTION_ARRAY_BOUNDS_EXCEEDED:
      return "EXCEPTION_ARRAY_BOUNDS_EXCEEDED";
    case EXCEPTION_BREAKPOINT:
      return "EXCEPTION_BREAKPOINT";
    case EXCEPTION_DATATYPE_MISALIGNMENT:
      return "EXCEPTION_DATATYPE_MISALIGNMENT";
    case EXCEPTION_FLT_DENORMAL_OPERAND:
      return "EXCEPTION_FLT_DENORMAL_OPERAND";
    case EXCEPTION_FLT_DIVIDE_BY_ZERO:
      return "EXCEPTION_FLT_DIVIDE_BY_ZERO";
    case EXCEPTION_FLT_INEXACT_RESULT:
      return "EXCEPTION_FLT_INEXACT_RESULT";
    case EXCEPTION_FLT_INVALID_OPERATION:
      return "EXCEPTION_FLT_INVALID_OPERATION";
    case EXCEPTION_FLT_OVERFLOW:
      return "EXCEPTION_FLT_OVERFLOW";
    case EXCEPTION_FLT_STACK_CHECK:
      return "EXCEPTION_FLT_STACK_CHECK";
    case EXCEPTION_FLT_UNDERFLOW:
      return "EXCEPTION_FLT_UNDERFLOW";
    case EXCEPTION_ILLEGAL_INSTRUCTION:
      return "EXCEPTION_ILLEGAL_INSTRUCTION";
    case EXCEPTION_IN_PAGE_ERROR:
      return "EXCEPTION_IN_PAGE_ERROR";
    case EXCEPTION_INT_DIVIDE_BY_ZERO:
      return "EXCEPTION_INT_DIVIDE_BY_ZERO";
    case EXCEPTION_INT_OVERFLOW:
      return "EXCEPTION_INT_OVERFLOW";
    case EXCEPTION_INVALID_DISPOSITION:
      return "EXCEPTION_INVALID_DISPOSITION";
    case EXCEPTION_NONCONTINUABLE_EXCEPTION:
      return "EXCEPTION_NONCONTINUABLE_EXCEPTION";
    case EXCEPTION_PRIV_INSTRUCTION:
      return "EXCEPTION_PRIV_INSTRUCTION";
    case EXCEPTION_SINGLE_STEP:
      return "EXCEPTION_SINGLE_STEP";
    case EXCEPTION_STACK_OVERFLOW:
      return "EXCEPTION_STACK_OVERFLOW";
    default:
      return "UNKNOWN";
  }

  return NULL;
}

static FILE* _dumpFile = NULL;

static void printChainedExceptionRecords(PEXCEPTION_RECORD record) {
  PEXCEPTION_RECORD ExceptionRecord = record;

    fprintf(_dumpFile, "\t\t%s at address 0x%p\r\n\r\n",  exceptionCodeToString(ExceptionRecord->ExceptionCode), ExceptionRecord->ExceptionAddress);
    fprintf(_dumpFile, "*********************************\r\n");

    if(ExceptionRecord->ExceptionRecord != NULL) {
      printChainedExceptionRecords(ExceptionRecord->ExceptionRecord);
    }

}

static char**
_backtraceDbg(PCONTEXT ctx)
{


  DwSymInitialize DwSymInitializePtr = NULL;
  DwStackWalk64 DwStackWalk64Ptr = NULL;
  DwSymCleanup DwSymCleanupPtr = NULL;
  DwSymFromAddr DwSymFromAddrPtr = NULL;
  DwSymGetModuleBase64 DwSymGetModuleBase64Ptr = NULL;
  DwSymFunctionTableAccess64 DwSymFunctionTableAccess64Ptr = NULL;
  HINSTANCE dllHandle = NULL;

  dllHandle = LoadLibraryA("mgwhelp.dll");

  if (dllHandle == NULL) {
    perror("Cannot load mgwhelp.dll");
    return NULL;
  }

  DwSymInitializePtr = (DwSymInitialize)GetProcAddress(dllHandle, "SymInitialize");
  DwStackWalk64Ptr = (DwStackWalk64)GetProcAddress(dllHandle, "StackWalk64");
  DwSymCleanupPtr = (DwSymCleanup)GetProcAddress(dllHandle, "SymCleanup");
  DwSymFromAddrPtr = (DwSymFromAddr)GetProcAddress(dllHandle, "SymFromAddr");
  DwSymGetModuleBase64Ptr = (DwSymGetModuleBase64)GetProcAddress(dllHandle, "SymGetModuleBase64");
  DwSymFunctionTableAccess64Ptr = (DwSymFunctionTableAccess64)GetProcAddress(dllHandle, "SymFunctionTableAccess64");


  HANDLE process = GetCurrentProcess();
  HANDLE thread = GetCurrentThread();

  CONTEXT context;
  if (ctx == NULL) {
    memset(&context, 0, sizeof(CONTEXT));
    context.ContextFlags = CONTEXT_FULL;
    RtlCaptureContext(&context);
  } else {
    memcpy(&context, ctx, sizeof(CONTEXT));
  }

  DwSymInitializePtr(process, NULL, TRUE);

  DWORD image;
  STACKFRAME64 stackframe;
  ZeroMemory(&stackframe, sizeof(STACKFRAME64));

#ifdef _M_IX86
  image = IMAGE_FILE_MACHINE_I386;
  stackframe.AddrPC.Offset = context.Eip;
  stackframe.AddrPC.Mode = AddrModeFlat;
  stackframe.AddrFrame.Offset = context.Ebp;
  stackframe.AddrFrame.Mode = AddrModeFlat;
  stackframe.AddrStack.Offset = context.Esp;
  stackframe.AddrStack.Mode = AddrModeFlat;
#elif _M_X64
  #error !x86
  image = IMAGE_FILE_MACHINE_AMD64;
  stackframe.AddrPC.Offset = context.Rip;
  stackframe.AddrPC.Mode = AddrModeFlat;
  stackframe.AddrFrame.Offset = context.Rsp;
  stackframe.AddrFrame.Mode = AddrModeFlat;
  stackframe.AddrStack.Offset = context.Rsp;
  stackframe.AddrStack.Mode = AddrModeFlat;
#elif _M_IA64
  #error !x86
  image = IMAGE_FILE_MACHINE_IA64;
  stackframe.AddrPC.Offset = context.StIIP;
  stackframe.AddrPC.Mode = AddrModeFlat;
  stackframe.AddrFrame.Offset = context.IntSp;
  stackframe.AddrFrame.Mode = AddrModeFlat;
  stackframe.AddrBStore.Offset = context.RsBSP;
  stackframe.AddrBStore.Mode = AddrModeFlat;
  stackframe.AddrStack.Offset = context.IntSp;
  stackframe.AddrStack.Mode = AddrModeFlat;
#endif

  char** res = (char**)malloc(32 * sizeof(char *));
  if (res != NULL) {
      for (size_t i = 0; i < 32; i++) {
        res[i] = NULL;
      }
    }


  for (size_t i = 0; i < 32; i++) {

    BOOL result = DwStackWalk64Ptr(
      image, process, thread,
      &stackframe, &context, NULL,
      DwSymFunctionTableAccess64Ptr, DwSymGetModuleBase64Ptr, NULL);

    if (!result) { break; }

    char buffer[sizeof(SYMBOL_INFO) + MAX_SYM_NAME * sizeof(TCHAR)];
    PSYMBOL_INFO symbol = (PSYMBOL_INFO)buffer;
    symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
    symbol->MaxNameLen = MAX_SYM_NAME;

    DWORD64 displacement = 0;
    char* stackRecord = NULL;
    size_t stackRecordSize = 0;
    if (DwSymFromAddrPtr(process, stackframe.AddrPC.Offset, &displacement, symbol)) {
      //printf("[%i] %s[0x%0llX]\n", i, symbol->Name, stackframe.AddrPC.Offset);
        if (res != NULL) {
            stackRecordSize = snprintf(NULL, 0, "\t\t[%i] %s [0x%0llX]\n", i, formatedName(symbol->Name), stackframe.AddrPC.Offset);
            stackRecord = (char *)malloc(stackRecordSize + 1);
            if (stackRecord != NULL) {
              snprintf(stackRecord, stackRecordSize, "\t\t[%i] %s [0x%0llX]\n", i, formatedName(symbol->Name), stackframe.AddrPC.Offset);
              stackRecord[stackRecordSize + 1] = '\0';
              res[i] = stackRecord;
            }
          }
      printf("\t\t[%i] %s [0x%0llX]\n", i, formatedName(symbol->Name), stackframe.AddrPC.Offset);
    } else {
        if (res != NULL) {
            stackRecordSize = snprintf(NULL, 0, "\t\t[%i] ??? [0x%0llX]\n", i, stackframe.AddrPC.Offset);
            stackRecord = (char *)malloc(stackRecordSize + 1);
            if (stackRecord != NULL) {
              snprintf(stackRecord, stackRecordSize, "\t\t[%i] ??? [0x%0llX]\n", i, stackframe.AddrPC.Offset);
              stackRecord[stackRecordSize + 1] = '\0';
              res[i] = stackRecord;
            }
          }
      printf("\t\t[%i] ??? [0x%0llX]\n", i, stackframe.AddrPC.Offset);
    }

  }

  DwSymCleanupPtr(process);

  return res;
}

LONG WINAPI dbg_exception_filter(LPEXCEPTION_POINTERS info) {
  time_t t = time(NULL);
    struct tm tm = *localtime(&t);
    char* name = NULL;
    size_t size = snprintf(NULL, 0, "DUMP-%d-%d-%dT%d-%d-%d.log", tm.tm_year+1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec);
    name = malloc(size + 1);
    if (name != NULL) {
      snprintf(name, size, "DUMP-%d-%d-%dT%d-%d-%d.log", tm.tm_year+1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec);
      name[size + 1] = '\0';
    } else {
      name = "DUMP.log";
    }
    _dumpFile = fopen(&(*name), "w+");

    if (_dumpFile == NULL) {
      perror("Cannot create dump file! ");
      _dumpFile = stderr;
    }

    PEXCEPTION_RECORD ExceptionRecord = info->ExceptionRecord;
    PCONTEXT ContextRecord = info->ContextRecord;

    fprintf(_dumpFile, "\t\tRuntime Error occured!\r\n\t\t%s at address 0x%p\r\n\r\n", exceptionCodeToString(ExceptionRecord->ExceptionCode), ExceptionRecord->ExceptionAddress);

    if (ExceptionRecord->ExceptionRecord != NULL) {
      fprintf(_dumpFile, "Has chained exception records\r\n");
      PEXCEPTION_RECORD SubExceptionRecord = ExceptionRecord->ExceptionRecord;

      fprintf(_dumpFile, "*********************************\r\n");
      printChainedExceptionRecords(SubExceptionRecord);
    }

    char** trace = NULL;

    trace = _backtraceDbg(ContextRecord);
    if (trace != NULL) {
        for (size_t i =0; i < 32; i++) {
          if (trace[i] == NULL)
            break;

          if (_dumpFile != stderr)
            fprintf(_dumpFile, "%s", trace[i]);
        }
      }

      if (_dumpFile != stderr)
        fclose(_dumpFile);


    return 0x1;
}

 void DynamorioUncaughtExceptionHandler(id exception) {

   time_t t = time(NULL);
     struct tm tm = *localtime(&t);
     char* name = NULL;
     size_t size = 0;
     const char* programName = NULL;

     if ([OFApplication programName] != nil) {
       programName = [[[OFApplication programName] lastPathComponent] lossyCStringWithEncoding:OF_STRING_ENCODING_ASCII];
     } else {
       programName = "";
     }

     size = snprintf(NULL, 0, "%s_DUMP-%d-%d-%dT%d-%d-%d.log", programName, tm.tm_year+1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec);
     name = malloc(size + 1);
     if (name != NULL) {
       snprintf(name, size, "%s_DUMP-%d-%d-%dT%d-%d-%d.log", programName, tm.tm_year+1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec);
       name[size + 1] = 0;
       if (name[size] != 'g')
         name[size] = 0;


     } else {
       name = "DUMP";
     }
     _dumpFile = fopen(&(*name), "w+");

     if (_dumpFile == NULL) {
       perror("Cannot create dump file! ");
       _dumpFile = stderr;
     }

     if (_dumpFile != stderr)
       fprintf(_dumpFile, "%s\n", [[exception description] lossyCStringWithEncoding:OF_STRING_ENCODING_UTF_8]);


      of_log(@"%@", exception);
     OFArray* debugBacktrace = nil;
     debugBacktrace = [exception debugBacktrace];
     if (debugBacktrace == nil) {
      for (OFString* addr in [exception backtrace]) {
          if (_dumpFile != stderr)
            fprintf(_dumpFile, "%s\n", [addr lossyCStringWithEncoding:OF_STRING_ENCODING_UTF_8]);


          of_log(@"%@", addr);
       }

      char** backtrace = NULL;
       backtrace = _backtraceDbg(NULL);

       for (size_t i = 0; i < 32; i++) {
             if (backtrace[i] == NULL)
               break;

             if (_dumpFile != stderr)
               fprintf(_dumpFile, "%s\n", backtrace[i]);
       }

       if (_dumpFile != stderr)
             fclose(_dumpFile);


       exit(1);
     }

     for (OFString* dbgInfo in debugBacktrace) {
         if (_dumpFile != stderr)
               fprintf(_dumpFile, "%s\n", [dbgInfo lossyCStringWithEncoding:OF_STRING_ENCODING_UTF_8]);


       of_log(@"%@", dbgInfo);
     }

     if (_dumpFile != stderr)
         fclose(_dumpFile);


     exit(1);
 }

@implementation OFException(DEBUG)

 - (OFArray *)debugBacktrace
 {
   OFMutableArray *backtrace = [OFMutableArray array];
     //OFMutableArray *backtraceSys = [OFMutableArray array];
     void *pool = objc_autoreleasePoolPush();
     HINSTANCE dllHandleS = NULL;
     HINSTANCE dllRio = NULL;
     drsym_init drsym_initPtr = NULL;
     dr_standalone_init dr_standalone_initPtr = NULL;
     drsym_exit drsym_exitPtr = NULL;
     drsym_lookup_symbol drsym_lookup_symbolPtr = NULL;
     drsym_lookup_address drsym_lookup_addressPtr = NULL;

     fprintf(stderr, "Try load Dynamorio DLL's...\n");
     dllHandleS = LoadLibraryA("drsyms.dll");
     dllRio = LoadLibraryA("dynamorio.dll");
     if (dllHandleS == NULL || dllRio == NULL) {
       perror("Cannot load Dynamorio DLL's");
       _backtraceDbg(NULL);
       return nil;
     }

     dr_standalone_initPtr = (dr_standalone_init)GetProcAddress(dllRio, "dr_standalone_init");
     drsym_initPtr = (drsym_init)GetProcAddress(dllHandleS, "drsym_init");
     drsym_exitPtr = (drsym_exit)GetProcAddress(dllHandleS, "drsym_exit");
     drsym_lookup_symbolPtr = (drsym_lookup_symbol)GetProcAddress(dllHandleS, "drsym_lookup_symbol");
     drsym_lookup_addressPtr = (drsym_lookup_address)GetProcAddress(dllHandleS, "drsym_lookup_address");

     dr_standalone_initPtr();



     DwSymInitialize DwSymInitializePtr = NULL;
     DwStackWalk64 DwStackWalk64Ptr = NULL;
     DwSymCleanup DwSymCleanupPtr = NULL;
     DwSymFromAddr DwSymFromAddrPtr = NULL;
     DwSymGetModuleBase64 DwSymGetModuleBase64Ptr = NULL;
     DwSymFunctionTableAccess64 DwSymFunctionTableAccess64Ptr = NULL;
     DwUnDecorateSymbolName DwUnDecorateSymbolNamePtr = NULL;
     DwSymGetLineFromAddr64 DwSymGetLineFromAddr64Ptr = NULL;
     DwSymSetOptions DwSymSetOptionsPtr = NULL;
     DwGetModuleFileNameEx DwGetModuleFileNameExPtr = NULL;
     HINSTANCE dllHandle = NULL;
     HINSTANCE dllPsapi = NULL;

     dllHandle = LoadLibraryA("mgwhelp.dll");
     dllPsapi = LoadLibraryA("psapi.dll");
     if (dllHandle == NULL || dllPsapi == NULL) {
         perror("Cannot load Dynamorio DLL's");
       }
     fprintf(stderr, "loaded\n");


     DwSymInitializePtr = (DwSymInitialize)GetProcAddress(dllHandle, "SymInitialize");
     DwStackWalk64Ptr = (DwStackWalk64)GetProcAddress(dllHandle, "StackWalk64");
     DwSymCleanupPtr = (DwSymCleanup)GetProcAddress(dllHandle, "SymCleanup");
     DwSymFromAddrPtr = (DwSymFromAddr)GetProcAddress(dllHandle, "SymFromAddr");
     DwSymGetModuleBase64Ptr = (DwSymGetModuleBase64)GetProcAddress(dllHandle, "SymGetModuleBase64");
     DwSymFunctionTableAccess64Ptr = (DwSymFunctionTableAccess64)GetProcAddress(dllHandle, "SymFunctionTableAccess64");
     DwUnDecorateSymbolNamePtr = (DwUnDecorateSymbolName)GetProcAddress(dllHandle, "UnDecorateSymbolName");
     DwSymGetLineFromAddr64Ptr = (DwSymGetLineFromAddr64)GetProcAddress(dllHandle, "SymGetLineFromAddr64");
     DwSymSetOptionsPtr = (DwSymSetOptions)GetProcAddress(dllHandle, "SymSetOptions");
     DwGetModuleFileNameExPtr = (DwGetModuleFileNameEx)GetProcAddress(dllPsapi, "GetModuleFileNameExA");


     HANDLE process = GetCurrentProcess();
     HANDLE thread = GetCurrentThread();

     CONTEXT context;
     memset(&context, 0, sizeof(CONTEXT));
     context.ContextFlags = CONTEXT_FULL;
     RtlCaptureContext(&context);

     DwSymInitializePtr(process, NULL, TRUE);

     DWORD image;
     STACKFRAME64 stackframe;
     ZeroMemory(&stackframe, sizeof(STACKFRAME64));


   #ifdef _M_IX86
     image = IMAGE_FILE_MACHINE_I386;
     stackframe.AddrPC.Offset = context.Eip;
     stackframe.AddrPC.Mode = AddrModeFlat;
     stackframe.AddrFrame.Offset = context.Ebp;
     stackframe.AddrFrame.Mode = AddrModeFlat;
     stackframe.AddrStack.Offset = context.Esp;
     stackframe.AddrStack.Mode = AddrModeFlat;
   #elif _M_X64
     #error !x86
     image = IMAGE_FILE_MACHINE_AMD64;
     stackframe.AddrPC.Offset = context.Rip;
     stackframe.AddrPC.Mode = AddrModeFlat;
     stackframe.AddrFrame.Offset = context.Rsp;
     stackframe.AddrFrame.Mode = AddrModeFlat;
     stackframe.AddrStack.Offset = context.Rsp;
     stackframe.AddrStack.Mode = AddrModeFlat;
   #elif _M_IA64
     #error !x86
     image = IMAGE_FILE_MACHINE_IA64;
     stackframe.AddrPC.Offset = context.StIIP;
     stackframe.AddrPC.Mode = AddrModeFlat;
     stackframe.AddrFrame.Offset = context.IntSp;
     stackframe.AddrFrame.Mode = AddrModeFlat;
     stackframe.AddrBStore.Offset = context.RsBSP;
     stackframe.AddrBStore.Mode = AddrModeFlat;
     stackframe.AddrStack.Offset = context.IntSp;
     stackframe.AddrStack.Mode = AddrModeFlat;
   #endif

     int nudge = 0;

     for (size_t i = 0; i < 32; i++) {

       BOOL result = DwStackWalk64Ptr(
         image, process, thread,
         &stackframe, &context, NULL,
         DwSymFunctionTableAccess64Ptr, DwSymGetModuleBase64Ptr, NULL);

       if (!result) { break; }

       char buffer[sizeof(SYMBOL_INFO) + MAX_SYM_NAME * sizeof(TCHAR)];
       PSYMBOL_INFO symbol = (PSYMBOL_INFO)buffer;
       symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
       symbol->MaxNameLen = MAX_SYM_NAME;

       IMAGEHLP_LINE64 line;
       ZeroMemory(&line, sizeof line);
       line.SizeOfStruct = sizeof line;

       DWORD64 displacement = 0;
       DWORD dwLineDisplacement = 0;
       DwSymSetOptionsPtr(SYMOPT_LOAD_LINES);

       DWORD64 AddrPC = stackframe.AddrPC.Offset;
       HMODULE hModule = (HMODULE)(INT_PTR)DwSymGetModuleBase64Ptr(process, (DWORD64)_backtrace[i]);
       TCHAR szModule[MAX_PATH];
       size_t modOffs = 0;
       char name[MAX_PATH];
       char file[MAX_PATH];
       drsym_info_t sym_info;
       sym_info.struct_size = sizeof(sym_info);
       sym_info.name = name;
       sym_info.name_size = MAX_PATH;
       sym_info.file = file;
       sym_info.file_size = MAX_PATH;


       DwGetModuleFileNameExPtr(process, hModule, szModule, MAX_PATH);

         if (DwSymFromAddrPtr(process, (DWORD64)_backtrace[i], &displacement, symbol)) {


           if (drsym_initPtr(NULL) == DRSYM_SUCCESS) {
             OFString* tmp = [OFString stringWithFormat:@"%s", szModule];
             if (drsym_lookup_symbolPtr([tmp cStringWithEncoding:OF_STRING_ENCODING_ASCII], symbol->Name, &modOffs, DRSYM_DEFAULT_FLAGS) == DRSYM_SUCCESS) {

               drsym_error_t ret = drsym_lookup_addressPtr([tmp cStringWithEncoding:OF_STRING_ENCODING_ASCII], modOffs, &sym_info, DRSYM_DEFAULT_FLAGS);

               if (ret == DRSYM_SUCCESS) {

                 [backtrace addObject:
                   [OFString stringWithFormat: @"%d %s %p %s +0x%p [%s : %llu] ", i, /*[tmp lossyCStringWithEncoding:OF_STRING_ENCODING_ASCII]*/[[tmp lastPathComponent] lossyCStringWithEncoding:OF_STRING_ENCODING_ASCII], _backtrace[i], formatedName(symbol->Name), modOffs, sym_info.file, sym_info.line]];

               } else if (ret == DRSYM_ERROR_LINE_NOT_AVAILABLE) {
                 [backtrace addObject:
                   [OFString stringWithFormat: @"%d %s %p %s +0x%p [%d : %d] ", i, /*[tmp lossyCStringWithEncoding:OF_STRING_ENCODING_ASCII]*/[[tmp lastPathComponent] lossyCStringWithEncoding:OF_STRING_ENCODING_ASCII], _backtrace[i], formatedName(symbol->Name), modOffs, sym_info.start_offs, sym_info.end_offs]];

               } else {

                 [backtrace addObject:
                   [OFString stringWithFormat: @"%d %p %s", i, _backtrace[i], symbol->Name]];
               }

             } else {

               [backtrace addObject:
                 [OFString stringWithFormat: @"%d %p %s", i, _backtrace[i], symbol->Name]];
             }

             drsym_exitPtr();

           } else {

             [backtrace addObject:
               [OFString stringWithFormat: @"%d %p %s", i, _backtrace[i], symbol->Name]];
           }


         } else {
           [backtrace addObject:
             [OFString stringWithFormat: @"%d %p ???", i, _backtrace[i]]];
         }
         (void)dwLineDisplacement;
         (void)AddrPC;
         (void)nudge;

         /*if (DwSymFromAddrPtr(process, AddrPC + nudge, &displacement, symbol)) {

           DwSymGetLineFromAddr64Ptr(process, AddrPC + nudge, &dwLineDisplacement, &line);

           [backtraceSys addObject:
             [OFString stringWithFormat: @"%p %s %s %s", (void *)stackframe.AddrPC.Offset, symbol->Name, szModule, line.FileName]];
         } else {
           [backtraceSys addObject:
             [OFString stringWithFormat: @"%p ???", (void *)stackframe.AddrPC.Offset]];
         }

       nudge = -1;*/
     }

     //DwSymCleanupPtr(process);
     objc_autoreleasePoolPop(pool);

     [backtrace makeImmutable];
     //[backtraceSys makeImmutable];

     return backtrace;
 }

@end

