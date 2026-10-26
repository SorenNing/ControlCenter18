#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// CC18 连接模块布局切换探针：
// 二进制分析：-[C18ConnectivityView setGridSize:] 中
//   cmp x2, #5  =>  _alternateLayout = (gridSize == 5)
// 即 gridSize==5 时启用第二套（alternate）布局。
// 这里把传入的 gridSize 强改为 5，观察是否切换到另一套布局。

static void CLlog(NSString *fmt, ...) {
    @autoreleasepool {
        va_list a; va_start(a, fmt);
        NSString *m = [[NSString alloc] initWithFormat:fmt arguments:a];
        va_end(a);
        NSString *p = @"/var/mobile/Documents/C18ConnLayout.log";
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:p]) [fm createFileAtPath:p contents:nil attributes:nil];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
        if (h) { [h seekToEndOfFile]; [h writeData:[[m stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile]; }
    }
}

static void (*orig_setGridSize)(id, SEL, long long);
static void hook_setGridSize(id self, SEL _cmd, long long size) {
    CLlog(@"setGridSize: %lld -> 5", size);
    if (orig_setGridSize) orig_setGridSize(self, _cmd, 5);
}

static void CLInstall(void) {
    Class cls = NSClassFromString(@"C18ConnectivityView");
    if (!cls) { CLlog(@"C18ConnectivityView not found"); return; }
    Method m = class_getInstanceMethod(cls, NSSelectorFromString(@"setGridSize:"));
    if (!m) { CLlog(@"no setGridSize:"); return; }
    if (orig_setGridSize) return;
    orig_setGridSize = (void (*)(id, SEL, long long))method_getImplementation(m);
    method_setImplementation(m, (IMP)hook_setGridSize);
    CLlog(@"setGridSize REPLACED %@", method_getImplementation(m) == (IMP)hook_setGridSize ? @"OK" : @"FAILED");
}

__attribute__((constructor)) static void CLInit(void) {
    @autoreleasepool {
        CLlog(@"C18ConnLayout loaded");
        dispatch_async(dispatch_get_main_queue(), ^{
            for (int i = 0; i < 8; i++) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * (i + 1) * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{ CLInstall(); });
            }
        });
    }
}