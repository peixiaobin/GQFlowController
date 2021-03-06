//
//  GQFlowController.m
//  GQFlowController
//
//  Created by 钱国强 on 13-3-24.
//  Copyright (c) 2013年 Qian GuoQiang (gonefish@gmail.com). All rights reserved.
//

#import "GQFlowController.h"
#import <objc/runtime.h>

#define BELOW_VIEW_OFFSET_SCALE .6

/**
 
 @param belowRect 下层视图的原始位置
 @param startPoint 上层视图的开始点
 @param endPoint 上层视图的结束点
 @param direction 上层视图移动的方法
 */
static CGRect GQBelowViewRectOffset(CGRect belowRect, CGPoint startPoint, CGPoint endPoint, GQFlowDirection direction) {
    CGFloat belowVCOffset = .0;
    
    if (direction == GQFlowDirectionLeft
        || direction == GQFlowDirectionRight) {
        belowVCOffset = ABS(startPoint.x - endPoint.x) * BELOW_VIEW_OFFSET_SCALE;
    } else {
        belowVCOffset = ABS(startPoint.y - endPoint.y) * BELOW_VIEW_OFFSET_SCALE;
    }
    
    CGRect belowVCFrame = CGRectZero;
    
    switch (direction) {
        case GQFlowDirectionLeft:
            belowVCFrame = CGRectOffset(belowRect, -belowVCOffset, .0);
            break;
        case GQFlowDirectionRight:
            belowVCFrame = CGRectOffset(belowRect, belowVCOffset, .0);
            break;
        case GQFlowDirectionUp:
            belowVCFrame = CGRectOffset(belowRect, .0, -belowVCOffset);
            break;
        case GQFlowDirectionDown:
            belowVCFrame = CGRectOffset(belowRect, .0, belowVCOffset);
            break;
        default:
            break;
    }
    
    return belowVCFrame;
}

@interface GQFlowController ()

@property (nonatomic, strong) UIViewController *topViewController;
@property (nonatomic, strong) NSMutableArray *innerViewControllers;

@property (nonatomic) CGPoint startPoint;
@property (nonatomic) CGRect topViewOriginalFrame;
@property (nonatomic) CGRect belowViewOriginalFrame;
@property (nonatomic) GQFlowDirection flowingDirection;

@property (nonatomic, strong) UIPanGestureRecognizer *topViewPanGestureRecognizer;

@property (nonatomic) BOOL isAnimating;
@property (nonatomic) BOOL isPanFlowingIn;
@property (nonatomic) BOOL shouldBeginAppearance;

// 保存在内存警告中释放视图的frame
@property (nonatomic, strong) NSMutableDictionary *releaseViewInfos;

@end

@implementation GQFlowController
@dynamic viewControllers;

- (void)loadView
{    
    CGRect initFrame = [[UIScreen mainScreen] bounds];
    
    if ([[[UIDevice currentDevice] systemVersion] integerValue] < 7
        && [self respondsToSelector:@selector(wantsFullScreenLayout)]) {
        if (self.wantsFullScreenLayout == NO) {
            CGRect statusBarFrame = [[UIApplication sharedApplication] statusBarFrame];
            initFrame = CGRectMake(.0,
                                   statusBarFrame.size.height,
                                   initFrame.size.width,
                                   initFrame.size.height - statusBarFrame.size.height);
        }
    }
    
    self.view = [[UIView alloc] initWithFrame:initFrame];
    self.view.backgroundColor = [UIColor whiteColor];

    self.view.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // 计算需要添加的视图控制器
    NSArray *vcs = [self visibleViewControllers];
    
    for (UIViewController *vc in vcs) {
        [self addChildContentViewController:vc];
    }
    
    // 添加手势
    [self addPanGestureRecognizer];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    
    if ([self isViewLoaded] == NO) return;
    
    NSArray *newVC = [self visibleViewControllers];
    
    for (UIViewController *obj in self.innerViewControllers) {
        if (![newVC containsObject:obj]) {
            NSDictionary *viewInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                      NSStringFromCGRect(obj.view.frame), @"frame",
                                      [NSNumber numberWithBool:obj.isOverlayContent], @"isOverlayContent",
                                      nil];
            NSString *viewKey = [NSString stringWithFormat:@"%u", [obj hash]];
            
            (self.releaseViewInfos)[viewKey] = viewInfo;
            
            [obj.view removeFromSuperview];
            
            NSInteger systemVersion = [[[UIDevice currentDevice] systemVersion] integerValue];
            
            if (systemVersion < 6) {
                [obj viewWillUnload];
            }
            
            obj.view = nil;
            
            if (systemVersion < 6) {
                [obj viewDidUnload];
            }
        }
    }
}

- (BOOL)automaticallyForwardAppearanceAndRotationMethodsToChildViewControllers
{
    return NO;
}

- (BOOL)shouldAutomaticallyForwardRotationMethods
{
    return YES;
}

