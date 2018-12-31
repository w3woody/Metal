//
//  MXView.m
//  Metal
//
//  Created by William Woody on 12/27/18.
//  Copyright © 2018 Glenview Software. All rights reserved.
//

#import "MXView.h"
#import "MXShaderTypes.h"
#import "MXGeometry.h"
#import "MXTransformationStack.h"

@interface MXView () <MTKViewDelegate>

// Command queue
@property (strong) id<MTLCommandQueue> commandQueue;

// The teapot, as a collection of meshes
@property (strong) NSArray<MTKMesh *> *teapot;

// Pipeline state stuff
@property (strong) id<MTLLibrary> library;
@property (strong) id<MTLFunction> vertexFunction;
@property (strong) id<MTLFunction> fragmentFunction;
@property (strong) id<MTLRenderPipelineState> pipeline;

// Depth stencil
@property (strong) id<MTLDepthStencilState> depth;

// Textures and support
@property (strong) id<MTLTexture> texture;

// Transformation matrices
@property (strong) MXTransformationStack *view;
@property (strong) MXTransformationStack *model;

// Starting time
@property (assign) double startTime;

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
	 *	Note the start time
	 */

	self.startTime = CACurrentMediaTime();

	/*
	 *	Application startup
	 */

	[self setupView];
	[self setupPipeline];
	[self setupTransformation];
	[self setupDepthStencilState];
	[self setupTextures];

	// Kludge to make sure our size is drawin in the proper order
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self mtkView:self drawableSizeWillChange:self.bounds.size];
	});
}

/****************************************************************************/
/*																			*/
/*	Texture Loading															*/
/*																			*/
/****************************************************************************/
#pragma mark - Texture Loading

- (void)setupTextures
{
	/*
	 *	Texture loader
	 */

	MTKTextureLoader *textureLoader = [[MTKTextureLoader alloc] initWithDevice:self.device];

	/*
	 *	Our textures
	 */

	self.texture = [textureLoader newTextureWithName:@"texture" scaleFactor:1.0 bundle:nil options:@{} error:nil];
}

/****************************************************************************/
/*																			*/
/*	Initialization Methods													*/
/*																			*/
/****************************************************************************/
#pragma mark - Initialization Methods

/*
 *	Routines which perform basic initialization: getting the device, setting
 *	screen parameters, and creating the command queue
 */

- (void)setupView
{
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
	self.depthStencilPixelFormat = MTLPixelFormatDepth32Float;

	// The following two calls essentially change the behavior of our view
	// so that it only updates on setNeedsDisplay. This behavior is useful
	// if you are creating a 3D CAD system instead of a game.
//	self.paused = YES;
//	self.enableSetNeedsDisplay = YES;

	/*
	 *	Get the command queue for this device.
	 */

	self.commandQueue = [self.device newCommandQueue];
}

- (void)setupDepthStencilState
{
	/*
	 *	Set up the depth stencil
	 */

	MTLDepthStencilDescriptor *depthDescriptor = [[MTLDepthStencilDescriptor alloc] init];
	depthDescriptor.depthCompareFunction = MTLCompareFunctionLess;
	[depthDescriptor setDepthWriteEnabled:YES];

	self.depth = [self.device newDepthStencilStateWithDescriptor:depthDescriptor];
}

/*
 *	This sets up our pipeline state. The pipeline state stores information
 *	such as the vertex and fragment shader functions on the GPU, and the
 *	attributes used to populate our contents so we can map the contents of
 *	our buffer (created in setupGeometry above) to the attributes passed to
 *	our GPU.
 *
 *	Note the pipeline state is pretty heavy-weight so we do this once here.
 */

