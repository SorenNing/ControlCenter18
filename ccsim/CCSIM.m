#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ControlCenterUIKit 私有基类：只声明类本身，方法全部自己实现
@interface CCUIToggleModule : NSObject
@end

// CoreTelephony 私有 API
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
@end

@protocol C18CTContext <NSObject>
- (long long)slotID;
- (NSUUID *)uuid;
- (NSString *)label;
- (BOOL)isSimPresent;
@end

static void C18SMLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
    NSString *path = @"/var/mobile/Library/C18SIM.log";
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        return;
    }
    @try {
        if ([fh seekToEndOfFile] > 64 * 1024) {
            [fh closeFile];
            [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            return;
        }
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } @catch (__unused NSException *e) {
    }
}

static id<C18CTClient> C18SMClient(void) {
    static id<C18CTClient> client;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = NSClassFromString(@"CoreTelephonyClient");
        if (!cls) return;
        dispatch_queue_t q = dispatch_queue_create("com.ning.c18.ccsim", DISPATCH_QUEUE_SERIAL);
        client = (id<C18CTClient>)[(id)[cls alloc] initWithQueue:q];
    });
    return client;
}

@interface C18SMEntry : NSObject
@property (nonatomic, strong) id context;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) long long slotID;
@property (nonatomic, assign) BOOL current;
@end

@implementation C18SMEntry
@end

// ===== 图二风格的卡片弹窗 =====
@interface C18CardController : UIViewController
@property (nonatomic, copy) NSArray<C18SMEntry *> *entries;
@property (nonatomic, strong) UIView *card;
@end

@implementation C18CardController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.28];

    UITapGestureRecognizer *bg = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(close)];
    [self.view addGestureRecognizer:bg];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    blur.translatesAutoresizingMaskIntoConstraints = NO;
    blur.layer.cornerRadius = 28.0;
    blur.layer.cornerCurve = kCACornerCurveContinuous;
    blur.clipsToBounds = YES;
    [self.view addSubview:blur];
    self.card = blur;

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 0.0;
    [blur.contentView addSubview:stack];

    // 头部：图标 + 标题
    UIView *head = [[UIView alloc] initWithFrame:CGRectZero];
    [head.heightAnchor constraintEqualToConstant:58.0].active = YES;

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectZero];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *img = [UIImage imageNamed:@"SettingsIcon" inBundle:[NSBundle bundleForClass:[self class]]
           compatibleWithTraitCollection:nil];
    if (!img) img = [UIImage systemImageNamed:@"simcard.fill"];
    icon.image = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    icon.tintColor = [UIColor whiteColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [head addSubview:icon];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"双卡切换";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    [head addSubview:title];

    [NSLayoutConstraint activateConstraints:@[
        [icon.centerXAnchor constraintEqualToAnchor:head.centerXAnchor],
        [icon.topAnchor constraintEqualToAnchor:head.topAnchor constant:2.0],
        [icon.widthAnchor constraintEqualToConstant:30.0],
        [icon.heightAnchor constraintEqualToConstant:30.0],
        [title.centerXAnchor constraintEqualToAnchor:head.centerXAnchor],
        [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:2.0],
    ]];
    [stack addArrangedSubview:head];

    [stack addArrangedSubview:[self separator]];

    UILabel *section = [[UILabel alloc] initWithFrame:CGRectZero];
    section.text = @"数据流量";
    section.textColor = [UIColor colorWithWhite:1.0 alpha:0.72];
    section.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    section.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *secWrap = [[UIView alloc] initWithFrame:CGRectZero];
    [secWrap.heightAnchor constraintEqualToConstant:34.0].active = YES;
    [secWrap addSubview:section];
    [NSLayoutConstraint activateConstraints:@[
        [section.leadingAnchor constraintEqualToAnchor:secWrap.leadingAnchor constant:18.0],
        [section.centerYAnchor constraintEqualToAnchor:secWrap.centerYAnchor],
    ]];
    [stack addArrangedSubview:secWrap];

    NSInteger idx = 0;
    for (C18SMEntry *e in self.entries) {
        [stack addArrangedSubview:[self rowForEntry:e index:idx++]];
        [stack addArrangedSubview:[self separator]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [blur.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [blur.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [blur.widthAnchor constraintEqualToConstant:320.0],
        [stack.leadingAnchor constraintEqualToAnchor:blur.contentView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:blur.contentView.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:blur.contentView.topAnchor constant:10.0],
        [stack.bottomAnchor constraintEqualToAnchor:blur.contentView.bottomAnchor constant:-10.0],
    ]];
}

- (UIView *)separator {
    UIView *line = [[UIView alloc] initWithFrame:CGRectZero];
    line.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.14];
    [line.heightAnchor constraintEqualToConstant:0.5].active = YES;
    return line;
}

- (UIView *)rowForEntry:(C18SMEntry *)entry index:(NSInteger)index {
    UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
    row.tag = index;
    [row.heightAnchor constraintEqualToConstant:44.0].active = YES;

    UILabel *mark = [[UILabel alloc] initWithFrame:CGRectZero];
    mark.translatesAutoresizingMaskIntoConstraints = NO;
    mark.text = entry.current ? @"✓" : @"";
    mark.textColor = [UIColor whiteColor];
    mark.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
    [row addSubview:mark];

    UILabel *name = [[UILabel alloc] initWithFrame:CGRectZero];
    name.translatesAutoresizingMaskIntoConstraints = NO;
    name.text = entry.name;
    name.textColor = [UIColor whiteColor];
    name.font = [UIFont systemFontOfSize:16.0 weight:entry.current ? UIFontWeightSemibold : UIFontWeightRegular];
    [row addSubview:name];

    [NSLayoutConstraint activateConstraints:@[
        [mark.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:18.0],
        [mark.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [mark.widthAnchor constraintEqualToConstant:16.0],
        [name.leadingAnchor constraintEqualToAnchor:mark.trailingAnchor constant:10.0],
        [name.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [name.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-18.0],
    ]];

    [row addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rowTapped:)]];
    return row;
}

- (void)rowTapped:(UITapGestureRecognizer *)g {
    NSInteger i = g.view.tag;
    if (i < 0 || i >= (NSInteger)self.entries.count) return;
    C18SMEntry *e = self.entries[(NSUInteger)i];
    if (e.current) { [self close]; return; }

    C18SMLog(@"switch -> slot=%lld %@", e.slotID, e.name);
    id ctx = e.context;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        [C18SMClient() setActiveUserDataSelection:ctx error:&err];
        C18SMLog(@"result err=%@", err);
    });
    [self close];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

