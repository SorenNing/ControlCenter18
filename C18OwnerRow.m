#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ControlCenter18 设置页底部添加一个分组：
//   组标题：Ning自用二改版（红字）
//   组内行：头像图标 + "Ning个人源"，点击跳转 GitHub 主页。
// 实现：hook viewWillAppear:，向 _specifiers 追加 group + link 两个 PSSpecifier

static NSString *const kOwnerRepoURL = @"https://github.com/SorenNing";
static NSString *const kGroupTitle = @"Ning自用二改版";
static NSString *const kRowTitle = @"Ning个人源";

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

#pragma mark - specifiers 追加

static void C18AppendOwnerGroup(id self) {
    NSArray *current = nil;
    @try { current = [self valueForKey:@"_specifiers"]; } @catch (__unused NSException *e) {}
    if (![current isKindOfClass:NSArray.class]) { C18Log(@"no _specifiers"); return; }
    C18Log(@"_specifiers count=%lu", (unsigned long)current.count);
    if (!current.count) { C18Log(@"_specifiers empty"); return; }

    // 防重复
    for (id sp in current) {
        id name = [sp valueForKey:@"name"];
        if ([name isKindOfClass:NSString.class] && [name isEqualToString:kGroupTitle]) {
            C18Log(@"group already present"); return;
        }
    }

    Class psc = NSClassFromString(@"PSSpecifier");
    if (!psc) { C18Log(@"no PSSpecifier"); return; }

    // 分组（标题红色）
    id group = nil;
    @try {
        group = ((id (*)(id, SEL, id))objc_msgSend)(psc, @selector(groupSpecifierWithName:), kGroupTitle);
        if (group) {
            [group setProperty:UIColor.systemRedColor forKey:@"titleColor"];
        }
    } @catch (__unused NSException *e) { group = nil; }

    // 链接行（头像 + 标题 + url）
    id link = nil;
    @try {
        link = ((id (*)(id, SEL, id, id, id, id, id, NSInteger, id))objc_msgSend)(
            psc, @selector(preferenceSpecifierNamed:target:set:get:detail:cell:edit:),
            kRowTitle, self, nil, nil, nil, 1 /* PSLinkCell */, nil);
        if (link) {
            UIImage *avatar = C18OwnerAvatar();
            if (avatar) [link setProperty:avatar forKey:@"iconImage"];
            [link setProperty:kOwnerRepoURL forKey:@"url"];
            [link setProperty:@YES forKey:@"isLink"];
        }
    } @catch (__unused NSException *e) { link = nil; }

    if (!group && !link) { C18Log(@"specifier create failed"); return; }

    NSMutableArray *newList = [current mutableCopy];
    if (group) [newList addObject:group];
    if (link) [newList addObject:link];
    @try {
        [self setValue:newList forKey:@"_specifiers"];
        SEL rs = NSSelectorFromString(@"reloadSpecifiers");
        if ([self respondsToSelector:rs]) ((void (*)(id, SEL))objc_msgSend)(self, rs);
    } @catch (__unused NSException *e) { C18Log(@"apply failed"); return; }
    C18Log(@"owner group appended (group=%@ link=%@)", group ? @"OK" : @"nil", link ? @"OK" : @"nil");
}

#pragma mark - hook

static void (*orig_viewDidAppear)(id, SEL, BOOL);
static void hook_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (orig_viewDidAppear) orig_viewDidAppear(self, _cmd, animated);
    // 作者用 _pendingSpecifiers 延迟应用，viewDidAppear 后才就绪
    C18AppendOwnerGroup(self);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ C18AppendOwnerGroup(self); });
}

static void C18Install(void) {
    Class cls = NSClassFromString(@"C18PRootListController");
    if (!cls) { C18Log(@"class not found"); return; }
    if (orig_viewDidAppear) { C18Log(@"already hooked"); return; }
    Method m = class_getInstanceMethod(cls, @selector(viewDidAppear:));
    if (!m) { C18Log(@"no viewDidAppear"); return; }
    IMP orig = method_getImplementation(m);
    class_addMethod(cls, @selector(viewDidAppear:), (IMP)hook_viewDidAppear, method_getTypeEncoding(m));
    orig_viewDidAppear = (void (*)(id, SEL, BOOL))orig;
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