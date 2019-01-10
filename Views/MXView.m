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

// Rendering semaphore
@property (strong) dispatch_semaphore_t semaphore;

// Command queue
@property (strong) id<MTLCommandQueue> commandQueue;

// The teapot, as a collection of meshes
@property (strong) NSArray<MTKMesh *> *cube;
@property (strong) NSArray<MTKMesh *> *cylinders;
@property (strong) NSArray<MTKMesh *> *sphere;

// Pipeline state stuff
@property (strong) id<MTLLibrary> library;

// Clear depth start
@property (strong) id<MTLComputePipelineState> clearDepthPipeline;

// Off screen color/depth buffers
@property (strong) id<MTLTexture> colorTexture;
@property (strong) id<MTLTexture> depthTexture;
@property (strong) id<MTLTexture> screenDepth;
@property (strong) id<MTLTexture> outTexture;
@property (strong) id<MTLTexture> stencilTexture;
@property (strong) id<MTLBuffer> sumsBuffer;
@property (strong) id<MTLBuffer> uniforms;

// Layer counting
@property (strong) id<MTLRenderPipelineState> layerCountPipeline;
@property (strong) id<MTLComputePipelineState> countPipeline;
@property (strong) id<MTLDepthStencilState> layerCountStencil;

// Layer extraction pipeline, stencil state
@property (strong) id<MTLRenderPipelineState> layerExtractPipeline;
@property (strong) id<MTLDepthStencilState> layerExtractStencil;

// Compute pipelines for support
@property (strong) id<MTLComputePipelineState> clearStencilPipeline;

// Layer parity test pipeline, stencil state
@property (strong) id<MTLRenderPipelineState> layerParityPipeline;
@property (strong) id<MTLDepthStencilState> layerParityStencil;

// Layer clear pipeline, stencil state. Used to clear rejected pixels
@property (strong) id<MTLRenderPipelineState> layerClearPipeline;
@property (strong) id<MTLDepthStencilState> layerClearStencil;
@property (strong) id<MTLBuffer> square;

// Merge pipeline
@property (strong) id<MTLComputePipelineState> layerMergePipeline;

// Output pipeline
@property (strong) id<MTLRenderPipelineState> outputResultPipeline;

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
	[self setupSquare];
	[self setupUniforms];

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

	// The following two calls essentially change the behavior of our view
	// so that it only updates on setNeedsDisplay. This behavior is useful
	// if you are creating a 3D CAD system instead of a game.
//	self.paused = YES;
//	self.enableSetNeedsDisplay = YES;

	/*
	 *	Get the command queue for this device.
	 */

	self.commandQueue = [self.device newCommandQueue];

	/*
	 *	Semaphore
	 */

	self.semaphore = dispatch_semaphore_create(1);
}

