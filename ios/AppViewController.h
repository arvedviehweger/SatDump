#pragma once

#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>

// Root view controller of the SatDump iOS app.
//
// It hosts the Metal view, performs SatDump initialization, drives the
// Dear ImGui render loop (via satdump::renderMainUI) and forwards touch and
// keyboard input to Dear ImGui.
@interface AppViewController : UIViewController <MTKViewDelegate, UITextFieldDelegate>
@end