- (BOOL)shouldAutomaticallyForwardAppearanceMethods
{
    return NO;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self visibleViewControllersBeginAppearanceTransition:YES animated:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [self visibleViewControllersEndAppearanceTransition];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [self visibleViewControllersBeginAppearanceTransition:NO animated:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    [self visibleViewControllersEndAppearanceTransition];
}

- (BOOL)shouldAutorotate
{
    return self.customShouldAutorotate;
}

- (NSUInteger)supportedInterfaceOrientations
{
    return self.customSupportedInterfaceOrientations;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if (self.topViewController) {
        return [self.topViewController shouldAutorotateToInterfaceOrientation:interfaceOrientation];
    } else {
        return [super shouldAutorotateToInterfaceOrientation:interfaceOrientation];
    }
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [super willRotateToInterfaceOrientation:toInterfaceOrientation
                                   duration:duration];
    
    // iOS 5手动处理
    if ([[[UIDevice currentDevice] systemVersion] integerValue] == 5) {
        for (UIViewController *vc in self.innerViewControllers) {
            if ([vc shouldAutorotateToInterfaceOrientation:toInterfaceOrientation]) {
                [vc willRotateToInterfaceOrientation:toInterfaceOrientation
                                            duration:duration];
            }
        }
    }
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation duration:(NSTimeInterval)duration
{
    [super willAnimateRotationToInterfaceOrientation:interfaceOrientation
                                            duration:duration];
    
    // iOS 5手动处理
    if ([[[UIDevice currentDevice] systemVersion] integerValue] == 5) {
        for (UIViewController *vc in self.innerViewControllers) {
            if ([vc shouldAutorotateToInterfaceOrientation:interfaceOrientation]) {
                [vc willAnimateRotationToInterfaceOrientation:interfaceOrientation
                                                     duration:duration];
            }
        };
    }
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    
    // iOS 5手动处理
    if ([[[UIDevice currentDevice] systemVersion] integerValue] == 5) {
        for (UIViewController *vc in self.innerViewControllers) {
            if ([vc shouldAutorotateToInterfaceOrientation:fromInterfaceOrientation]) {
                [vc didRotateFromInterfaceOrientation:fromInterfaceOrientation];
            }  
        };
    }
}

- (void)dismissModalViewControllerAnimated:(BOOL)animated
{
    [self safeDismissFlowController];
    
    [super dismissModalViewControllerAnimated:animated];
}

- (void)dismissViewControllerAnimated:(BOOL)flag completion:(void (^)(void))completion
{
    [self safeDismissFlowController];
    
    [super dismissViewControllerAnimated:flag completion:completion];
}

#pragma mark - Public Method

- (id)init
{
    self = [super init];
    
    if (self) {
        self.viewFlowingBoundary = 0.15;
        
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
            self.customSupportedInterfaceOrientations = UIInterfaceOrientationMaskAllButUpsideDown;
            self.viewFlowingDuration = 0.3;
        } else {
            self.customSupportedInterfaceOrientations = UIInterfaceOrientationMaskAll;
            self.viewFlowingDuration = 1.0;
        }
        
        self.releaseViewInfos = [NSMutableDictionary dictionary];
    }
    
    return self;
}

- (id)initWithViewControllers:(NSArray *)viewControllers
{
    self = [self init];
    
    if (self) {
        self.viewControllers = viewControllers;
    }
    
    return self;
}

- (id)initWithRootViewController:(UIViewController *)rootViewController
{
    return [self initWithViewControllers:@[rootViewController]];
}

- (void)flowInViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    NSAssert([NSThread isMainThread], @"必须在主线程调用");
    
    if ([viewController isKindOfClass:[self class]]
        || self.isAnimating == YES) {
        return;
    }
    
    if ([self isViewLoaded]) {
        [self flowInViewController:viewController
                          animated:animated
                   completionBlock:nil];
    } else {
        [self.innerViewControllers addObject:viewController];
        
        self.topViewController = viewController;
    }
}

- (UIViewController *)flowOutViewControllerAnimated:(BOOL)animated
{
    NSAssert([NSThread isMainThread], @"必须在主线程调用");
    
    if (self.isAnimating == YES) {
        return nil;
    }
    
    if ([self.innerViewControllers count] > 1) {
        NSArray *popViewControllers = [self flowOutIndexSet:[NSIndexSet indexSetWithIndex:[self.innerViewControllers count] -1]
                                                   animated:animated];
        if ([popViewControllers count] == 1) {
            return popViewControllers[0];
        } else {
            return nil;
        }
    } else {
        return nil;
    }
}

- (NSArray *)flowOutToRootViewControllerAnimated:(BOOL)animated
{
    NSAssert([NSThread isMainThread], @"必须在主线程调用");
    
    if (self.isAnimating == YES) {
        return nil;
    }
    
    if ([self.innerViewControllers count] > 1) {
        NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, [self.innerViewControllers count] - 1)];
        
        return [self flowOutIndexSet:indexSet
                            animated:animated];
    } else {
        return nil;
    }
}

- (NSArray *)flowOutToViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    NSAssert([NSThread isMainThread], @"必须在主线程调用");
    
    if (self.isAnimating == YES) {
        return nil;
    }
    
    if ([self.innerViewControllers count] > 1) {
        __block NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
        
        [self.innerViewControllers enumerateObjectsWithOptions:NSEnumerationReverse
                                                    usingBlock:^(id obj, NSUInteger idx, BOOL *stop){
                                                        if (obj == viewController) {
                                                            *stop = YES;
                                                        } else {
                                                            [indexSet addIndex:idx];
                                                        }
                                                    }];
        
        return [self flowOutIndexSet:indexSet
                            animated:animated];
    } else {
        return nil;
    }
}

- (NSArray *)viewControllers
{
    return [self.innerViewControllers copy];
}

- (void)setViewControllers:(NSArray *)aViewControllers
{
    [self setViewControllers:aViewControllers animated:NO];
}

