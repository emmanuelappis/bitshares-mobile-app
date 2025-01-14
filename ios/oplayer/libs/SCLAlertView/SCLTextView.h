//
//  SCLTextView.h
//  SCLAlertView
//
//  Created by Diogo Autilio on 9/18/15.
//  Copyright © 2015-2016 AnyKey Entertainment. All rights reserved.
//

#if defined(__has_feature) && __has_feature(modules)
@import UIKit;
#else
#import <UIKit/UIKit.h>
#endif

@interface SCLTextView : UITextField

@property (nonatomic, assign) BOOL bLimitInputThreshold;

- (BOOL)isValidAuthorityThreshold:(NSString*)new_string;

@end
