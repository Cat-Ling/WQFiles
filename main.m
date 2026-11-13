//
//  main.m
//  WQ Files
//
//  App backup and restore manager for iOS 26+ that reaches other containers
//  through the worse_query sandbox escape by Taj C (forcequit),
//  https://github.com/forcequitOS/worse_query, GPL-3.0-or-later.
//  This app is GPL-3.0-or-later as well (see LICENSE).
//

#import <UIKit/UIKit.h>
#import "WQAccess.h"
#import "WQLaunchServices.h"
#import "WQUI.h"
#import "WQSharing.h"
#import "WQApps.h"
#import "WQHealth.h"

#pragma mark - Log

@interface WQLogViewController : UIViewController
@end

@implementation WQLogViewController {
    UITextView *_textView;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = WQLocalizedNullable(@"Log");
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    _textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    _textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _textView.editable = NO;
    _textView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _textView.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    _textView.textAlignment = NSTextAlignmentLeft;   // log lines stay left to right
    [self.view addSubview:_textView];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                                           target:self action:@selector(share:)];
}

// App version, device and iOS first, so a Log someone sends in says where it
// came from.
- (NSString *)fullLog
{
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    return WQLocalizedFormat(@"WQ Files %@ (%@)\n%@\n\n%@",
            info[@"CFBundleShortVersionString"] ?: @"?", info[@"CFBundleVersion"] ?: @"?", wq_device_line(), wq_log_text());
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    _textView.text = [self fullLog];
}

- (void)share:(UIBarButtonItem *)sender
{
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[[self fullLog]]
                                                                        applicationActivities:nil];
    share.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:share animated:YES completion:nil];
}

@end

#pragma mark - Navigation

// Adds a Home button next to Back on screens two or more levels deep.
@interface WQNavigationController : UINavigationController <UINavigationControllerDelegate>
@end

@implementation WQNavigationController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.delegate = self;
}

- (void)navigationController:(UINavigationController *)nav willShowViewController:(UIViewController *)vc animated:(BOOL)animated
{
    [nav setToolbarHidden:YES animated:animated];
    NSUInteger depth = [nav.viewControllers indexOfObject:vc];
    if (depth == NSNotFound || depth < 2) {
        if (vc.navigationItem.leftBarButtonItem.tag == 0x484f4d45) vc.navigationItem.leftBarButtonItem = nil;
        return;
    }
    if (vc.navigationItem.leftBarButtonItem) return;
    UIBarButtonItem *home = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"house"]
                                                             style:UIBarButtonItemStylePlain target:self action:@selector(goHome)];
    home.tag = 0x484f4d45;   // "HOME"
    home.accessibilityLabel = WQLocalizedNullable(@"Home");
    vc.navigationItem.leftItemsSupplementBackButton = YES;
    vc.navigationItem.leftBarButtonItem = home;
}

- (void)goHome
{
    [self popToRootViewControllerAnimated:YES];
}

@end

#pragma mark - Root

@interface WQHealthViewController : UITableViewController
- (instancetype)initWithChecks:(NSArray<WQHealthCheck *> *)checks;
@property (nonatomic, copy, nullable) void (^onPassed)(NSArray<WQHealthCheck *> *checks);
@end

@interface WQRootViewController : UITableViewController
@end

static NSString *const kWQLanguagePref = @"WQLanguage";

// The language picked in WQ Files, or nil for the device's.
static NSString *wq_chosen_language(void)
{
    NSString *code = [NSUserDefaults.standardUserDefaults stringForKey:kWQLanguagePref];
    return code.length ? code : nil;
}

// Each language in its own name, so it can be found whatever is shown now.
static NSString *wq_language_name(NSString *code)
{
    if (!code.length) return WQLocalized(@"System Default");
    // A regional table (pt-BR) is named with its region: "Português (Brasil)".
    NSLocale *own = [NSLocale localeWithLocaleIdentifier:code];
    NSString *name = [code containsString:@"-"] && ![code isEqualToString:@"zh-Hans"]
        ? [own localizedStringForLocaleIdentifier:code] : [own localizedStringForLanguageCode:code];
    if ([code isEqualToString:@"zh-Hans"]) name = @"简体中文";
    return name.length ? [[name substringToIndex:1].uppercaseString stringByAppendingString:[name substringFromIndex:1]] : code;
}