- (void)setViewControllers:(NSArray *)viewControllers animated:(BOOL)animated
{
    NSAssert([NSThread isMainThread], @"必须在主线程调用");
    
    if (self.isAnimating == YES) {
        return;
    }
    
    // 如果不是UIViewController的子类或自己，则过滤掉
    NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];

    [viewControllers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop){
        if (![obj isKindOfClass:[UIViewController class]]
            || [obj isKindOfClass:[self class]]) {
            [indexSet addIndex:idx];
        } else {
            [obj performSelector:@selector(setFlowController:)
                      withObject:self];
        }
    }];
    
    NSMutableArray *newArray = [viewControllers mutableCopy];
    
    [newArray removeObjectsAtIndexes:indexSet];
    
    if ([self isViewLoaded]) {
        if (animated) {
            if ([self.innerViewControllers containsObject:[newArray lastObject]]) {
                UIViewController *lastViewController = [self.innerViewControllers lastObject];
                
                if ([newArray lastObject] == lastViewController) {
                    // No Animate
                    [self holdViewControllers:@[[newArray lastObject]]];
                    
                    [self updateChildViewControllers:newArray];
                } else {
                    // Flow Out
                    // 保留最上面的视图控制器
                    [self holdViewControllers:@[lastViewController]];
                    
                    [newArray addObject:lastViewController];
                    
                    [self updateChildViewControllers:newArray];
                    
                    [self flowOutViewControllerAnimated:YES];
                }
            } else {
                // Flow In
                // 重构层级中的视图控制器
                UIViewController *flowInViewController = [newArray lastObject];
                
                [self flowInViewController:flowInViewController
                                  animated:animated
                           completionBlock:^(){
                               // 同上面 No Animate
                               [self holdViewControllers:@[[newArray lastObject]]];
                               
                               [self updateChildViewControllers:newArray];
                           }];
            }
        } else {
            [self removePanGestureRecognizer];
            
            // 移除现在的视图控制器
            [self removeAllChildContentViewControllers];
            
            [self updateChildViewControllers:newArray];
            
            [self addPanGestureRecognizer];
        }
    } else {
        self.innerViewControllers = newArray;
        
        self.topViewController = [newArray lastObject];
    }
}

- (void)flowingViewController:(UIViewController *)viewController toFrame:(CGRect)toFrame animationsBlock:(void(^)(void))animationsBlock completionBlock:(void(^)(BOOL finished))completionBlock
{
    NSAssert([NSThread isMainThread], @"必须在主线程调用");
    
    if (viewController.view.superview == nil
        || self.isAnimating) {
        return;
    }
    
    [self prepareBelowViewControllers];
    
    NSTimeInterval duration = self.viewFlowingDuration;
    
    if ([viewController respondsToSelector:@selector(flowingDuration)]) {
        duration = [(id <GQViewController>)viewController flowingDuration];
    }
    
    self.isAnimating = YES;
    
    [UIView animateWithDuration:duration
                     animations:^{
                         viewController.view.frame = toFrame;
                         
                         if (animationsBlock) {
                             animationsBlock();
                         }
                     }
                     completion:^(BOOL finished){
                         if (completionBlock) {
                             completionBlock(finished);
                         }
                         
                         self.isAnimating = NO;
                     }];
}


#pragma mark - Container View Controller Method

- (void)addChildContentViewController:(UIViewController *)childController
{
    [self addChildViewController:childController];
    
    [self.view addSubview:childController.view];
    
    [childController didMoveToParentViewController:self];
}

- (void)removeAllChildContentViewControllers
{
    for (UIViewController *vc in self.innerViewControllers) {
        [self removeChildContentViewControler:vc];
    }
}

- (void)holdViewControllers:(NSArray *)viewControllers
{
    // 移除没有指定的视图控制器
    for (UIViewController *vc in self.innerViewControllers) {
        if (viewControllers == nil
            || ![viewControllers containsObject:vc]) {
            [self removeChildContentViewControler:vc];
        }
    }
}

- (void)removeChildContentViewControler:(UIViewController *)viewController
{
    [viewController willMoveToParentViewController:nil];
    
    [viewController.view removeFromSuperview];
    
    [viewController removeFromParentViewController];
}

/**
 更新子控制器
 */
- (void)updateChildViewControllers:(NSMutableArray *)viewControllers
{
    self.innerViewControllers = viewControllers;
    
    self.topViewController = [viewControllers lastObject];
    
    [self layoutViewControllers];
}

- (void)addTopViewController:(UIViewController *)viewController
{
    // 设置UIViewControllerItem
    [viewController performSelector:@selector(setFlowController:)
                         withObject:self];
    
    self.topViewController = viewController;
    
    [self.innerViewControllers addObject:viewController];
    
    [self addChildContentViewController:viewController];
    
    viewController.view.frame = [self inOriginRectForViewController:viewController];
}

- (void)removeTopViewController
{
    [self removePanGestureRecognizer];
    
    [self removeChildContentViewControler:self.topViewController];
    
    // 不自己删除lastObject是因为确保viewControllers被设置时的正确性
    self.topViewController = [self.innerViewControllers lastObject];
}

/**
 重新对视图进行布局
 */
- (void)layoutViewControllers
{
    // 计算需要添加的视图控制器
    NSArray *vcs = [self visibleViewControllers];
    
    for (UIViewController *vc in vcs) {
        [self addChildContentViewController:vc];
    }
}


#pragma mark - Other Method

- (NSMutableArray *)innerViewControllers
{
    if (_innerViewControllers == nil) {
        _innerViewControllers = [NSMutableArray array];
    }
    
    return _innerViewControllers;
}

- (BOOL)shouldAutomaticallyOverlayContentForViewController:(UIViewController *)viewController
{
    BOOL yesOrNo = YES;
    
    if ([viewController respondsToSelector:@selector(shouldAutomaticallyOverlayContent)]) {
        yesOrNo = [(id <GQViewController>)viewController shouldAutomaticallyOverlayContent];
    }
    
    return yesOrNo;
}

