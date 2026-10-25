#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// 在 ControlCenter18 设置页的 tableHeaderView（作者头像横幅）正下方
// 追加一行：圆形头像 + "Ning自用二改版"，点击跳转 GitHub 主页。

static NSString *const kOwnerRepoURL = @"https://github.com/SorenNing";

#pragma mark - 私有声明

@interface PSListController : UIViewController
@property(nonatomic, strong) UITableView *table;
@end

@interface C18PRootListController : PSListController
@end

#pragma mark - 头像

static UIImage *C18OwnerAvatar(void) {
    NSBundle *bundle = [NSBundle bundleWithPath:@"/Library/PreferenceBundles/ControlCenter18Prefs.bundle"];
    if (!bundle) return nil;
    return [UIImage imageNamed:@"owner-avatar" inBundle:bundle compatibleWithTraitCollection:nil];
}

static void C18OwnerTapped(void) {
    NSURL *url = [NSURL URLWithString:kOwnerRepoURL];
    if (url) {
        if (@available(iOS 10.0, *)) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    }
}

#pragma mark - 加行

static void C18BPrototypeAddRow(UITableView *table, UIView *headerView) {
    if (!table || !headerView) return;
    if (objc_getAssociatedObject(headerView, "c18OwnerRow")) return;
    objc_setAssociatedObject(headerView, "c18OwnerRow", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    const CGFloat rowHeight = 46.0;
    CGFloat width = table.bounds.size.width;
    if (width < 1) width = UIScreen.mainScreen.bounds.size.width;

    CGRect hf = headerView.frame;
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, hf.size.height + rowHeight)];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    // 原 header 放顶部，不动它
    headerView.frame = CGRectMake(0, 0, width, hf.size.height);
    headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [container addSubview:headerView];

    // 新行（整行是一个按钮）
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
}

#pragma mark - hook

static void (*orig_C18_viewDidLoad)(id, SEL);
static void hook_C18_viewDidLoad(id self, SEL _cmd) {
    if (orig_C18_viewDidLoad) orig_C18_viewDidLoad(self, _cmd);
    @try {
        UITableView *table = [self valueForKey:@"table"];
        UIView *hv = table.tableHeaderView;
        if (hv) C18BPrototypeAddRow(table, hv);
    } @catch (__unused NSException *e) {}
}

static void C18Install(void) {
    Class cls = NSClassFromString(@"C18PRootListController");
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (!m) return;
    IMP orig = method_getImplementation(m);
    if (!class_addMethod(cls, @selector(viewDidLoad), (IMP)hook_C18_viewDidLoad, method_getTypeEncoding(m))) {
        Method own = class_getInstanceMethod(cls, @selector(viewDidLoad));
        if (own) {
            orig = method_getImplementation(own);
            method_setImplementation(own, (IMP)hook_C18_viewDidLoad);
        }
    }
    orig_C18_viewDidLoad = (void (*)(id, SEL))orig;
}

__attribute__((constructor)) static void C18Init(void) {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{ C18Install(); });
    }
}