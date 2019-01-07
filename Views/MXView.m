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
@property (strong) NSArray<MTKMesh *> *cube;
@property (strong) NSArray<MTKMesh *> *cylinders;
@property (strong) NSArray<MTKMesh *> *sphere;

// Pipeline state stuff
@property (strong) id<MTLLibrary> library;
@property (strong) id<MTLFunction> vertexFunction;
@property (strong) id<MTLFunction> fragmentFunction;
@property (strong) id<MTLRenderPipelineState> pipeline;

// Depth stencil
@property (strong) id<MTLDepthStencilState> depth;

// Layer counting resources
@property (strong) id<MTLRenderPipelineState> layerCountPipeline;
@property (strong) id<MTLDepthStencilState> layerCountDepth;
@property (strong) id<MTLTexture> layerCountStencil;

@property (strong) id<MTLFunction> layerCountFunction;
@property (strong) id<MTLComputePipelineState> countPipeline;

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
	 *	Grab the device and library
	 */

	self.device = MTLCreateSystemDefaultDevice();
	self.library = [self.device newDefaultLibrary];

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



	// Kludge to make sure our size is drawin in the proper order
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self mtkView:self drawableSizeWillChange:self.bounds.size];
	});
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

	MTLDepthStencilDescriptor *descriptor = [[MTLDepthStencilDescriptor alloc] init];
	descriptor.depthCompareFunction = MTLCompareFunctionLess;
	descriptor.depthWriteEnabled = YES;
	self.depth = [self.device newDepthStencilStateWithDescriptor:descriptor];

	/*
	 *	Layer count
	 */

	MTLStencilDescriptor *stencil = [[MTLStencilDescriptor alloc] init];
	stencil.depthStencilPassOperation = MTLStencilOperationIncrementClamp;

	descriptor = [[MTLDepthStencilDescriptor alloc] init];
	descriptor.depthCompareFunction = MTLCompareFunctionAlways;
	descriptor.backFaceStencil = stencil;
	descriptor.frontFaceStencil = stencil;
	descriptor.depthWriteEnabled = NO;
	self.layerCountDepth = [self.device newDepthStencilStateWithDescriptor:descriptor];
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
	 *	Get our vertex and fragment functions. These should be the
	 *	same names as the functions declared in our MXShader file.
	 */

	self.vertexFunction = [self.library newFunctionWithName:@"vertex_main"];
	self.fragmentFunction = [self.library newFunctionWithName:@"fragment_main"];
	self.layerCountFunction = [self.library newFunctionWithName:@"layer_count"];

	/*
	 *	Construct our vertex descriptor. We do this to map the
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
	 *	Start building the pipeline descriptor and pipeline. This is used to
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

	self.pipeline = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];

	/*
	 *	Build the pipeline for counting layers
	 */

	pipelineDescriptor = [MTLRenderPipelineDescriptor new];
	pipelineDescriptor.vertexFunction = self.vertexFunction;
	pipelineDescriptor.fragmentFunction = nil;
	pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(d);
	pipelineDescriptor.stencilAttachmentPixelFormat = MTLPixelFormatStencil8;

	self.layerCountPipeline = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];

	/*
	 *	Build the compute kernel to count the results
	 */

	self.countPipeline = [self.device newComputePipelineStateWithFunction:self.layerCountFunction error:nil];

	/*
	 *	Use the vertex descriptor to load our model.
	 */

	NSURL *modelURL;
	MDLAsset *asset;
	MTKMeshBufferAllocator *allocator = [[MTKMeshBufferAllocator alloc] initWithDevice:self.device];

	modelURL = [[NSBundle mainBundle] URLForResource:@"Cube" withExtension:@"stl"];
	asset = [[MDLAsset alloc] initWithURL:modelURL vertexDescriptor:d bufferAllocator:allocator];
	self.cube = [MTKMesh newMeshesFromAsset:asset device:self.device sourceMeshes:nil error:nil];

	modelURL = [[NSBundle mainBundle] URLForResource:@"Sphere" withExtension:@"stl"];
	asset = [[MDLAsset alloc] initWithURL:modelURL vertexDescriptor:d bufferAllocator:allocator];
	self.sphere = [MTKMesh newMeshesFromAsset:asset device:self.device sourceMeshes:nil error:nil];

	modelURL = [[NSBundle mainBundle] URLForResource:@"Cylinders" withExtension:@"stl"];
	asset = [[MDLAsset alloc] initWithURL:modelURL vertexDescriptor:d bufferAllocator:allocator];
	self.cylinders = [MTKMesh newMeshesFromAsset:asset device:self.device sourceMeshes:nil error:nil];
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
/*	Drawing Support															*/
/*																			*/
/****************************************************************************/
#pragma mark - Drawing Support

