#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// CC18 连接模块：只保留 5 个按钮（飞行/热点/蜂窝/WiFi/蓝牙），按指定顺序重排。
// 做法：布局后接管 _cluster —— 移除多余按钮、按新顺序重排、修正命中。

static void CLlog(NSString *fmt, ...) {
    @autoreleasepool {
        va_list ap; va_start(ap, fmt);
        NSString *m = [[NSString alloc] initWithFormat:fmt arguments:ap];
        va_end(ap);
        NSString *p = @"/var/mobile/Documents/C18ConnLayout.log";
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:p]) [fm createFileAtPath:p contents:nil attributes:nil];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:p];
        if (fh) { [fh seekToEndOfFile]; [fh writeData:[[m stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
    }
}

#define KEEP_COUNT 5

// 期望顺序里的按钮索引（由探测日志确定后填入；-1 表示未知，按原顺序补）
static int gWanted[KEEP_COUNT] = {-1, -1, -1, -1, -1};

static void (*orig_layout)(id, SEL);
static CGRect gSlot[8];
static NSUInteger gSlotCount = 0;

static NSString *ButtonIconName(UIView *b) {
    // 尝试从 CC18 的按钮里读图标/标识
    @try {
        id glyph = [b valueForKey:@"_glyphView"];
        if (glyph) return NSStringFromClass([glyph class]);
    } @catch (__unused NSException *e) {}
    @try {
        id ident = [b valueForKey:@"_identifier"];
        if ([ident isKindOfClass:NSString.class]) return ident;
    } @catch (__unused NSException *e) {}
    return NSStringFromClass([b class]);
}

static void hook_layout(id self, SEL _cmd) {
    if (orig_layout) orig_layout(self, _cmd);

    NSArray *buttons = nil;
    UIView *cluster = nil;
    @try { buttons = [self valueForKey:@"_buttons"]; } @catch (__unused NSException *e) {}
    @try { cluster = [self valueForKey:@"_cluster"]; } @catch (__unused NSException *e) {}
    if (![buttons isKindOfClass:NSArray.class] || buttons.count < 2) return;
    if (!cluster) cluster = [buttons.firstObject superview];
    if (!cluster) return;

    static BOOL loggedOnce = NO;
    if (!loggedOnce) {
        loggedOnce = YES;
        CLlog(@"=== buttons=%lu cluster=%@ ===", (unsigned long)buttons.count, NSStringFromCGRect(cluster.bounds));
        for (NSUInteger i = 0; i < buttons.count; i++) {
            UIView *b = buttons[i];
            CLlog(@"  #%lu icon=%@ frame=%@ center=%@",
                  (unsigned long)i, ButtonIconName(b),
                  NSStringFromCGRect(b.frame), NSStringFromCGPoint(b.center));
            // 尝试 dump 所有 ivar 名，帮助识别
            unsigned int cnt = 0;
            Ivar *ivars = class_copyIvarList([b class], &cnt);
            NSMutableString *iv = [NSMutableString string];
            for (unsigned int k = 0; k < cnt && k < 12; k++) {
                [iv appendFormat:@"%s ", ivar_getName(ivars[k])];
            }
            free(ivars);
            CLlog(@"      ivars: %@", iv);
        }
    }

    // 归零 transform（CC18 用 transform 定位）
    for (UIView *b in buttons) {
        if (!CGAffineTransformIsIdentity(b.transform)) b.transform = CGAffineTransformIdentity;
    }

    CGRect cb = cluster.bounds;
    CGFloat bw = 0, bh = 0;
    for (UIView *b in buttons) {
        if (b.bounds.size.width > bw) { bw = b.bounds.size.width; bh = b.bounds.size.height; }
    }
    if (bw <= 0) return;

    CGFloat margin = 8.0;
    NSUInteger shown = MIN((NSUInteger)KEEP_COUNT, buttons.count);
    CGFloat usable = cb.size.width - margin * 2;
    CGFloat gap = (shown > 1) ? (usable - shown * bw) / (CGFloat)(shown - 1) : 0;
    if (gap < 2.0) gap = 2.0;
    CGFloat cy = cb.size.height / 2.0;

    // 决定实际显示顺序
    NSMutableArray *order = [NSMutableArray array];
    for (int i = 0; i < KEEP_COUNT; i++) {
        int idx = gWanted[i];
        if (idx >= 0 && idx < (int)buttons.count) [order addObject:@(idx)];
    }
    if (order.count < shown) {
        // 未配置时按原顺序补
        for (NSUInteger i = 0; i < buttons.count && order.count < shown; i++) {
            if (![order containsObject:@(i)]) [order addObject:@(i)];
        }
    }

    gSlotCount = order.count;
    for (NSUInteger k = 0; k < order.count; k++) {
        UIView *b = buttons[[order[k] unsignedIntegerValue]];
        b.hidden = NO;
        b.alpha = 1.0;
        CGRect f = CGRectMake(margin + k * (bw + gap), cy - bh / 2.0, bw, bh);
        b.frame = f;
        b.userInteractionEnabled = YES;
        gSlot[k] = f;
    }
    // 未选中的隐藏
    for (UIView *b in buttons) {
        BOOL keep = NO;
        for (NSNumber *n in order) if (buttons[[n unsignedIntegerValue]] == b) { keep = YES; break; }
        if (!keep) b.hidden = YES;
    }
}

static UIView *(*orig_hitTest)(id, SEL, CGPoint, UIEvent *);
static UIView *hook_hitTest(id self, SEL _cmd, CGPoint point, UIEvent *event) {
    NSArray *buttons = nil;
    @try { buttons = [self valueForKey:@"_buttons"]; } @catch (__unused NSException *e) {}
    if (gSlotCount > 0 && [buttons isKindOfClass:NSArray.class]) {
        UIView *cluster = [buttons.firstObject superview];
        if (cluster) {
            CGPoint p = [self convertPoint:point toView:cluster];
            NSUInteger n = MIN(gSlotCount, buttons.count);
            for (NSUInteger i = 0; i < n; i++) {
                UIView *b = buttons[i];
                if (b.hidden) continue;
                if (CGRectContainsPoint(CGRectInset(gSlot[i], -4, -4), p)) return b;
            }
        }
    }
    return orig_hitTest ? orig_hitTest(self, _cmd, point, event) : nil;
}

static void CLInstall(void) {
    Class cls = NSClassFromString(@"C18ConnectivityView");
    if (!cls) { CLlog(@"C18ConnectivityView not found"); return; }
    if (orig_layout) return;
    Method m = class_getInstanceMethod(cls, @selector(layoutSubviews));
    if (!m) { CLlog(@"no layoutSubviews"); return; }
    orig_layout = (void (*)(id, SEL))method_getImplementation(m);
    method_setImplementation(m, (IMP)hook_layout);
    Method h = class_getInstanceMethod(cls, @selector(hitTest:withEvent:));
    if (h) {
        orig_hitTest = (UIView *(*)(id, SEL, CGPoint, UIEvent *))method_getImplementation(h);
        method_setImplementation(h, (IMP)hook_hitTest);
    }
    CLlog(@"hooks installed (layout+hitTest)");
}

__attribute__((constructor)) static void CLInit(void) {
    @autoreleasepool {
        CLlog(@"C18ConnLayout v3 loaded");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ CLInstall(); });
    }
}
