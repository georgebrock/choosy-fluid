//
//  ChoosyFluidController.m
//  ChoosyFluid
//
//  Created by George on 19/02/2009.
//  Copyright 2009 George Brocklehurst. Some rights reserved. 
//	See accompanying LICENSE file for more details.
//

#import "ChoosyFluidController.h"
#import "ChoosyFluidInstance.h"


@implementation ChoosyFluidController

@synthesize 
	fluidInstances,
	statusMessage;

- (void)applicationDidFinishLaunching:(NSNotification*)notification
{
	// Initialise the array for discovered fluid instances
	self.fluidInstances = [NSMutableArray array];
	
	// Display the progress panel
	[NSApp beginSheet:progressPanel	modalForWindow:mainWindow modalDelegate:self didEndSelector:NULL contextInfo:nil];
	[progressBar animate:nil];
	
	// Load the Choosy behaviours
	[self loadChoosyBehaviours];
		
	// Begin the search for fluid instances in all possible directories
	NSArray *applicationsDirectories = NSSearchPathForDirectoriesInDomains(NSApplicationDirectory, NSAllDomainsMask, TRUE);
	NSString *path;
	NSEnumerator *applicationDirectoryEnumerator = [applicationsDirectories objectEnumerator];
	while(path = [applicationDirectoryEnumerator nextObject])
		[self findFluidInstancesInDirectory:path];
		
	// Hide the progress panel
	[NSApp endSheet:progressPanel];
	[progressPanel orderOut:nil];
	
	// Select all fluid instances
	[fluidInstancesController setSelectedObjects:[fluidInstancesController arrangedObjects]];
	
	// Alert the user if we didn't find anything
	if([[fluidInstancesController arrangedObjects] count] == 0)
	{
		NSRunCriticalAlertPanel(
		   @"No Fluid instances were found",
		   @"Either you don't have any Fluid instances or you already have Choosy rules set up for all of them",
		   nil,
		   nil,
		   nil
		);
	}
}

- (void)findFluidInstancesInDirectory:(NSString*)path
{
	// Update the UI's status message
	self.statusMessage = [NSString stringWithFormat:@"Searching for Fluid instances in %@", path];
	
	// Get an array of apps that are already the basis of behaviour rules
	NSArray *applicationsUsedByRules = [choosyBehaviours valueForKey:@"behaviourArgument"];
	
	// Enumerate over the application in the directory
	NSString *file;
	NSString *appPath;
	NSBundle *appBundle;
	ChoosyFluidInstance *fluidInstance;
	NSDirectoryEnumerator *fileEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:path];
	while(file = [fileEnumerator nextObject])
	{
		if([[file pathExtension] isEqualToString:@"app"])
		{
			// Check that there isn't already a Choosy behaviour for this application
			appPath = [path stringByAppendingPathComponent:file];
			if([applicationsUsedByRules containsObject:appPath])
				continue;
		
			// Get a bundle object for the application
			appBundle = [[NSBundle alloc] initWithPath:appPath];
			
			// Check the bundle identifier
			NSString *fluidInstanceBundlePrefix = @"com.fluidapp.FluidInstance.";
			NSRange fluidInstanceRange = [[appBundle bundleIdentifier] rangeOfString:fluidInstanceBundlePrefix];
			if(fluidInstanceRange.location == 0 && fluidInstanceRange.length == [fluidInstanceBundlePrefix length])
			{
				fluidInstance = [[ChoosyFluidInstance alloc] initWithPath:appPath];
				[fluidInstancesController addObject:fluidInstance];
				[fluidInstance release], fluidInstance = nil;
			}
			
			// Tidy up
			[appBundle release], appBundle = nil;
		
			// Don't descend into app's contents
			[fileEnumerator skipDescendents];
		}
	}
	
}

