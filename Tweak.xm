#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>

static NSString * const kWALGGestureInstalledKey = @"com.darthplagueiswise.walg.gestureInstalled";
static NSString * const kWALGOverridesKey = @"com.darthplagueiswise.walg.overrides";

static NSArray<NSString *> *WALGHookKeys(void);
static NSArray<NSString *> *WALGDefaultsKeys(void);
static BOOL WALGOverrideEnabled(NSString *key);
static void WALGWriteExperimentDefaultsIfNeeded(void);
static void WALGEnableOverrideHelperIfNeeded(void);

@interface WALGMenuHandler : NSObject
+ (instancetype)sharedInstance;
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture;
@end

@implementation WALGMenuHandler

+ (instancetype)sharedInstance {
    static WALGMenuHandler *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }

    UIViewController *top = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *candidate in windowScene.windows) {
            if (candidate.isKeyWindow) {
                top = candidate.rootViewController;
                break;
            }
        }
        if (top) {
            break;
        }
    }

    while (top.presentedViewController) {
        top = top.presentedViewController;
    }

    if (!top) {
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"LiquidGlass Experiments" message:@"Tap a toggle to override the original method result." preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSString *key in WALGHookKeys()) {
        NSDictionary *stored = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kWALGOverridesKey];
        BOOL enabled = [stored[key] boolValue];
        NSString *title = [NSString stringWithFormat:@"%@: %@", key, enabled ? @"ON" : @"OFF"];
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NSMutableDictionary *next = stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
            next[key] = @(!enabled);
            [[NSUserDefaults standardUserDefaults] setObject:next forKey:kWALGOverridesKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
            WALGWriteExperimentDefaultsIfNeeded();
            WALGEnableOverrideHelperIfNeeded();
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Reset All" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kWALGOverridesKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = gesture.view;
        alert.popoverPresentationController.sourceRect = gesture.view.bounds;
    }

    [top presentViewController:alert animated:YES completion:nil];
}

@end

static NSArray<NSString *> *WALGHookKeys(void) {
    static NSArray<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = @[
            @"WDSLiquidGlass.hasLiquidGlassLaunched",
            @"WDSLiquidGlass.isM0Enabled",
            @"WDSLiquidGlass.isM1Enabled",
            @"WDSLiquidGlass.isM1_5Enabled",
            @"WDSLiquidGlass.isM1_5ContextMenuEnabled",
            @"WDSLiquidGlass.isLargerComposerEnabled",
            @"WDSLiquidGlass.isNativeSidebarEnabled",
            @"WDSLiquidGlass.shouldUseNativeSwipeActions",
            @"WAABProperties.ios_liquid_glass_enabled",
            @"WAABProperties.ios_liquid_glass_launched",
            @"WAABProperties.ios_liquid_glass_m1",
            @"WAABProperties.ios_liquid_glass_m_1_5",
            @"WAABProperties.ios_liquid_glass_m_1_5_context_menu",
            @"WAABProperties.ios_liquid_glass_media_m0",
            @"WAABProperties.ios_liquid_glass_larger_composer",
            @"WAABProperties.ios_liquid_glass_media_editor_enabled",
            @"WAABProperties.ios_liquid_glass_calling_improvement_enabled",
            @"WAABProperties.ios_liquid_glass_workaround_attachment_tray",
            @"WAABProperties.ios_liquid_glass_reduce_transparency",
            @"WAABProperties.ios_liquid_glass_fixes_for_older_ios",
            @"WAABProperties.status_viewer_redesign_enabled",
            @"WALiquidGlassOverrideMethodUserDefaults.isEnabled",
            @"IGLiquidGlassExperimentHelper.isEnabled",
            @"Bootstrap.WriteDefaults",
            @"Bootstrap.EnableOverrideHelper"
        ];
    });
    return keys;
}

static NSArray<NSString *> *WALGDefaultsKeys(void) {
    static NSArray<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = @[
            @"liquid_glass_override_enabled",
            @"WALiquidGlassOverrideEnabled",
            @"ios_liquid_glass_enabled",
            @"ios_liquid_glass_launched",
            @"ios_liquid_glass_m1",
            @"ios_liquid_glass_m_1_5",
            @"ios_liquid_glass_m_1_5_context_menu",
            @"ios_liquid_glass_media_m0",
            @"ios_liquid_glass_larger_composer",
            @"ios_liquid_glass_media_editor_enabled",
            @"ios_liquid_glass_calling_improvement_enabled",
            @"ios_liquid_glass_workaround_attachment_tray",
            @"ios_liquid_glass_reduce_transparency",
            @"ios_liquid_glass_fixes_for_older_ios",
            @"status_viewer_redesign_enabled"
        ];
    });
    return keys;
}

static BOOL WALGOverrideEnabled(NSString *key) {
    NSDictionary *stored = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kWALGOverridesKey];
    id value = stored[key];
    return value ? [value boolValue] : NO;
}

