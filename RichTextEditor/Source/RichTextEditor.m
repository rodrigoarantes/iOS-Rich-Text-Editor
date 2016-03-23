//
//  RichTextEditor.m
//  RichTextEdtor
//
//  Created by Aryan Gh on 7/21/13.
//  Copyright (c) 2013 Aryan Ghassemi. All rights reserved.
//
// https://github.com/aryaxt/iOS-Rich-Text-Editor
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "RichTextEditor.h"
#import <QuartzCore/QuartzCore.h>
#import "UIFont+RichTextEditor.h"
#import "NSAttributedString+RichTextEditor.h"
#import "UIView+RichTextEditor.h"

#define RICHTEXTEDITOR_TOOLBAR_HEIGHT 40
#define BULLET_STRING @"\t•\t"
#define DEFAULT_PLACEHOLDER_COLOR [UIColor colorWithRed:170/255.f green:170/255.f blue:170/255.f alpha:1]

@interface RichTextEditor() <RichTextEditorToolbarDelegate, RichTextEditorToolbarDataSource, UITextViewDelegate>
@property (nonatomic, strong) RichTextEditorToolbar *toolBar;

// Gets set to YES when the user starts chaning attributes when there is no text selection (selecting bold, italic, etc)
// Gets set to NO  when the user changes selection or starts typing
@property (nonatomic, assign) BOOL typingAttributesInProgress;

@property (nonatomic, strong) NSArray *googleDriveFonts;
@property (strong, nonatomic) UILabel *lblPlaceHolder;

@end

@implementation RichTextEditor

#pragma mark - Initialization -

- (id)init
{
    if (self = [super init])
	{
        [self commonInitialization];
    }
	
    return self;
}

- (id)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame])
	{
        [self commonInitialization];
    }
	
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
	if (self = [super initWithCoder:aDecoder])
	{
		[self commonInitialization];
	}
	
	return self;
}

- (void)commonInitialization
{
    [self setDelegate:self];
    
    self.borderColor = [UIColor lightGrayColor];
    self.borderWidth = 1.0;

	self.toolBar = [[RichTextEditorToolbar alloc] initWithFrame:CGRectMake(0, 0, [self currentScreenBoundsDependOnOrientation].size.width, RICHTEXTEDITOR_TOOLBAR_HEIGHT)
													   delegate:self
													 dataSource:self];
	
	self.typingAttributesInProgress = NO;
	self.defaultIndentationSize = 15;
	
	[self setupMenuItems];
	[self updateToolbarState];
	
	// When text changes check to see if we need to add bullet, or delete bullet on backspace
	[[NSNotificationCenter defaultCenter] addObserverForName:UITextViewTextDidChangeNotification
													  object:self
													   queue:nil
												  usingBlock:^(NSNotification *n){
													  [self applyBulletListIfApplicable];
													  [self deleteBulletListWhenApplicable];
												  }];
    
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0) {
        self.layoutManager.allowsNonContiguousLayout = NO;
    }
}

#pragma mark - Override Methods -

- (void)setSelectedTextRange:(UITextRange *)selectedTextRange
{
	[super setSelectedTextRange:selectedTextRange];
	
	[self updateToolbarState];
	self.typingAttributesInProgress = NO;
}

