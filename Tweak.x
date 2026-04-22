/**
 * InstagramTweaks.dylib v5.17
 *
 * Baseado na arquitetura real do Tweak.x enviado pelo usuário:
 *  - NSUserDefaults como fonte de verdade
 *  - swizzle limpo via method_setImplementation para ObjC/Swift
 *  - hooks C via MSHookFunction sob demanda
 *  - menu visual por long-press no item “Help and Feedback”
 *  - flags customizadas nome -> BOOL
 *
 * Adaptado para SharedModules / WDSLiquidGlass / WA LiquidGlass.
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <substrate.h>

#define TWEAK_VERSION @"5.17.0"

// ── Chaves NSUserDefaults ─────────────────────────────────────────────────────
#define kWAT_WAIsLiquidGlassEnabled          @"wat_wa_is_liquid_glass_enabled"
#define kWAT_METAIsLiquidGlassEnabled        @"wat_meta_is_liquid_glass_enabled"
#define kWAT_WAOverrideLiquidGlassDisabled   @"wat_wa_override_liquid_glass_disabled"
#define kWAT_WAApplyLiquidGlassOverrideNoop  @"wat_wa_apply_liquid_glass_override_noop"
#define kWAT_WDSLiquidGlassHooks             @"wat_wds_liquid_glass_hooks"
#define kWAT_UseLiquidGlassDesign            @"wat_use_liquid_glass_design"
#define kWAT_UseLiquidGlassStyle             @"wat_use_liquid_glass_style"
#define kWAT_ShouldUseLiquidGlassConfig      @"wat_should_use_liquid_glass_config"
#define kWAT_NewLiquidGlassLayout            @"wat_new_liquid_glass_layout"
#define kWAT_HasLiquidGlassLaunched          @"wat_has_liquid_glass_launched"
#define kWAT_ChatTopBarM2                    @"wat_liquid_glass_chat_topbar_m2"
#define kWAT_AttachmentTray                  @"wat_liquid_glass_attachment_tray"
#define kWAT_CustomFlags                     @"wat_custom_flags"

// ── Helpers de Preferências ───────────────────────────────────────────────────
static BOOL WATGetBool(NSString *key, BOOL defaultVal) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:key] == nil) return defaultVal;
    return [ud boolForKey:key];
}

static void WATSetBool(NSString *key, BOOL value) {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static NSMutableDictionary *g_customFlags = nil;

static void WATLoadCustomFlags(void) {
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kWAT_CustomFlags];
    g_customFlags = saved ? [saved mutableCopy] : [NSMutableDictionary dictionary];
}

static void WATSaveCustomFlags(void) {
    [[NSUserDefaults standardUserDefaults] setObject:[g_customFlags copy] forKey:kWAT_CustomFlags];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static void WATRegisterDefaults(void) {
    NSDictionary *defs = @{
        kWAT_WAIsLiquidGlassEnabled: @YES,
        kWAT_METAIsLiquidGlassEnabled: @YES,
        kWAT_WAOverrideLiquidGlassDisabled: @YES,
        kWAT_WAApplyLiquidGlassOverrideNoop: @NO,
        kWAT_WDSLiquidGlassHooks: @YES,
        kWAT_UseLiquidGlassDesign: @YES,
        kWAT_UseLiquidGlassStyle: @YES,
        kWAT_ShouldUseLiquidGlassConfig: @YES,
        kWAT_NewLiquidGlassLayout: @YES,
        kWAT_HasLiquidGlassLaunched: @YES,
        kWAT_ChatTopBarM2: @YES,
        kWAT_AttachmentTray: @YES,
        kWAT_CustomFlags: @{}
    };
    [[NSUserDefaults standardUserDefaults] registerDefaults:defs];
}

// ── Helpers de Runtime ────────────────────────────────────────────────────────
static UIViewController *WATTopViewController(void) {
    UIWindow *key = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (w.isKeyWindow) { key = w; break; }
    }
    UIViewController *top = key.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if ([top isKindOfClass:[UINavigationController class]])
        top = ((UINavigationController *)top).visibleViewController ?: top;
    return top;
}

static NSString *WATCellVisibleText(UITableViewCell *cell) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (cell.textLabel.text.length) [parts addObject:cell.textLabel.text];
    if (cell.detailTextLabel.text.length) [parts addObject:cell.detailTextLabel.text];
    for (UIView *sub in cell.contentView.subviews) {
        if ([sub isKindOfClass:[UILabel class]]) {
            NSString *t = ((UILabel *)sub).text;
            if (t.length && ![parts containsObject:t]) [parts addObject:t];
        }
    }
    return [[parts componentsJoinedByString:@" "] lowercaseString];
}

static BOOL WATIsHelpAndFeedbackCell(UITableViewCell *cell) {
    NSString *text = WATCellVisibleText(cell);
    if (!text.length) return NO;
    NSArray *needles = @[@"help and feedback", @"help & feedback", @"ajuda e feedback", @"ajuda e comentario", @"suporte", @"help", @"feedback"];
    BOOL hasHelp = NO, hasFeedback = NO;
    for (NSString *n in needles) {
        if ([text containsString:n]) {
            if ([n containsString:@"help"] || [n containsString:@"ajuda"] || [n containsString:@"suporte"]) hasHelp = YES;
            if ([n containsString:@"feedback"] || [n containsString:@"comentario"]) hasFeedback = YES;
        }
    }
    return (hasHelp && hasFeedback) || [text containsString:@"help and feedback"] || [text containsString:@"ajuda e feedback"];
}

// ── Swizzle Helpers ───────────────────────────────────────────────────────────
static void WATSwizzleInstance(Class cls, SEL sel, IMP newImp, IMP *outOrig) {
    if (!cls || !sel || !newImp) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    if (outOrig) *outOrig = method_getImplementation(m);
    method_setImplementation(m, newImp);
}

static void WATSwizzleClass(Class cls, SEL sel, IMP newImp, IMP *outOrig) {
    if (!cls || !sel || !newImp) return;
    Class meta = object_getClass((id)cls);
    Method m = class_getClassMethod(cls, sel);
    if (!m || !meta) return;
    if (outOrig) *outOrig = method_getImplementation(m);
    method_setImplementation(class_getInstanceMethod(meta, sel), newImp);
}

static BOOL WATMaybeReturnForSelector(SEL _cmd, BOOL *handled, BOOL origDefault) {
    NSString *name = NSStringFromSelector(_cmd).lowercaseString;
    *handled = YES;
    if ([name containsString:@"useliquidglassdesign"]) return WATGetBool(kWAT_UseLiquidGlassDesign, YES);
    if ([name containsString:@"useliquidglassstyle"]) return WATGetBool(kWAT_UseLiquidGlassStyle, YES);
    if ([name containsString:@"shoulduseliquidglassconfiguration"]) return WATGetBool(kWAT_ShouldUseLiquidGlassConfig, YES);
    if ([name containsString:@"isnewliquidglasslayoutenabled"]) return WATGetBool(kWAT_NewLiquidGlassLayout, YES);
    if ([name containsString:@"hasliquidglasslaunched"]) return WATGetBool(kWAT_HasLiquidGlassLaunched, YES);
    if ([name containsString:@"liquidglasschattopbarm2enabled"]) return WATGetBool(kWAT_ChatTopBarM2, YES);
    if ([name containsString:@"liquidglassworkaroundattachmenttray"]) return WATGetBool(kWAT_AttachmentTray, YES);
    if ([name containsString:@"iscustomtoolbardisabledforliquidglass"]) return NO;
    NSString *raw = NSStringFromSelector(_cmd);
    NSNumber *flag = g_customFlags[raw];
    if (flag) return [flag boolValue];
    *handled = NO;
    return origDefault;
}

// ── Hooks C ───────────────────────────────────────────────────────────────────
static BOOL (*orig_WAIsLiquidGlassEnabled)(void) = NULL;
static BOOL hook_WAIsLiquidGlassEnabled(void) {
    return WATGetBool(kWAT_WAIsLiquidGlassEnabled, YES);
}

static BOOL (*orig_METAIsLiquidGlassEnabled)(void) = NULL;
static BOOL hook_METAIsLiquidGlassEnabled(void) {
    return WATGetBool(kWAT_METAIsLiquidGlassEnabled, YES);
}

static BOOL (*orig_WAOverrideLiquidGlassEnabled)(void) = NULL;
static BOOL hook_WAOverrideLiquidGlassEnabled(void) {
    if (WATGetBool(kWAT_WAOverrideLiquidGlassDisabled, YES)) return NO;
    return orig_WAOverrideLiquidGlassEnabled ? orig_WAOverrideLiquidGlassEnabled() : NO;
}

static void (*orig_WAApplyLiquidGlassOverride)(void) = NULL;
static void hook_WAApplyLiquidGlassOverride(void) {
    if (WATGetBool(kWAT_WAApplyLiquidGlassOverrideNoop, NO)) return;
    if (orig_WAApplyLiquidGlassOverride) orig_WAApplyLiquidGlassOverride();
}

static void WATHookSymbol(const char *sym, void *replacement, void **orig) {
    void *addr = dlsym(RTLD_DEFAULT, sym);
    if (!addr) return;
    MSHookFunction(addr, replacement, orig);
}

// ── WDSLiquidGlass selectors ─────────────────────────────────────────────────
static IMP orig_WDS_isEnabled = NULL;
static BOOL hooked_WDS_isEnabled(id self, SEL _cmd) {
    BOOL handled = NO;
    BOOL forced = WATMaybeReturnForSelector(_cmd, &handled, YES);
    if (handled) return forced;
    return orig_WDS_isEnabled ? ((BOOL(*)(id,SEL))orig_WDS_isEnabled)(self,_cmd) : YES;
}

static IMP orig_WDS_genericBool = NULL;
static BOOL hooked_WDS_genericBool(id self, SEL _cmd) {
    BOOL handled = NO;
    BOOL forced = WATMaybeReturnForSelector(_cmd, &handled, YES);
    if (handled) return forced;
    return orig_WDS_genericBool ? ((BOOL(*)(id,SEL))orig_WDS_genericBool)(self,_cmd) : YES;
}

static IMP orig_WDS_setBool = NULL;
static void hooked_WDS_setBool(id self, SEL _cmd, BOOL value) {
    NSString *name = NSStringFromSelector(_cmd).lowercaseString;
    if ([name containsString:@"setliquidglasschattopbarm2enabled"]) value = WATGetBool(kWAT_ChatTopBarM2, YES);
    else if ([name containsString:@"setliquidglassworkaroundattachmenttray"]) value = WATGetBool(kWAT_AttachmentTray, YES);
    if (orig_WDS_setBool) ((void(*)(id,SEL,BOOL))orig_WDS_setBool)(self,_cmd,value);
}

static void WATInstallWDSHooks(void) {
    if (!WATGetBool(kWAT_WDSLiquidGlassHooks, YES)) return;
    Class cls = objc_getClass("WDSLiquidGlass");
    if (!cls) return;

    NSArray<NSString *> *classBools = @[
        @"isEnabled",
        @"useLiquidGlassDesign",
        @"useLiquidGlassStyle",
        @"shouldUseLiquidGlassConfiguration",
        @"isNewLiquidGlassLayoutEnabled",
        @"hasLiquidGlassLaunched",
        @"liquidGlassChatTopBarM2Enabled",
        @"liquidGlassWorkaroundAttachmentTray",
        @"isCustomToolbarDisabledForLiquidGlass",
    ];
    for (NSString *selName in classBools) {
        SEL sel = NSSelectorFromString(selName);
        Method m = class_getClassMethod(cls, sel);
        if (!m) continue;
        IMP *slot = [selName isEqualToString:@"isEnabled"] ? &orig_WDS_isEnabled : &orig_WDS_genericBool;
        WATSwizzleClass(cls, sel, (IMP)([selName isEqualToString:@"isEnabled"] ? hooked_WDS_isEnabled : hooked_WDS_genericBool), slot);
    }

    NSArray<NSString *> *instanceBools = @[
        @"useLiquidGlassDesign",
        @"useLiquidGlassStyle",
        @"shouldUseLiquidGlassConfiguration",
        @"isNewLiquidGlassLayoutEnabled",
        @"hasLiquidGlassLaunched",
        @"liquidGlassChatTopBarM2Enabled",
        @"liquidGlassWorkaroundAttachmentTray",
        @"isCustomToolbarDisabledForLiquidGlass",
    ];
    for (NSString *selName in instanceBools) {
        SEL sel = NSSelectorFromString(selName);
        if (class_getInstanceMethod(cls, sel)) WATSwizzleInstance(cls, sel, (IMP)hooked_WDS_genericBool, &orig_WDS_genericBool);
    }

    NSArray<NSString *> *setters = @[
        @"setLiquidGlassChatTopBarM2Enabled:",
        @"setLiquidGlassWorkaroundAttachmentTray:",
    ];
    for (NSString *selName in setters) {
        SEL sel = NSSelectorFromString(selName);
        if (class_getInstanceMethod(cls, sel)) WATSwizzleInstance(cls, sel, (IMP)hooked_WDS_setBool, &orig_WDS_setBool);
    }
}

// ── Menu ──────────────────────────────────────────────────────────────────────
@interface WATMenu : NSObject
+ (void)showFromVC:(UIViewController *)vc;
+ (void)showCustomFlagsFromVC:(UIViewController *)vc;
@end

@implementation WATMenu
+ (void)showFromVC:(UIViewController *)vc {
    NSString *title = [NSString stringWithFormat:@"SharedModules LiquidGlass %@", TWEAK_VERSION];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    void (^addToggle)(NSString *, NSString *) = ^(NSString *label, NSString *key) {
        BOOL on = WATGetBool(key, YES);
        NSString *t = [NSString stringWithFormat:@"%@ %@", on ? @"✓" : @"○", label];
        [alert addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            WATSetBool(key, !on);
            [self showFromVC:vc];
        }]];
    };

    addToggle(@"WAIsLiquidGlassEnabled",         kWAT_WAIsLiquidGlassEnabled);
    addToggle(@"METAIsLiquidGlassEnabled",       kWAT_METAIsLiquidGlassEnabled);
    addToggle(@"Disable WAOverrideLiquidGlass",  kWAT_WAOverrideLiquidGlassDisabled);
    addToggle(@"NO-OP WAApplyLiquidGlassOverride", kWAT_WAApplyLiquidGlassOverrideNoop);
    addToggle(@"Hook WDSLiquidGlass selectors",  kWAT_WDSLiquidGlassHooks);
    addToggle(@"useLiquidGlassDesign",           kWAT_UseLiquidGlassDesign);
    addToggle(@"useLiquidGlassStyle",            kWAT_UseLiquidGlassStyle);
    addToggle(@"shouldUseLiquidGlassConfiguration", kWAT_ShouldUseLiquidGlassConfig);
    addToggle(@"isNewLiquidGlassLayoutEnabled",  kWAT_NewLiquidGlassLayout);
    addToggle(@"hasLiquidGlassLaunched",         kWAT_HasLiquidGlassLaunched);
    addToggle(@"liquidGlassChatTopBarM2Enabled", kWAT_ChatTopBarM2);
    addToggle(@"liquidGlassWorkaroundAttachmentTray", kWAT_AttachmentTray);

    [alert addAction:[UIAlertAction actionWithTitle:@"🏷 Custom Flags" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [self showCustomFlagsFromVC:vc];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"🔄 Restart App" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
        exit(0);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Fechar" style:UIAlertActionStyleCancel handler:nil]];

    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = vc.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(vc.view.bounds), CGRectGetMidY(vc.view.bounds), 0, 0);
        alert.popoverPresentationController.permittedArrowDirections = 0;
    }
    [vc presentViewController:alert animated:YES completion:nil];
}

+ (void)showCustomFlagsFromVC:(UIViewController *)vc {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Custom Flags" message:@"Selector -> BOOL" preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *sortedKeys = [[g_customFlags allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSUInteger shown = 0;
    for (NSString *key in sortedKeys) {
        if (shown >= 20) break;
        BOOL on = [g_customFlags[key] boolValue];
        NSString *t = [NSString stringWithFormat:@"%@ %@", on ? @"✓" : @"○", key];
        [alert addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            g_customFlags[key] = @(!on);
            WATSaveCustomFlags();
            [self showCustomFlagsFromVC:vc];
        }]];
        shown++;
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"＋ Add selector flag" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UIAlertController *input = [UIAlertController alertControllerWithTitle:@"New selector flag" message:@"Ex: useLiquidGlassDesign" preferredStyle:UIAlertControllerStyleAlert];
        [input addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"useLiquidGlassDesign"; }];
        [input addAction:[UIAlertAction actionWithTitle:@"Adicionar (ON)" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a2) {
            NSString *name = input.textFields.firstObject.text;
            if (name.length > 0) { g_customFlags[name] = @YES; WATSaveCustomFlags(); }
            [self showCustomFlagsFromVC:vc];
        }]];
        [input addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
        [vc presentViewController:input animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Voltar" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *a) {
        [self showFromVC:vc];
    }]];
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = vc.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(vc.view.bounds), CGRectGetMidY(vc.view.bounds), 0, 0);
        alert.popoverPresentationController.permittedArrowDirections = 0;
    }
    [vc presentViewController:alert animated:YES completion:nil];
}
@end

// ── Long press no item “Help and Feedback” ───────────────────────────────────
static IMP orig_tableView_layoutSubviews = NULL;
static char kWATLongPressAttachedKey;

@interface UITableViewCell (WATMenu)
- (void)wat_handleHelpFeedbackLongPress:(UILongPressGestureRecognizer *)lp;
@end

@implementation UITableViewCell (WATMenu)
- (void)wat_handleHelpFeedbackLongPress:(UILongPressGestureRecognizer *)lp {
    if (lp.state != UIGestureRecognizerStateBegan) return;
    UIViewController *top = WATTopViewController();
    if (top) [WATMenu showFromVC:top];
}
@end

static void hooked_tableView_layoutSubviews(UITableView *self, SEL _cmd) {
    if (orig_tableView_layoutSubviews) ((void(*)(id,SEL))orig_tableView_layoutSubviews)(self,_cmd);
    for (UITableViewCell *cell in self.visibleCells) {
        if (![cell isKindOfClass:[UITableViewCell class]]) continue;
        if (!WATIsHelpAndFeedbackCell(cell)) continue;
        NSNumber *attached = objc_getAssociatedObject(cell, &kWATLongPressAttachedKey);
        if (attached.boolValue) continue;
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:cell action:@selector(wat_handleHelpFeedbackLongPress:)];
        lp.minimumPressDuration = 0.6;
        [cell.contentView addGestureRecognizer:lp];
        cell.contentView.userInteractionEnabled = YES;
        objc_setAssociatedObject(cell, &kWATLongPressAttachedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// ── Constructor ───────────────────────────────────────────────────────────────
__attribute__((constructor(101)))
static void WATInit(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        WATRegisterDefaults();
        WATLoadCustomFlags();

        // Hooks C centrais
        WATHookSymbol("WAIsLiquidGlassEnabled", (void *)hook_WAIsLiquidGlassEnabled, (void **)&orig_WAIsLiquidGlassEnabled);
        WATHookSymbol("METAIsLiquidGlassEnabled", (void *)hook_METAIsLiquidGlassEnabled, (void **)&orig_METAIsLiquidGlassEnabled);
        WATHookSymbol("WAOverrideLiquidGlassEnabled", (void *)hook_WAOverrideLiquidGlassEnabled, (void **)&orig_WAOverrideLiquidGlassEnabled);
        WATHookSymbol("WAApplyLiquidGlassOverride", (void *)hook_WAApplyLiquidGlassOverride, (void **)&orig_WAApplyLiquidGlassOverride);

        // Hooks ObjC/Swift-like
        WATInstallWDSHooks();

        // Long press dentro do menu “Help and Feedback”
        WATSwizzleInstance([UITableView class], @selector(layoutSubviews), (IMP)hooked_tableView_layoutSubviews, &orig_tableView_layoutSubviews);
    });
}
