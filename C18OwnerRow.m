#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// 在 ControlCenter18 设置页的 tableHeaderView（作者头像横幅）正下方
// 追加一行：圆形头像 + "Ning自用二改版"，点击跳转 GitHub 主页。

static NSString *const kOwnerRepoURL = @"https://github.com/SorenNing";

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

#pragma mark - 私有声明

@interface PSListController : UIViewController
@property(nonatomic, strong) UITableView *table;
@end

@interface C18PRootListController : PSListController
@end

#pragma mark - 头像

static UIImage *C18OwnerAvatar(void) {
    NSBundle *bundle = [NSBundle bundleWithPath:@"/Library/PreferenceBundles/ControlCenter18Prefs.bundle"];
    if (!bundle) { C18Log(@"no prefs bundle"); return nil; }
    UIImage *img = [UIImage imageNamed:@"owner-avatar" inBundle:bundle compatibleWithTraitCollection:nil];
    C18Log(@"avatar img: %@", img ? @"OK" : @"nil");
    return img;
}

static void C18OwnerTapped(void) {
    NSURL *url = [NSURL URLWithString:kOwnerRepoURL];
    if (url) {
        if (@available(iOS 10.0, *)) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            C18Log(@"open url");
        }
    }
}

#pragma mark - 加行

static void C18BPrototypeAddRow(UITableView *table, UIView *headerView) {
    if (!table || !headerView) { C18Log(@"addRow: skip (table/header nil)"); return; }
    if (objc_getAssociatedObject(headerView, "c18OwnerRow")) { C18Log(@"addRow: already"); return; }
    objc_setAssociatedObject(headerView, "c18OwnerRow", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    C18Log(@"addRow: header h=%.1f w=%.1f", headerView.bounds.size.height, headerView.bounds.size.width);

    const CGFloat rowHeight = 46.0;
    CGFloat width = table.bounds.size.width;
    if (width < 1) width = UIScreen.mainScreen.bounds.size.width;

    CGRect hf = headerView.frame;
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, hf.size.height + rowHeight)];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    headerView.frame = CGRectMake(0, 0, width, hf.size.height);
    headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [container addSubview:headerView];

    UIButton *row = [UIButton buttonWithType:UIButtonTypeSystem];
    row.frame = CGRectMake(0, hf.size.height, width, rowHeight);
    row.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    row.backgroundColor = [UIColor secondarySystemBackgroundColor];
    row.userInteractionEnabled = YES;
    if (@available(iOS 14.0, *)) {
        [row addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
            (void)action;
            C18OwnerTapped();
        }] forControlEvents:UIControlEventTouchUpInside];
    }

    UIImageView *iv = [[UIImageView alloc] initWithImage:C18OwnerAvatar()];
    iv.contentMode = UIViewContentModeScaleAspectFill;
    iv.layer.cornerRadius = 13.0;
    iv.layer.masksToBounds = YES;
    iv.frame = CGRectMake(16, (rowHeight - 26) / 2.0, 26, 26);
    [row addSubview:iv];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(52, 0, width - 92, rowHeight)];
    label.text = @"Ning自用二改版";
    label.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    label.textColor = UIColor.labelColor;
    label.userInteractionEnabled = NO;
    [row addSubview:label];

    UIImageView *chev = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"arrow.up.right.square"]];
    chev.tintColor = UIColor.secondaryLabelColor;
    chev.contentMode = UIViewContentModeScaleAspectFit;
    chev.frame = CGRectMake(width - 36, (rowHeight - 15) / 2.0, 15, 15);
    chev.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [row addSubview:chev];

    [container addSubview:row];
    table.tableHeaderView = container;
    C18Log(@"addRow: done");
}