// A flag for each shipped language, drawn as an image so the names line up.
// Languages are spoken in many countries; the flag is the usual pick for
// language menus (English: UK, Arabic: Saudi Arabia, Portuguese: Brazil as
// shipped). System Default gets a globe.
static UIImage *wq_language_flag(NSString *code)
{
    if (!code.length) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
        return [UIImage systemImageNamed:@"globe" withConfiguration:cfg];
    }
    static NSDictionary<NSString *, NSString *> *regions;
    static NSCache *images;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        regions = @{ @"en": @"GB", @"de": @"DE", @"it": @"IT", @"es": @"ES", @"pt-BR": @"BR", @"pl": @"PL",
                     @"ru": @"RU", @"ko": @"KR", @"zh-Hans": @"CN", @"ar": @"SA", @"tr": @"TR" };
        images = [NSCache new];
    });
    NSString *region = regions[code];
    if (!region) region = [[NSLocale localeWithLocaleIdentifier:code] objectForKey:NSLocaleCountryCode];
    if (region.length != 2) return nil;
    UIImage *cached = [images objectForKey:region];
    if (cached) return cached;
    // Regional indicator symbols: A = U+1F1E6.
    NSMutableString *flag = [NSMutableString new];
    for (NSUInteger i = 0; i < 2; i++) {
        UTF32Char scalar = 0x1F1E6 + ([region.uppercaseString characterAtIndex:i] - 'A');
        UTF32Char be = NSSwapHostIntToBig(scalar);
        [flag appendString:[[NSString alloc] initWithBytes:&be length:4 encoding:NSUTF32BigEndianStringEncoding]];
    }
    NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:24] };
    CGSize size = [flag sizeWithAttributes:attrs];
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *__unused ctx) {
        [flag drawAtPoint:CGPointZero withAttributes:attrs];
    }];
    [images setObject:image forKey:region];
    return image;
}

// iOS only offers Settings → WQ Files → Language when the device has more
// than one preferred language, so WQ Files has its own list, built from the
// languages the app ships. The choice is this app's AppleLanguages default,
// which iOS applies at launch (text and right-to-left layout alike), so it
// takes effect when WQ Files restarts.
@interface WQLanguageViewController : UITableViewController
@end

@implementation WQLanguageViewController {
    NSArray<NSString *> *_codes;
}

- (instancetype)init
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        self.title = WQLocalized(@"Language");
        // localizations can name a language twice (the .lproj folder and the
        // CFBundleLocalizations entry, sometimes spelled differently): one
        // row per language.
        NSMutableArray *codes = [NSMutableArray new];
        NSMutableSet *seen = [NSMutableSet new];
        for (NSString *code in NSBundle.mainBundle.localizations) {
            NSString *canonical = [NSLocale canonicalLanguageIdentifierFromString:code];
            if ([code isEqualToString:@"Base"] || [seen containsObject:canonical]) continue;
            [seen addObject:canonical];
            [codes addObject:code];
        }
        [codes sortUsingComparator:^NSComparisonResult(NSString *x, NSString *y) {
            return [wq_language_name(x) localizedCaseInsensitiveCompare:wq_language_name(y)];
        }];
        _codes = codes;
    }
    return self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 0 ? 1 : (NSInteger)_codes.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return section == 1 ? WQLocalized(@"The new language is used the next time WQ Files starts.") : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"l"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"l"];
    UIListContentConfiguration *c = [UIListContentConfiguration subtitleCellConfiguration];
    NSString *code = indexPath.section == 0 ? @"" : _codes[(NSUInteger)indexPath.row];
    c.text = wq_language_name(code);
    c.image = wq_language_flag(code);
    c.imageProperties.reservedLayoutSize = CGSizeMake(34, 0);
    if (!code.length) c.imageProperties.tintColor = UIColor.secondaryLabelColor;
    // Like iOS: each language in its own name, and in the one shown now.
    NSString *shownLanguage = NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en";
    if (code.length) {
        NSLocale *shown = [NSLocale localeWithLocaleIdentifier:shownLanguage];
        NSString *here = [code containsString:@"-"] && ![code isEqualToString:@"zh-Hans"]
            ? [shown localizedStringForLocaleIdentifier:code] : [shown localizedStringForLanguageCode:code];
        if (here.length && [here localizedCaseInsensitiveCompare:c.text] != NSOrderedSame) c.secondaryText = here;
    } else {
        NSString *device = [NSLocale preferredLanguages].firstObject;
        if (device.length) c.secondaryText = [[NSLocale localeWithLocaleIdentifier:shownLanguage] localizedStringForLanguageCode:device];
    }
    c.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    cell.contentConfiguration = c;
    cell.accessoryType = [code isEqualToString:wq_chosen_language() ?: @""] ? UITableViewCellAccessoryCheckmark
                                                                          : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *code = indexPath.section == 0 ? @"" : _codes[(NSUInteger)indexPath.row];
    if ([code isEqualToString:wq_chosen_language() ?: @""]) return;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (code.length) {
        [defaults setObject:code forKey:kWQLanguagePref];
        [defaults setObject:@[code] forKey:@"AppleLanguages"];
    } else {
        [defaults removeObjectForKey:kWQLanguagePref];
        [defaults removeObjectForKey:@"AppleLanguages"];
    }
    [tableView reloadData];
    UIAlertController *restart = wq_alert_controller(@"Restart WQ Files",
        @"The new language is used the next time WQ Files starts.", UIAlertControllerStyleAlert);
    [restart addAction:wq_alert_action(@"Later", UIAlertActionStyleCancel, nil)];
    [restart addAction:wq_alert_action(@"Quit Now", UIAlertActionStyleDefault, ^(UIAlertAction *__unused a) {
        [NSUserDefaults.standardUserDefaults synchronize];
        exit(0);
    })];
    [self presentViewController:restart animated:YES completion:nil];
}