- (BOOL)canBecomeFirstResponder
{
	RichTextEditorFeature features = [self featuresEnabledForRichTextEditorToolbar];
    
    if (features == RichTextEditorFeatureNone) {
        return YES;
    } else {
        if (![self.dataSource respondsToSelector:@selector(shouldDisplayToolbarForRichTextEditor:)] ||
            [self.dataSource shouldDisplayToolbarForRichTextEditor:self])
        {
            self.inputAccessoryView = self.toolBar;
            
            // Redraw in case enabbled features have changes
            [self.toolBar redraw];
        }
        else
        {
            self.inputAccessoryView = nil;
        }
        
        return [super canBecomeFirstResponder];
    }
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender
{
	RichTextEditorFeature features = [self featuresEnabledForRichTextEditorToolbar];
	
	if ([self.dataSource respondsToSelector:@selector(shouldDisplayRichTextOptionsInMenuControllerForRichTextEditor:)] &&
		[self.dataSource shouldDisplayRichTextOptionsInMenuControllerForRichTextEditor:self])
	{
		if (action == @selector(richTextEditorToolbarDidSelectBold) && (features & RichTextEditorFeatureBold  || features & RichTextEditorFeatureAll))
			return YES;
		
		if (action == @selector(richTextEditorToolbarDidSelectItalic) && (features & RichTextEditorFeatureItalic  || features & RichTextEditorFeatureAll))
			return YES;
		
		if (action == @selector(richTextEditorToolbarDidSelectUnderline) && (features & RichTextEditorFeatureUnderline  || features & RichTextEditorFeatureAll))
			return YES;
		
		if (action == @selector(richTextEditorToolbarDidSelectStrikeThrough) && (features & RichTextEditorFeatureStrikeThrough  || features & RichTextEditorFeatureAll))
			return YES;
	}
	
	if (action == @selector(selectParagraph:) && self.selectedRange.length > 0)
		return YES;
	
    if ((action == @selector(richTextEditorToolbarDidSelectBold) ||
         action == @selector(richTextEditorToolbarDidSelectItalic) ||
         action == @selector(richTextEditorToolbarDidSelectUnderline) ||
         action == @selector(richTextEditorToolbarDidSelectStrikeThrough)) &&
         features == RichTextEditorFeatureNone) {
        return NO;
    }
    
	return [super canPerformAction:action withSender:sender];
}

- (void)setAttributedText:(NSAttributedString *)attributedText
{
	[super setAttributedText:attributedText];
	[self updateToolbarState];
}

- (void)setText:(NSString *)text
{
	[super setText:text];
	[self updateToolbarState];
    [self updateLabelPlaceHolderState];
}

- (void)setFont:(UIFont *)font
{
	[super setFont:font];
	[self updateToolbarState];
}

#pragma mark - MenuController Methods -

- (void)setupMenuItems
{
	UIMenuItem *selectParagraph = [[UIMenuItem alloc] initWithTitle:@"Select Paragraph" action:@selector(selectParagraph:)];
	UIMenuItem *boldItem = [[UIMenuItem alloc] initWithTitle:@"Bold" action:@selector(richTextEditorToolbarDidSelectBold)];
	UIMenuItem *italicItem = [[UIMenuItem alloc] initWithTitle:@"Italic" action:@selector(richTextEditorToolbarDidSelectItalic)];
	UIMenuItem *underlineItem = [[UIMenuItem alloc] initWithTitle:@"Underline" action:@selector(richTextEditorToolbarDidSelectUnderline)];
	UIMenuItem *strikeThroughItem = [[UIMenuItem alloc] initWithTitle:@"Strike" action:@selector(richTextEditorToolbarDidSelectStrikeThrough)];
	
	[[UIMenuController sharedMenuController] setMenuItems:@[selectParagraph, boldItem, italicItem, underlineItem, strikeThroughItem]];
}

- (void)selectParagraph:(id)sender
{
	NSRange range = [self.attributedText firstParagraphRangeFromTextRange:self.selectedRange];
	[self setSelectedRange:range];

	[[UIMenuController sharedMenuController] setTargetRect:[self frameOfTextAtRange:self.selectedRange] inView:self];
	[[UIMenuController sharedMenuController] setMenuVisible:YES animated:YES];
}

#pragma mark - Public Methods -

- (void)setHtmlString:(NSString *)htmlString
{
	if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))
	{
		NSLog(@"Method setHtmlString is only supported on iOS 7 and above");
		return;
	}

	NSError *error ;
	NSData *data = [htmlString dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableAttributedString *str = [[NSMutableAttributedString alloc] initWithData:data
                                                                             options:@{NSDocumentTypeDocumentAttribute : NSHTMLTextDocumentType,
                                                                                       NSCharacterEncodingDocumentAttribute : [NSNumber numberWithInt:NSUTF8StringEncoding]}
                                                                  documentAttributes:nil error:&error];
    
    NSRange rang = (NSRange){0,[str length]};
    __block NSDictionary<NSString *, id> *currentAttributes;
    [str enumerateAttributesInRange:rang options:NSAttributedStringEnumerationLongestEffectiveRangeNotRequired usingBlock:^(NSDictionary<NSString *, id> *attributes, NSRange range, BOOL *stop) {
        
        if (rang.length == (range.length + range.location)) {
            [str addAttributes:currentAttributes range:range];
        }
        
        currentAttributes = attributes;
    }];
	
	if (error)
		NSLog(@"%@", error);
	else
		self.attributedText = str;
}

- (NSString *)htmlString
{
	if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))
	{
		NSLog(@"Method setHtmlString is only supported on iOS 7 and above");
		return nil;
	}
	
//	NSData *data = [self.attributedText dataFromRange:NSMakeRange(0, self.text.length) documentAttributes:@{NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
//																							 NSCharacterEncodingDocumentAttribute: [NSNumber numberWithInt:NSUTF8StringEncoding]}
//								 error:nil];
//	
//	return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	return [self.attributedText htmlString];
}

- (void)setBorderColor:(UIColor *)borderColor
{
    self.layer.borderColor = borderColor.CGColor;
}

- (void)setBorderWidth:(CGFloat)borderWidth
{
    self.layer.borderWidth = borderWidth;
}

#pragma mark - RichTextEditorToolbarDelegate Methods -

- (void)richTextEditorToolbarDidSelectBold
{
//	UIFont *font = [self fontAtIndex:self.selectedRange.location];
    UIFont *font = [[self typingAttributes] objectForKey:NSFontAttributeName];
	[self applyFontAttributesToSelectedRangeWithBoldTrait:[NSNumber numberWithBool:![font isBold]] italicTrait:nil fontName:nil fontSize:nil];
}

- (void)richTextEditorToolbarDidSelectItalic
{
//	UIFont *font = [self fontAtIndex:self.selectedRange.location];
    UIFont *font = [[self typingAttributes] objectForKey:NSFontAttributeName];
	[self applyFontAttributesToSelectedRangeWithBoldTrait:nil italicTrait:[NSNumber numberWithBool:![font isItalic]] fontName:nil fontSize:nil];
}

