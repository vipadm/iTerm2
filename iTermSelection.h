//
//  iTermSelection.h
//  iTerm
//
//  Created by George Nachman on 2/10/14.
//
//

#import <Foundation/Foundation.h>
#import "VT100GridTypes.h"

@class iTermSelection;

typedef enum {
    kiTermSelectionModeCharacter,
    kiTermSelectionModeWord,
    kiTermSelectionModeLine,
    kiTermSelectionModeSmart,
    kiTermSelectionModeBox,
    kiTermSelectionModeWholeLine
} iTermSelectionMode;

@protocol iTermSelectionDelegate <NSObject>

- (void)selectionDidChange:(iTermSelection *)selection;
// Returns range of (parenthesized phrase) startin or ending at coord, or
// -1,-1,-1,-1 if none.
- (VT100GridCoordRange)selectionRangeForParentheticalAt:(VT100GridCoord)coord;

// Returns range of word including coord.
- (VT100GridCoordRange)selectionRangeForWordAt:(VT100GridCoord)coord;

// Returns range of smart selection at coord.
- (VT100GridCoordRange)selectionRangeForSmartSelectionAt:(VT100GridCoord)coord;

// Returns range of full wrapped line at coord.
- (VT100GridCoordRange)selectionRangeForWrappedLineAt:(VT100GridCoord)coord;

// Returns range of single line at coord.
- (VT100GridCoordRange)selectionRangeForLineAt:(VT100GridCoord)coord;

// Returns the x range of trailing nulls on a line.
- (VT100GridRange)selectionRangeOfTerminalNullsOnLine:(int)lineNumber;

// Returns the coordinate of the coordinate just before coord.
- (VT100GridCoord)selectionPredecessorOfCoord:(VT100GridCoord)coord;

@end

// Represents the region of selected text.
@interface iTermSelection : NSObject <NSCopying>

@property(nonatomic, assign) id<iTermSelectionDelegate> delegate;

// If set, the selection is currently being extended.
@property(nonatomic, readonly) BOOL extending;

// How to perform selection.
@property(nonatomic, assign) iTermSelectionMode selectionMode;

// Does the selection range's start come after its end? Not meaningful for box
// selections.
@property(nonatomic, readonly) BOOL isFlipped;

// The range of selections. May be flipped.
@property(nonatomic, assign) VT100GridCoordRange selectedRange;

// A selection is in progress.
@property(nonatomic, readonly) BOOL live;

// Start a new selection, erasing the old one. Enters live selection.
- (void)beginSelectionAt:(VT100GridCoord)coord mode:(iTermSelectionMode)mode;

// Start extending an existing election, moving an endpoint to the given
// coordinate in a way appropriate for the selection mode. Enters live selection.
- (void)beginExtendingSelectionAt:(VT100GridCoord)coord;

// During live selection, adjust the endpoint.
- (void)moveSelectionEndpointTo:(VT100GridCoord)coord;

// End live selection.
- (void)endLiveSelection;

// Remove selection.
- (void)clearSelection;

// Subtract numLines from y coordinates.
- (void)moveUpByLines:(int)numLines;

// Indicates if there is a non-empty selection.
- (BOOL)hasSelection;

// Indicates if the selection contains the coordinate.
- (BOOL)containsCoord:(VT100GridCoord)coord;

// Length of the selection in characters.
- (long long)length;

@end
