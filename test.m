#import <ObjFW/ObjFW.h>
#import "OFException+WinBacktrace.h"


int main(int argc, char const *argv[])
{
	
	@try {
		@throw [OFException exception];

	} @catch(OFException* e) {
		of_log(@"%@", [e debugBacktrace]);
	}


	return 0;
}