@end

@implementation WQRootViewController {
    // Kept between visits so Apps shows its last list right away instead of
    // scanning every container again.
    WQAppsViewController *_apps;
    BOOL _checkingAccess;
    // A failed startup check waits here until the start screen is in front
    // with nothing presented over it.
    NSArray<WQHealthCheck *> *_pendingHealthFailure;
    BOOL _healthRetryScheduled;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    if (!_apps.parentViewController) _apps = nil;
}

- (instancetype)init
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        self.title = WQLocalizedNullable(@"WQ Files");
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.tableView.tableFooterView = [self authorFooter];
    dispatch_async(wq_io(), ^{
        NSString *recovery = wq_recover_interrupted_restore();
        if (recovery) {
            dispatch_async(dispatch_get_main_queue(), ^{
                wq_alert(self, @"Restore recovery", recovery);
            });
        }
        (void)wq_app_group();   // resolves (and logs) the group off the main thread
    });
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (self.isViewLoaded && self.tableView.numberOfSections > 1) {
        [self.tableView reloadRowsAtIndexPaths:@[
            [NSIndexPath indexPathForRow:0 inSection:1],
            [NSIndexPath indexPathForRow:3 inSection:1],
        ] withRowAnimation:UITableViewRowAnimationNone];
    }
}

// The startup check (WQHealth), once the start screen is on screen: it runs
// in the background so nothing waits for it, and browsing stays possible. A
// failure covers the app with WQHealthViewController once the user is back
// on the start screen with nothing open over it (never over an action, a
// confirmation or a progress sheet); warnings are shown once per build.
- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self presentPendingHealthFailure];
    static BOOL checked;
    if (checked) return;
    checked = YES;
    _checkingAccess = YES;
    // A spinner in the bar while it runs: unlike a text row, it doesn't move
    // the list when it goes away.
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithFrame:CGRectZero];
    [spinner sizeToFit];
    [spinner startAnimating];
    spinner.accessibilityLabel = WQLocalized(@"Checking access…");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<WQHealthCheck *> *checks = wq_health_run(nil);
        dispatch_async(dispatch_get_main_queue(), ^{ [self healthCheckFinished:checks]; });
    });
}

- (void)healthCheckFinished:(NSArray<WQHealthCheck *> *)checks
{
    _checkingAccess = NO;
    self.navigationItem.rightBarButtonItem = nil;
    [self.tableView reloadData];
    WQHealthState worst = wq_health_worst(checks);
    if (worst == WQHealthWarning) { [self showHealthWarnings:checks]; return; }
    if (worst < WQHealthFailed) return;
    _pendingHealthFailure = checks;
    [self presentPendingHealthFailure];
}

// Idle: the start screen is the visible screen, the app is active and
// nothing (alert, sheet, scan window) is presented.
- (BOOL)healthFailureCanPresent
{
    UIViewController *host = self.navigationController ?: self;
    if (!self.view.window || host.presentedViewController) return NO;
    if (self.navigationController && self.navigationController.topViewController != self) return NO;
    return UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
}

- (void)presentPendingHealthFailure
{
    NSArray<WQHealthCheck *> *checks = _pendingHealthFailure;
    if (!checks) return;
    if (![self healthFailureCanPresent]) {
        static BOOL logged;
        if (!logged) {
            logged = YES;
            wq_log(@"health: check failed; the result is shown when the start screen is back in front");
        }
        if (_healthRetryScheduled) return;
        _healthRetryScheduled = YES;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_healthRetryScheduled = NO;
            [strongSelf presentPendingHealthFailure];
        });
        return;
    }
    _pendingHealthFailure = nil;
    WQHealthViewController *health = [[WQHealthViewController alloc] initWithChecks:checks];
    __weak typeof(self) weakSelf = self;
    health.onPassed = ^(NSArray<WQHealthCheck *> *passed) {
        [weakSelf.tableView reloadData];
        if (wq_health_worst(passed) == WQHealthWarning) [weakSelf showHealthWarnings:passed];
    };
    WQNavigationController *nav = [[WQNavigationController alloc] initWithRootViewController:health];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    nav.modalInPresentation = YES;
    [(self.navigationController ?: self) presentViewController:nav animated:YES completion:nil];
}