- (IBAction)processSelectedFluidInstances:(id)sender
{
	// Update the UI's status message
	self.statusMessage = @"Creating Choosy behaviour rules";

	// Display the progress panel
	[NSApp beginSheet:progressPanel	modalForWindow:mainWindow modalDelegate:self didEndSelector:NULL contextInfo:nil];
	[progressBar animate:nil];
	
	// Create Choosy behaviour rules for each Fluid instance
	ChoosyFluidInstance *fluidInstance;
	NSEnumerator *fluidInstanceEnumerator = [[fluidInstancesController selectedObjects] objectEnumerator];
	while(fluidInstance = [fluidInstanceEnumerator nextObject])
	{
		// Read the Fluid instance's preferences to get the URL pattern
		NSArray *matchingURLPatterns = [fluidInstance matchingURLPatterns];
		
		// Build predicate for the rule
		NSMutableArray *subpredicates = [NSMutableArray arrayWithCapacity:[matchingURLPatterns count]];
		
		NSDictionary *pattern;
		NSEnumerator *patternEnumerator = [matchingURLPatterns objectEnumerator];
		while(pattern = [patternEnumerator nextObject])
			[subpredicates addObject:[NSPredicate predicateWithFormat:[NSString stringWithFormat:@"URL LIKE \"%@\"", [pattern objectForKey:@"value"]]]];

		NSPredicate *predicate = [NSCompoundPredicate orPredicateWithSubpredicates:subpredicates];
		
		// Check the predicate is valid
		if(!predicate || [[(NSCompoundPredicate*)predicate subpredicates] count] < 1)
		{
			NSRunCriticalAlertPanel(
			   [NSString stringWithFormat:@"Failed to create a Choosy behaviour rule for %@", fluidInstance.name],
			   @"ChoosyFluid wasn't able to get enough information from Fluid's preferences to create this rule",
			   @"Continue",
			   nil,
			   nil
			);

			continue;
		}
		
		// Create the Choosy behaviour
		NSDictionary *choosyBehaviour = [NSDictionary dictionaryWithObjectsAndKeys:
			[NSString stringWithFormat:@"Fluid: Use the \"%@\" site specific browser", fluidInstance.name], @"title",
			[predicate predicateFormat], @"predicate",
			[NSNumber numberWithBool:TRUE], @"enabled",
			[NSNumber numberWithInt:6], @"behaviour",
			fluidInstance.path, @"behaviourArgument",
			nil];
		
		[choosyBehaviours addObject:choosyBehaviour];
		
		// Remove the Fluid instance from the table
		[fluidInstancesController removeObject:fluidInstance];
	}
	
	// Write the updated Choosy behaviours to disk
	[self saveChoosyBehaviours];
	
	// Restart the Choosy helper applications
	NSTask *killTask = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/killall" arguments:[NSArray arrayWithObject:@"Choosy"]];
	[killTask waitUntilExit];
	
	[[NSWorkspace sharedWorkspace] 
		launchAppWithBundleIdentifier:@"com.choosyosx.Choosy"
		options:NSWorkspaceLaunchWithoutActivation
		additionalEventParamDescriptor:nil
		launchIdentifier:NULL];
	
	// Hide the progress panel
	[NSApp endSheet:progressPanel];
	[progressPanel orderOut:nil];
}

- (void)loadChoosyBehaviours
{
	// Load the property list from disk
	NSString *advancedBehavioursPath = [@"~/Library/Application Support/Choosy/behaviours.plist" stringByExpandingTildeInPath];
	NSData *loadedData = [NSData dataWithContentsOfFile:advancedBehavioursPath];
	
	// Convert to an array of NSDictionaries
	NSArray *loadedBehaviours = [NSPropertyListSerialization propertyListFromData:loadedData mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:NULL];
	
	// Get a mutable copy
	[choosyBehaviours release], choosyBehaviours = [loadedBehaviours mutableCopy];
}

- (void)saveChoosyBehaviours
{
	NSString *advancedBehavioursPath = [@"~/Library/Application Support/Choosy/behaviours.plist" stringByExpandingTildeInPath];
	NSData *saveData = [NSPropertyListSerialization dataFromPropertyList:choosyBehaviours format:NSPropertyListXMLFormat_v1_0 errorDescription:NULL];
	[saveData writeToFile:advancedBehavioursPath atomically:TRUE];
}

- (void)dealloc
{
	[fluidInstances release], fluidInstances = nil;
	[choosyBehaviours release], choosyBehaviours = nil;
	[super dealloc];
}

@end