- (void)setupDepthStencilState
{
	MTLDepthStencilDescriptor *descriptor;
	MTLStencilDescriptor *stencil;

	/*
	 *	Layer counting.
	 */

	stencil = [[MTLStencilDescriptor alloc] init];
	stencil.stencilCompareFunction = MTLCompareFunctionAlways;
	stencil.depthStencilPassOperation = MTLStencilOperationIncrementClamp;

	descriptor = [[MTLDepthStencilDescriptor alloc] init];
	descriptor.depthCompareFunction = MTLCompareFunctionAlways;
	descriptor.backFaceStencil = stencil;
	descriptor.frontFaceStencil = stencil;
	descriptor.depthWriteEnabled = NO;
	self.layerCountStencil = [self.device newDepthStencilStateWithDescriptor:descriptor];

	/*
	 *	Layer extraction. This is used to draw the 'kth' layer of an image,
	 *	as the first part of drawing each product layer. Note we can save
	 *	ourselves a bunch of effort by ignoring the depth compare.
	 */

	stencil = [[MTLStencilDescriptor alloc] init];
	stencil.stencilCompareFunction = MTLCompareFunctionEqual;
	stencil.depthStencilPassOperation = MTLStencilOperationIncrementClamp;
	stencil.stencilFailureOperation = MTLStencilOperationIncrementClamp;
	stencil.depthFailureOperation = MTLStencilOperationIncrementClamp;

	descriptor = [[MTLDepthStencilDescriptor alloc] init];
	descriptor.depthCompareFunction = MTLCompareFunctionAlways;
	descriptor.backFaceStencil = stencil;
	descriptor.frontFaceStencil = stencil;
	descriptor.depthWriteEnabled = YES;
	self.layerExtractStencil = [self.device newDepthStencilStateWithDescriptor:descriptor];

	/*
	 *	Parity testing. This basically does everything but play with the
	 *	stencil, since we're using a 32-bit texture array as our stencil.
	 */

	stencil = [[MTLStencilDescriptor alloc] init];
	stencil.depthStencilPassOperation = MTLStencilOperationInvert;
	stencil.stencilFailureOperation = MTLStencilOperationKeep;
	stencil.depthFailureOperation = MTLStencilOperationKeep;
	stencil.readMask = 1;
	stencil.writeMask = 1;

	descriptor = [[MTLDepthStencilDescriptor alloc] init];
	descriptor.depthCompareFunction = MTLCompareFunctionLessEqual;
	descriptor.depthWriteEnabled = NO;
	descriptor.backFaceStencil = stencil;
	descriptor.frontFaceStencil = stencil;
	self.layerParityStencil = [self.device newDepthStencilStateWithDescriptor:descriptor];

	/*
	 *	Clear testing. This essentially clears all that doesn't match
	 *	the stencil
	 */

	stencil = [[MTLStencilDescriptor alloc] init];
	stencil.stencilCompareFunction = MTLCompareFunctionNotEqual;
	stencil.depthStencilPassOperation = MTLStencilOperationZero;
	stencil.stencilFailureOperation = MTLStencilOperationZero;
	stencil.depthFailureOperation = MTLStencilOperationZero;

	descriptor = [[MTLDepthStencilDescriptor alloc] init];
	descriptor.depthCompareFunction = MTLCompareFunctionAlways;
	descriptor.depthWriteEnabled = YES;
	descriptor.backFaceStencil = stencil;
	descriptor.frontFaceStencil = stencil;
	self.layerClearStencil = [self.device newDepthStencilStateWithDescriptor:descriptor];
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
	MTLRenderPipelineDescriptor *pipelineDescriptor;

	/*
	 *	Get our vertex and fragment functions. These should be the
	 *	same names as the functions declared in our MXShader file.
	 */

	id<MTLFunction> vertexFunction = [self.library newFunctionWithName:@"vertex_main"];
	id<MTLFunction> fragmentFunction = [self.library newFunctionWithName:@"fragment_main"];
	id<MTLFunction> screenVertexFunction = [self.library newFunctionWithName:@"vertex_screen"];
	id<MTLFunction> screenFragmentFunction = [self.library newFunctionWithName:@"fragment_screen"];
	id<MTLFunction> mergeFunction = [self.library newFunctionWithName:@"layer_merge"];
	id<MTLFunction> clearDepth = [self.library newFunctionWithName:@"layer_cleardepth"];
	id<MTLFunction> outputFunction = [self.library newFunctionWithName:@"output_fragment"];
	id<MTLFunction> countFunction = [self.library newFunctionWithName:@"layer_count"];

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
	 *	Layer extraction pipeline. This is used to extract the kth layer and
	 *	render the layer to or display.
	 */

	pipelineDescriptor = [MTLRenderPipelineDescriptor new];
	pipelineDescriptor.vertexFunction = vertexFunction;
	pipelineDescriptor.fragmentFunction = nil;
	pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(d);
	pipelineDescriptor.stencilAttachmentPixelFormat = MTLPixelFormatStencil8;

	self.layerCountPipeline = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];

	/*
	 *	Layer extraction pipeline. This is used to extract the kth layer and
	 *	render the layer to or display.
	 */

	pipelineDescriptor = [MTLRenderPipelineDescriptor new];
	pipelineDescriptor.vertexFunction = vertexFunction;
	pipelineDescriptor.fragmentFunction = fragmentFunction;
	pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(d);
	pipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
	pipelineDescriptor.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
	pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

	self.layerExtractPipeline = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];

	/*
	 *	Layer parity pipeline. This is used to determine the parity count when
	 *	calculating render layers
	 */

	pipelineDescriptor = [MTLRenderPipelineDescriptor new];
	pipelineDescriptor.vertexFunction = vertexFunction;
	pipelineDescriptor.fragmentFunction = nil;
	pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(d);
	pipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
	pipelineDescriptor.colorAttachments[0].writeMask = MTLColorWriteMaskNone;
	pipelineDescriptor.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
	pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

	self.layerParityPipeline = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];

	/*
	 *	Layer clear pipeline. This is used to determine the parity count when
	 *	calculating render layers
	 */

	MTLVertexDescriptor *dsc = [[MTLVertexDescriptor alloc] init];
	dsc.attributes[0].offset = 0;
	dsc.attributes[0].bufferIndex = 0;
	dsc.attributes[0].format = MTLVertexFormatFloat2;
	dsc.layouts[0].stride = sizeof(MXScreenVertex);

	pipelineDescriptor = [MTLRenderPipelineDescriptor new];
	pipelineDescriptor.vertexFunction = screenVertexFunction;
	pipelineDescriptor.fragmentFunction = screenFragmentFunction;
	pipelineDescriptor.vertexDescriptor = dsc;
	pipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
	pipelineDescriptor.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
	pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

	self.layerClearPipeline = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];

	pipelineDescriptor = [MTLRenderPipelineDescriptor new];
	pipelineDescriptor.vertexFunction = screenVertexFunction;
	pipelineDescriptor.fragmentFunction = outputFunction;
	pipelineDescriptor.vertexDescriptor = dsc;
	pipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;

	self.outputResultPipeline = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];

	/*
	 *	Layer merge, clear depth
	 */

	self.layerMergePipeline = [self.device newComputePipelineStateWithFunction:mergeFunction error:nil];
	self.clearDepthPipeline = [self.device newComputePipelineStateWithFunction:clearDepth error:nil];
	self.countPipeline = [self.device newComputePipelineStateWithFunction:countFunction error:nil];