// Each set of warnings once per build, so the same notice doesn't repeat on
// every launch.
- (void)showHealthWarnings:(NSArray<WQHealthCheck *> *)checks
{
    NSMutableArray *lines = [NSMutableArray new];
    for (WQHealthCheck *c in checks)
        if (c.state == WQHealthWarning) [lines addObject:[NSString stringWithFormat:@"%@: %@", c.title, c.detail]];
    NSString *text = [lines componentsJoinedByString:@"\n\n"];
    NSString *key = [NSString stringWithFormat:@"%@|%@", NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"], text];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([[defaults stringForKey:@"WQHealthWarned"] isEqualToString:key]) return;
    [defaults setObject:key forKey:@"WQHealthWarned"];
    UIAlertController *alert = wq_alert_controller(@"Not everything works here", text, UIAlertControllerStyleAlert);
    [alert addAction:wq_alert_action(@"OK", UIAlertActionStyleCancel, nil)];
    UIViewController *host = self.navigationController ?: self;
    while (host.presentedViewController) host = host.presentedViewController;
    [host presentViewController:alert animated:YES completion:nil];
}

// "by kolbicz" with GitHub and X links, under the last section.
- (UIView *)authorFooter
{
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 128)];
    UILabel *by = [UILabel new];
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    by.text = WQLocalizedFormat(@"WQ Files %@ (%@) by kolbicz",
               info[@"CFBundleShortVersionString"] ?: @"?", info[@"CFBundleVersion"] ?: @"?");
    by.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    by.textColor = UIColor.secondaryLabelColor;

    UIButton *(^link)(NSString *, NSString *, NSString *) = ^UIButton *(NSString *title, NSString *symbol, NSString *url) {
        UIButtonConfiguration *cfg = [UIButtonConfiguration tintedButtonConfiguration];
        cfg.title = title;
        cfg.image = [UIImage systemImageNamed:symbol];
        cfg.imagePadding = 6;
        cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        cfg.buttonSize = UIButtonConfigurationSizeSmall;
        return [UIButton buttonWithConfiguration:cfg primaryAction:[UIAction actionWithHandler:^(UIAction *__unused a) {
            [UIApplication.sharedApplication openURL:[NSURL URLWithString:url] options:@{} completionHandler:nil];
        }]];
    };
    UIStackView *links = [[UIStackView alloc] initWithArrangedSubviews:@[
        link(@"GitHub", @"chevron.left.forwardslash.chevron.right", @"https://github.com/kolbicz"),
        link(@"@_kolbicz", @"at", @"https://x.com/_kolbicz"),
    ]];
    links.spacing = 12;

    UIButtonConfiguration *creditCfg = [UIButtonConfiguration plainButtonConfiguration];
    creditCfg.attributedTitle = [[NSAttributedString alloc] initWithString:WQLocalized(@"Sandbox escape: worse_query by @forcequitOS")
        attributes:@{NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]}];
    creditCfg.buttonSize = UIButtonConfigurationSizeSmall;
    UIButton *credit = [UIButton buttonWithConfiguration:creditCfg primaryAction:[UIAction actionWithHandler:^(UIAction *__unused a) {
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://x.com/forcequitOS"] options:@{} completionHandler:nil];
    }]];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[by, links, credit]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor],
        [stack.topAnchor constraintEqualToAnchor:footer.topAnchor constant:8],
    ]];
    return footer;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 0 ? 3 : 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return section == 0 ? WQLocalized(@"Backup & Restore") : WQLocalized(@"Settings");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0)
        return WQLocalized(@"Backups are stored in WQFiles/AppBackups and are also visible in the Files app.");
    return [NSString stringWithFormat:@"%@\n\n%@",
            WQLocalized(@"Backup Mode: choose whether backing up an app saves its IPA (including iTunesMetadata.plist, SC_Info and receipts) and data, only the IPA, or only app data."),
            WQLocalized(@"Allow Deleting: when off, nothing can be deleted and Clear Data is disabled.\n\nKeep Data Before Restore: restoring an app backup first backs up what's there now, so a failed restore can be undone. When off, that backup is deleted once the restore succeeded.")];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"r"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"r"];
    UIListContentConfiguration *c = cell.defaultContentConfiguration;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            UIListContentConfiguration *v = [UIListContentConfiguration valueCellConfiguration];
            v.text = WQLocalized(@"Backup Mode");
            v.image = [UIImage systemImageNamed:@"archivebox"];
            v.secondaryText = wq_app_backup_mode_title(wq_app_backup_mode());
            cell.contentConfiguration = v;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        if (indexPath.row == 3) {
            UIListContentConfiguration *v = [UIListContentConfiguration valueCellConfiguration];
            v.text = WQLocalized(@"Language");
            v.image = [UIImage systemImageNamed:@"globe"];
            v.secondaryText = wq_language_name(wq_chosen_language());
            cell.contentConfiguration = v;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        cell.accessoryType = UITableViewCellAccessoryNone;
        BOOL isKeep = indexPath.row == 2;
        c.text = WQLocalized(isKeep ? @"Keep Data Before Restore" : @"Allow Deleting");
        c.image = [UIImage systemImageNamed:isKeep ? @"clock.arrow.circlepath" : @"trash.slash"];
        UISwitch *toggle = [UISwitch new];
        toggle.on = isKeep ? wq_keep_before_restore() : wq_deleting_allowed();
        [toggle addAction:[UIAction actionWithHandler:^(UIAction *action) {
            BOOL on = ((UISwitch *)action.sender).isOn;
            if (isKeep) wq_set_keep_before_restore(on);
            else wq_set_deleting_allowed(on);
        }] forControlEvents:UIControlEventValueChanged];
        cell.contentConfiguration = c;
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSArray *tools = @[@[@"Apps", @"square.grid.3x3"],
                       @[@"App Backups", @"clock.arrow.circlepath"],
                       @[@"Log", @"doc.plaintext"]];
    c.text = WQLocalizedNullable(tools[(NSUInteger)indexPath.row][0]);
    c.image = [UIImage systemImageNamed:tools[(NSUInteger)indexPath.row][1]];
    cell.contentConfiguration = c;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            [self pickBackupModeFrom:[tableView cellForRowAtIndexPath:indexPath]];
        } else if (indexPath.row == 3) {
            [self.navigationController pushViewController:[WQLanguageViewController new] animated:YES];
        }
        return;
    }
    UIViewController *next = nil;
    if (indexPath.row == 0) {
        if (!_apps || _apps.parentViewController) _apps = [WQAppsViewController new];
        next = _apps;
    } else if (indexPath.row == 1) {
        [NSFileManager.defaultManager createDirectoryAtPath:wq_app_backup_root() withIntermediateDirectories:YES attributes:nil error:nil];
        next = [WQAppBackupsViewController new];
    } else {
        next = [WQLogViewController new];
    }
    [self.navigationController pushViewController:next animated:YES];
}

