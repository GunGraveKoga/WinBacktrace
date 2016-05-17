#import "DrMinGWModule.h"

@interface DrMinGWModule(PRIVATE)

- (void)setProcessHandle:(HANDLE)process;
- (void)setThreadHandle:(HANDLE)thread;
- (void)setSymbol:(PSYMBOL_INFO)symbol;

@end