//	### TODO: Finish writing code which clears according to the stencil above.
//	### Add code to repeat for the other three objects in our scene.
//	### Add code to repeat for the full four layers in our scene.

	/*
	 *	Use the vertex descriptor to load our models.
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

/*
 *	Setup geometry
 */

- (void)setupSquare
{
	static const MXScreenVertex square[] = {
		{ { -1, -1 } },
		{ { -1,  1 } },
		{ {  1, -1 } },
		{ { -1,  1 } },
		{ {  1, -1 } },
		{ {  1,  1 } }
	};
	self.square = [self.device newBufferWithBytes:square length:sizeof(square) options:MTLResourceOptionCPUCacheModeDefault];
}

- (void)setupUniforms
{
	self.uniforms = [self.device newBufferWithLength:sizeof(MXUniforms) options:MTLResourceOptionCPUCacheModeDefault];
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

	/*
	 *	Offscreen texturing
	 */

	MTLTextureDescriptor *descriptor;

	descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float_Stencil8 width:size.width height:size.height mipmapped:NO];
	descriptor.storageMode = MTLStorageModePrivate;
	descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
	self.depthTexture = [self.device newTextureWithDescriptor:descriptor];

	descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:self.colorPixelFormat width:size.width height:size.height mipmapped:NO];
	descriptor.storageMode = MTLStorageModePrivate;
	descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
	self.colorTexture = [self.device newTextureWithDescriptor:descriptor];
	self.outTexture = [self.device newTextureWithDescriptor:descriptor];

	descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR32Float width:size.width height:size.height mipmapped:NO];
	descriptor.storageMode = MTLStorageModePrivate;
	descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
	self.screenDepth = [self.device newTextureWithDescriptor:descriptor];

	descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatStencil8 width:size.width height:size.height mipmapped:NO];
	descriptor.storageMode = MTLStorageModePrivate;
	descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
	self.stencilTexture = [self.device newTextureWithDescriptor:descriptor];

	self.sumsBuffer = [self.device newBufferWithLength:size.width options:MTLResourceOptionCPUCacheModeDefault];
}