- (void)pickBackupModeFrom:(UIView *)source
{
    UIAlertController *sheet = wq_alert_controller(@"Backup Mode",
                                                   @"Choose what to save when backing up an app.",
                                                   UIAlertControllerStyleActionSheet);
    WQAppBackupMode current = wq_app_backup_mode();
    NSArray<NSNumber *> *modes = @[@(WQAppBackupModeIPAAndData), @(WQAppBackupModeIPAOnly), @(WQAppBackupModeDataOnly)];
    for (NSNumber *m in modes) {
        WQAppBackupMode mode = (WQAppBackupMode)m.integerValue;
        NSString *title = wq_app_backup_mode_title(mode);
        if (mode == current) title = [NSString stringWithFormat:@"✓ %@", title];
        [sheet addAction:wq_alert_action(WQVerbatim(title), UIAlertActionStyleDefault, ^(UIAlertAction *__unused a) {
            wq_set_app_backup_mode(mode);
            [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:1]]
                                  withRowAnimation:UITableViewRowAnimationNone];
        })];
    }
    [sheet addAction:wq_alert_action(@"Cancel", UIAlertActionStyleCancel, nil)];
    sheet.popoverPresentationController.sourceView = source ?: self.view;
    sheet.popoverPresentationController.sourceRect = (source ?: self.view).bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

#pragma mark - Startup check

// The startup check runs in the background while the start screen is up
// (WQRootViewController). When something essential fails, this screen covers
// the app with what failed; it only goes away through Try Again (when the
// check then passes) or Continue Anyway. (Declared before the start screen.)

@implementation WQHealthViewController {
    NSArray<WQHealthCheck *> *_checks;
    NSString *_stage;
    BOOL _running;
}

- (instancetype)initWithChecks:(NSArray<WQHealthCheck *> *)checks
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) _checks = [checks copy];
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = WQLocalizedNullable(@"WQ Files");
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.tableView.tableHeaderView = wq_device_header(self.view.bounds.size.width);
}

