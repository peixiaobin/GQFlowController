//
//  GQFlowController.h
//  GQFlowController
//
//  Created by 钱国强 on 13-3-24.
//  Copyright (c) 2014年 Qian GuoQiang (gonefish@gmail.com). All rights reserved.
//

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

typedef enum {
    GQFlowDirectionUnknow,
    GQFlowDirectionRight,
    GQFlowDirectionLeft,
    GQFlowDirectionUp,
    GQFlowDirectionDown
} GQFlowDirection;

@interface GQFlowController : UIViewController

// Like UINavigationController methods

/** Like initWithRootViewController:
 */
- (id)initWithRootViewController:(UIViewController *)rootViewController;

/** Like pushViewController:animated:
 */
- (void)flowInViewController:(UIViewController *)viewController animated:(BOOL)animated;


/** Like popViewControllerAnimated:
 */
- (UIViewController *)flowOutViewControllerAnimated:(BOOL)animated;


/** Like popToRootViewControllerAnimated:
 */
- (NSArray *)flowOutToRootViewControllerAnimated:(BOOL)animated;


/** Like popToViewController:animated:
 */
- (NSArray *)flowOutToViewController:(UIViewController *)viewController animated:(BOOL)animated;


/** Like setViewControllers:animated:
 */
- (void)setViewControllers:(NSArray *)viewControllers animated:(BOOL)animated;

@property (nonatomic, copy) NSArray *viewControllers;

@property (nonatomic, strong, readonly) UIViewController *topViewController;

/** 创建多个控制器的初始化方法
 */
- (id)initWithViewControllers:(NSArray *)viewControllers;

/** 滑动已经添加的视图控制器到指定位置

 */
- (void)flowingViewController:(UIViewController *)viewController toFrame:(CGRect)toFrame animationsBlock:(void(^)(void))animationsBlock completionBlock:(void(^)(BOOL finished))completionBlock;


@property (nonatomic, strong, readonly) UIPanGestureRecognizer *topViewPanGestureRecognizer;

@property (nonatomic) NSTimeInterval viewFlowingDuration;

@property (nonatomic) CGFloat viewFlowingBoundary;

@property (nonatomic) NSUInteger customSupportedInterfaceOrientations;

@property (nonatomic) BOOL customShouldAutorotate;

@end

/**
 实现这个协议来激活压住滑动功能
 */
@protocol GQViewController <UIGestureRecognizerDelegate>

@optional

/** 返回当前滑动方法的目标位置
 
 @param direction 滑动方位
 @return 目标位置
 */
- (CGRect)destinationRectForFlowDirection:(GQFlowDirection)direction;


/** 手势滑动时的UIViewController
 
 @param direction 滑动方位
 @return 滑动的视图控制器
 */
- (UIViewController *)viewControllerForFlowDirection:(GQFlowDirection)direction;


/** 滑动时是否移动到指定的位置
 
 @param frame 目标位置
 @return 是否应该滑动
 */
- (BOOL)shouldFlowToRect:(CGRect)frame;


/** 滑动手势移动结束
 */
- (void)didFlowToDestinationRect;


/** 触发自动滑动到目标位置的系数 
 
 @return 返回值在.0 ~ 1.0之间
 */
- (CGFloat)flowingBoundary;

/** 是否跟随Top View滑动，默认值为YES
 */
- (BOOL)shouldFollowAboveViewFlowing;

/** 滑动动画的持续时间
 
 @return 单位为秒
 */
- (NSTimeInterval)flowingDuration;


/** 是否自动处理覆盖层
 
 @return 默认为YES
 */
- (BOOL)shouldAutomaticallyOverlayContent;

/** 自定义覆盖层视图
 */
- (UIView *)overlayContentView;

/** 覆盖层的Tap Gesture Recongnizer Action
 */
- (void)overlayContentTapAction:(UITapGestureRecognizer *)gestureRecognizer;

@end

@interface UIViewController (GQFlowControllerAdditions)

@property (nonatomic, strong, readonly) GQFlowController *flowController;

@property (nonatomic) GQFlowDirection flowInDirection;

@property (nonatomic) GQFlowDirection flowOutDirection;

@property (nonatomic, getter=isOverlayContent) BOOL overlayContent;

@end