// iOS application entry point for SatDump.

#import <UIKit/UIKit.h>
#import "AppViewController.h"

#include "main_ui.h"
#include "core/config.h"

// ----------------------------------------------------------------------------
// Application delegate
// ----------------------------------------------------------------------------

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = [[AppViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Persist user settings, mirroring the Android SAVE_STATE handling.
    if (satdump::recorder_app)
        satdump::recorder_app->save_settings();
    if (satdump::viewer_app)
        satdump::viewer_app->save_settings();
    satdump::config::saveUserConfig();
}

@end

// ----------------------------------------------------------------------------
// main
// ----------------------------------------------------------------------------

int main(int argc, char *argv[])
{
    @autoreleasepool
    {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
