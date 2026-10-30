#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ===== CoreTelephony 私有 API：只声明用到的部分，运行时通过协议解析 =====
@protocol C18CTClient <NSObject>
- (instancetype)initWithQueue:(dispatch_queue_t)queue;
- (id)getSubscriptionInfoWithError:(id *)error;
- (id)getCurrentDataSubscriptionContextSync:(id *)sync;
- (void)setActiveUserDataSelection:(id)selection error:(id *)error;
- (id)copyLabel:(id)label error:(id *)error;
@end

@protocol C18CTSubInfo <NSObject>
- (NSArray *)subscriptions;
- (NSArray *)subscriptionsInUse;
- (NSArray *)subscriptionsValid;
@end

@protocol C18CTContext <NSObject>
- (long long)slotID;
- (NSUUID *)uuid;
- (NSString *)label;
- (BOOL)isSimPresent;
@end

static void C18SwitchLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
    NSString *path = @"/var/mobile/Library/C18SwitchData.log";
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        return;
    }
    @try {
        unsigned long long size = [fh seekToEndOfFile];
        if (size > 64 * 1024) {
            [fh closeFile];
            [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            return;
        }
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } @catch (__unused NSException *e) {
    }
}

static id<C18CTClient> C18SharedCTClient(void) {
    static id<C18CTClient> client;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = NSClassFromString(@"CoreTelephonyClient");
        if (!cls) {
            C18SwitchLog(@"CoreTelephonyClient 类不存在");
            return;
        }
        dispatch_queue_t q = dispatch_queue_create("com.ning.c18.switchdata", DISPATCH_QUEUE_SERIAL);
        client = (id<C18CTClient>)[(id)[cls alloc] initWithQueue:q];
        C18SwitchLog(@"CT client 初始化 %@", client ? @"成功" : @"失败");
    });
    return client;
}

@interface C18SIMItem : NSObject
@property (nonatomic, strong) id context;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) long long slotID;
@property (nonatomic, assign) BOOL current;
@end

@implementation C18SIMItem
@end

// ===== 内容视图：折叠态显示当前卡，展开态显示可点的卡列表 =====
@interface CCSwitchDataModuleViewController : UIViewController
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UIStackView *listStack;
@property (nonatomic, copy) NSArray<C18SIMItem *> *items;
@property (nonatomic, assign) BOOL expanded;
@property (nonatomic, assign) BOOL refreshing;
@end

@implementation CCSwitchDataModuleViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    UILabel *summary = [[UILabel alloc] initWithFrame:CGRectZero];
    summary.translatesAutoresizingMaskIntoConstraints = NO;
    summary.textAlignment = NSTextAlignmentCenter;
    summary.textColor = [UIColor whiteColor];
    summary.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    summary.adjustsFontSizeToFitWidth = YES;
    summary.minimumScaleFactor = 0.55;
    summary.text = @"蜂窝数据";
    [self.view addSubview:summary];
    self.summaryLabel = summary;

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6.0;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.hidden = YES;
    [self.view addSubview:stack];
    self.listStack = stack;

    [NSLayoutConstraint activateConstraints:@[
        [summary.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [summary.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [summary.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:8.0],
        [summary.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-8.0],

        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:6.0],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-6.0],
        [stack.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:4.0],
        [stack.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-4.0],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onAppear)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [self refresh];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self onAppear];
}

- (void)onAppear {
    [self refresh];
}

- (void)refresh {
    if (self.refreshing) return;
    self.refreshing = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<C18SIMItem *> *items = [self loadItems];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.refreshing = NO;
            self.items = items;
            [self rebuild];
        });
    });
}

- (NSArray<C18SIMItem *> *)loadItems {
    id<C18CTClient> client = C18SharedCTClient();
    if (!client) return @[];

    NSError *err = nil;
    id info = [client getSubscriptionInfoWithError:&err];
    NSArray *subs = nil;
    if ([info respondsToSelector:@selector(subscriptionsInUse)]) {
        subs = [(id<C18CTSubInfo>)info subscriptionsInUse];
    }
    if (!subs.count && [info respondsToSelector:@selector(subscriptions)]) {
        subs = [(id<C18CTSubInfo>)info subscriptions];
    }
    if (!subs.count && [info respondsToSelector:@selector(subscriptionsValid)]) {
        subs = [(id<C18CTSubInfo>)info subscriptionsValid];
    }

    id current = [client getCurrentDataSubscriptionContextSync:&err];
    NSUUID *currentUUID = nil;
    if ([current respondsToSelector:@selector(uuid)]) {
        currentUUID = [(id<C18CTContext>)current uuid];
    }

    NSMutableArray<C18SIMItem *> *result = [NSMutableArray array];
    for (id ctx in subs) {
        if (![ctx respondsToSelector:@selector(slotID)]) continue;
        BOOL present = YES;
        if ([ctx respondsToSelector:@selector(isSimPresent)]) {
            present = [(id<C18CTContext>)ctx isSimPresent];
        }
        if (!present) continue;

        C18SIMItem *item = [[C18SIMItem alloc] init];
        item.context = ctx;
        item.slotID = [(id<C18CTContext>)ctx slotID];
        NSError *nameErr = nil;
        NSString *label = [client copyLabel:ctx error:&nameErr];
        if (![label isKindOfClass:[NSString class]] || label.length == 0) {
            label = [ctx respondsToSelector:@selector(label)] ? [(id<C18CTContext>)ctx label] : nil;
        }
        item.name = label.length ? label : [NSString stringWithFormat:@"卡 %lld", item.slotID + 1];
        NSUUID *uuid = [ctx respondsToSelector:@selector(uuid)] ? [(id<C18CTContext>)ctx uuid] : nil;
        item.current = (currentUUID && uuid) ? [currentUUID isEqual:uuid] : NO;
        [result addObject:item];
    }

    C18SwitchLog(@"读取到 %lu 张卡，当前数据卡 uuid=%@", (unsigned long)result.count, currentUUID);
    for (C18SIMItem *it in result) {
        C18SwitchLog(@"  slot=%lld name=%@ current=%d", it.slotID, it.name, it.current);
    }
    return result;
}

