//
//  ChoosyFluidInstance.h
//  ChoosyFluid
//
//  Created by George on 19/02/2009.
//  Copyright 2009 George Brocklehurst. Some rights reserved. 
//	See accompanying LICENSE file for more details.
//

#import <Cocoa/Cocoa.h>


@interface ChoosyFluidInstance : NSObject 
{
	NSString *path;
	NSString *name;
	NSImage *icon;
}

@property(readwrite,retain) NSString *path;
@property(readonly,retain) NSString *name;
@property(readonly,retain) NSImage *icon;

- (id)initWithPath:(NSString*)newPath;
- (NSArray*)matchingURLPatterns;

@end
