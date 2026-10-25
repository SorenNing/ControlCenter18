#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ControlCenter18 设置页最后添加一个标准设置项（cell）：
// 头像图标 + "Ning自用二改版"，点击跳转 GitHub 主页。
// 实现：hook 表格数据源（最后一个 section 的最后一行插入）。

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

static void C18OwnerOpen(void) {
    NSURL *url = [NSURL URLWithString:kOwnerRepoURL];
    if (url && @available(iOS 10.0, *)) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        C18Log(@"open url");
    }
}

#pragma mark - 最后一行判定

static BOOL C18IsOwnerIndexPath(NSIndexPath *ip, id table, id controller) {
    NSInteger sections = 0;
    @try {
        sections = ((NSInteger (*)(id, SEL, id))objc_msgSend)(controller, @selector(numberOfSectionsInTableView:), table);
    } @catch (__unused NSException *e) { return NO; }
    if (ip.section != sections - 1) return NO;
    NSInteger rows = 0;
    @try {
        rows = ((NSInteger (*)(id, SEL, id, NSInteger))objc_msgSend)(
            controller, @selector(tableView:numberOfRowsInSection:), table, ip.section);
    } @catch (__unused NSException *e) { return NO; }
    return ip.row == rows - 1;
}

#pragma mark - 数据源 hook

static NSInteger (*orig_numberOfRows)(id, SEL, id, NSInteger);
static NSInteger hook_numberOfRows(id self, SEL _cmd, id table, NSInteger section) {
    NSInteger rows = orig_numberOfRows ? orig_numberOfRows(self, _cmd, table, section) : 0;
    NSInteger sections = 0;
    @try {
        sections = ((NSInteger (*)(id, SEL, id))objc_msgSend)(self, @selector(numberOfSectionsInTableView:), table);
    } @catch (__unused NSException *e) { return rows; }
    if (section == sections - 1) return rows + 1; // 最后分组多一行
    return rows;
}

static id (*orig_cellForRow)(id, SEL, id, id);
static id hook_cellForRow(id self, SEL _cmd, id table, NSIndexPath *ip) {
    if (C18IsOwnerIndexPath(ip, table, self)) {
        NSString *reuse = @"c18OwnerCell";
        UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:reuse];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];
            cell.imageView.layer.cornerRadius = 13.0;
            cell.imageView.layer.masksToBounds = YES;
            cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        cell.textLabel.text = kRowTitle;
        cell.imageView.image = C18OwnerAvatar();
        [cell.imageView sizeToFit];
        return cell;
    }
    return orig_cellForRow ? orig_cellForRow(self, _cmd, table, ip) : nil;
}

static void (*orig_didSelect)(id, SEL, id, id);
static void hook_didSelect(id self, SEL _cmd, id table, NSIndexPath *ip) {
    if (C18IsOwnerIndexPath(ip, table, self)) {
        [table deselectRowAtIndexPath:ip animated:YES];
        C18OwnerOpen();
        return;
    }
    if (orig_didSelect) orig_didSelect(self, _cmd, table, ip);
}

#pragma mark - hook 安装

static void C18Install(void) {
    Class cls = NSClassFromString(@"C18PRootListController");
    if (!cls) { C18Log(@"class not found"); return; }
    if (orig_numberOfRows) { C18Log(@"already hooked"); return; }

    Method m;

    m = class_getInstanceMethod(cls, @selector(tableView:numberOfRowsInSection:));
    if (m) {
        IMP orig = method_getImplementation(m);
        class_addMethod(cls, @selector(tableView:numberOfRowsInSection:), (IMP)hook_numberOfRows, method_getTypeEncoding(m));
        orig_numberOfRows = (NSInteger (*)(id, SEL, id, NSInteger))orig;
    }
    m = class_getInstanceMethod(cls, @selector(tableView:cellForRowAtIndexPath:));
    if (m) {
        IMP orig = method_getImplementation(m);
        class_addMethod(cls, @selector(tableView:cellForRowAtIndexPath:), (IMP)hook_cellForRow, method_getTypeEncoding(m));
        orig_cellForRow = (id (*)(id, SEL, id, id))orig;
    }
    m = class_getInstanceMethod(cls, @selector(tableView:didSelectRowAtIndexPath:));
    if (m) {
        IMP orig = method_getImplementation(m);
        class_addMethod(cls, @selector(tableView:didSelectRowAtIndexPath:), (IMP)hook_didSelect, method_getTypeEncoding(m));
        orig_didSelect = (void (*)(id, SEL, id, id))orig;
    }
    C18Log(@"datasource hooked");
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