- (void)richTextEditorToolbarDidSelectFontSize:(NSNumber *)fontSize
{
	[self applyFontAttributesToSelectedRangeWithBoldTrait:nil italicTrait:nil fontName:nil fontSize:fontSize];
}

- (void)richTextEditorToolbarDidSelectFontWithName:(NSString *)fontName
{
	[self applyFontAttributesToSelectedRangeWithBoldTrait:nil italicTrait:nil fontName:fontName fontSize:nil];
}

- (void)richTextEditorToolbarDidSelectTextBackgroundColor:(UIColor *)color
{
	if (color)
		[self applyAttrubutesToSelectedRange:color forKey:NSBackgroundColorAttributeName];
	else
		[self removeAttributeForKeyFromSelectedRange:NSBackgroundColorAttributeName];
}

- (void)richTextEditorToolbarDidSelectTextForegroundColor:(UIColor *)color
{
	if (color)
		[self applyAttrubutesToSelectedRange:color forKey:NSForegroundColorAttributeName];
	else
		[self removeAttributeForKeyFromSelectedRange:NSForegroundColorAttributeName];
}

- (void)richTextEditorToolbarDidSelectUnderline
{
//	NSDictionary *dictionary = [self dictionaryAtIndex:self.selectedRange.location];
//	NSNumber *existingUnderlineStyle = [dictionary objectForKey:NSUnderlineStyleAttributeName];
    NSNumber *existingUnderlineStyle = [self.typingAttributes objectForKey:NSUnderlineStyleAttributeName];
	
	if (!existingUnderlineStyle || existingUnderlineStyle.intValue == NSUnderlineStyleNone)
		existingUnderlineStyle = [NSNumber numberWithInteger:NSUnderlineStyleSingle];
	else
		existingUnderlineStyle = [NSNumber numberWithInteger:NSUnderlineStyleNone];
	
	[self applyAttrubutesToSelectedRange:existingUnderlineStyle forKey:NSUnderlineStyleAttributeName];
}

- (void)richTextEditorToolbarDidSelectStrikeThrough
{
//	NSDictionary *dictionary = [self dictionaryAtIndex:self.selectedRange.location];
//	NSNumber *existingUnderlineStyle = [dictionary objectForKey:NSStrikethroughStyleAttributeName];
    NSNumber *existingUnderlineStyle = [self.typingAttributes objectForKey:NSStrikethroughStyleAttributeName];
	
	if (!existingUnderlineStyle || existingUnderlineStyle.intValue == NSUnderlineStyleNone)
		existingUnderlineStyle = [NSNumber numberWithInteger:NSUnderlineStyleSingle];
	else
		existingUnderlineStyle = [NSNumber numberWithInteger:NSUnderlineStyleNone];
	
	[self applyAttrubutesToSelectedRange:existingUnderlineStyle forKey:NSStrikethroughStyleAttributeName];
}

- (void)richTextEditorToolbarDidSelectParagraphIndentation:(ParagraphIndentation)paragraphIndentation
{
	[self enumarateThroughParagraphsInRange:self.selectedRange withBlock:^(NSRange paragraphRange){
		NSDictionary *dictionary = [self dictionaryAtIndex:paragraphRange.location];
		NSMutableParagraphStyle *paragraphStyle = [[dictionary objectForKey:NSParagraphStyleAttributeName] mutableCopy];
		
		if (!paragraphStyle)
			paragraphStyle = [[NSMutableParagraphStyle alloc] init];
		
		if (paragraphIndentation == ParagraphIndentationIncrease)
		{
			paragraphStyle.headIndent += self.defaultIndentationSize;
			paragraphStyle.firstLineHeadIndent += self.defaultIndentationSize;
		}
		else if (paragraphIndentation == ParagraphIndentationDecrease)
		{
			paragraphStyle.headIndent -= self.defaultIndentationSize;
			paragraphStyle.firstLineHeadIndent -= self.defaultIndentationSize;
			
			if (paragraphStyle.headIndent < 0)
				paragraphStyle.headIndent = 0;
			
			if (paragraphStyle.firstLineHeadIndent < 0)
				paragraphStyle.firstLineHeadIndent = 0;
		}
		
		[self applyAttributes:paragraphStyle forKey:NSParagraphStyleAttributeName atRange:paragraphRange];
	}];
}

- (void)richTextEditorToolbarDidSelectParagraphFirstLineHeadIndent
{
	[self enumarateThroughParagraphsInRange:self.selectedRange withBlock:^(NSRange paragraphRange){
		NSDictionary *dictionary = [self dictionaryAtIndex:paragraphRange.location];
		NSMutableParagraphStyle *paragraphStyle = [[dictionary objectForKey:NSParagraphStyleAttributeName] mutableCopy];
		
		if (!paragraphStyle)
			paragraphStyle = [[NSMutableParagraphStyle alloc] init];
		
		if (paragraphStyle.headIndent == paragraphStyle.firstLineHeadIndent)
		{
			paragraphStyle.firstLineHeadIndent += self.defaultIndentationSize;
		}
		else
		{
			paragraphStyle.firstLineHeadIndent = paragraphStyle.headIndent;
		}
		
		[self applyAttributes:paragraphStyle forKey:NSParagraphStyleAttributeName atRange:paragraphRange];
	}];
}