- (void)flowInViewController:(UIViewController *)viewController animated:(BOOL)animated completionBlock:(void (^)(void))block
{
    UIViewController *belowVC = self.topViewController;
    
    // 添加到容器中，并设置将要滑入的起始位置
    [self addTopViewController:viewController];
    
    if ([self shouldAutomaticallyOverlayContentForViewController:belowVC]) {
        belowVC.overlayContent = YES;
    }
    
    if ([self shouldAutomaticallyOverlayContentForViewController:viewController]) {
        viewController.overlayContent = YES;
    }
    
    [viewController beginAppearanceTransition:YES
                                     animated:animated];
        
    [belowVC beginAppearanceTransition:NO
                              animated:animated];
    
    CGRect toFrame = [self inDestinationRectForViewController:viewController];
    
    CGRect belowVCFrame = GQBelowViewRectOffset(belowVC.view.frame,
                                                viewController.view.frame.origin,
                                                toFrame.origin,
                                                viewController.flowInDirection);
    
    void (^completionBlock)(BOOL) = ^(BOOL finished) {
        [viewController endAppearanceTransition];
        
        [belowVC endAppearanceTransition];
        
        if ([self shouldAutomaticallyOverlayContentForViewController:viewController]) {
            viewController.overlayContent = NO;
        }
        
        [self addPanGestureRecognizer];
        
        if (block) {
            block();
        }
    };

    if (animated) {
        [self flowingViewController:viewController
                            toFrame:toFrame
                    animationsBlock:^{
                        [self flowingBelowViewController:belowVC toRect:belowVCFrame];
                    }
                    completionBlock:completionBlock];
    } else {
        viewController.view.frame = toFrame;
        
        completionBlock(NO);
    }
}

- (NSArray *)flowOutIndexSet:(NSIndexSet *)indexSet animated:(BOOL)animated
{
    NSArray *flowOutVCs = [self.innerViewControllers objectsAtIndexes:indexSet];
    
    if ([self isViewLoaded]) {
        // 准备移除控制器
        NSMutableArray *popViewControllers = [flowOutVCs mutableCopy];
        
        [popViewControllers removeLastObject];
        
        [self.innerViewControllers removeObjectsInArray:popViewControllers];
        
        for (UIViewController *vc in popViewControllers) {
            // 设置UIViewController的flowController属性为nil
            [vc performSelector:@selector(setFlowController:)
                     withObject:nil];
            
            if (vc != self.topViewController) {
                [self removeChildContentViewControler:vc];
            }
        }

        UIViewController *belowVC = [self belowViewController];
        
        [self.topViewController beginAppearanceTransition:NO
                                                 animated:animated];
        
        // 确保视图已经添加
        NSArray *appearanceBelowViewControllers = [self prepareBelowViewControllers];
        
        for (UIViewController *vc in appearanceBelowViewControllers) {
            [vc beginAppearanceTransition:YES
                                 animated:animated];
        }
        
        if ([self shouldAutomaticallyOverlayContentForViewController:self.topViewController]) {
            self.topViewController.overlayContent = YES;
        }
        
        if ([self shouldAutomaticallyOverlayContentForViewController:belowVC]) {
            belowVC.overlayContent = YES;
        }
        
        CGRect toFrame = [self outDestinationRectForViewController:self.topViewController];
        
        CGRect belowVCFrame = GQBelowViewRectOffset(belowVC.view.frame,
                                                    self.topViewController.view.frame.origin,
                                                    toFrame.origin,
                                                    self.topViewController.flowOutDirection);

        void (^animationsBlock)(void) = ^{
            [self flowingBelowViewController:belowVC toRect:belowVCFrame];
        };
        
        void (^completionBlock)(BOOL) = ^(BOOL finished) {
            [self.topViewController endAppearanceTransition];
            
            for (UIViewController *vc in appearanceBelowViewControllers) {
                [vc endAppearanceTransition];
            }
            
            [self.innerViewControllers removeLastObject];
            
            [self removeTopViewController];
            
            [self addPanGestureRecognizer];
            
            if ([self shouldAutomaticallyOverlayContentForViewController:belowVC]) {
                belowVC.overlayContent = NO;
            }
        };
        
        if (animated) {
            [self flowingViewController:self.topViewController
                                toFrame:toFrame
                        animationsBlock:animationsBlock
                        completionBlock:completionBlock];
        } else {
            animationsBlock();
            completionBlock(YES);
        }
        
        
    } else {
        // 设置UIViewController的flowController属性为nil
        [flowOutVCs makeObjectsPerformSelector:@selector(setFlowController:)
                                    withObject:nil];
        
        [self.innerViewControllers removeObjectsInArray:flowOutVCs];
    }
    
    return flowOutVCs;
}

// 滑入的起初位置
- (CGRect)inOriginRectForViewController:(UIViewController *)viewController
{
    // 默认的目标frame以容器为基准
    CGRect destinationFrame = self.view.bounds;
    
    // 允许自定义滑入时的最终frame
    if ([self.topViewController respondsToSelector:@selector(destinationRectForFlowDirection:)]) {
        destinationFrame = [(id <GQViewController>)self.topViewController
                                                                 destinationRectForFlowDirection:viewController.flowInDirection];
    }
    
    // 根据滑入的最终frame计算起点
    CGRect originFrame = CGRectZero;
    
    switch (viewController.flowInDirection) {
        case GQFlowDirectionLeft:
            originFrame = CGRectMake(self.view.bounds.size.width,
                                     destinationFrame.origin.y,
                                     destinationFrame.size.width,
                                     destinationFrame.size.height);
            break;
        case GQFlowDirectionRight:
            originFrame = CGRectMake(-destinationFrame.size.width,
                                     destinationFrame.origin.y,
                                     destinationFrame.size.width,
                                     destinationFrame.size.height);
            break;
        case GQFlowDirectionUp:
            originFrame = CGRectMake(destinationFrame.origin.x,
                                     self.view.bounds.size.height,
                                     destinationFrame.size.width,
                                     destinationFrame.size.height);
            break;
        case GQFlowDirectionDown:
            originFrame = CGRectMake(destinationFrame.origin.x,
                                     -destinationFrame.size.height,
                                     destinationFrame.size.width,
                                     destinationFrame.size.height);
            break;
        default:
            originFrame = destinationFrame;
            break;
    }
    
    return originFrame;
}