- (void)retry
{
    if (_running) return;
    _running = YES;
    _stage = WQLocalized(@"Checking access…");
    [self.tableView reloadData];
    wq_enumerate_invalidate();
    wq_display_names_reset_miss();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *checks = wq_health_run(^(NSString *text) {
            dispatch_async(dispatch_get_main_queue(), ^{ self->_stage = text; [self.tableView reloadData]; });
        });
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_running = NO;
            self->_checks = checks;
            if (wq_health_worst(checks) < WQHealthFailed) {
                void (^passed)(NSArray *) = self.onPassed;
                [self dismissViewControllerAnimated:YES completion:^{ if (passed) passed(checks); }];
                return;
            }
            [self.tableView reloadData];
        });
    });
}

// The buttons under the checks: 0 Try Again, 1 Log, 3 Signing Help (when
// the App Group is missing), 4 Reset Access Cache (when no folder opens),
// 2 Continue Anyway.
- (NSArray<NSNumber *> *)actions
{
    BOOL noGroup = _checks.count && _checks[0].state == WQHealthFailed;
    BOOL noAccess = NO;
    for (WQHealthCheck *c in _checks)
        if ([c.key isEqualToString:@"Sandbox access"] && c.state == WQHealthFailed) noAccess = YES;
    if (noGroup) return @[@0, @1, @3, @2];
    return noAccess ? @[@0, @4, @1, @2] : @[@0, @1, @2];
}

- (void)resetAccessCache
{
    UIAlertController *alert = wq_alert_controller(@"Reset Access Cache?",
        @"Another app that shares WQ Files' App Group (for example one signed with the same tool) can leave its cache folder in a state that blocks sandbox access. This puts it back; nothing is deleted.",
        UIAlertControllerStyleAlert);
    [alert addAction:wq_alert_action(@"Cancel", UIAlertActionStyleCancel, nil)];
    [alert addAction:wq_alert_action(@"Reset", UIAlertActionStyleDefault, ^(UIAlertAction *__unused a) {
        NSString *error = nil;
        if (wq_reset_access_cache(&error)) { [self retry]; return; }
        wq_alert(self, @"Reset failed", error ?: @"see Log");
    })];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return _running ? 1 : 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (_running) return 1;
    return section == 0 ? (NSInteger)_checks.count : (NSInteger)self.actions.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return !_running && section == 0 ? WQLocalized(@"WQ Files can't work properly here") : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (_running) return nil;
    if (section == 0)
        return WQLocalized(@"WQ Files stopped here instead of showing empty or wrong lists. A new iOS version can block its sandbox access; please send the Log with your device and iOS version.");
    return WQLocalized(@"Continue Anyway opens WQ Files as it is: lists may be empty or wrong, and nothing should be restored or deleted based on them.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"h"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"h"];
    UIListContentConfiguration *c = [UIListContentConfiguration subtitleCellConfiguration];
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (_running) {
        c.text = _stage;
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithFrame:CGRectZero];
        [spinner sizeToFit];
        [spinner startAnimating];
        cell.accessoryView = spinner;
    } else if (indexPath.section == 0) {
        WQHealthCheck *check = _checks[(NSUInteger)indexPath.row];
        NSArray *symbols = @[@"checkmark.circle.fill", @"minus.circle", @"exclamationmark.triangle.fill", @"xmark.octagon.fill"];
        NSArray *colors = @[UIColor.systemGreenColor, UIColor.secondaryLabelColor, UIColor.systemOrangeColor, UIColor.systemRedColor];
        c.text = check.title;
        c.secondaryText = check.detail;
        c.secondaryTextProperties.numberOfLines = 0;
        c.secondaryTextProperties.color = UIColor.secondaryLabelColor;
        c.image = [UIImage systemImageNamed:symbols[(NSUInteger)check.state]];
        c.imageProperties.tintColor = colors[(NSUInteger)check.state];
    } else {
        NSArray *titles = @[@"Try Again", @"Log", @"Continue Anyway", @"Signing Help", @"Reset Access Cache"];
        NSUInteger action = self.actions[(NSUInteger)indexPath.row].unsignedIntegerValue;
        c = [UIListContentConfiguration cellConfiguration];
        c.text = WQLocalized(titles[action]);
        c.textProperties.color = action == 2 ? UIColor.systemRedColor : self.view.tintColor;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    cell.contentConfiguration = c;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_running || indexPath.section != 1) return;
    switch (self.actions[(NSUInteger)indexPath.row].integerValue) {
        case 0:
            [self retry];
            break;
        case 1:
            [self.navigationController pushViewController:[WQLogViewController new] animated:YES];
            break;
        case 3:
            [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://github.com/kolbicz/WQFiles#signing-the-app-group"]
                                             options:@{} completionHandler:nil];
            break;
        case 4:
            [self resetAccessCache];
            break;
        default: {
            UIAlertController *alert = wq_alert_controller(@"Continue Anyway?",
                @"Lists may be empty or wrong. Don't restore, clean or delete anything based on them.", UIAlertControllerStyleAlert);
            [alert addAction:wq_alert_action(@"Cancel", UIAlertActionStyleCancel, nil)];
            [alert addAction:wq_alert_action(@"Continue", UIAlertActionStyleDestructive, ^(UIAlertAction *__unused a) {
                wq_log(@"health: the user continued despite failed checks");
                [self dismissViewControllerAnimated:YES completion:nil];
            })];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
}

@end

#pragma mark - App

@interface WQSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation WQSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options
{
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    window.rootViewController = [[WQNavigationController alloc] initWithRootViewController:[WQRootViewController new]];
    [window makeKeyAndVisible];
    self.window = window;
}

@end

#pragma mark - Full scan: confirmation and progress window

static UIViewController *wq_top_view_controller(void)
{
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.isKeyWindow) continue;
            UIViewController *top = window.rootViewController;
            while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
            return top;
        }
    }
    return nil;
}