- (void)richTextEditorToolbarDidSelectTextAlignment:(NSTextAlignment)textAlignment
{
	[self enumarateThroughParagraphsInRange:self.selectedRange withBlock:^(NSRange paragraphRange){
		NSDictionary *dictionary = [self dictionaryAtIndex:paragraphRange.location];
		NSMutableParagraphStyle *paragraphStyle = [[dictionary objectForKey:NSParagraphStyleAttributeName] mutableCopy];
		
		if (!paragraphStyle)
			paragraphStyle = [[NSMutableParagraphStyle alloc] init];
		
		paragraphStyle.alignment = textAlignment;
		
		[self applyAttributes:paragraphStyle forKey:NSParagraphStyleAttributeName atRange:paragraphRange];
	}];
}

- (void)richTextEditorToolbarDidSelectBulletList
{
	NSRange initialSelectedRange = self.selectedRange;
	NSArray *rangeOfParagraphsInSelectedText = [self.attributedText rangeOfParagraphsFromTextRange:self.selectedRange];
	NSRange rangeOfFirstParagraphRange = [self.attributedText firstParagraphRangeFromTextRange:self.selectedRange];
	BOOL firstParagraphHasBullet = ([[[self.attributedText string] substringFromIndex:rangeOfFirstParagraphRange.location] hasPrefix:BULLET_STRING]) ? YES: NO;
	
	__block NSInteger rangeOffset = 0;
	
	[self enumarateThroughParagraphsInRange:self.selectedRange withBlock:^(NSRange paragraphRange){
		NSRange range = NSMakeRange(paragraphRange.location + rangeOffset, paragraphRange.length);
		NSMutableAttributedString *currentAttributedString = [self.attributedText mutableCopy];
		NSDictionary *dictionary = [self dictionaryAtIndex:MAX((int)range.location-1, 0)];
		NSMutableParagraphStyle *paragraphStyle = [[dictionary objectForKey:NSParagraphStyleAttributeName] mutableCopy];
		
		if (!paragraphStyle)
			paragraphStyle = [[NSMutableParagraphStyle alloc] init];
		
		BOOL currentParagraphHasBullet = ([[[currentAttributedString string] substringFromIndex:range.location] hasPrefix:BULLET_STRING]) ? YES : NO;
		
		if (firstParagraphHasBullet != currentParagraphHasBullet)
			return;
		
		if (currentParagraphHasBullet)
		{
			range = NSMakeRange(range.location, range.length - BULLET_STRING.length);
			
			[currentAttributedString deleteCharactersInRange:NSMakeRange(range.location, BULLET_STRING.length)];
			
			paragraphStyle.firstLineHeadIndent = 0;
			paragraphStyle.headIndent = 0;
			
			rangeOffset = rangeOffset - BULLET_STRING.length;
		}
		else
		{
			range = NSMakeRange(range.location, range.length + BULLET_STRING.length);
			
			// The bullet should be bold
			NSMutableAttributedString *bulletAttributedString = [[NSMutableAttributedString alloc] initWithString:BULLET_STRING attributes:nil];
			[bulletAttributedString setAttributes:dictionary range:NSMakeRange(0, BULLET_STRING.length)];
			
			[currentAttributedString insertAttributedString:bulletAttributedString atIndex:range.location];
			
			CGSize expectedStringSize = [BULLET_STRING sizeWithFont:[dictionary objectForKey:NSFontAttributeName]
												  constrainedToSize:CGSizeMake(MAXFLOAT, MAXFLOAT)
													  lineBreakMode:NSLineBreakByWordWrapping];
			
			paragraphStyle.firstLineHeadIndent = 0;
			paragraphStyle.headIndent = expectedStringSize.width;
			
			rangeOffset = rangeOffset + BULLET_STRING.length;
		}
		
		self.attributedText = currentAttributedString;
		[self applyAttributes:paragraphStyle forKey:NSParagraphStyleAttributeName atRange:range];
	}];
	
	// If paragraph is empty move cursor to front of bullet, so the user can start typing right away
	if (rangeOfParagraphsInSelectedText.count == 1 && rangeOfFirstParagraphRange.length == 0)
	{
		[self setSelectedRange:NSMakeRange(rangeOfFirstParagraphRange.location + BULLET_STRING.length, 0)];
	}
	else
	{
		if (initialSelectedRange.length == 0)
		{
			[self setSelectedRange:NSMakeRange(initialSelectedRange.location+rangeOffset, 0)];
		}
		else
		{
			NSRange fullRange = [self fullRangeFromArrayOfParagraphRanges:rangeOfParagraphsInSelectedText];
			[self setSelectedRange:NSMakeRange(fullRange.location, fullRange.length+rangeOffset)];
		}
	}
}