- (void)drawInMTKView:(MTKView *)view
{
	id<MTLCommandBuffer> buffer;
	MTLRenderPassDescriptor *descriptor;
	id<MTLRenderCommandEncoder> encoder;
	id<MTLComputeCommandEncoder> compute;
	MTLSize threadGroupSize;
	NSUInteger s;
	MTLSize threadsPerGroup;

	/*
	 *	Return if not initialized
	 */

	if (self.colorTexture == nil) return;

	/*
	 *	Semaphore limits access
	 */

	dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER);

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
	memmove(self.uniforms.contents,&u,sizeof(u));

	/*
	 *	Phase 1: Calculate the maximum number of layers and the layer stencil
	 *	map
	 */

	buffer = [self.commandQueue commandBuffer];

	descriptor = [[MTLRenderPassDescriptor alloc] init];
	descriptor.stencilAttachment.texture = self.stencilTexture;
	descriptor.stencilAttachment.loadAction = MTLLoadActionClear;
	descriptor.stencilAttachment.storeAction = MTLStoreActionStore;
	descriptor.stencilAttachment.clearStencil = 0;

	encoder = [buffer renderCommandEncoderWithDescriptor:descriptor];

	[encoder setRenderPipelineState:self.layerCountPipeline];
	[encoder setCullMode:MTLCullModeFront];
	[encoder setDepthStencilState:self.layerCountStencil];
	[encoder setVertexBytes:&u length:sizeof(MXUniforms) atIndex:MXVertexIndexUniforms];

	// Render pass
	[encoder setCullMode:MTLCullModeFront];
	[self renderMesh:self.cube inEncoder:encoder];
	[self renderMesh:self.sphere inEncoder:encoder];
	[encoder setCullMode:MTLCullModeBack];
	[self renderMesh:self.cylinders inEncoder:encoder];
	[encoder endEncoding];

	NSInteger width = [self.stencilTexture width];

	compute = [buffer computeCommandEncoder];
	[compute setComputePipelineState:self.countPipeline];
	[compute setTexture:self.stencilTexture atIndex:0];
	[compute setBuffer:self.sumsBuffer offset:0 atIndex:1];
	memset(self.sumsBuffer.contents,0,width);

	threadGroupSize = MTLSizeMake(width, [self.stencilTexture height], 1);
	s = self.countPipeline.maxTotalThreadsPerThreadgroup;
	threadsPerGroup = MTLSizeMake(s, 1, 1);
	[compute dispatchThreads:threadGroupSize threadsPerThreadgroup:threadsPerGroup];
	[compute endEncoding];
	// Debug. Figure out how to extract max value

	[buffer addCompletedHandler:^(id<MTLCommandBuffer> cmdBuffer) {
		uint8_t klen = 0;
		uint8_t *buf = (uint8_t *)self.sumsBuffer.contents;
		for (NSInteger i = 0; i < width; ++i) {
			if (klen < buf[i]) klen = buf[i];
		}

		[self renderPhaseTwoWithKLen:klen];
	}];

	[buffer commit];
}