static NSString *wq_duration_text(double seconds)
{
    if (seconds < 90) return WQLocalized(@"about a minute");
    if (seconds < 3600) return WQLocalizedFormat(@"about %.0f minutes", ceil(seconds / 60));
    return WQLocalizedFormat(@"about %.1f hours", seconds / 3600);
}

static NSString *wq_count_text(int64_t n)
{
    if (n >= 1000000) return WQLocalizedFormat(@"%.0f million", n / 1e6);
    return [NSNumberFormatter localizedStringFromNumber:@(n) numberStyle:NSNumberFormatterDecimalStyle];
}

@interface WQScanWindowController : UIViewController
- (void)updateDone:(int64_t)done total:(int64_t)total;
@end

@implementation WQScanWindowController {
    UIProgressView *_bar;
    UILabel *_status;
    CFAbsoluteTime _started;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    _started = CFAbsoluteTimeGetCurrent();
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]];
    icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:40 weight:UIImageSymbolWeightRegular];
    icon.tintColor = UIColor.tintColor;
    UILabel *title = [UILabel new];
    title.text = WQLocalizedNullable(@"Scanning all files");
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    title.adjustsFontForContentSizeCategory = YES;
    UILabel *text = [UILabel new];
    text.numberOfLines = 0;
    text.textAlignment = NSTextAlignmentCenter;
    text.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    text.textColor = UIColor.secondaryLabelColor;
    text.text = WQLocalizedNullable(@"iOS doesn't let WQ Files list these folders directly, so it checks every file on this device once. This is only slow the first time: later scans only check new files.\n\nKeep WQ Files open. Switching to another app or locking the screen pauses the scan.");
    _bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _status = [UILabel new];
    _status.font = [UIFont monospacedDigitSystemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize
                                                    weight:UIFontWeightRegular];
    _status.textAlignment = NSTextAlignmentCenter;
    _status.text = WQLocalizedNullable(@"Starting…");
    UIButton *hide = [UIButton buttonWithConfiguration:UIButtonConfiguration.borderedButtonConfiguration primaryAction:
        [UIAction actionWithTitle:WQLocalizedNullable(@"Hide") image:nil identifier:nil handler:^(UIAction *__unused a) {
            [self dismissViewControllerAnimated:YES completion:nil];
        }]];
    UIButtonConfiguration *stopConfig = UIButtonConfiguration.borderedButtonConfiguration;
    stopConfig.baseForegroundColor = UIColor.systemRedColor;
    UIButton *stop = [UIButton buttonWithConfiguration:stopConfig primaryAction:
        [UIAction actionWithTitle:WQLocalizedNullable(@"Stop Scan") image:nil identifier:nil handler:^(UIAction *__unused a) {
            wq_full_scan_stop();
            [self dismissViewControllerAnimated:YES completion:nil];
        }]];
    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[hide, stop]];
    buttons.spacing = 12;
    buttons.distribution = UIStackViewDistributionFillEqually;
    UILabel *note = [UILabel new];
    note.numberOfLines = 0;
    note.textAlignment = NSTextAlignmentCenter;
    note.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    note.textColor = UIColor.tertiaryLabelColor;
    note.text = WQLocalizedNullable(@"Hide keeps the scan running; the list fills in when it's done.");
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title, text, _bar, _status, buttons, note]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-24],
        [_bar.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [buttons.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [text.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [note.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    ]];
}

- (void)updateDone:(int64_t)done total:(int64_t)total
{
    if (total <= 0) return;
    float fraction = (float)((double)done / (double)total);
    [_bar setProgress:fraction animated:NO];
    double elapsed = CFAbsoluteTimeGetCurrent() - _started;
    NSString *left = @"";
    if (elapsed > 5 && done > 0 && done < total) {
        double remaining = elapsed * (double)(total - done) / (double)done;
        left = WQLocalizedFormat(@" · %@ left", wq_duration_text(remaining));
    }
    _status.text = [NSString stringWithFormat:@"%.0f%%%@", fraction * 100, left];
}

@end

static WQScanWindowController *gScanWindow;
static UIBackgroundTaskIdentifier gScanBackgroundTask;   // 0 is UIBackgroundTaskInvalid

// Called on a scan thread: asks on the main thread and waits for the answer.
static BOOL wq_confirm_full_scan(NSString *what, int64_t ids, double seconds)
{
    dispatch_semaphore_t answered = dispatch_semaphore_create(0);
    __block BOOL start = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = wq_top_view_controller();
        if (!top) { dispatch_semaphore_signal(answered); return; }   // not in front: don't scan unasked
        NSString *message = WQLocalizedFormat(@"To list %@, WQ Files has to check every file on this device once: %@ files, %@.\n\nThis is only needed the first time; later scans only check new files and take seconds.\n\nKeep WQ Files open while it scans.", what, wq_count_text(ids), wq_duration_text(seconds));
        UIAlertController *alert = wq_alert_controller(@"Scan all files?", message, UIAlertControllerStyleAlert);
        [alert addAction:wq_alert_action(@"Not Now", UIAlertActionStyleCancel, ^(UIAlertAction *__unused a) {
            dispatch_semaphore_signal(answered);
        })];
        [alert addAction:wq_alert_action(@"Start Scan", UIAlertActionStyleDefault, ^(UIAlertAction *__unused a) {
            start = YES;
            // A little extra time when the user switches away (iOS grants about 30 s).
            if (gScanBackgroundTask == UIBackgroundTaskInvalid) {
                gScanBackgroundTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"WQ full scan" expirationHandler:^{
                    [UIApplication.sharedApplication endBackgroundTask:gScanBackgroundTask];
                    gScanBackgroundTask = UIBackgroundTaskInvalid;
                }];
            }
            WQScanWindowController *window = [WQScanWindowController new];
            window.modalPresentationStyle = UIModalPresentationPageSheet;
            window.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                                                          UISheetPresentationControllerDetent.largeDetent];
            window.sheetPresentationController.prefersGrabberVisible = YES;
            gScanWindow = window;
            dispatch_semaphore_signal(answered);
            // After the alert has gone (presenting during its dismissal fails).
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIViewController *host = wq_top_view_controller();
                if (gScanWindow == window && host && host != window) [host presentViewController:window animated:YES completion:nil];
            });
        })];
        [top presentViewController:alert animated:YES completion:nil];
    });
    dispatch_semaphore_wait(answered, DISPATCH_TIME_FOREVER);
    return start;
}

