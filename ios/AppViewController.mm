#import "AppViewController.h"
#import "backend.h"
#import "imgui_backends/imgui_metal_renderer.h"

#include <float.h>
#include <unistd.h>

#include "imgui/imgui.h"
#include "logger.h"
#include "init.h"
#include "main_ui.h"
#include "core/backend.h"
#include "core/style.h"
#include "core/config.h"
#include "loader/loader.h"
#include "common/tracking/tle.h"

void restore_security_scoped_bookmarks();

// ----------------------------------------------------------------------------
// Hidden UITextField subclass that drives the on-screen keyboard.
//
// We intentionally keep the backing field empty (shouldChangeCharactersInRange
// returns NO). On iOS that means Backspace is delivered via -deleteBackward,
// not via shouldChangeCharactersInRange with an empty replacement string -
// the empty-string callback fires unreliably when the field has no content.
// Overriding -deleteBackward gives us a consistent Backspace path.
// ----------------------------------------------------------------------------
@interface SatDumpKeyboardField : UITextField
@end

@implementation SatDumpKeyboardField
- (void)deleteBackward
{
    ImGuiIO &io = ImGui::GetIO();
    io.AddKeyEvent(ImGuiKey_Backspace, true);
    io.AddKeyEvent(ImGuiKey_Backspace, false);
    [super deleteBackward];
}
@end

@implementation AppViewController
{
    BOOL _satdumpReady;
    SatDumpKeyboardField *_keyboardField; // hidden field driving the on-screen keyboard
}

// ----------------------------------------------------------------------------
// View setup
// ----------------------------------------------------------------------------

- (void)loadView
{
    self.view = [[MTKView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _satdumpReady = NO;

    // --- Metal device / command queue ---
    g_metalDevice = MTLCreateSystemDefaultDevice();
    g_metalCommandQueue = [g_metalDevice newCommandQueue];

    // --- Metal view ---
    MTKView *mtkView = (MTKView *)self.view;
    mtkView.device = g_metalDevice;
    mtkView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    mtkView.depthStencilPixelFormat = MTLPixelFormatInvalid;
    mtkView.delegate = self;
    mtkView.enableSetNeedsDisplay = NO;
    mtkView.paused = YES; // no automatic drawing until init completed
    g_metalView = mtkView;

    [self setupKeyboardField];

    // --- Working directory (resources, config, output) ---
    [self setupWorkingDirectory];
    restore_security_scoped_bookmarks();

    // --- Logger ---
    initLogger();

    // --- Dear ImGui context ---
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO &io = ImGui::GetIO();
    io.IniFilename = NULL;          // no imgui.ini persistence
    io.MouseDrawCursor = false;     // touch input: no software cursor

    // --- Metal renderer + SatDump backend bindings ---
    if (!ImGuiMetal_Init(g_metalDevice, mtkView.colorPixelFormat))
        NSLog(@"[SatDump] Failed to initialize the Metal renderer");
    bindBackendFunctions();
    bindImageTextureFunctions();

    style::setFonts(backend::device_scale);

    // --- Initialize SatDump (synchronous, shows the loading screen) ---
    std::shared_ptr<satdump::LoadingScreenSink> loadingScreen =
        std::make_shared<satdump::LoadingScreenSink>();
    logger->add_sink(loadingScreen);

    satdump::tle_do_update_on_init = false;
    satdump::initSatdump(true);
    satdump::initMainUI();

    logger->del_sink(loadingScreen);
    loadingScreen.reset();

    // Background TLE update.
    satdump::ui_thread_pool.push([](int)
                                 { satdump::autoUpdateTLE(satdump::user_path + "/satdump_tles.txt"); });

    _satdumpReady = YES;
    mtkView.paused = NO; // start the render loop
}

// Copies the read-only bundled resources into a writable working directory
// inside the app sandbox and chdir()s into it. Mirrors the Android port.
- (void)setupWorkingDirectory
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *documents =
        [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *bundle = [[NSBundle mainBundle] resourcePath];

    // resources/ and pipelines/ are large and read-only: copy once.
    //
    // In the bundle the folders are named "satdump_resources" and
    // "satdump_pipelines" (see ios/CMakeLists.txt) - a plain "resources"
    // folder at the bundle root would collide with codesign's macOS-style
    // ^Resources/ rule pattern on the case-insensitive filesystem and break
    // signing. The destinations inside Documents keep the original names so
    // the rest of SatDump finds "resources/..." in the working directory
    // unchanged.
    NSDictionary<NSString *, NSString *> *bundledFolders = @{
        @"satdump_resources" : @"resources",
        @"satdump_pipelines" : @"pipelines",
    };
    for (NSString *bundleName in bundledFolders)
    {
        NSString *runtimeName = bundledFolders[bundleName];
        NSString *destination = [documents stringByAppendingPathComponent:runtimeName];
        NSString *source = [bundle stringByAppendingPathComponent:bundleName];
        if (![fileManager fileExistsAtPath:destination] && [fileManager fileExistsAtPath:source])
        {
            NSError *error = nil;
            if (![fileManager copyItemAtPath:source toPath:destination error:&error])
                NSLog(@"[SatDump] Could not copy %@: %@", bundleName, error);
        }
    }

    // satdump_cfg.json: copy only if missing, so user changes are kept.
    NSString *configDestination = [documents stringByAppendingPathComponent:@"satdump_cfg.json"];
    NSString *configSource = [bundle stringByAppendingPathComponent:@"satdump_cfg.json"];
    if (![fileManager fileExistsAtPath:configDestination] && [fileManager fileExistsAtPath:configSource])
        [fileManager copyItemAtPath:configSource toPath:configDestination error:nil];

    chdir([documents fileSystemRepresentation]);
}

// ----------------------------------------------------------------------------
// Render loop (MTKViewDelegate)
// ----------------------------------------------------------------------------

- (void)drawInMTKView:(MTKView *)view
{
    if (!_satdumpReady)
        return;

    @autoreleasepool
    {
        satdump::renderMainUI();
    }

    [self syncKeyboardState];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Dear ImGui reads the current drawable size every frame in funcBeginFrame().
}

// ----------------------------------------------------------------------------
// Touch input
// ----------------------------------------------------------------------------

- (void)forwardTouchPosition:(UITouch *)touch
{
    if (touch == nil)
        return;
    CGPoint location = [touch locationInView:self.view];
    CGFloat scale = self.view.contentScaleFactor;
    ImGuiIO &io = ImGui::GetIO();
    // Mark the events as coming from a touch screen so Dear ImGui uses its
    // touch-friendly behaviour (no pre-press hover, more lenient hit aiming).
    io.AddMouseSourceEvent(ImGuiMouseSource_TouchScreen);
    io.AddMousePosEvent((float)(location.x * scale), (float)(location.y * scale));
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self forwardTouchPosition:touches.anyObject];
    ImGui::GetIO().AddMouseButtonEvent(0, true);
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self forwardTouchPosition:touches.anyObject];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    // Forward the final position then release the button. Do NOT move the
    // cursor off-screen here: Dear ImGui finalizes a click on the next frame
    // by checking that the position is still over the widget. Resetting the
    // position before that frame swallows every tap.
    [self forwardTouchPosition:touches.anyObject];
    ImGui::GetIO().AddMouseButtonEvent(0, false);
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    // A cancelled touch is intentionally NOT a click - drop the position so
    // no widget is left hovered/clicked.
    ImGuiIO &io = ImGui::GetIO();
    io.AddMouseButtonEvent(0, false);
    io.AddMousePosEvent(-FLT_MAX, -FLT_MAX);
}

