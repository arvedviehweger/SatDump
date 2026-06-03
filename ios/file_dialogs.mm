#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <mutex>
#include <string>

@interface SatDumpDocumentPickerDelegate : NSObject <UIDocumentPickerDelegate>
@property(nonatomic, assign) BOOL directory;
@end

namespace
{
std::mutex g_dialogMutex;
std::string g_fileDialogResult;
std::string g_directoryDialogResult;
bool g_pickerActive = false;
NSMutableArray<NSURL *> *g_securityScopedURLs = nil;
SatDumpDocumentPickerDelegate *g_filePickerDelegate = nil;
SatDumpDocumentPickerDelegate *g_directoryPickerDelegate = nil;

NSString *satdumpDocumentsDirectory()
{
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
}

NSString *writableDirectoryPathForPickedURL(NSURL *url)
{
    NSString *documents = satdumpDocumentsDirectory();
    NSString *pickedPath = url.path;
    if (documents == nil || pickedPath == nil)
        return pickedPath;

    if ([pickedPath hasPrefix:documents])
        return pickedPath;

    NSString *localName = pickedPath.lastPathComponent.length > 0 ? pickedPath.lastPathComponent : @"SatDump";
    NSString *localPath = [documents stringByAppendingPathComponent:localName];
    [[NSFileManager defaultManager] createDirectoryAtPath:localPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return localPath;
}

UIViewController *satdumpRootViewController()
{
    UIWindow *keyWindow = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
    {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:UIWindowScene.class])
            continue;

        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows)
        {
            if (window.isKeyWindow)
            {
                keyWindow = window;
                break;
            }
        }
        if (keyWindow != nil)
            break;
    }

    UIViewController *controller = keyWindow.rootViewController;
    while (controller.presentedViewController != nil)
        controller = controller.presentedViewController;
    return controller;
}

void setDialogResult(bool directory, const std::string &result)
{
    std::lock_guard<std::mutex> lock(g_dialogMutex);
    if (directory)
        g_directoryDialogResult = result;
    else
        g_fileDialogResult = result;
    g_pickerActive = false;
}

} // namespace

@implementation SatDumpDocumentPickerDelegate

- (void)finishPickingURL:(NSURL *)url
{
    if (url == nil || url.path == nil)
    {
        setDialogResult(self.directory == YES, "NO_PATH_SELECTED");
        return;
    }

    [url startAccessingSecurityScopedResource];
    if (g_securityScopedURLs == nil)
        g_securityScopedURLs = [[NSMutableArray alloc] init];
    [g_securityScopedURLs addObject:url];

    NSString *path = self.directory == YES ? writableDirectoryPathForPickedURL(url) : url.path;
    setDialogResult(self.directory == YES, path.UTF8String);
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    [self finishPickingURL:urls.firstObject];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
      didPickDocumentAtURL:(NSURL *)url
{
    [self finishPickingURL:url];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
    setDialogResult(self.directory == YES, "NO_PATH_SELECTED");
}

@end

namespace
{

void showDocumentPicker(bool directory)
{
    dispatch_async(dispatch_get_main_queue(), ^{
      {
          std::lock_guard<std::mutex> lock(g_dialogMutex);
          if (g_pickerActive)
              return;
          g_pickerActive = true;
      }

      UIViewController *presentingController = satdumpRootViewController();
      if (presentingController == nil)
      {
          setDialogResult(directory, "NO_PATH_SELECTED");
          return;
      }

      NSArray<UTType *> *contentTypes = directory
                                            ? @[ [UTType typeWithIdentifier:@"public.folder"] ]
                                            : @[ [UTType typeWithIdentifier:@"public.item"] ];
      UIDocumentPickerViewController *picker =
          [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes
                                                                      asCopy:NO];
      picker.allowsMultipleSelection = NO;

      SatDumpDocumentPickerDelegate *delegate = [[SatDumpDocumentPickerDelegate alloc] init];
      delegate.directory = directory;
      picker.delegate = delegate;
      if (directory)
          g_directoryPickerDelegate = delegate;
      else
          g_filePickerDelegate = delegate;

      [presentingController presentViewController:picker animated:YES completion:nil];
    });
}

std::string takeDialogResult(bool directory)
{
    std::lock_guard<std::mutex> lock(g_dialogMutex);
    std::string &result = directory ? g_directoryDialogResult : g_fileDialogResult;
    std::string copy = result;
    result.clear();
    return copy;
}
} // namespace

void show_select_file_dialog()
{
    showDocumentPicker(false);
}

std::string get_select_file_dialog_result()
{
    return takeDialogResult(false);
}

void show_select_directory_dialog()
{
    showDocumentPicker(true);
}

std::string get_select_directory_dialog_result()
{
    return takeDialogResult(true);
}
