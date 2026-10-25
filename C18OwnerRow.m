#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ControlCenter18 设置页底部追加一行（tableFooterView）：
// 圆形头像 + "Ning自用二改版"，点击跳转 GitHub 主页。

static NSString *const kOwnerRepoURL = @"https://github.com/SorenNing";
static NSString *const kRowTitle = @"Ning自用二改版";

#pragma mark - 日志

static void C18Log(NSString *fmt, ...) {
    @autoreleasepool {
        va_list args; va_start(args, fmt);
        NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
        va_end(args);
        NSString *path = @"/var/mobile/Documents/C18OwnerRow.log";
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (fh) { [fh seekToEndOfFile]; [fh writeData:[[msg stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
    }
}

#pragma mark - 头像

static UIImage *C18OwnerAvatar(void) {
    NSBundle *bundle = [NSBundle bundleForClass:NSClassFromString(@"C18PRootListController")];
    if (!bundle) {
        for (NSBundle *bb in [NSBundle allBundles]) {
            if ([bb.bundlePath containsString:@"ControlCenter18Prefs"]) { bundle = bb; break; }
        }
    }
    if (!bundle) { C18Log(@"avatar: no bundle (main=%@)", NSBundle.mainBundle.bundlePath); return nil; }
    UIImage *img = [UIImage imageNamed:@"owner-avatar" inBundle:bundle compatibleWithTraitCollection:nil];
    C18Log(@"avatar: %@ (bundle=%@)", img ? @"OK" : @"nil", bundle.bundlePath);
    return img;
}

static void C18OwnerTapped(void) {
    NSURL *url = [NSURL URLWithString:kOwnerRepoURL];
    if (url && @available(iOS 10.0, *)) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        C18Log(@"open url");
    }
}

#pragma mark - 底部行

static void C18BSetupFooter(id panel) {
    static const char kKey = 0;
    if (objc_getAssociatedObject(panel, &kKey)) { C18Log(@"footer: already"); return; }
    objc_setAssociatedObject(panel, &kKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    C18Log(@"footer setup for %@", NSStringFromClass([panel class]));

    UITableView *table = nil;
    @try { table = [panel valueForKey:@"table"]; } @catch (__unused NSException *e) {}
    if (!table) { C18Log(@"footer: no table"); return; }

    CGFloat width = table.bounds.size.width > 1 ? table.bounds.size.width : UIScreen.mainScreen.bounds.size.width;
    const CGFloat rowH = 46.0;

    UIButton *row = [UIButton buttonWithType:UIButtonTypeSystem];
    row.frame = CGRectMake(0, 0, width, rowH);
    row.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    row.backgroundColor = [UIColor secondarySystemBackgroundColor];
    if (@available(iOS 14.0, *)) {
        [row addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
            (void)action; C18OwnerTapped();
        }] forControlEvents:UIControlEventTouchUpInside];
    }

    UIImage *avatar = C18OwnerAvatar();
    UIImageView *iv = [[UIImageView alloc] initWithImage:avatar];
    iv.contentMode = UIViewContentModeScaleAspectFill;
    iv.layer.cornerRadius = 13.0;
    iv.layer.masksToBounds = YES;
    iv.frame = CGRectMake(16, (rowH - 26) / 2.0, 26, 26);
    [row addSubview:iv];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(52, 0, width - 92, rowH)];
    label.text = kRowTitle;
    label.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    label.textColor = UIColor.labelColor;
    label.userInteractionEnabled = NO;
    [row addSubview:label];

    UIImageView *chev = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"arrow.up.right.square"]];
    chev.tintColor = UIColor.secondaryLabelColor;
    chev.contentMode = UIViewContentModeScaleAspectFit;
    chev.frame = CGRectMake(width - 36, (rowH - 15) / 2.0, 15, 15);
    chev.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [row addSubview:chev];

    table.tableFooterView = row;
    C18Log(@"footer set (h=%.1f, avatar=%@)", rowH, avatar ? @"OK" : @"nil");
}

#pragma mark - hook

static void (*orig_C18_viewDidAppear)(id, SEL, BOOL);
static void hook_C18_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (orig_C18_viewDidAppear) orig_C18_viewDidAppear(self, _cmd, animated);
    C18BSetupFooter(self);
}

static void C18Install(void) {
    Class cls = NSClassFromString(@"C18PRootListController");
    if (!cls) { C18Log(@"class not found"); return; }
    Method m = class_getInstanceMethod(cls, @selector(viewDidAppear:));
    if (!m) return;
    IMP orig = method_getImplementation(m);
    if (!class_addMethod(cls, @selector(viewDidAppear:), (IMP)hook_C18_viewDidAppear, method_getTypeEncoding(m))) {
        Method own = class_getInstanceMethod(cls, @selector(viewDidAppear:));
        orig = method_getImplementation(own);
        method_setImplementation(own, (IMP)hook_C18_viewDidAppear);
    }
    orig_C18_viewDidAppear = (void (*)(id, SEL, BOOL))orig;
    C18Log(@"viewDidAppear hooked");
}

__attribute__((constructor)) static void C18Init(void) {
    @autoreleasepool {
        @try {
            CFPreferencesSetAppValue(CFSTR("probe_time"),
                (__bridge CFPropertyListRef)[NSNumber numberWithDouble:CACurrentMediaTime()],
                CFSTR("com.minis.c18ownerrow"));
            CFPreferencesAppSynchronize(CFSTR("com.minis.c18ownerrow"));
        } @catch (__unused NSException *e) {}
        C18Log(@"C18OwnerRow loaded, bundle=%@", NSBundle.mainBundle.bundleIdentifier);
        dispatch_async(dispatch_get_main_queue(), ^{
            for (int i = 0; i < 6; i++) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * (i + 1) * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{ C18Install(); });
            }
        });
    }
}