// 滑入的目标位置
- (CGRect)inDestinationRectForViewController:(UIViewController *)viewController
{
    CGRect destinationFrame = CGRectZero;
    
    // 允许自定义滑入时的最终frame
    if ([self.topViewController respondsToSelector:@selector(destinationRectForFlowDirection:)]) {
        destinationFrame = [(id <GQViewController>)self.topViewController
                                                                 destinationRectForFlowDirection:viewController.flowInDirection];
    } else {
        // 默认的目标frame以容器为基准
        CGRect viewBounds = self.view.bounds;
        
        // 通过容器的bounds计算滑入的frame
        switch (viewController.flowInDirection) {
            case GQFlowDirectionLeft:
                destinationFrame = CGRectMake(self.view.bounds.size.width - viewBounds.size.width,
                                              viewBounds.origin.y,
                                              viewBounds.size.width,
                                              viewBounds.size.height);
                break;
            case GQFlowDirectionRight:
                destinationFrame = CGRectMake(.0,
                                              viewBounds.origin.y,
                                              viewBounds.size.width,
                                              viewBounds.size.height);
                break;
            case GQFlowDirectionUp:
                destinationFrame = CGRectMake(viewBounds.origin.x,
                                              self.view.bounds.size.height - viewBounds.size.height,
                                              viewBounds.size.width,
                                              viewBounds.size.height);
                break;
            case GQFlowDirectionDown:
                destinationFrame = CGRectMake(viewBounds.origin.x,
                                              .0,
                                              viewBounds.size.width,
                                              viewBounds.size.height);
                break;
            default:
                destinationFrame = viewBounds;
                break;
        }
    }
    
    return destinationFrame;
}

//// 滑出的默认初始位置
//- (CGRect)outOriginRectForViewController:(UIViewController *)viewController
//{
//    CGRect viewFrame = viewController.view.frame;
//    CGRect originFrame = CGRectZero;
//
//    return originFrame;
//}

// 滑出的目标位置、任意位置都能滑出
- (CGRect)outDestinationRectForViewController:(UIViewController *)viewController
{
    CGRect viewFrame = viewController.view.frame;
    CGRect destinationFrame = CGRectZero;
    
    switch (viewController.flowOutDirection) {
        case GQFlowDirectionLeft:
            destinationFrame = CGRectMake(-viewFrame.size.width,
                                          viewFrame.origin.y,
                                          viewFrame.size.width,
                                          viewFrame.size.height);
            break;
        case GQFlowDirectionRight:
            destinationFrame = CGRectMake(self.view.bounds.size.width,
                                          viewFrame.origin.y,
                                          viewFrame.size.width,
                                          viewFrame.size.height);
            
            break;
        case GQFlowDirectionUp:
            destinationFrame = CGRectMake(viewFrame.origin.x,
                                          -viewFrame.size.height,
                                          viewFrame.size.width,
                                          viewFrame.size.height);
            break;
        case GQFlowDirectionDown:
            destinationFrame = CGRectMake(viewFrame.origin.x,
                                          self.view.bounds.size.height,
                                          viewFrame.size.width,
                                          viewFrame.size.height);
            break;
        default:
            destinationFrame = viewFrame;
            break;
    }
    
    return destinationFrame;
}

- (void)resetPressStatus
{
    self.startPoint = CGPointZero;
    self.topViewOriginalFrame = CGRectZero;
    self.belowViewOriginalFrame = CGRectZero;
    self.flowingDirection = GQFlowDirectionUnknow;
    self.shouldBeginAppearance = NO;
}

// 添加手势
- (void)addPanGestureRecognizer
{
    // 判断是否实现GQViewController Protocol
    if (![self.topViewController conformsToProtocol:@protocol(GQViewController)]) {
        return;
    }
    
    // 仅有1个视图控制器时总是不添加手势
    if ([self.viewControllers count] < 2) {
        return;
    }
    
    if (self.topViewPanGestureRecognizer == nil) {
        self.topViewPanGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                                   action:@selector(panGestureAction)];
    }
    
    self.topViewPanGestureRecognizer.delegate = (id <GQViewController>)self.topViewController;
    [self.topViewController.view addGestureRecognizer:self.topViewPanGestureRecognizer];
}

// 移除手势
- (void)removePanGestureRecognizer
{
    if (self.topViewPanGestureRecognizer) {
        self.topViewPanGestureRecognizer.delegate = nil;
        [self.topViewController.view removeGestureRecognizer:self.topViewPanGestureRecognizer];
    }
}