// ----------------------------------------------------------------------------
// Keyboard input
//
// A zero-sized off-screen UITextField drives the iOS on-screen keyboard.
// Typed characters are forwarded to Dear ImGui; the field itself stays empty.
// ----------------------------------------------------------------------------

- (void)setupKeyboardField
{
    _keyboardField = [[SatDumpKeyboardField alloc] initWithFrame:CGRectZero];
    _keyboardField.delegate = self;
    _keyboardField.autocorrectionType = UITextAutocorrectionTypeNo;
    _keyboardField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _keyboardField.spellCheckingType = UITextSpellCheckingTypeNo;
    [self.view addSubview:_keyboardField];
}

// Shows / hides the keyboard depending on whether Dear ImGui wants text input.
- (void)syncKeyboardState
{
    bool wantInput = ImGui::GetIO().WantTextInput;
    if (wantInput && !_keyboardField.isFirstResponder)
        [_keyboardField becomeFirstResponder];
    else if (!wantInput && _keyboardField.isFirstResponder)
        [_keyboardField resignFirstResponder];
}

- (BOOL)textField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)string
{
    // Backspace is handled by SatDumpKeyboardField's -deleteBackward override
    // (more reliable on an empty field than this delegate callback).
    ImGuiIO &io = ImGui::GetIO();
    for (NSUInteger i = 0; i < string.length; i++)
        io.AddInputCharacter([string characterAtIndex:i]);
    return NO; // keep the backing text field empty
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    ImGuiIO &io = ImGui::GetIO();
    io.AddKeyEvent(ImGuiKey_Enter, true);
    io.AddKeyEvent(ImGuiKey_Enter, false);
    return NO;
}

// ----------------------------------------------------------------------------
// Misc
// ----------------------------------------------------------------------------

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

@end