static void WALGWriteExperimentDefaultsIfNeeded(void) {
    if (!WALGOverrideEnabled(@"Bootstrap.WriteDefaults")) {
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (NSString *key in WALGDefaultsKeys()) {
        [defaults setBool:YES forKey:key];
    }
    [defaults synchronize];
}

static void WALGEnableOverrideHelperIfNeeded(void) {
    if (!WALGOverrideEnabled(@"Bootstrap.EnableOverrideHelper")) {
        return;
    }

    Class overrideClass = NSClassFromString(@"WALiquidGlassOverrideMethodUserDefaults");
    if (!overrideClass) {
        return;
    }

    SEL sharedInstanceSelector = NSSelectorFromString(@"sharedInstance");
    if (![object_getClass(overrideClass) respondsToSelector:sharedInstanceSelector]) {
        return;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id sharedInstance = [overrideClass performSelector:sharedInstanceSelector];
#pragma clang diagnostic pop

    if (!sharedInstance) {
        return;
    }

    SEL setEnabledSelector = NSSelectorFromString(@"setEnabled:");
    if (![sharedInstance respondsToSelector:setEnabledSelector]) {
        return;
    }

    NSMethodSignature *signature = [sharedInstance methodSignatureForSelector:setEnabledSelector];
    if (!signature) {
        return;
    }

    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    BOOL enabled = YES;
    [invocation setSelector:setEnabledSelector];
    [invocation setTarget:sharedInstance];
    [invocation setArgument:&enabled atIndex:2];
    [invocation invoke];
}

%hook WDSSettingsListItemTableCell

- (void)didMoveToWindow {
    %orig;

    NSNumber *installed = objc_getAssociatedObject(self, (__bridge const void *)(kWALGGestureInstalledKey));
    if ([installed boolValue]) {
        return;
    }

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:[WALGMenuHandler sharedInstance] action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.8;
    [self addGestureRecognizer:longPress];
    objc_setAssociatedObject(self, (__bridge const void *)(kWALGGestureInstalledKey), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%end

%hook WDSLiquidGlass
+ (BOOL)hasLiquidGlassLaunched { return WALGOverrideEnabled(@"WDSLiquidGlass.hasLiquidGlassLaunched") ? YES : %orig; }
+ (BOOL)isM0Enabled { return WALGOverrideEnabled(@"WDSLiquidGlass.isM0Enabled") ? YES : %orig; }
+ (BOOL)isM1Enabled { return WALGOverrideEnabled(@"WDSLiquidGlass.isM1Enabled") ? YES : %orig; }
+ (BOOL)isM1_5Enabled { return WALGOverrideEnabled(@"WDSLiquidGlass.isM1_5Enabled") ? YES : %orig; }
+ (BOOL)isM1_5ContextMenuEnabled { return WALGOverrideEnabled(@"WDSLiquidGlass.isM1_5ContextMenuEnabled") ? YES : %orig; }
+ (BOOL)isLargerComposerEnabled { return WALGOverrideEnabled(@"WDSLiquidGlass.isLargerComposerEnabled") ? YES : %orig; }
+ (BOOL)isNativeSidebarEnabled { return WALGOverrideEnabled(@"WDSLiquidGlass.isNativeSidebarEnabled") ? YES : %orig; }
+ (BOOL)shouldUseNativeSwipeActions { return WALGOverrideEnabled(@"WDSLiquidGlass.shouldUseNativeSwipeActions") ? YES : %orig; }
%end

%hook WAABProperties
- (BOOL)ios_liquid_glass_enabled { return WALGOverrideEnabled(@"WAABProperties.ios_liquid_glass_enabled") ? YES : %orig; }
- (BOOL)ios_liquid_glass_launched { return WALGOverrideEnabled(@"WAABProperties.ios_liquid_glass_launched") ? YES : %orig; }
- (BOOL)ios_liquid_glass_m1 { return WALGOverrideEnabled(@"WAABProperties.ios_liquid_glass_m1") ? YES : %orig; }
- (BOOL)ios_liquid_glass_m_1_5 { return WALGOverrideEnabled(@"WAABProperties.ios_liquid_glass_m_1_5") ? YES : %orig; }
- (BOOL)ios_liquid_glass_m_1_5_context_menu { return WALGOverrideEnabled(@"WAABProperties.ios_liquid_glass_m_1_5_context_menu") ? YES : %orig; }
- (BOOL)ios_liquid_glass_media_m0 { return WALGOverrideEnabled(@"WAABProperties.ios_liquid_glass_media_m0") ? YES : %orig; }
- (BOOL)ios_liquid_glass_larger_composer { return WALGOverrideEnabled(@"WAABProperties.ios_liquid_glass_larger_composer") ? YES : %orig; }
- (BOOL)ios_liquid_glass_media_editor_enabled { return WALGOverrideEnabled(@"WAABProperties.ios_liquid_glass_media_editor_enabled") ? YES : %orig; }
- (BOOL)ios_liquid_glass_calling_improvement_enabled { return WALGOverrideEnabled(@"WAABProperties.ios_liquid_glass_calling_improvement_enabled") ? YES : %orig; }
- (BOOL)ios_liquid_glass_workaround_attachment_tray { return WALGOverrideEnabled(@"WAABProperties.ios_liquid_glass_workaround_attachment_tray") ? YES : %orig; }
- (BOOL)ios_liquid_glass_reduce_transparency { return WALGOverrideEnabled(@"WAABProperties.ios_liquid_glass_reduce_transparency") ? YES : %orig; }
- (BOOL)ios_liquid_glass_fixes_for_older_ios { return WALGOverrideEnabled(@"WAABProperties.ios_liquid_glass_fixes_for_older_ios") ? YES : %orig; }
- (BOOL)status_viewer_redesign_enabled { return WALGOverrideEnabled(@"WAABProperties.status_viewer_redesign_enabled") ? YES : %orig; }
%end

%hook WALiquidGlassOverrideMethodUserDefaults
- (BOOL)isEnabled { return WALGOverrideEnabled(@"WALiquidGlassOverrideMethodUserDefaults.isEnabled") ? YES : %orig; }
%end

%hook IGLiquidGlassExperimentHelper
+ (BOOL)isEnabled { return WALGOverrideEnabled(@"IGLiquidGlassExperimentHelper.isEnabled") ? YES : %orig; }
%end

%ctor {
    @autoreleasepool {
        [WALGMenuHandler sharedInstance];
        WALGWriteExperimentDefaultsIfNeeded();
        %init;
        WALGEnableOverrideHelperIfNeeded();
    }
}
