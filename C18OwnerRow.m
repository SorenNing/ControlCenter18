#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ControlCenter18 设置页底部（最后一个分组下方）添加一行：
// 圆形头像 + "Ning自用二改版"，点击跳转 GitHub 主页。
// 实现：hook tableView:viewForFooterInSection: + heightForFooterInSection:（标准 UITableViewDelegate）

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

#pragma mark - footer 视图（单例复用）

static UIView *C18OwnerFooterView(void) {
    static UIView *footer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGFloat width = UIScreen.mainScreen.bounds.size.width;
        const CGFloat rowH = 46.0;
        UIButton *row = [UIButton buttonWithType:UIButtonTypeSystem];
        row.frame = CGRectMake(16, 8, width - 32, rowH);
        row.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
            return trait.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithWhite:0.13 alpha:1.0]
                : [UIColor colorWithWhite:0.95 alpha:1.0];
        }];
        row.layer.cornerRadius = 12.0;
        row.layer.masksToBounds = YES;
        if (@available(iOS 14.0, *)) {
            [row addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
                (void)action; C18OwnerTapped();
            }] forControlEvents:UIControlEventTouchUpInside];
        }

        UIImageView *iv = [[UIImageView alloc] initWithImage:C18OwnerAvatar()];
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.layer.cornerRadius = 13.0;
        iv.layer.masksToBounds = YES;
        iv.frame = CGRectMake(12, (rowH - 26) / 2.0, 26, 26);
        [row addSubview:iv];

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(48, 0, row.bounds.size.width - 96, rowH)];
        label.text = kRowTitle;
        label.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        label.textColor = UIColor.labelColor;
        label.userInteractionEnabled = NO;
        [row addSubview:label];

        UIImageView *chev = [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:@"arrow.up.right.square"]];
        chev.tintColor = UIColor.secondaryLabelColor;
        chev.contentMode = UIViewContentModeScaleAspectFit;
        chev.frame = CGRectMake(row.bounds.size.width - 34, (rowH - 15) / 2.0, 15, 15);
        chev.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [row addSubview:chev];

        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, rowH + 16)];
        [container addSubview:row];
        footer = container;
        C18Log(@"footer view built");
    });
    return footer;
}

#pragma mark - delegate hook

static id (*orig_viewForFooter)(id, SEL, id, NSInteger);
static id hook_viewForFooter(id self, SEL _cmd, id table, NSInteger section) {
    id v = orig_viewForFooter ? orig_viewForFooter(self, _cmd, table, section) : nil;
    if (v) return v;
    NSInteger last = 0;
    @try {
        last = ((NSInteger (*)(id, SEL, id))objc_msgSend)(self, @selector(numberOfSectionsInTableView:), table) - 1;
    } @catch (__unused NSException *e) { return nil; }
    if (section == last) return C18OwnerFooterView();
    return nil;
}

static CGFloat (*orig_heightForFooter)(id, SEL, id, NSInteger);
static CGFloat hook_heightForFooter(id self, SEL _cmd, id table, NSInteger section) {
    CGFloat h = orig_heightForFooter ? orig_heightForFooter(self, _cmd, table, section) : 0;
    NSInteger last = 0;
    @try {
        last = ((NSInteger (*)(id, SEL, id))objc_msgSend)(self, @selector(numberOfSectionsInTableView:), table) - 1;
    } @catch (__unused NSException *e) { return h; }
    if (section == last && h < 62) return 62.0;
    return h;
}

#pragma mark - hook 安装

static void C18Install(void) {
    Class cls = NSClassFromString(@"C18PRootListController");
    if (!cls) { C18Log(@"class not found"); return; }
    Method m;

    m = class_getInstanceMethod(cls, @selector(tableView:viewForFooterInSection:));
    {
        IMP orig = m ? method_getImplementation(m) : NULL;
        if (!class_addMethod(cls, @selector(tableView:viewForFooterInSection:),
                             (IMP)hook_viewForFooter, "v@:@q")) {
            Method own = class_getInstanceMethod(cls, @selector(tableView:viewForFooterInSection:));
            orig = method_getImplementation(own);
            method_setImplementation(own, (IMP)hook_viewForFooter);
        }
        orig_viewForFooter = (id (*)(id, SEL, id, NSInteger))orig;
    }
    m = class_getInstanceMethod(cls, @selector(tableView:heightForFooterInSection:));
    {
        IMP orig = m ? method_getImplementation(m) : NULL;
        if (!class_addMethod(cls, @selector(tableView:heightForFooterInSection:),
                             (IMP)hook_heightForFooter, "d@:@q")) {
            Method own = class_getInstanceMethod(cls, @selector(tableView:heightForFooterInSection:));
            orig = method_getImplementation(own);
            method_setImplementation(own, (IMP)hook_heightForFooter);
        }
        orig_heightForFooter = (CGFloat (*)(id, SEL, id, NSInteger))orig;
    }
    C18Log(@"footer-delegate hooked");
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