- (void)richTextEditorToolbarDidSelectTextAttachment:(UIImage *)textAttachment
{
	NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
	[attachment setImage:textAttachment];
	NSAttributedString *attributedStringAttachment = [NSAttributedString attributedStringWithAttachment:attachment];
	
	NSDictionary *previousAttributes = [self dictionaryAtIndex:self.selectedRange.location];
	
	NSMutableAttributedString *attributedString = [self.attributedText mutableCopy];
	[attributedString insertAttributedString:attributedStringAttachment atIndex:self.selectedRange.location];
	[attributedString addAttributes:previousAttributes range:NSMakeRange(self.selectedRange.location, 1)];
	self.attributedText = attributedString;
}

/// UNDO AND REDO

/**
 *  Undo and redo Actions
 *
 *  @since 25/01/14
 *  @author Rodrigo Arantes
 */
- (void)richTextEditorToolbarDidSelectUndo{
    [self.undoManager undo];
    [self updateUndoAndRedoState];
}

- (void)richTextEditorToolbarDidSelectRedo{
    [self.undoManager redo];
    [self updateUndoAndRedoState];
}

- (void)richTextEditorToolbarDidSelectHyperlink{
    [self.richTextDelegate didTouchHyperlinkButton:self];
}

#pragma mark - TEXT VIEW DELEGATE

/**
 *  Update undo and redo state
 *
 *  @since 25/01/14
 *  @author Rodrigo Arantes
 */
- (void)textViewDidChange:(UITextView *)textView{
    [self updateUndoAndRedoState];
    
    if([self.richTextDelegate respondsToSelector:@selector(textViewDidChange:)]){
        [self.richTextDelegate textViewDidChange:(RichTextEditor *)textView];
    }
}

- (void)updateUndoAndRedoState{
    self.toolBar.btnRedo.enabled = [self.undoManager canRedo];
    self.toolBar.btnUndo.enabled = [self.undoManager canUndo];
}

#pragma mark - Private Methods -

- (CGRect)frameOfTextAtRange:(NSRange)range
{
	UITextRange *selectionRange = [self selectedTextRange];
	NSArray *selectionRects = [self selectionRectsForRange:selectionRange];
	CGRect completeRect = CGRectNull;
	
	for (UITextSelectionRect *selectionRect in selectionRects)
	{
		completeRect = (CGRectIsNull(completeRect))
			? selectionRect.rect
			: CGRectUnion(completeRect,selectionRect.rect);
	}
	
	return completeRect;
}

- (void)enumarateThroughParagraphsInRange:(NSRange)range withBlock:(void (^)(NSRange paragraphRange))block
{
	NSArray *rangeOfParagraphsInSelectedText = [self.attributedText rangeOfParagraphsFromTextRange:self.selectedRange];
	
	for (int i=0 ; i<rangeOfParagraphsInSelectedText.count ; i++)
	{
		NSValue *value = [rangeOfParagraphsInSelectedText objectAtIndex:i];
		NSRange paragraphRange = [value rangeValue];
		block(paragraphRange);
	}
	
	NSRange fullRange = [self fullRangeFromArrayOfParagraphRanges:rangeOfParagraphsInSelectedText];
	[self setSelectedRange:fullRange];
}

- (void)updateToolbarState
{
	// There is a bug in iOS6 that causes a crash when accessing typingAttribute on an empty text
	if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0") && ![self hasText])
		return;
	
	// If no text exists or typing attributes is in progress update toolbar using typing attributes instead of selected text
	if (self.typingAttributesInProgress || ![self hasText])
	{
		[self.toolBar updateStateWithAttributes:self.typingAttributes];
	}
	else
	{
		NSInteger location = (self.selectedRange.length == 0)
			? MAX((int)self.selectedRange.location-1, 0)
			: (int)self.selectedRange.location;
		
		NSDictionary *attributes = [self.attributedText attributesAtIndex:location effectiveRange:nil];
		[self.toolBar updateStateWithAttributes:attributes];
	}
}

- (NSRange)fullRangeFromArrayOfParagraphRanges:(NSArray *)paragraphRanges
{
	if (!paragraphRanges.count)
		return NSMakeRange(0, 0);
	
	NSRange firstRange = [[paragraphRanges objectAtIndex:0] rangeValue];
	NSRange lastRange = [[paragraphRanges lastObject] rangeValue];
	return NSMakeRange(firstRange.location, lastRange.location + lastRange.length - firstRange.location);
}

- (UIFont *)fontAtIndex:(NSInteger)index
{
	// If index at end of string, get attributes starting from previous character
	if (index == self.attributedText.string.length && [self hasText])
		--index;
    
	// If no text exists get font from typing attributes
    NSDictionary *dictionary = ([self hasText])
		? [self.attributedText attributesAtIndex:index effectiveRange:nil]
		: self.typingAttributes;
    
    return [dictionary objectForKey:NSFontAttributeName];
}

- (NSDictionary *)dictionaryAtIndex:(NSInteger)index
{
	// If index at end of string, get attributes starting from previous character
	if (index == self.attributedText.string.length && [self hasText])
        --index;
	
    // If no text exists get font from typing attributes
    return  ([self hasText])
		? [self.attributedText attributesAtIndex:index effectiveRange:nil]
		: self.typingAttributes;
}