- (NSArray *)visibleViewControllersWithViewControllers:(NSArray *)vcs
{
    __block CGRect checkRect = CGRectZero;
    __block NSMutableArray *nvcs = [NSMutableArray arrayWithCapacity:1];
    __block UIViewController *aboveVC = nil;
    CGRect defaultRect = CGRectMake(.0,
                                    .0,
                                    self.view.bounds.size.width,
                                    self.view.bounds.size.height);
    
    [vcs enumerateObjectsWithOptions:NSEnumerationReverse
                          usingBlock:^(UIViewController *obj, NSUInteger idx, BOOL *stop) {
                              [nvcs insertObject:obj atIndex:0];
                              
                              NSString *belowVCKey = [NSString stringWithFormat:@"%u", [obj hash]];
                              
                              NSDictionary *viewInfo = [self.releaseViewInfos objectForKey:belowVCKey];
                              
                              // 检测是否存在内存警告时保存的信息
                              if (viewInfo) {
                                  NSString *frameString = viewInfo[@"frame"];
                                  
                                  if (frameString) {
                                      obj.view.frame = CGRectFromString(frameString);
                                  }
                                  
                                  NSNumber *isOverlayContent = viewInfo[@"isOverlayContent"];
                                  
                                  if (isOverlayContent) {
                                      obj.overlayContent = [isOverlayContent boolValue];
                                  }
                                  
                                  [self.releaseViewInfos removeObjectForKey:belowVCKey];
                              } else {
                                  // 需要初始化位置
                                  if (![obj isViewLoaded]) {
                                      if ([obj respondsToSelector:@selector(destinationRectForFlowDirection:)]) {
                                          obj.view.frame = [(id<GQViewController>)obj destinationRectForFlowDirection:obj.flowInDirection];
                                      } else {
                                          obj.view.frame = defaultRect;
                                      }
                                      
                                      if (aboveVC) {
                                          CGRect aboveVCInOriginRect = [self inOriginRectForViewController:obj];
                                          
                                          CGRect objFrame = GQBelowViewRectOffset(obj.view.frame,
                                                                                  aboveVCInOriginRect.origin,
                                                                                  aboveVC.view.frame.origin,
                                                                                  obj.flowInDirection);
                                          
                                          [self flowingBelowViewController:obj
                                                                    toRect:objFrame];
                                      }
                                  }
                              }
                              
                              if ([obj.view.backgroundColor isEqual:[UIColor colorWithRed:.0 green:.0 blue:.0 alpha:.0]]
                                  || [obj.view.backgroundColor isEqual:[UIColor clearColor]]
                                  || obj.view.alpha < 1.0) {
                                  return;
                              }
                              
                              if (aboveVC == nil) {
                                  checkRect = CGRectIntersection(obj.view.frame, defaultRect);
                              } else {
                                  checkRect = CGRectUnion(checkRect, CGRectIntersection(obj.view.frame, defaultRect));
                              }
                              
                              aboveVC = obj;
                              
                              // 检测是否遮盖住其它视图
                              if (CGRectEqualToRect(checkRect, defaultRect)
                                  || !CGRectContainsRect(defaultRect, checkRect)) {
                                  *stop = YES;
                              }
                          }];
    
    return [nvcs copy];
}

- (NSArray *)visibleViewControllers
{
    return [self visibleViewControllersWithViewControllers:self.innerViewControllers];
}

/** 确保下层视图是否已经添加
 */
- (NSArray *)prepareBelowViewControllers
{
    NSMutableArray *newVCs = [NSMutableArray array];
    NSMutableArray *prepareVCS = [NSMutableArray arrayWithArray:self.innerViewControllers];
    [prepareVCS removeLastObject];
    
    for (UIViewController *vc in [self visibleViewControllersWithViewControllers:prepareVCS]) {
        if (vc.view.superview == nil) {
            [self.view insertSubview:vc.view atIndex:[self.innerViewControllers indexOfObject:vc]];
            [newVCs addObject:vc];
        }
    }
    
    return [newVCs copy];
}

