//
//  DBProfileSegmentedControlView.h
//  DBProfileViewController
//
//  Created by Devon Boyer on 2016-01-08.
//  Copyright (c) 2015 Devon Boyer. All rights reserved.
//
//  Released under an MIT license: http://opensource.org/licenses/MIT
//

#import <UIKit/UIKit.h>

@interface DBProfileSegmentedControlView : UIView

@property (nonatomic, strong) UISegmentedControl *segmentedControl;

@property (nonatomic, assign) BOOL showsTopBorder;
@property (nonatomic, assign) BOOL showsBottomBorder;

@end