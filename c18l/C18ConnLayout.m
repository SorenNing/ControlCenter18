#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// v4：正确方案 —— 把 _buttons 缩减为 5 个 + 强制 gridSize=3，
// 让 CC18 自己的 layoutSubviews 排版（不碰 frame，不再错位）。
// 目标顺序：飞行 > WiFi > 蓝牙 > 热点 > 蜂窝

static void CLlog(NSString *fmt, ...) {
    @autoreleasepool {
        va_list a; va_start(a, fmt);
        NSString *m = [[NSString alloc] initWithFormat:fmt arguments:a];
        va_end(a);
        NSString *p = @"/var/mobile/Documents/C18ConnLayout.log";
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:p]) [fm createFileAtPath:p contents:nil attributes:nil];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:p];
        if (fh) { [fh seekToEndOfFile]; [fh writeData:[[m stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
    }
}

static NSArray *g_origButtons;

// 目标顺序（用小写关键字匹配 VC 类名/标识）
static NSArray<NSString *> *CLDesiredOrder(void) {
    return @[@"airplane", @"wifi", @"bluetooth", @"hotspot", @"cellular"];
}

static NSString *CLIdentForButton(NSArray *buttons, NSUInteger idx, id legacyDict) {
    // 先试 dictionary allKeys
    if ([legacyDict isKindOfClass:[NSDictionary class]]) {
        NSArray *keys = [legacyDict allKeys];
        if (idx < keys.count) return [keys[idx] description];
    }
    return nil;
}

static void CLFilterButtons(id self) {
    @try {
        NSArray *buttons = [self valueForKey:@"_buttons"];
        if (![buttons isKindOfClass:[NSArray class]]) { CLlog(@"no _buttons"); return; }
        if (g_origButtons && [buttons isEqualToArray:g_origButtons]) {
            // already filtered
        }
        id legacy = nil;
        @try { legacy = [self valueForKey:@"_legacy"]; } @catch (__unused NSException *e) {}

        CLlog(@"=== buttons=%lu legacyKeys=%@ ===", (unsigned long)buttons.count,
              [legacy isKindOfClass:[NSDictionary class]] ? [[legacy allKeys] componentsJoinedByString:@","] : @"n/a");

        NSMutableArray *named = [NSMutableArray array];
        for (NSUInteger i = 0; i < buttons.count; i++) {
            UIView *b = buttons[i];
            NSString *cls = NSStringFromClass([b class]);
            NSInteger tag = b.tag;
            UIImage *glyph = nil;
            @try { glyph = [b valueForKey:@"_glyphImage"]; } @catch (__unused NSException *e) {}
            NSString *gdesc = glyph ? [NSString stringWithFormat:@"%.0fx%.0f", glyph.size.width, glyph.size.height] : @"nil";
            NSString *ident = CLIdentForButton(buttons, i, legacy) ?: @"?";
            [named addObject:ident.lowercaseString];
            CLlog(@"  #%lu cls=%@ tag=%ld glyph=%@ ident=%@ frame=%@",
                  (unsigned long)i, cls, (long)tag, gdesc, ident, NSStringFromCGRect(b.frame));
        }

        if (!g_origButtons) g_origButtons = [buttons copy];

        // 按目标顺序挑选
        NSMutableArray *picked = [NSMutableArray array];
        NSMutableIndexSet *used = [NSMutableIndexSet indexSet];
        for (NSString *want in CLDesiredOrder()) {
            for (NSUInteger i = 0; i < named.count; i++) {
                if ([used containsIndex:i]) continue;
                if ([named[i] containsString:want]) { [picked addObject:buttons[i]]; [used addIndex:i]; break; }
            }
        }
        if (picked.count < 5) {
            // 关键字没匹配上：退回前 5 个，保证数量正确
            CLlog(@"keyword match only %lu, fallback to first 5", (unsigned long)picked.count);
            [picked removeAllObjects];
            for (NSUInteger i = 0; i < buttons.count && picked.count < 5; i++) [picked addObject:buttons[i]];
        }
        CLlog(@"picked=%lu order=%@", (unsigned long)picked.count, named);

        [self setValue:[picked copy] forKey:@"_buttons"];
        // 强制 5 按钮布局分支
        SEL sg = NSSelectorFromString(@"setGridSize:");
        if ([self respondsToSelector:sg]) { void (*f)(id,SEL,long long) = (void (*)(id,SEL,long long))[self methodForSelector:sg]; if (f) f(self, sg, 3); }
        CLlog(@"_buttons set to 5, gridSize=3");
        (void)sg;
    } @catch (NSException *e) { CLlog(@"filter fail: %@", e.reason); }
}

static id (*orig_initLegacy)(id, SEL, id);
static id hook_initLegacy(id self, SEL _cmd, id module) {
    id r = orig_initLegacy ? orig_initLegacy(self, _cmd, module) : nil;
    if (r) CLFilterButtons(r);
    return r;
}

__attribute__((constructor)) static void CLInit(void) {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            for (int i = 0; i < 8; i++) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * (i + 1) * NSEC_PER_SEC)),
                  dispatch_get_main_queue(), ^{
                    Class cls = NSClassFromString(@"C18ConnectivityView");
                    if (!cls) return;
                    Method m = class_getInstanceMethod(cls, NSSelectorFromString(@"initWithLegacyModule:"));
                    if (!m || orig_initLegacy) return;
                    orig_initLegacy = (id (*)(id, SEL, id))method_getImplementation(m);
                    method_setImplementation(m, (IMP)hook_initLegacy);
                    CLlog(@"initWithLegacyModule REPLACED OK");
                });
            }
        });
    }
}
