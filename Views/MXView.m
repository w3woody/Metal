//
//  MXView.m
//  Metal
//
//  Created by William Woody on 12/27/18.
//  Copyright © 2018 Glenview Software. All rights reserved.
//

#import "MXView.h"

@interface MXView () <MTKViewDelegate>

// Command queue
@property (strong) id<MTLCommandQueue> commandQueue;
@end

@implementation MXView

/****************************************************************************/
/*																			*/
/*	Construction/Destruction												*/
/*																			*/
/****************************************************************************/
#pragma mark - Construction/Destruction

- (instancetype)initWithFrame:(NSRect)frameRect
{
	if (nil != (self = [super initWithFrame:frameRect])) {
		[self internalInit];
	}
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
	if (nil != (self = [super initWithCoder:coder])) {
		[self internalInit];
	}
	return self;
}

/*	internalInit
 *
 *		Construction class which sets up metal
 */

- (void)internalInit
{
	/*
	 *	We're using ourselves as the delegate.
	 */

	self.delegate = self;

	/*
	 *	Get the device for this view. (For a real MacOS application, this
	 *	should be replaced with a more sophisticated system that determines
	 *	the appropriate device depending on which screen this view is located,
	 *	and which updates the device and device parameters as needed if the
	 *	view is moved across screens.)
	 */

	self.device = MTLCreateSystemDefaultDevice();

	/*
	 *	Set certain parameters for our view's behavior, color depth, background
	 *	color and the like.
	 */

	self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
	self.clearColor = MTLClearColorMake(0.1, 0.1, 0.2, 1.0);

	// The following two calls essentially change the behavior of our view
	// so that it only updates on setNeedsDisplay. This behavior is useful
	// if you are creating a 3D CAD system instead of a game.
	self.paused = YES;
	self.enableSetNeedsDisplay = YES;

	/*
	 *	Get the command queue for this device.
	 */

	self.commandQueue = [self.device newCommandQueue];
}


/****************************************************************************/
/*																			*/
/*	MTKViewDelegate Methods													*/
/*																			*/
/****************************************************************************/
#pragma mark - MTKViewDelegate Methods

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{
}

- (void)drawInMTKView:(MTKView *)view
{
	/*
	 *	First step: get the command buffer.
	 */

	id<MTLCommandBuffer> buffer = [self.commandQueue commandBuffer];

	/*
	 *	Third create render command encoder by first building a
	 *	descriptor and initializing it.
	 */

	MTLRenderPassDescriptor *descriptor = [view currentRenderPassDescriptor];

	/*
	 *	Use the descriptor to generate our encoder.
	 */

	id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:descriptor];

	/*
	 *	Commit the encoder, which finishes drawing for this rendering pass
	 */

	[encoder endEncoding];

	/*
	 *	Give our buffer a reference to the drawable screen so our screen can
	 *	be updated ("presented") when drawing is complete.
	 */

	[buffer presentDrawable:self.currentDrawable];

	/*
	 *	Finish and submit the buffer to the GPU
	 */

	[buffer commit];
}

@end