static void wq_full_scan_progress(int64_t done, int64_t total, BOOL finished)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!finished) { [gScanWindow updateDone:done total:total]; return; }
        WQScanWindowController *window = gScanWindow;
        gScanWindow = nil;
        if (window.presentingViewController && !window.isBeingDismissed) [window dismissViewControllerAnimated:YES completion:nil];
        if (gScanBackgroundTask != UIBackgroundTaskInvalid) {
            [UIApplication.sharedApplication endBackgroundTask:gScanBackgroundTask];
            gScanBackgroundTask = UIBackgroundTaskInvalid;
        }
    });
}

@interface WQAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation WQAppDelegate

- (UISceneConfiguration *)application:(UIApplication *)application
configurationForConnectingSceneSession:(UISceneSession *)session
                              options:(UISceneConnectionOptions *)options
{
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];
    config.delegateClass = WQSceneDelegate.class;
    return config;
}

@end

int main(int argc, char *argv[])
{
    @autoreleasepool {
        // Container folders get their bundle id from the LaunchServices database
        // when the identifier attribute can't be read (iOS 27.2).
        wq_set_container_label_resolver(wq_bundle_id_for_container);
        wq_set_container_list_provider(wq_ls_container_paths);
        wq_set_full_scan_ui(wq_confirm_full_scan, wq_full_scan_progress);
        // Temporary share exports left by earlier runs.
        wq_share_sweep_stale_exports();
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(WQAppDelegate.class));
    }
}
