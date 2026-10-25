#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// 在 ControlCenter18 设置页底部追加一行：
// 圆形头像 + "Ning自用二改版"，点击跳转 GitHub 主页。
// 实现：hook C18PRootListController -specifiers，末尾追加 PSSpecifier(PSLinkCell)。

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
    return [UIImage imageNamed:@"owner-avatar" inBundle:bundle compatibleWithTraitCollection:nil];
}

#pragma mark - specifiers hook

static NSArray *(*orig_specifiers)(id, SEL);
static NSArray *hook_specifiers(id self, SEL _cmd) {
    NSArray *list = orig_specifiers ? orig_specifiers(self, _cmd) : nil;
    if (![list isKindOfClass:NSArray.class]) return list;

    // 防重复（PSListController 可能多次调用）
    for (id sp in list) {
        id name = [sp valueForKey:@"name"];
        if ([name isKindOfClass:NSString.class] && [name isEqualToString:kRowTitle]) return list;
    }

    Class psc = NSClassFromString(@"PSSpecifier");
    if (!psc) return list;
    id sp = nil;
    @try {
        sp = ((id (*)(id, SEL, id, id, id, id, id, NSInteger, id))objc_msgSend)(
            psc, @selector(preferenceSpecifierNamed:target:set:get:detail:cell:edit:),
            kRowTitle, self, nil, nil, nil, 1 /* PSLinkCell */, nil);
        if (sp) {
            UIImage *avatar = C18OwnerAvatar();
            if (avatar) [sp setProperty:avatar forKey:@"iconImage"];
            [sp setProperty:kOwnerRepoURL forKey:@"url"];
            [sp setProperty:@YES forKey:@"isLink"];
            C18Log(@"specifier added: %@, avatar=%@", kRowTitle, avatar ? @"OK" : @"nil");
        }
    } @catch (__unused NSException *e) {
        C18Log(@"specifier create exception");
    }
    if (!sp) return list;
    NSMutableArray *m = [list mutableCopy];
    [m addObject:sp];
    return [m copy];
}

#pragma mark - hook 安装

static void C18Install(void) {
    Class cls = NSClassFromString(@"C18PRootListController");
    if (!cls) { C18Log(@"class not found"); return; }
    Method m = class_getInstanceMethod(cls, @selector(specifiers));
    if (!m) { C18Log(@"no -specifiers"); return; }
    IMP orig = method_getImplementation(m);
    if (!class_addMethod(cls, @selector(specifiers), (IMP)hook_specifiers, method_getTypeEncoding(m))) {
        Method own = class_getInstanceMethod(cls, @selector(specifiers));
        orig = method_getImplementation(own);
        method_setImplementation(own, (IMP)hook_specifiers);
    }
    orig_specifiers = (NSArray *(*)(id, SEL))orig;
    C18Log(@"specifiers hooked");
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