// ===== 开关模块（保持圆形）=====
@interface CCSIM : CCUIToggleModule {
    BOOL _selected;
}
@property (nonatomic, assign) BOOL selected;
@end

@implementation CCSIM

- (UIImage *)iconGlyph {
    UIImage *img = [UIImage imageNamed:@"CCSIM" inBundle:[NSBundle bundleForClass:[self class]]
           compatibleWithTraitCollection:nil];
    return img ?: [UIImage systemImageNamed:@"simcard.fill"];
}

- (UIColor *)selectedColor {
    return [UIColor systemBlueColor];
}

- (BOOL)isSelected {
    return _selected;
}

- (void)setSelected:(BOOL)selected {
    _selected = selected;
}

- (void)refreshState {
}

- (void)onSelected {
    [self presentCard];
}

- (NSArray<C18SMEntry *> *)loadEntries {
    id<C18CTClient> client = C18SMClient();
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
    id current = [client getCurrentDataSubscriptionContextSync:&err];
    NSUUID *curUUID = [current respondsToSelector:@selector(uuid)] ? [(id<C18CTContext>)current uuid] : nil;

    NSMutableArray<C18SMEntry *> *out = [NSMutableArray array];
    for (id ctx in subs) {
        if (![ctx respondsToSelector:@selector(slotID)]) continue;
        BOOL present = YES;
        if ([ctx respondsToSelector:@selector(isSimPresent)]) {
            present = [(id<C18CTContext>)ctx isSimPresent];
        }
        if (!present) continue;
        C18SMEntry *e = [[C18SMEntry alloc] init];
        e.context = ctx;
        e.slotID = [(id<C18CTContext>)ctx slotID];
        NSError *le = nil;
        NSString *label = [client copyLabel:ctx error:&le];
        if (![label isKindOfClass:[NSString class]] || label.length == 0) {
            label = [ctx respondsToSelector:@selector(label)] ? [(id<C18CTContext>)ctx label] : nil;
        }
        e.name = label.length ? label : [NSString stringWithFormat:@"卡 %lld", e.slotID + 1];
        NSUUID *u = [ctx respondsToSelector:@selector(uuid)] ? [(id<C18CTContext>)ctx uuid] : nil;
        e.current = (curUUID && u) ? [curUUID isEqual:u] : NO;
        [out addObject:e];
    }
    return out;
}

- (UIViewController *)topViewController {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        for (UIWindow *w in ws.windows) {
            if (!w.isKeyWindow) continue;
            UIViewController *vc = w.rootViewController;
            while (vc.presentedViewController) vc = vc.presentedViewController;
            if (vc) return vc;
        }
    }
    return nil;
}

- (void)presentCard {
    UIViewController *top = [self topViewController];
    if (!top) {
        C18SMLog(@"找不到顶层控制器");
        return;
    }
    C18CardController *card = [[C18CardController alloc] initWithNibName:nil bundle:nil];
    card.entries = [self loadEntries];
    card.modalPresentationStyle = UIModalPresentationOverFullScreen;
    card.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [top presentViewController:card animated:YES completion:nil];
}

@end