- (void)panGestureAction
{
    CGPoint panPoint = [self.topViewPanGestureRecognizer translationInView:self.view];
    
    if (self.topViewPanGestureRecognizer.state == UIGestureRecognizerStateBegan) {
        // 设置初始点
        self.startPoint = panPoint;
        
        // 记录移动视图的原始位置
        self.topViewOriginalFrame = self.topViewController.view.frame;
        
        [self prepareBelowViewControllers];
        
        UIViewController *belowVC = [self belowViewController];
        
        self.belowViewOriginalFrame = belowVC.view.frame;
    } else if (self.topViewPanGestureRecognizer.state == UIGestureRecognizerStateChanged) {
        // 判断移动的视图
        if (self.flowingDirection == GQFlowDirectionUnknow) {
            self.shouldBeginAppearance = YES;
            
            // 判断移动的方向            
            if (ABS(panPoint.x) > ABS(panPoint.y)) {
                if (panPoint.x > .0) {
                    self.flowingDirection = GQFlowDirectionRight;
                } else {
                    self.flowingDirection = GQFlowDirectionLeft;
                }
            } else {
                if (panPoint.y > .0) {
                    self.flowingDirection = GQFlowDirectionDown;
                } else {
                    self.flowingDirection = GQFlowDirectionUp;
                }
            }
            
            self.isPanFlowingIn = NO;

            // 响应滑动手势可以不是当前的Top View Controller
            if ([self.topViewController respondsToSelector:@selector(viewControllerForFlowDirection:)]) {
                UIViewController *controller = [(id<GQViewController>)self.topViewController viewControllerForFlowDirection:self.flowingDirection];
                
                // 校验不是topViewController，并添加到容器中
                if (controller != self.topViewController) {
                    // 判断是否实现GQViewController Protocol
                    if (![controller conformsToProtocol:@protocol(GQViewController)]) {
                        NSLog(@"滑出其它的控制器必须实现GQViewController Protocol");
                    } else {
                        // 更新需要移动视图的原始位置
                        self.belowViewOriginalFrame = self.topViewController.view.frame;
                        
                        [self addTopViewController:controller];
                        
                        self.topViewOriginalFrame = self.topViewController.view.frame;
                        
                        self.isPanFlowingIn = NO;
                    }
                }
            }
        }

        // 计算新的移动位置
        CGRect newFrame = CGRectZero;
        
        if (self.flowingDirection == GQFlowDirectionLeft
            || self.flowingDirection == GQFlowDirectionRight) {
            newFrame = CGRectOffset(self.topViewOriginalFrame, panPoint.x, .0);
        } else {
            newFrame = CGRectOffset(self.topViewOriginalFrame, .0, panPoint.y);
        }
        
        BOOL shouldMove = NO; // 是否需要移动
        
        // 默认仅允许滑入和滑出的移动方位
        if (self.flowingDirection == self.topViewController.flowInDirection
            || self.flowingDirection == self.topViewController.flowOutDirection) {
            shouldMove = YES;
            
            // 可以实现GQViewController来进行控制
            if ([self.topViewController respondsToSelector:@selector(shouldFlowToRect:)]) {
                shouldMove = [(id<GQViewController>)self.topViewController shouldFlowToRect:newFrame];
            }
        }
        
        if (shouldMove) {
            if (self.shouldBeginAppearance) {
                UIViewController *belowVC = [self belowViewController];
                
                // Customizing Appearance
                if (self.isPanFlowingIn) {
                    // 手势滑入
                    [belowVC beginAppearanceTransition:NO animated:YES];
                    [self.topViewController beginAppearanceTransition:YES animated:YES];
                } else {
                    // 手势滑出
                    [self.topViewController beginAppearanceTransition:NO animated:YES];
                    [belowVC beginAppearanceTransition:YES animated:YES];
                }
                
                self.shouldBeginAppearance = NO;
            }
            
            // 滑动时激活遮罩层
            if ([self shouldAutomaticallyOverlayContentForViewController:self.topViewController]) {
                self.topViewController.overlayContent = YES;
            }
            
            self.topViewController.view.frame = newFrame;
            
            UIViewController *belowVC = [self belowViewController];
            
            if (belowVC) {
                if ([self shouldAutomaticallyOverlayContentForViewController:belowVC]) {
                    belowVC.overlayContent = YES;
                }
                
                CGRect belowVCFrame = GQBelowViewRectOffset(self.belowViewOriginalFrame,
                                                            self.topViewOriginalFrame.origin,
                                                            newFrame.origin,
                                                            self.flowingDirection);
                
                [self flowingBelowViewController:belowVC toRect:belowVCFrame];
            }
        }
    } else if (self.topViewPanGestureRecognizer.state == UIGestureRecognizerStateEnded
               || self.topViewPanGestureRecognizer.state == UIGestureRecognizerStateCancelled) {
        // 如果位置没有任何变化直接返回
        if (CGRectEqualToRect(self.topViewController.view.frame, self.topViewOriginalFrame)) {
            [self resetPressStatus];
            return;
        }
        
        // 手势结束时需要自动对齐的位置，默认为原始位置
        CGRect destinationFrame = self.topViewOriginalFrame;
        
        BOOL flowingOriginalFrame = NO; // 是否需要滑动到原始位置
        
        BOOL skipAutoAlign = NO; // 是否跳过自动对齐的检测
        
        if (self.topViewPanGestureRecognizer.state == UIGestureRecognizerStateEnded) {
            // 判断是否支持自定义的对齐位置
            if ([self.topViewController respondsToSelector:@selector(destinationRectForFlowDirection:)]) {
                destinationFrame = [(id<GQViewController>)self.topViewController destinationRectForFlowDirection:self.flowingDirection];
                
                // 对返回的结果进行验证
                if (CGRectEqualToRect(CGRectZero, destinationFrame)) {
                    destinationFrame = self.topViewOriginalFrame;
                } else {
                    // delegate返回有效的值时，采用自定义的对齐位置
                    skipAutoAlign = YES;
                }
            }
            
            // 计算自动对齐的位置
            if (skipAutoAlign == NO) {
                CGFloat boundary = self.viewFlowingBoundary;
                
                // delegate返回滑回的触发距离
                if ([self.topViewController respondsToSelector:@selector(flowingBoundary)]) {
                    boundary = [(id<GQViewController>)self.topViewController flowingBoundary];
                }
                
                if (boundary > .0
                    && boundary < 1.0) {
                    CGFloat length = .0;
                    
                    // 计算移动的距离
                    if (self.flowingDirection == GQFlowDirectionLeft
                        || self.flowingDirection == GQFlowDirectionRight) {
                        length = panPoint.x - self.startPoint.x;
                    } else if (self.flowingDirection == GQFlowDirectionUp
                               || self.flowingDirection == GQFlowDirectionDown) {
                        length = panPoint.y - self.startPoint.y;
                    }
                    
                    // 如果移动的距离没有超过边界值，则回退到原始位置
                    if (ABS(length) <= self.topViewController.view.frame.size.width * boundary) {
                        flowingOriginalFrame = YES;
                    }
                }
                
                if (!flowingOriginalFrame) {
                    if (self.flowingDirection == self.topViewController.flowInDirection) {
                        destinationFrame = [self inDestinationRectForViewController:self.topViewController];
                    }
                    
                    // 如果in和out是同一方向，则以out为主
                    if (self.flowingDirection == self.topViewController.flowOutDirection) {
                        destinationFrame = [self outDestinationRectForViewController:self.topViewController];
                    }
                }
            }
        }
        
        UIViewController *belowVC = [self belowViewController];
        
        CGRect belowVCFrame = GQBelowViewRectOffset(self.belowViewOriginalFrame,
                                                    self.topViewOriginalFrame.origin,
                                                    destinationFrame.origin,
                                                    self.flowingDirection);
        
        [self flowingViewController:self.topViewController
                            toFrame:destinationFrame
                    animationsBlock:^{
                        [self flowingBelowViewController:belowVC toRect:belowVCFrame];
                    }
                    completionBlock:^(BOOL finished){
                        if ([self shouldAutomaticallyOverlayContentForViewController:self.topViewController]) {
                            self.topViewController.overlayContent = NO;
                        }
                        
                        if ([self shouldAutomaticallyOverlayContentForViewController:belowVC]) {
                            belowVC.overlayContent = NO;
                        }
                        
                        // Customizing Appearance
                        if (self.isPanFlowingIn) {
                            if (flowingOriginalFrame) {
                                [self.topViewController beginAppearanceTransition:NO animated:YES];
                                [belowVC beginAppearanceTransition:YES animated:YES];
                            }
                            
                            [belowVC endAppearanceTransition];
                            [self.topViewController endAppearanceTransition];
                        } else {
                            if (flowingOriginalFrame) {
                                [self.topViewController beginAppearanceTransition:YES animated:YES];
                                [belowVC beginAppearanceTransition:NO animated:YES];
                            }
                            
                            [belowVC endAppearanceTransition];
                            [self.topViewController endAppearanceTransition];
                        }
                        
                        UIViewController *topViewController = self.topViewController;
                        
                        // 如果topViewController已经移出窗口，则进行删除操作
                        if (!CGRectIntersectsRect(self.view.frame, self.topViewController.view.frame)) {
                            [self.innerViewControllers removeLastObject];
                            
                            [self removeTopViewController];
                        }
                        
                        // 重新添加top view的手势
                        [self addPanGestureRecognizer];
                        
                        // 重置长按状态信息
                        [self resetPressStatus];
                        
                        if ([topViewController respondsToSelector:@selector(didFlowToDestinationRect)]) {
                            [(id<GQViewController>)topViewController didFlowToDestinationRect];
                        }
                    }];
    }
}