- (void)applyAttributeToTypingAttribute:(id)attribute forKey:(NSString *)key
{
	NSMutableDictionary *dictionary = [self.typingAttributes mutableCopy];
	[dictionary setObject:attribute forKey:key];
	[self setTypingAttributes:dictionary];
}

- (void)applyAttributes:(id)attribute forKey:(NSString *)key atRange:(NSRange)range
{
    if([self.richTextDelegate respondsToSelector:@selector(textViewDidApplyNewAttributes:)]){
        [self.richTextDelegate textViewDidApplyNewAttributes:self];
    }
    
	// If any text selected apply attributes to text
	if (range.length > 0)
	{
		NSMutableAttributedString *attributedString = [self.attributedText mutableCopy];
		
        // Workaround for when there is only one paragraph,
		// sometimes the attributedString is actually longer by one then the displayed text,
		// and this results in not being able to set to lef align anymore.
        if (range.length == attributedString.length-1 && range.length == self.text.length)
            ++range.length;
        
		[attributedString addAttributes:[NSDictionary dictionaryWithObject:attribute forKey:key] range:range];
		
		[self setAttributedText:attributedString];
		[self setSelectedRange:range];
	}
	// If no text is selected apply attributes to typingAttribute
	else
	{
		self.typingAttributesInProgress = YES;
		[self applyAttributeToTypingAttribute:attribute forKey:key];
	}
	
	[self updateToolbarState];
}

- (void)removeAttributeForKey:(NSString *)key atRange:(NSRange)range
{
	NSRange initialRange = self.selectedRange;
	
	NSMutableAttributedString *attributedString = [self.attributedText mutableCopy];
	[attributedString removeAttribute:key range:range];
	self.attributedText = attributedString;
	
	[self setSelectedRange:initialRange];
}

- (void)removeAttributeForKeyFromSelectedRange:(NSString *)key
{
	[self removeAttributeForKey:key atRange:self.selectedRange];
}

- (void)applyAttrubutesToSelectedRange:(id)attribute forKey:(NSString *)key
{
	[self applyAttributes:attribute forKey:key atRange:self.selectedRange];
}

- (void)applyFontAttributesToSelectedRangeWithBoldTrait:(NSNumber *)isBold italicTrait:(NSNumber *)isItalic fontName:(NSString *)fontName fontSize:(NSNumber *)fontSize
{
	[self applyFontAttributesWithBoldTrait:isBold italicTrait:isItalic fontName:fontName fontSize:fontSize toTextAtRange:self.selectedRange];
}

- (void)applyFontAttributesWithBoldTrait:(NSNumber *)isBold italicTrait:(NSNumber *)isItalic fontName:(NSString *)fontName fontSize:(NSNumber *)fontSize toTextAtRange:(NSRange)range
{
    if([self.richTextDelegate respondsToSelector:@selector(textViewDidApplyNewAttributes:)]){
        [self.richTextDelegate textViewDidApplyNewAttributes:self];
    }
    
	// If any text selected apply attributes to tex
	if (range.length > 0)
	{
		NSMutableAttributedString *attributedString = [self.attributedText mutableCopy];
		
		[attributedString beginEditing];
		[attributedString enumerateAttributesInRange:range
											 options:NSAttributedStringEnumerationLongestEffectiveRangeNotRequired
										  usingBlock:^(NSDictionary *dictionary, NSRange range, BOOL *stop){
											  
											  UIFont *newFont = [self fontwithBoldTrait:isBold
																			italicTrait:isItalic
																			   fontName:fontName
																			   fontSize:fontSize
																		 fromDictionary:dictionary];
											  
											  if (newFont)
												  [attributedString addAttributes:[NSDictionary dictionaryWithObject:newFont forKey:NSFontAttributeName] range:range];
										  }];
		[attributedString endEditing];
		self.attributedText = attributedString;
		
		[self setSelectedRange:range];
	}
	// If no text is selected apply attributes to typingAttribute
	else
	{		
		self.typingAttributesInProgress = YES;
		
		UIFont *newFont = [self fontwithBoldTrait:isBold
									  italicTrait:isItalic
										 fontName:fontName
										 fontSize:fontSize
								   fromDictionary:self.typingAttributes];
		if (newFont) 
            [self applyAttributeToTypingAttribute:newFont forKey:NSFontAttributeName];
	}
	
	[self updateToolbarState];
}

// Returns a font with given attributes. For any missing parameter takes the attribute from a given dictionary
- (UIFont *)fontwithBoldTrait:(NSNumber *)isBold italicTrait:(NSNumber *)isItalic fontName:(NSString *)fontName fontSize:(NSNumber *)fontSize fromDictionary:(NSDictionary *)dictionary
{
	UIFont *newFont = nil;
	UIFont *font = [dictionary objectForKey:NSFontAttributeName];
	BOOL newBold = (isBold) ? isBold.intValue : [font isBold];
	BOOL newItalic = (isItalic) ? isItalic.intValue : [font isItalic];
	CGFloat newFontSize = (fontSize) ? fontSize.floatValue : font.pointSize;
	
	if (fontName)
	{
		newFont = [UIFont fontWithName:fontName size:newFontSize boldTrait:newBold italicTrait:newItalic];
	}
	else
	{
		newFont = [font fontWithBoldTrait:newBold italicTrait:newItalic andSize:newFontSize];
	}
	
	return newFont;
}

