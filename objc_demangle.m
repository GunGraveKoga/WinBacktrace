#import <ObjFW/ObjFW.h>
#import "objc_demangle.h"

OFString* objc_demangle(OFString* mangled) {

	if (mangled == nil)
		return nil;

	if ([mangled length] <= 3)
		return nil;

	if (([mangled characterAtIndex:0] == '-' || [mangled characterAtIndex:0] == '+') && [mangled characterAtIndex:1] == '[')
		return nil;

	if ([mangled characterAtIndex:0] == '_' &&
		([mangled characterAtIndex:1] == 'i' || [mangled characterAtIndex:1] == 'c') &&
		[mangled characterAtIndex:2] == '_') {


		OFMutableString* demangled = [OFMutableString new];

		void* pool = objc_autoreleasePoolPush();

		if ([mangled characterAtIndex:1] == 'i')
			[demangled appendUTF8String:"-"];
		else
			[demangled appendUTF8String:"+"];

		size_t pos = 0;
		[demangled appendUTF8String:"["];

		for (size_t idx = 3; idx < [mangled length]; idx++) {
			if ([mangled characterAtIndex:idx] == '_')
				continue;
			else {
				pos = idx;
				break;
			}
		}

		of_range_t character_range = [mangled rangeOfString:@"_" options:0 range:of_range(pos, [mangled length] - pos)];

		if (character_range.location == OF_NOT_FOUND) {
			objc_autoreleasePoolPop(pool);
			[demangled release];

			return nil;
		}
		size_t classNameLength = character_range.location - pos;
		of_unichar_t* className = (of_unichar_t*)__builtin_alloca(sizeof(of_unichar_t) * (classNameLength+1));
		memset(className, 0, sizeof(of_unichar_t) * (classNameLength+1));
		[mangled getCharacters:className inRange:of_range(pos, classNameLength)];
		[demangled appendCharacters:className length:classNameLength];

		pos = character_range.location;

		if ([mangled characterAtIndex:pos+1] == '_') {
			[demangled appendUTF8String:" "];

			pos += 2;

		} else {
			[demangled appendUTF8String:"("];

			pos += 1;

			character_range = [mangled rangeOfString:@"_" options:0 range:of_range(pos, [mangled length] - pos)];

			if (character_range.location == OF_NOT_FOUND) {
				objc_autoreleasePoolPop(pool);
				[demangled release];

				return nil;
			}

			size_t categoryNameLength = character_range.location - pos;
			of_unichar_t* categoryName = (of_unichar_t*)__builtin_alloca(sizeof(of_unichar_t) * (categoryNameLength+1));
			memset(categoryName, 0, sizeof(of_unichar_t) * (categoryNameLength+1));

			[mangled getCharacters:categoryName inRange:of_range(pos, categoryNameLength)];
			[demangled appendCharacters:categoryName length:categoryNameLength];

			[demangled appendUTF8String:") "];

			pos = character_range.location;
			pos += 1;
		}

		for (size_t idx = pos; idx < [mangled length]; idx++) {
			if ([mangled characterAtIndex:idx] == '_')
				continue;
			else {
				size_t initialPrefixLength = (idx - pos);
				of_unichar_t* initialPrefix = (of_unichar_t*)__builtin_alloca(sizeof(of_unichar_t)*(initialPrefixLength+1));
				memset(initialPrefix, 0, sizeof(of_unichar_t) * (initialPrefixLength + 1));
				[mangled getCharacters:initialPrefix inRange:of_range(pos, initialPrefixLength)];

				[demangled appendCharacters:initialPrefix length:initialPrefixLength];

				pos = idx;
				break;
			}
		}

		if ([mangled characterAtIndex:[mangled length] - 1] != '_') {
			size_t fullMethodLength = [mangled length] - pos;
			of_unichar_t* fullMethodName = (of_unichar_t*)__builtin_alloca(sizeof(of_unichar_t) * (fullMethodLength + 1));
			memset(fullMethodName, 0, sizeof(of_unichar_t) * (fullMethodLength + 1));

			[mangled getCharacters:fullMethodName inRange:of_range(pos, fullMethodLength)];

			[demangled appendCharacters:fullMethodName length:fullMethodLength];

			[demangled appendUTF8String:"]"];

			objc_autoreleasePoolPop(pool);

			[demangled makeImmutable];

			return [demangled autorelease];
		}

		size_t partMethodLength = 0;
		of_unichar_t* partMethodName = NULL;
		
		for (size_t idx = pos; idx < [mangled length]; idx++) {
			
			if ([mangled characterAtIndex:idx] == '_') {

				if (idx < ([mangled length] - 1) && [mangled characterAtIndex:idx + 1] == '_') { //Assume that multiple '_'
					size_t subidx = idx+1;

					while(subidx < [mangled length] && [mangled characterAtIndex:subidx] == '_')
						subidx++;

					if (subidx >= ([mangled length] - 1)) {
						partMethodLength = [mangled length] - pos;
						partMethodName = (of_unichar_t*)__builtin_alloca(sizeof(of_unichar_t) * (partMethodLength + 1));
						memset(partMethodName, 0, sizeof(of_unichar_t) * (partMethodLength + 1));

						[mangled getCharacters:partMethodName inRange:of_range(pos, partMethodLength)];

						[demangled appendCharacters:partMethodName length:partMethodLength];

						break;
					}

					idx = subidx;
					continue;

				}

				partMethodLength = idx - pos;
				partMethodName = (of_unichar_t*)__builtin_alloca(sizeof(of_unichar_t) * (partMethodLength + 1));
				memset(partMethodName, 0, sizeof(of_unichar_t) * (partMethodLength + 1));

				[mangled getCharacters:partMethodName inRange:of_range(pos, partMethodLength)];

				[demangled appendCharacters:partMethodName length:partMethodLength];

				[demangled appendUTF8String:":"];

				pos = idx+1;


				partMethodLength = 0;
				partMethodName = NULL;

				continue;
			}

			continue;
		}

		if ([demangled characterAtIndex:[demangled length] - 1] != ':')
			[demangled replaceCharactersInRange:of_range(([demangled length] -1), 1) withString:@":"];

		[demangled appendUTF8String:"]"];

		objc_autoreleasePoolPop(pool);
		[demangled makeImmutable];

		return [demangled autorelease];
	}

	return nil;


}