- (UIViewController *)belowViewController
{
    NSUInteger vcCount = [self.viewControllers count];
    
    if (vcCount > 1) {
        return (UIViewController *)(self.viewControllers)[vcCount - 2];
    } else {
        return nil;
    }
}

- (void)safeDismissFlowController
{
    if (self.presentedViewController == nil
        && self.presentingViewController.presentedViewController == self) {
        // 在Model视图控制器中调用dismiss
        [self.viewControllers makeObjectsPerformSelector:@selector(setFlowController:) withObject:nil];
    } else if ([self.presentedViewController isKindOfClass:[GQFlowController class]]) {
        // 在presented的视图控制器调用dismiss
        [[(GQFlowController *)self.presentedViewController viewControllers]
         makeObjectsPerformSelector:@selector(setFlowController:) withObject:nil];
    }
}

- (void)flowingBelowViewController:(UIViewController *)viewController toRect:(CGRect)rect
{
    BOOL follow = YES;
    
    if ([viewController respondsToSelector:@selector(shouldFollowAboveViewFlowing)]) {
        follow = [(id<GQViewController>)viewController shouldFollowAboveViewFlowing];
    }
    
    if (follow
        && !CGRectEqualToRect(rect, CGRectZero)) {
        viewController.view.frame = rect;
    }
}

- (void)visibleViewControllersEndAppearanceTransition
{
    NSArray *vcs = [self visibleViewControllers];
    
    for (UIViewController *vc in vcs) {
        [vc endAppearanceTransition];
    }
}

- (void)visibleViewControllersBeginAppearanceTransition:(BOOL)transition animated:(BOOL)animated
{
    NSArray *vcs = [self visibleViewControllers];
    
    for (UIViewController *vc in vcs) {
        [vc beginAppearanceTransition:transition animated:animated];
    }
}

@end

#pragma mark - GQFlowController Category

static char kGQFlowControllerObjectKey;
static char kGQFlowInDirectionObjectKey;
static char kGQFlowOutDirectionObjectKey;
static char kQGOverlayContentObjectKey;
static char kQGOverlayViewObjectKey;

@implementation UIViewController (GQFlowControllerAdditions)

@dynamic flowController;
@dynamic flowInDirection;
@dynamic flowOutDirection;
@dynamic overlayContent;

#pragma mark -

- (GQFlowController *)flowController
{    
    return (GQFlowController *)objc_getAssociatedObject(self, &kGQFlowControllerObjectKey);
}

- (void)setFlowController:(GQFlowController *)flowController
{
    objc_setAssociatedObject(self, &kGQFlowControllerObjectKey, flowController, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (GQFlowDirection)flowInDirection
{
    NSNumber *direction = (NSNumber *)objc_getAssociatedObject(self, &kGQFlowInDirectionObjectKey);
    
    if (direction == nil) {
        self.flowInDirection = GQFlowDirectionLeft;
        
        direction = @(GQFlowDirectionLeft);
    }
    
    return [direction intValue];
}

- (void)setFlowInDirection:(GQFlowDirection)flowInDirection
{
    objc_setAssociatedObject(self, &kGQFlowInDirectionObjectKey, [NSNumber numberWithInt:flowInDirection], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (GQFlowDirection)flowOutDirection
{
    NSNumber *direction = (NSNumber *)objc_getAssociatedObject(self, &kGQFlowOutDirectionObjectKey);
    
    if (direction == nil) {
        self.flowOutDirection = GQFlowDirectionRight;
        
        direction = @(GQFlowDirectionRight);
    }
    
    return [direction intValue];
}

- (void)setFlowOutDirection:(GQFlowDirection)flowOutDirection
{
    objc_setAssociatedObject(self, &kGQFlowOutDirectionObjectKey, [NSNumber numberWithInt:flowOutDirection], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)setOverlayContent:(BOOL)yesOrNo
{
    UIView *overlayView = objc_getAssociatedObject(self, &kQGOverlayViewObjectKey);
    
    // 优化状态处理
    if (self.isOverlayContent == yesOrNo
        && overlayView.superview) {
        return;
    }
    
    objc_setAssociatedObject(self, &kQGOverlayContentObjectKey, [NSNumber numberWithInt:yesOrNo], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    if (overlayView == nil) {
        if ([self respondsToSelector:@selector(overlayContentView)]) {
            overlayView = [(id<GQViewController>)self overlayContentView];
        }
        
        if (overlayView == nil
            && ![overlayView isKindOfClass:[UIView class]]) {
            overlayView = [[UIView alloc] initWithFrame:self.view.bounds];
            overlayView.backgroundColor = [UIColor clearColor];
        }
        
        overlayView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin;
        
        if ([self respondsToSelector:@selector(overlayContentTapAction:)]) {
            UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                                   action:@selector(overlayContentTapAction:)];
            [overlayView addGestureRecognizer:tapGestureRecognizer];
        }

        objc_setAssociatedObject(self, &kQGOverlayViewObjectKey, overlayView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    if (yesOrNo) {
        [self.view addSubview:overlayView];
    } else {
        [overlayView removeFromSuperview];
    }
}

- (BOOL)isOverlayContent
{
    return [(NSNumber *)objc_getAssociatedObject(self, &kQGOverlayContentObjectKey) boolValue];
}

@end