- (CGRect)currentScreenBoundsDependOnOrientation
{
    CGRect screenBounds = [UIScreen mainScreen].bounds ;
    CGFloat width = CGRectGetWidth(screenBounds)  ;
    CGFloat height = CGRectGetHeight(screenBounds) ;
    UIInterfaceOrientation interfaceOrientation = [UIApplication sharedApplication].statusBarOrientation;
	
    if (UIInterfaceOrientationIsPortrait(interfaceOrientation))
	{
        screenBounds.size = CGSizeMake(width, height);
    }
	else if (UIInterfaceOrientationIsLandscape(interfaceOrientation))
	{
        screenBounds.size = CGSizeMake(height, width);
    }
	
    return screenBounds ;
}

- (void)applyBulletListIfApplicable
{
	NSRange rangeOfCurrentParagraph = [self.attributedText firstParagraphRangeFromTextRange:self.selectedRange];
	if (rangeOfCurrentParagraph.length != 0)
		return;
    
    NSRange range;
    if (rangeOfCurrentParagraph.location == 0) {
        range = NSMakeRange(0, 0);
    } else {
        range = NSMakeRange(rangeOfCurrentParagraph.location-1, 0);
    }
	
	NSRange rangeOfPreviousParagraph = [self.attributedText firstParagraphRangeFromTextRange:range];
	if ([[self.attributedText.string substringFromIndex:rangeOfPreviousParagraph.location] hasPrefix:BULLET_STRING])
		[self richTextEditorToolbarDidSelectBulletList];
}

- (void)deleteBulletListWhenApplicable
{
	NSRange range = self.selectedRange;
	
	if (range.location > 0)
	{
		if ((int)range.location-2 >= 0 && [[self.attributedText.string substringFromIndex:range.location-2] hasPrefix:@"\t•"])
		{
			NSMutableAttributedString *mutableAttributedString = [self.attributedText mutableCopy];
			[mutableAttributedString deleteCharactersInRange:NSMakeRange(range.location-2, 2)];
			self.attributedText = mutableAttributedString;
			[self setSelectedRange:NSMakeRange(range.location-2, 0)];
		}
	}
}

#pragma mark - RichTextEditorToolbarDataSource Methods -

- (NSArray *)fontFamilySelectionForRichTextEditorToolbar
{
	
    
    if(!self.googleDriveFonts){
        if (self.dataSource && [self.dataSource respondsToSelector:@selector(fontFamilySelectionForRichTextEditor:)])
        {
            return [self.dataSource fontFamilySelectionForRichTextEditor:self];
        }
    } else {
        return self.googleDriveFonts;
    }
	
	return nil;
}

- (NSArray *)fontSizeSelectionForRichTextEditorToolbar
{
	if (self.dataSource && [self.dataSource respondsToSelector:@selector(fontSizeSelectionForRichTextEditor:)])
	{
		return [self.dataSource fontSizeSelectionForRichTextEditor:self];
	}
	
	return nil;
}

- (RichTextEditorToolbarPresentationStyle)presentationStyleForRichTextEditorToolbar
{
	if (self.dataSource && [self.dataSource respondsToSelector:@selector(presentationStyleForRichTextEditor:)])
	{
		return [self.dataSource presentationStyleForRichTextEditor:self];
	}

	return (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
		? RichTextEditorToolbarPresentationStylePopover
		: RichTextEditorToolbarPresentationStyleModal;
}

- (UIModalPresentationStyle)modalPresentationStyleForRichTextEditorToolbar
{
	if (self.dataSource && [self.dataSource respondsToSelector:@selector(modalPresentationStyleForRichTextEditor:)])
	{
		return [self.dataSource modalPresentationStyleForRichTextEditor:self];
	}
	
	return (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
		? UIModalPresentationFormSheet
		: UIModalPresentationFullScreen;
}

- (UIModalTransitionStyle)modalTransitionStyleForRichTextEditorToolbar
{
	if (self.dataSource && [self.dataSource respondsToSelector:@selector(modalTransitionStyleForRichTextEditor:)])
	{
		return [self.dataSource modalTransitionStyleForRichTextEditor:self];
	}
	
	return UIModalTransitionStyleCoverVertical;
}

- (RichTextEditorFeature)featuresEnabledForRichTextEditorToolbar
{
	if (self.dataSource && [self.dataSource respondsToSelector:@selector(featuresEnabledForRichTextEditor:)])
	{
		return [self.dataSource featuresEnabledForRichTextEditor:self];
	}
	
	return RichTextEditorFeatureAll;
}

- (UIViewController *)firsAvailableViewControllerForRichTextEditorToolbar
{
	return [self firstAvailableViewController];
}

#pragma mark - Add HyperLink

/**
 *  Add a hyperlink
 *
 *  @since 27/01/14
 *  @author Rodrigo Arantes
 */
- (void)addHyperLinkForStringUrl:(NSString *)stringUrl{
    
    NSRange range = self.selectedRange;
    
    NSMutableAttributedString *mutableAttributedString = [self.attributedText mutableCopy];
    NSDictionary *attributes = @{NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle), NSForegroundColorAttributeName : [UIColor blueColor]};
    [mutableAttributedString insertAttributedString:[[NSAttributedString alloc] initWithString:stringUrl attributes:attributes] atIndex:range.location];
    self.attributedText = mutableAttributedString;
    
    // add non attribute
    mutableAttributedString = [self.attributedText mutableCopy];
    attributes = @{NSUnderlineStyleAttributeName: @(NSUnderlineStyleNone), NSForegroundColorAttributeName : [UIColor blackColor]};
    [mutableAttributedString insertAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:attributes] atIndex:range.location + stringUrl.length];
    self.attributedText = mutableAttributedString;
    
}

