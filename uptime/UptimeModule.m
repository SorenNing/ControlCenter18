#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import <sys/time.h>
#include <time.h>

// ControlCenterUIKit 私有协议：只声明本模块用到的方法
@protocol UptimeContentModule <NSObject>
- (UIViewController *)contentViewController;
- (UIViewController *)backgroundViewController;
- (CGSize)moduleSizeForOrientation:(long long)orientation;
@end

static unsigned long long UptimeSeconds(void) {
    struct timeval boot;
    memset(&boot, 0, sizeof(boot));
    size_t len = sizeof(boot);
    int mib[2] = {CTL_KERN, KERN_BOOTTIME};
    if (sysctl(mib, 2, &boot, &len, NULL, 0) == 0 && boot.tv_sec > 0) {
        time_t now = time(NULL);
        if (now > boot.tv_sec) {
            return (unsigned long long)(now - boot.tv_sec);
        }
    }
    // 兜底：不含睡眠时间的单调时钟
    return (unsigned long long)([[NSProcessInfo processInfo] systemUptime]);
}

static NSString *UptimeText(unsigned long long s) {
    unsigned long long d = s / 86400ULL;
    unsigned long long h = (s % 86400ULL) / 3600ULL;
    unsigned long long m = (s % 3600ULL) / 60ULL;
    unsigned long long sec = s % 60ULL;
    // 原版是「❤️ 系统已运行:」+ 时长两行，这里去掉爱心，保留文案
    NSString *dur;
    if (d > 0) {
        dur = [NSString stringWithFormat:@"%llu天 %llu时 %llu分 %llu秒", d, h, m, sec];
    } else {
        dur = [NSString stringWithFormat:@"%llu时 %llu分 %llu秒", h, m, sec];
    }
    return [NSString stringWithFormat:@"系统已运行\n%@", dur];
}

@interface UptimeModuleContentViewController : UIViewController
@property (nonatomic, strong) UILabel *uptimeLabel;
@property (nonatomic, strong) NSTimer *uptimeTimer;
@property (nonatomic, assign) BOOL expanded;
@end

@implementation UptimeModuleContentViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.55;
    label.numberOfLines = 2;
    label.text = @"--";
    [self.view addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:8.0],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-8.0],
    ]];
    self.uptimeLabel = label;

    // 首帧立即写文字，不依赖宿主回调
    [self refresh];
    [self startTimer];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
    [self startTimer];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self refresh];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopTimer];
}

- (void)dealloc {
    [self stopTimer];
}

#pragma mark - Timer

- (void)startTimer {
    [self stopTimer];
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0
                                             target:self
                                           selector:@selector(refresh)
                                           userInfo:nil
                                            repeats:YES];
    // CommonModes：滑动/动画期间也继续走
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.uptimeTimer = timer;
}

- (void)stopTimer {
    [self.uptimeTimer invalidate];
    self.uptimeTimer = nil;
}

- (void)refresh {
    self.uptimeLabel.text = UptimeText(UptimeSeconds());
}

#pragma mark - ControlCenterUIKit

- (void)controlCenterWillPresent {
    [self refresh];
    [self startTimer];
}

- (void)controlCenterDidDismiss {
    [self stopTimer];
}

- (BOOL)_canShowWhileLocked {
    return YES;
}

- (CGFloat)preferredExpandedContentHeight {
    return 110.0;
}

- (CGFloat)preferredExpandedContentWidth {
    return 320.0;
}

@end

@interface UptimeModule : NSObject <UptimeContentModule> {
    UptimeModuleContentViewController *_contentViewController;
    UIViewController *_backgroundViewController;
}
@end

@implementation UptimeModule

- (instancetype)init {
    self = [super init];
    if (self) {
        _contentViewController = [[UptimeModuleContentViewController alloc] initWithNibName:nil bundle:nil];
        _backgroundViewController = [[UIViewController alloc] initWithNibName:nil bundle:nil];
        _backgroundViewController.view.backgroundColor = [UIColor clearColor];
    }
    return self;
}

- (UIViewController *)contentViewController {
    return _contentViewController;
}

- (UIViewController *)backgroundViewController {
    return _backgroundViewController;
}

- (CGSize)moduleSizeForOrientation:(long long)orientation {
    return CGSizeMake(2.0, 1.0);
}

@end