static void C18BPrototypeOnController(id self) {
    UITableView *table = nil;
    @try { table = [self valueForKey:@"table"]; } @catch (__unused NSException *e) {}
    if (!table) { C18Log(@"no table on %@", NSStringFromClass([self class])); return; }
    UIView *hv = table.tableHeaderView;
    C18Log(@"controller %@ header=%@", NSStringFromClass([self class]), hv ? @"exists" : @"nil");

    // ---- 探针：打印作者控制器与 header 类的完整方法列表 ----
    static BOOL probed = NO;
    if (!probed) {
        probed = YES;
        for (NSString *clsName in @[@"C18PRootListController", @"C18PHeaderView"]) {
            Class cls = NSClassFromString(clsName);
            if (!cls) { C18Log(@"probe: %@ not found", clsName); continue; }
            C18Log(@"probe: %@ methods:", clsName);
            unsigned int mc = 0;
            Method *methods = class_copyMethodList(cls, &mc);
            for (unsigned int i = 0; i < mc; i++) {
                C18Log(@"   -[%s %s]", [clsName UTF8String], sel_getName(method_getName(methods[i])));
            }
            free(methods);
            // 类方法
            unsigned int cc = 0;
            Method *cms = class_copyMethodList(object_getClass(cls), &cc);
            for (unsigned int i = 0; i < cc; i++) {
                C18Log(@"   +[%s %s]", [clsName UTF8String], sel_getName(method_getName(cms[i])));
            }
            free(cms);
        }
    }

    if (hv) {
        C18BPrototypeAddRow(table, hv);
    } else {
        // 稍后再试（header 可能延迟设置）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                UIView *hv2 = table.tableHeaderView;
                if (hv2) C18BPrototypeAddRow(table, hv2);
            });
    }
}

#pragma mark - hook

static void (*orig_C18_viewDidLoad)(id, SEL);
static void hook_C18_viewDidLoad(id self, SEL _cmd) {
    if (orig_C18_viewDidLoad) orig_C18_viewDidLoad(self, _cmd);
    C18Log(@"viewDidLoad fired");
    C18BPrototypeOnController(self);
}

static void (*orig_C18_viewDidAppear)(id, SEL, BOOL);
static void hook_C18_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (orig_C18_viewDidAppear) orig_C18_viewDidAppear(self, _cmd, animated);
    C18Log(@"viewDidAppear fired");
    C18BPrototypeOnController(self);
}

static void C18Install(void) {
    Class cls = NSClassFromString(@"C18PRootListController");
    if (!cls) { C18Log(@"class not found"); return; }
    C18Log(@"installing hooks on %@", NSStringFromClass(cls));
    Method m;

    m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) {
        IMP orig = method_getImplementation(m);
        if (!class_addMethod(cls, @selector(viewDidLoad), (IMP)hook_C18_viewDidLoad, method_getTypeEncoding(m))) {
            Method own = class_getInstanceMethod(cls, @selector(viewDidLoad));
            orig = method_getImplementation(own);
            method_setImplementation(own, (IMP)hook_C18_viewDidLoad);
        }
        orig_C18_viewDidLoad = (void (*)(id, SEL))orig;
        C18Log(@"viewDidLoad hooked");
    }
    m = class_getInstanceMethod(cls, @selector(viewDidAppear:));
    if (m) {
        IMP orig = method_getImplementation(m);
        if (!class_addMethod(cls, @selector(viewDidAppear:), (IMP)hook_C18_viewDidAppear, method_getTypeEncoding(m))) {
            Method own = class_getInstanceMethod(cls, @selector(viewDidAppear:));
            orig = method_getImplementation(own);
            method_setImplementation(own, (IMP)hook_C18_viewDidAppear);
        }
        orig_C18_viewDidAppear = (void (*)(id, SEL, BOOL))orig;
        C18Log(@"viewDidAppear hooked");
    }
}

__attribute__((constructor)) static void C18Init(void) {
    @autoreleasepool {
        C18Log(@"C18OwnerRow loaded, bundle=%@", NSBundle.mainBundle.bundleIdentifier);
        dispatch_async(dispatch_get_main_queue(), ^{
            // 多次尝试：设置 bundle 的 dylib 注入晚于 launch
            for (int i = 0; i < 6; i++) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * (i + 1) * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{ C18Install(); });
            }
        });
    }
}