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

#define TESTALL(mask, var) (((mask) & (var)) == (mask))
/* check if any bit in mask is set in var */
#define TESTANY(mask, var) (((mask) & (var)) != 0)

# define FULL_PDB_DEBUG_KIND \
        (DRSYM_SYMBOLS | DRSYM_LINE_NUMS | DRSYM_PDB)
# define FULL_PECOFF_DEBUG_KIND \
        (DRSYM_SYMBOLS | DRSYM_LINE_NUMS | \
         DRSYM_PECOFF_SYMTAB | DRSYM_DWARF_LINE)