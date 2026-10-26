#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// CC18「添加控制」资源库汉化：CC18 把模块名硬编码成英文，这里 hook
// C18GalleryItem / C18GallerySection 的 setTitle: 做映射替换。

static void CGLog(NSString *fmt, ...) {
    @autoreleasepool {
        va_list args; va_start(args, fmt);
        NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
        va_end(args);
        NSString *path = @"/var/mobile/Documents/C18GalleryCN.log";
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (fh) { [fh seekToEndOfFile]; [fh writeData:[[msg stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
    }
}

static NSDictionary<NSString *, NSString *> *CNMap(void) {
    static NSDictionary *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        m = @{
            // 资源库模块名
            @"Translate": @"翻译",
            @"Alarm": @"闹钟",
            @"Timer": @"计时器",
            @"Text Size": @"文字大小",
            @"Magnifier": @"放大器",
            @"Voice Memo": @"语音备忘录",
            @"Dark Mode": @"深色模式",
            @"Flashlight": @"手电筒",
            @"Stopwatch": @"秒表",
            @"Quick Note": @"快速备忘录",
            @"Low Power Mode": @"低电量模式",
            @"Scan Code": @"扫描二维码",
            @"Home": @"家庭",
            @"Screen Mirroring": @"屏幕镜像",
            @"Recognize Music": @"识别音乐",
            @"Notes": @"备忘录",
            @"Volume": @"音量",
            @"Silent Mode": @"静音模式",
            @"Now Playing": @"正在播放",
            @"Shortcut": @"快捷指令",
            @"Shortcuts": @"快捷指令",
            @"Open App": @"打开 App",
            @"Remote": @"遥控器",
            @"Connectivity": @"连接",
            @"Camera": @"相机",
            @"Calculator": @"计算器",
            @"Print Center": @"打印中心",
            @"Announce Notifications": @"播报通知",
            @"Ping My Watch": @"查找我的手表",
            @"Other": @"其他",
            @"Accessibility Shortcuts": @"辅助功能快捷键",
            @"Guided Access": @"引导式访问",
            @"Background Sounds": @"背景音",
            @"Hearing": @"听力",
            @"Headphone Levels": @"耳机音量",
            @"Live Listen": @"实时收听",
            @"Sound Recognition": @"声音识别",
            @"Headphone Accommodations": @"耳机调节",
            @"Vehicle Motion Cues": @"车辆运动提示",
            // 分组标题（CC18 自己的键名，万一直接拿到英文也翻）
            @"Sounds": @"声音",
            @"Capture": @"拍摄",
            @"Utilities": @"工具",
            @"Display & Brightness": @"显示与亮度",
            @"Accessibility": @"辅助功能",
            @"Vision": @"视觉",
            @"Motor": @"动作",
            // 连接类（遗留模块名，图里仍显示英文的）
            @"Airplane Mode": @"飞行模式",
            @"Cellular Data": @"蜂窝数据",
            @"Personal Hotspot": @"个人热点",
            @"AirDrop": @"隔空投送",
            @"Bluetooth": @"蓝牙",
            @"VPN": @"VPN",
            @"Wi-Fi": @"无线局域网",
            @"WiFi": @"无线局域网",
            @"Cellular": @"蜂窝网络",
            // 显示与亮度
            @"Brightness": @"亮度",
            @"Wallet": @"钱包",
            @"Do Not Disturb": @"勿扰模式",
            @"Sleep": @"睡眠",
            // 上一版误删、补回
            @"Screen Recording": @"屏幕录制",
            @"Orientation Lock": @"方向锁定",
            @"Focus": @"专注模式",
            @"Low Power": @"低电量",
            @"Music Recognition": @"音乐识别",
        };
    });
    return m;
}

static NSString *CNTranslate(NSString *s) {
    if (![s isKindOfClass:NSString.class] || s.length == 0) return s;
    NSString *t = CNMap()[s];
    if (t) return t;
    // 已含中文就不动
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c >= 0x4E00 && c <= 0x9FFF) return s;
    }
    return s;
}

static void (*orig_setTitle_item)(id, SEL, NSString *);
static void hook_setTitle_item(id self, SEL _cmd, NSString *title) {
    NSString *t = CNTranslate(title);
    if (orig_setTitle_item) orig_setTitle_item(self, _cmd, t);
}

static NSString *(*orig_getTitle_item)(id, SEL);
static NSString *hook_getTitle_item(id self, SEL _cmd) {
    NSString *t = orig_getTitle_item ? orig_getTitle_item(self, _cmd) : nil;
    return CNTranslate(t);
}

static void (*orig_setTitle_section)(id, SEL, NSString *);
static void hook_setTitle_section(id self, SEL _cmd, NSString *title) {
    NSString *t = CNTranslate(title);
    if (orig_setTitle_section) orig_setTitle_section(self, _cmd, t);
}

static void CGInstall(void) {
    Class itemCls = NSClassFromString(@"C18GalleryItem");
    if (itemCls) {
        Method m = class_getInstanceMethod(itemCls, @selector(setTitle:));
        if (m) {
            if (!orig_setTitle_item) {
                orig_setTitle_item = (void (*)(id, SEL, NSString *))method_getImplementation(m);
                method_setImplementation(m, (IMP)hook_setTitle_item);
                CGLog(@"C18GalleryItem setTitle hooked");
            }
        } else CGLog(@"no setTitle: on C18GalleryItem");
        Method g = class_getInstanceMethod(itemCls, @selector(title));
        if (g && !orig_getTitle_item) {
            orig_getTitle_item = (NSString *(*)(id, SEL))method_getImplementation(g);
            method_setImplementation(g, (IMP)hook_getTitle_item);
            CGLog(@"C18GalleryItem title getter hooked");
        }
    } else CGLog(@"C18GalleryItem not found");

    Class secCls = NSClassFromString(@"C18GallerySection");
    if (secCls) {
        Method m = class_getInstanceMethod(secCls, @selector(setTitle:));
        if (m) {
            if (!orig_setTitle_section) {
                orig_setTitle_section = (void (*)(id, SEL, NSString *))method_getImplementation(m);
                method_setImplementation(m, (IMP)hook_setTitle_section);
                CGLog(@"C18GallerySection setTitle hooked");
            }
        }
    }
}

__attribute__((constructor)) static void CGInit(void) {
    @autoreleasepool {
        CGLog(@"C18GalleryCN loaded");
        dispatch_async(dispatch_get_main_queue(), ^{
            for (int i = 0; i < 10; i++) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * (i + 1) * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{ CGInstall(); });
            }
        });
    }
}