- (void)renderPhaseTwoWithKLen:(uint8_t)klen
{
	id<MTLCommandBuffer> buffer;
	MTLRenderPassDescriptor *descriptor;
	id<MTLRenderCommandEncoder> encoder;
	id<MTLComputeCommandEncoder> compute;
	MTLSize threadGroupSize;
	NSUInteger s;
	MTLSize threadsPerGroup;
	vector_float3 color;

	/*
	 *	Phase 2: run the calculations to render our scene based on the found
	 *	depth parameter
	 */

	buffer = [self.commandQueue commandBuffer];

	[buffer addCompletedHandler:^(id<MTLCommandBuffer> cmdBuffer) {
		dispatch_semaphore_signal(self.semaphore);
	}];

	/*
	 *	Clear depth
	 */

	compute = [buffer computeCommandEncoder];
	[compute setComputePipelineState:self.clearDepthPipeline];
	[compute setTexture:self.screenDepth atIndex:MXTextureIndexOutDepth];
	[compute setTexture:self.outTexture atIndex:MXTextureIndexOutColor];

	threadGroupSize = MTLSizeMake([self.colorTexture width], [self.colorTexture height], 1);
	s = sqrt(self.layerMergePipeline.maxTotalThreadsPerThreadgroup);
	threadsPerGroup = MTLSizeMake(s, s, 1);

	[compute dispatchThreads:threadGroupSize threadsPerThreadgroup:threadsPerGroup];
	[compute endEncoding];


	/*
	 *	Test layer merging of two objects assuming fixed k. (Note k maxes at 4)
	 */


	for (int k = 0; k < klen; ++k) {
		/*
		 *	Render kth layer
		 */

		descriptor = [[MTLRenderPassDescriptor alloc] init];
		descriptor.depthAttachment.texture = self.depthTexture;
		descriptor.depthAttachment.loadAction = MTLLoadActionClear;
		descriptor.depthAttachment.storeAction = MTLStoreActionStore;
		descriptor.depthAttachment.clearDepth = 1.0;
		descriptor.stencilAttachment.texture = self.depthTexture;
		descriptor.stencilAttachment.loadAction = MTLLoadActionClear;
		descriptor.stencilAttachment.storeAction = MTLStoreActionDontCare;
		descriptor.stencilAttachment.clearStencil = 0;
		descriptor.colorAttachments[0].texture = self.colorTexture;
		descriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
		descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
		descriptor.colorAttachments[0].clearColor = self.clearColor;
		encoder = [buffer renderCommandEncoderWithDescriptor:descriptor];

		[encoder setRenderPipelineState:self.layerExtractPipeline];
		[encoder setDepthStencilState:self.layerExtractStencil];
		[encoder setVertexBuffer:self.uniforms offset:0 atIndex:MXVertexIndexUniforms];
		[encoder setStencilReferenceValue:k];

		[encoder setCullMode:MTLCullModeFront];

		color = (vector_float3){ 1, 0.5, 0.3 };
		[encoder setFragmentBytes:&color length:sizeof(color) atIndex:MXFragmentIndexColor];
		[self renderMesh:self.cube inEncoder:encoder];

		color = (vector_float3){ 0.3, 1.0, 0.3 };
		[encoder setFragmentBytes:&color length:sizeof(color) atIndex:MXFragmentIndexColor];
		[self renderMesh:self.sphere inEncoder:encoder];

		[encoder setCullMode:MTLCullModeBack];

		color = (vector_float3){ 0.3, 0.5, 1.0 };
		[encoder setFragmentBytes:&color length:sizeof(color) atIndex:MXFragmentIndexColor];
		[self renderMesh:self.cylinders inEncoder:encoder];

		[encoder endEncoding];

		/*
		 *	Do parity testing pass. At the end we'll have a bit array set
		 */

		descriptor = [[MTLRenderPassDescriptor alloc] init];
		descriptor.depthAttachment.texture = self.depthTexture;
		descriptor.depthAttachment.loadAction = MTLLoadActionLoad;
		descriptor.depthAttachment.storeAction = MTLStoreActionStore;
		descriptor.stencilAttachment.texture = self.depthTexture;
		descriptor.stencilAttachment.loadAction = MTLLoadActionClear;
		descriptor.stencilAttachment.storeAction = MTLStoreActionDontCare;
		descriptor.stencilAttachment.clearStencil = 0;
		descriptor.colorAttachments[0].texture = self.colorTexture;
		descriptor.colorAttachments[0].loadAction = MTLLoadActionLoad;
		descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
		descriptor.colorAttachments[0].clearColor = self.clearColor;
		encoder = [buffer renderCommandEncoderWithDescriptor:descriptor];

		// Render phase
		[encoder setRenderPipelineState:self.layerParityPipeline];
		[encoder setDepthStencilState:self.layerParityStencil];
		[encoder setStencilReferenceValue:1];
		[encoder setVertexBuffer:self.uniforms offset:0 atIndex:MXVertexIndexUniforms];
		[encoder setCullMode:MTLCullModeNone];

		MTLClearColor clearColor = self.clearColor;
		color = (vector_float3){ clearColor.red, clearColor.green, clearColor.blue };
		[encoder setFragmentBytes:&color length:sizeof(color) atIndex:MXFragmentIndexColor];
		[self renderMesh:self.cube inEncoder:encoder];

		// Hide phase
		[encoder setRenderPipelineState:self.layerClearPipeline];
		[encoder setDepthStencilState:self.layerClearStencil];
		[encoder setStencilReferenceValue:1];	// Odd: not subtracted
		[encoder setVertexBuffer:self.square offset:0 atIndex:MXVertexIndexVertices];
		[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];

		[encoder endEncoding];

		// Render phase
		encoder = [buffer renderCommandEncoderWithDescriptor:descriptor];

		[encoder setRenderPipelineState:self.layerParityPipeline];
		[encoder setDepthStencilState:self.layerParityStencil];
		[encoder setStencilReferenceValue:1];
		[encoder setVertexBuffer:self.uniforms offset:0 atIndex:MXVertexIndexUniforms];
		[encoder setCullMode:MTLCullModeNone];

		[encoder setFragmentBytes:&color length:sizeof(color) atIndex:MXFragmentIndexColor];
		[self renderMesh:self.sphere inEncoder:encoder];

		// Hide phase
		[encoder setRenderPipelineState:self.layerClearPipeline];
		[encoder setDepthStencilState:self.layerClearStencil];
		[encoder setStencilReferenceValue:1];	// Odd: not subtracted
		[encoder setVertexBuffer:self.square offset:0 atIndex:MXVertexIndexVertices];
		[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];

		[encoder endEncoding];

		// Render phase
		encoder = [buffer renderCommandEncoderWithDescriptor:descriptor];

		[encoder setRenderPipelineState:self.layerParityPipeline];
		[encoder setDepthStencilState:self.layerParityStencil];
		[encoder setStencilReferenceValue:1];
		[encoder setVertexBuffer:self.uniforms offset:0 atIndex:MXVertexIndexUniforms];
		[encoder setCullMode:MTLCullModeNone];

		[encoder setFragmentBytes:&color length:sizeof(color) atIndex:MXFragmentIndexColor];
		[self renderMesh:self.cylinders inEncoder:encoder];

		// Hide phase
		[encoder setRenderPipelineState:self.layerClearPipeline];
		[encoder setDepthStencilState:self.layerClearStencil];
		[encoder setStencilReferenceValue:0];	// Even: subtracted
		[encoder setVertexBuffer:self.square offset:0 atIndex:MXVertexIndexVertices];
		[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
		[encoder endEncoding];

		/*
		 *	Merge phase uses a compute kernel to do the merging
		 */

		compute = [buffer computeCommandEncoder];
		[compute setComputePipelineState:self.layerMergePipeline];
		[compute setTexture:self.colorTexture atIndex:MXTextureIndexInColor];
		[compute setTexture:self.depthTexture atIndex:MXTextureIndexInDepth];
		[compute setTexture:self.outTexture atIndex:MXTextureIndexOutColor];
		[compute setTexture:self.screenDepth atIndex:MXTextureIndexOutDepth];

		MTLSize threadGroupSize = MTLSizeMake([self.colorTexture width], [self.colorTexture height], 1);
		uint s = sqrt(self.layerMergePipeline.maxTotalThreadsPerThreadgroup);
		MTLSize threadsPerGroup = MTLSizeMake(s, s, 1);

		[compute dispatchThreads:threadGroupSize threadsPerThreadgroup:threadsPerGroup];
		[compute endEncoding];
	}

	/*
	 *	Final step: render to screen
	 */

	descriptor = self.currentRenderPassDescriptor;
	encoder = [buffer renderCommandEncoderWithDescriptor:descriptor];

	[encoder setRenderPipelineState:self.outputResultPipeline];
	[encoder setVertexBuffer:self.square offset:0 atIndex:MXVertexIndexVertices];
	[encoder setFragmentTexture:self.outTexture atIndex:MXTextureIndexInColor];
	[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
	[encoder endEncoding];

	/*
	 *	Give our buffer a reference to the drawable screen so our screen can
	 *	be updated ("presented") when drawing is complete.
	 */

	[buffer presentDrawable:self.currentDrawable];
	[buffer commit];
}

@end