- (void)rebuild {
    C18SIMItem *current = nil;
    for (C18SIMItem *it in self.items) {
        if (it.current) { current = it; break; }
    }
    self.summaryLabel.text = current ? current.name : (self.items.count ? self.items.firstObject.name : @"蜂窝数据");

    for (UIView *v in self.listStack.arrangedSubviews) {
        [v removeFromSuperview];
    }

    NSInteger index = 0;
    for (C18SIMItem *it in self.items) {
        UIView *row = [self rowForItem:it index:index++];
        [self.listStack addArrangedSubview:row];
    }
    [self applyExpandedLayout];
}

- (UIView *)rowForItem:(C18SIMItem *)item index:(NSInteger)index {
    UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
    row.tag = index;
    row.layer.cornerRadius = 10.0;
    row.layer.cornerCurve = kCACornerCurveContinuous;
    row.backgroundColor = item.current
        ? [UIColor colorWithWhite:1.0 alpha:0.16]
        : [UIColor colorWithWhite:1.0 alpha:0.06];

    UILabel *name = [[UILabel alloc] initWithFrame:CGRectZero];
    name.translatesAutoresizingMaskIntoConstraints = NO;
    name.text = item.name;
    name.textColor = [UIColor whiteColor];
    name.font = [UIFont systemFontOfSize:14.0 weight:item.current ? UIFontWeightSemibold : UIFontWeightRegular];
    name.adjustsFontSizeToFitWidth = YES;
    name.minimumScaleFactor = 0.6;
    [row addSubview:name];

    UILabel *mark = [[UILabel alloc] initWithFrame:CGRectZero];
    mark.translatesAutoresizingMaskIntoConstraints = NO;
    mark.text = item.current ? @"✓" : @"";
    mark.textColor = [UIColor whiteColor];
    mark.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    mark.textAlignment = NSTextAlignmentRight;
    [mark setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [row addSubview:mark];

    [NSLayoutConstraint activateConstraints:@[
        [name.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12.0],
        [name.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [mark.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12.0],
        [mark.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [name.trailingAnchor constraintLessThanOrEqualToAnchor:mark.leadingAnchor constant:-8.0],
    ]];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rowTapped:)];
    [row addGestureRecognizer:tap];
    return row;
}

- (void)rowTapped:(UITapGestureRecognizer *)gesture {
    NSInteger index = gesture.view.tag;
    if (index < 0 || index >= (NSInteger)self.items.count) return;
    C18SIMItem *item = self.items[(NSUInteger)index];
    if (item.current) return;

    C18SwitchLog(@"切换数据卡 -> slot=%lld %@", item.slotID, item.name);
    id context = item.context;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        [C18SharedCTClient() setActiveUserDataSelection:context error:&err];
        C18SwitchLog(@"切换结果 err=%@", err);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self refresh];
        });
    });
}

- (void)applyExpandedLayout {
    self.summaryLabel.hidden = self.expanded;
    self.listStack.hidden = !self.expanded;
}

#pragma mark - ControlCenterUIKit

- (void)willTransitionToExpandedContentMode:(BOOL)willTransition {
    self.expanded = willTransition;
    [self applyExpandedLayout];
    [self refresh];
}

- (BOOL)_canShowWhileLocked {
    return YES;
}

- (CGFloat)preferredExpandedContentHeight {
    return 100.0;
}

- (CGFloat)preferredExpandedContentWidth {
    return 320.0;
}

@end

// ===== 模块入口 =====
@interface CCSwitchDataModule : NSObject {
    CCSwitchDataModuleViewController *_contentViewController;
    UIViewController *_backgroundViewController;
}
@end

@implementation CCSwitchDataModule

- (instancetype)init {
    self = [super init];
    if (self) {
        _contentViewController = [[CCSwitchDataModuleViewController alloc] initWithNibName:nil bundle:nil];
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
    return CGSizeMake(4.0, 2.0);
}

@end