- (void)setupPipeline
{
	/*
	 *	Step 1: Get our library. This is the library of GPU methods that have
	 *	been precompiled by Xcode
	 */

	self.library = [self.device newDefaultLibrary];

	/*
	 *	Step 2: Get our vertex and fragment functions. These should be the
	 *	same names as the functions declared in our MXShader file.
	 */

	self.vertexFunction = [self.library newFunctionWithName:@"vertex_main"];
	self.fragmentFunction = [self.library newFunctionWithName:@"fragment_main"];

	/*
	 *	Step 3: Construct our vertex descriptor. We do this to map the
	 *	offsets in our trangle buffer to the attrite offsets sent to our
	 *	GPU. Because we're not using the Model I/O API to load a model, we
	 *	build the MTLVertexDescriptor directly.
	 *
	 *	If we were using the Model I/O API to load a model from a resource,
	 *	we'd create the MDLVertexDescriptor (which are more or less the same
	 *	thing except not in GPU memory) and use the funnction call
	 *	MTKMetalVertexDescriptorFromModelIO to convert.
	 */

	MDLVertexDescriptor *d = [[MDLVertexDescriptor alloc] init];
	d.attributes[0] = [[MDLVertexAttribute alloc] initWithName:MDLVertexAttributePosition format:MDLVertexFormatFloat3 offset:0 bufferIndex:0];
	d.attributes[1] = [[MDLVertexAttribute alloc] initWithName:MDLVertexAttributeNormal format:MDLVertexFormatFloat3 offset:sizeof(vector_float3) bufferIndex:0];
	d.attributes[2] = [[MDLVertexAttribute alloc] initWithName:MDLVertexAttributeTextureCoordinate format:MDLVertexFormatFloat2 offset:sizeof(vector_float3) * 2 bufferIndex:0];
	d.layouts[0] = [[MDLVertexBufferLayout alloc] initWithStride:sizeof(MXVertex)];


	/*
	 *	Step 4: Start building the pipeline descriptor. This is used to
	 *	eventually build our pipeline state. Note if we were doing anything
	 *	more complicated with our pipeline (such as using stencils or depth
	 *	detection for 3D rendering) we'd set that stuff here.
	 */

	MTLRenderPipelineDescriptor *pipelineDescriptor = [MTLRenderPipelineDescriptor new];
	pipelineDescriptor.vertexFunction = self.vertexFunction;
	pipelineDescriptor.fragmentFunction = self.fragmentFunction;
	pipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
	pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(d);
	pipelineDescriptor.depthAttachmentPixelFormat = self.depthStencilPixelFormat;

	/*
	 *	Build our pipeline state object.
	 */

	self.pipeline = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];

	/*
	 *	Use the vertex descriptor to load our model.
	 */

	NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"teapot" withExtension:@"obj"];
	MTKMeshBufferAllocator *allocator = [[MTKMeshBufferAllocator alloc] initWithDevice:self.device];
	MDLAsset *asset = [[MDLAsset alloc] initWithURL:modelURL vertexDescriptor:d bufferAllocator:allocator];
	self.teapot = [MTKMesh newMeshesFromAsset:asset device:self.device sourceMeshes:nil error:nil];

}

/*
 *	Setup transformation
 */

- (void)setupTransformation
{
	self.view = [[MXTransformationStack alloc] init];
	self.model = [[MXTransformationStack alloc] init];
}

/****************************************************************************/
/*																			*/
/*	MTKViewDelegate Methods													*/
/*																			*/
/****************************************************************************/
#pragma mark - MTKViewDelegate Methods

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{
	[self.view clear];
	[self.view perspective:M_PI/3 aspect:size.width/size.height near:0.1 far:1000];
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
	 *	Set up our encoder by indicating the pipeline we will be using for
	 *	rendering our triangle.
	 */

	[encoder setRenderPipelineState:self.pipeline];

	/*
	 *	Update the model transformation
	 */

	double elapsed = CACurrentMediaTime() - self.startTime;
	[self.model clear];
	[self.model translateByX:0 y:0 z:-2];
	[self.model rotateAroundFixedAxis:MTXXAxis byAngle:0.4];
	[self.model rotateAroundAxis:(vector_float3){ 0, 1, 0 } byAngle:elapsed];
	[self.model scaleBy:2];

	MXUniforms u;
	u.view = self.view.ctm;
	u.model = self.model.ctm;
	u.inverse = self.model.inverseCtm;
	[encoder setVertexBytes:&u length:sizeof(MXUniforms) atIndex:MXVertexIndexUniforms];

	/*
	 *	Enable back-face culling
	 */

	[encoder setCullMode:MTLCullModeFront];

	/*
	 *	Set the depth stencil
	 */

	[encoder setDepthStencilState:self.depth];

	/*
	 *	Set textures
	 */

	[encoder setFragmentTexture:self.texture atIndex:MXTextureIndex0];

	/*
	 *	Now tell our encoder about where our vertex information is located,
	 *	and ask it to render our triangle.
	 */

	for (MTKMesh *mesh in self.teapot) {
		MTKMeshBuffer *vertexBuffer = [[mesh vertexBuffers] firstObject];
		[encoder setVertexBuffer:vertexBuffer.buffer offset:vertexBuffer.offset atIndex:0];

		for (MTKSubmesh *submesh in mesh.submeshes) {
			MTKMeshBuffer *indexBuffer = submesh.indexBuffer;
			[encoder drawIndexedPrimitives:submesh.primitiveType indexCount:submesh.indexCount indexType:submesh.indexType indexBuffer:indexBuffer.buffer indexBufferOffset:indexBuffer.offset];
		}
	}

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
