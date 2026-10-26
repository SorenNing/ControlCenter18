#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// 连接模块：保留 CC18 原有 7 按钮角色/状态逻辑，
// 但在布局完成后自行排布：只显示前 5 个，均匀铺满一行，隐藏其余。

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

static void (*orig_layout)(id, SEL);
static void hook_layout(id self, SEL _cmd) {
    if (orig_layout) orig_layout(self, _cmd);

    NSArray *buttons = nil;
    UIView *cluster = nil;
    @try { buttons = [self valueForKey:@"_buttons"]; } @catch (__unused NSException *e) {}
    @try { cluster = [self valueForKey:@"_cluster"]; } @catch (__unused NSException *e) {}
    if (![buttons isKindOfClass:NSArray.class] || buttons.count < 2) {
        CLlog(@"no buttons (count=%lu)", (unsigned long)buttons.count);
        return;
    }
    if (!cluster) cluster = [buttons.firstObject superview];
    if (!cluster) { CLlog(@"no cluster"); return; }

    static BOOL loggedOnce = NO;
    if (!loggedOnce) {
        loggedOnce = YES;
        CLlog(@"buttons=%lu cluster=%@", (unsigned long)buttons.count, NSStringFromCGRect(cluster.bounds));
        for (NSUInteger i = 0; i < buttons.count; i++) {
            UIView *b = buttons[i];
            CLlog(@"  #%lu frame=%@ alpha=%.2f hidden=%d cls=%@",
                  (unsigned long)i, NSStringFromCGRect(b.frame), b.alpha, b.hidden,
                  NSStringFromClass(b.class));
        }
    }

    // 排布：前 KEEP_COUNT 个均匀一行，其余隐藏
    CGRect cb = cluster.bounds;
    CGFloat bw = 0, bh = 0;
    for (UIView *b in buttons) {
        if (b.bounds.size.width > bw) { bw = b.bounds.size.width; bh = b.bounds.size.height; }
    }
    if (bw <= 0) return;

    CGFloat margin = 10.0;
    NSUInteger shown = MIN((NSUInteger)KEEP_COUNT, buttons.count);
    CGFloat usable = cb.size.width - margin * 2;
    CGFloat gap = (usable - shown * bw) / MAX((CGFloat)(shown - 1), 1.0);
    if (gap < 4.0) gap = 4.0;
    CGFloat cy = cb.size.height / 2.0;

    for (NSUInteger i = 0; i < buttons.count; i++) {
        UIView *b = buttons[i];
        if (i < shown) {
            b.hidden = NO;
            b.alpha = 1.0;
            b.transform = CGAffineTransformIdentity;
            b.frame = CGRectMake(margin + i * (bw + gap), cy - bh / 2.0, bw, bh);
        } else {
            b.hidden = YES;
        }
    }
}

static void CLInstall(void) {
    Class cls = NSClassFromString(@"C18ConnectivityView");
    if (!cls) { CLlog(@"C18ConnectivityView not found"); return; }
    if (orig_layout) return;
    Method m = class_getInstanceMethod(cls, @selector(layoutSubviews));
    if (!m) { CLlog(@"no layoutSubviews"); return; }
    orig_layout = (void (*)(id, SEL))method_getImplementation(m);
    method_setImplementation(m, (IMP)hook_layout);
    CLlog(@"layoutSubviews REPLACED OK");
}

__attribute__((constructor)) static void CLInit(void) {
    @autoreleasepool {
        CLlog(@"C18ConnLayout loaded");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ CLInstall(); });
    }
}