- (void)renderMesh:(NSArray<MTKMesh *> *)meshArray inEncoder:(id<MTLRenderCommandEncoder>)encoder
{
    for (MTKMesh *mesh in meshArray) {
        MTKMeshBuffer *vertexBuffer = [[mesh vertexBuffers] firstObject];
        [encoder setVertexBuffer:vertexBuffer.buffer offset:vertexBuffer.offset atIndex:0];

        for (MTKSubmesh *submesh in mesh.submeshes) {
            MTKMeshBuffer *indexBuffer = submesh.indexBuffer;
            [encoder drawIndexedPrimitives:submesh.primitiveType indexCount:submesh.indexCount indexType:submesh.indexType indexBuffer:indexBuffer.buffer indexBufferOffset:indexBuffer.offset];
        }
    }
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

	MTLTextureDescriptor *descriptor;

	descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatStencil8 width:size.width height:size.height mipmapped:NO];
	descriptor.storageMode = MTLStorageModePrivate;
	descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
	self.layerCountStencil = [self.device newTextureWithDescriptor:descriptor];
}

- (void)drawInMTKView:(MTKView *)view
{
	id<MTLCommandBuffer> buffer;
	MTLRenderPassDescriptor *descriptor;
	id<MTLRenderCommandEncoder> encoder;
	id<MTLComputeCommandEncoder> compute;

	if (self.layerCountStencil == nil) return;

	/*
	 *	Populate uniform
	 */

	double elapsed = CACurrentMediaTime() - self.startTime;
	[self.model clear];
	[self.model translateByX:0 y:0 z:-2];
	[self.model rotateAroundFixedAxis:MTXXAxis byAngle:0.4];
	[self.model rotateAroundAxis:(vector_float3){ 0, 1, 0 } byAngle:elapsed];

	MXUniforms u;
	u.view = self.view.ctm;
	u.model = self.model.ctm;
	u.inverse = self.model.inverseCtm;

	/*
	 *	Phase 1: Calculate the maximum number of layers and the layer stencil
	 *	map
	 */

	buffer = [self.commandQueue commandBuffer];

	descriptor = [[MTLRenderPassDescriptor alloc] init];
	descriptor.stencilAttachment.texture = self.layerCountStencil;
	descriptor.stencilAttachment.loadAction = MTLLoadActionClear;
	descriptor.stencilAttachment.storeAction = MTLStoreActionStore;
	descriptor.stencilAttachment.clearStencil = 0;

	encoder = [buffer renderCommandEncoderWithDescriptor:descriptor];

	[encoder setRenderPipelineState:self.layerCountPipeline];
	[encoder setCullMode:MTLCullModeFront];
	[encoder setDepthStencilState:self.layerCountDepth];
	[encoder setVertexBytes:&u length:sizeof(MXUniforms) atIndex:MXVertexIndexUniforms];

	// Render pass
	[encoder setCullMode:MTLCullModeFront];
	[self renderMesh:self.cube inEncoder:encoder];
	[self renderMesh:self.sphere inEncoder:encoder];
	[encoder setCullMode:MTLCullModeBack];
	[self renderMesh:self.cylinders inEncoder:encoder];

	[encoder endEncoding];

	compute = [buffer computeCommandEncoder];
	[compute setComputePipelineState:self.countPipeline];
	[compute setTexture:self.layerCountStencil atIndex:0];
	id<MTLBuffer> count = [self.device newBufferWithLength:sizeof(MXLayerCount) options:MTLResourceOptionCPUCacheModeDefault];
	[compute setBuffer:count offset:0 atIndex:1];

	MTLSize threadgroupCounts = MTLSizeMake(8, 8, 1);
	MTLSize threadgroups = MTLSizeMake([self.layerCountStencil width] / threadgroupCounts.width, [self.layerCountStencil height] / threadgroupCounts.height, 1);
	[compute dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadgroupCounts];
	[compute endEncoding];
	// Debug. Figure out how to extract max value

	[buffer commit];

	// ### TODO: Seeparate

	/*
	 *	First step: get the command buffer.
	 */

	buffer = [self.commandQueue commandBuffer];

	descriptor = [view currentRenderPassDescriptor];
	encoder = [buffer renderCommandEncoderWithDescriptor:descriptor];

	[encoder setRenderPipelineState:self.pipeline];
	[encoder setCullMode:MTLCullModeFront];
	[encoder setDepthStencilState:self.depth];
	[encoder setVertexBytes:&u length:sizeof(MXUniforms) atIndex:MXVertexIndexUniforms];

	/*
	 *	Now tell our encoder about where our vertex information is located,
	 *	and ask it to render our triangle.
	 */

	vector_float3 color = { 1, 0.5, 0.3 };
	[encoder setFragmentBytes:&color length:sizeof(color) atIndex:MXFragmentIndexColor];
	[self renderMesh:self.cube inEncoder:encoder];

	color = (vector_float3){ 0.3, 1.0, 0.3 };
	[encoder setFragmentBytes:&color length:sizeof(color) atIndex:MXFragmentIndexColor];
	[self renderMesh:self.sphere inEncoder:encoder];

	color = (vector_float3){ 0.3, 0.5, 1.0 };
	[encoder setFragmentBytes:&color length:sizeof(color) atIndex:MXFragmentIndexColor];
	[self renderMesh:self.cylinders inEncoder:encoder];

	/*
	 *	Commit the encoder, which finishes drawing for this rendering pass
	 */

	[encoder endEncoding];

	/*
	 *	Give our buffer a reference to the drawable screen so our screen can
	 *	be updated ("presented") when drawing is complete.
	 */

	[buffer presentDrawable:self.currentDrawable];
	[buffer commit];
}

@end