#pragma mark - RICH TEXT DELEGATE

/**
 *  The rich text editor is using the UITextView delegate
 *  This delegate redirects to the the delegate richTextDelegate
 *
 *  @since 27/01/14
 *  @author Rodrigo Arantes
 */

- (void)textViewDidBeginEditing:(UITextView *)textView{
    if([self.richTextDelegate respondsToSelector:@selector(textViewDidBeginEditing:)]){
        [self.richTextDelegate textViewDidBeginEditing:(RichTextEditor *)textView];
    }
}

- (void)textViewDidEndEditing:(UITextView *)textView{
    if([self.richTextDelegate respondsToSelector:@selector(textViewDidEndEditing:)]){
        [self.richTextDelegate textViewDidEndEditing:(RichTextEditor *)textView];
    }
}

- (BOOL)textView:(RichTextEditor *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text{
    if([self.richTextDelegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)]){
        return [self.richTextDelegate textView:(RichTextEditor *)textView shouldChangeTextInRange:range replacementText:text];
    }
    
    return YES;
}

- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)characterRange {
    if([self.richTextDelegate respondsToSelector:@selector(textView:shouldInteractWithURL:inRange:)]){
        return [self.richTextDelegate textView:(RichTextEditor *)textView shouldInteractWithURL:URL inRange:characterRange];
    }
    return YES;
}

- (void)setFontName:(NSString *)fontName andfontSize:(CGFloat)fontSize
{
    NSMutableAttributedString *attributedString = [self.attributedText mutableCopy];
    
    [attributedString beginEditing];
    [attributedString enumerateAttributesInRange:NSMakeRange(0, self.text.length)
                                         options:NSAttributedStringEnumerationLongestEffectiveRangeNotRequired
                                      usingBlock:^(NSDictionary *dictionary, NSRange range, BOOL *stop){
                                          
                                          UIFont *newFont = [self fontwithBoldTrait:nil
                                                                        italicTrait:nil
                                                                           fontName:fontName
                                                                           fontSize:@(fontSize)
                                                                     fromDictionary:dictionary];
                                          
                                          if (newFont)
                                              [attributedString addAttributes:[NSDictionary dictionaryWithObject:newFont forKey:NSFontAttributeName] range:range];
                                      }];
    [attributedString endEditing];
    self.attributedText = attributedString;
}

#pragma mark - DEFAULT GOOGLE DRIVE FONTS

- (void)setDefaultGoogleDriveFonts{
    NSArray *fonts = @[@"Helvetica", @"Arial", @"Georgia", @"Courier New", @"Verdana", @"Times New Roman", @"Trebuchet MS", @"Helvetica Neue", @"Comic Sans MS"];
    _googleDriveFonts = [fonts sortedArrayUsingComparator:^NSComparisonResult(NSString *obj1, NSString *obj2) {
        return [obj1 compare:obj2];
    }];
}

#pragma mark - HELPERS

- (void)setupPlaceHolder{
    self.lblPlaceHolder = [[UILabel alloc] initWithFrame:CGRectZero];
    self.lblPlaceHolder.text = ([NSString isEmpty:self.placeHolderString] ? @"Text goes here..." : self.placeHolderString);
    self.lblPlaceHolder.font = self.font;
    [self setPlaceHolderTextColor:nil];
    [self updateLabelPlaceHolderState];
    [self.textInputView addSubview:self.lblPlaceHolder];
    [[[[[[AutoLayoutBuilder pinView:self.lblPlaceHolder] toLeadingWithAmount:5.f] toTrailingWithAmount:4.f] toTop] toBottom] install];
}

- (void)setPlaceHolderTextColor:(UIColor *)placeHolderTextColor{
    _placeHolderTextColor = placeHolderTextColor;
    [self.lblPlaceHolder setTextColor:(placeHolderTextColor != nil ? placeHolderTextColor : DEFAULT_PLACEHOLDER_COLOR)];
}

- (void)updateLabelPlaceHolderState{
    self.lblPlaceHolder.hidden = [self canHidePlaceHolder];
}

- (void)setPlaceHolderString:(NSString *)placeHolderString{
    _placeHolderString = placeHolderString;
    
    self.lblPlaceHolder.text = ([NSString isEmpty:self.placeHolderString] ? @"Text goes here..." : self.placeHolderString);
}

- (BOOL)canHidePlaceHolder{
    return self.text.length > 0;
}

@end
