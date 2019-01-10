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

#define MAX_FAIRYLIGHTS	20					// 20 lights

#define SHADOW_WIDTH	1024
#define SHADOW_HEIGHT	1024

@interface MXView () <MTKViewDelegate>
{
	// The fairy lights as a fixed sized array
	MXFairyLocation fairyLights[MAX_FAIRYLIGHTS];
}

// Command queue
@property (strong) id<MTLCommandQueue> commandQueue;

// The teapot, as a collection of meshes
@property (strong) NSArray<MTKMesh *> *teapot;
@property (strong) id<MTLBuffer> square;

// Pipeline state stuff
@property (strong) id<MTLLibrary> library;

// Shadow pipeline
@property (strong) id<MTLFunction> shadowVertexFunction;
@property (strong) id<MTLFunction> shadowFragmentFunction;
@property (strong) id<MTLRenderPipelineState> shadowPipeline;

// Fairy pipeline
@property (strong) id<MTLFunction> fairyVertexFunction;
@property (strong) id<MTLFunction> fairyFragmentFunction;
@property (strong) id<MTLRenderPipelineState> fairyPipeline;

// Fairy pipeline
@property (strong) id<MTLFunction> fairyLightVertexFunction;
@property (strong) id<MTLFunction> fairyLightFragmentFunction;
@property (strong) id<MTLRenderPipelineState> fairyLightPipeline;

// GBuffer pipeline
@property (strong) id<MTLFunction> gVertexFunction;
@property (strong) id<MTLFunction> gFragmentFunction;
@property (strong) id<MTLRenderPipelineState> gPipeline;

// GBuffer rendering
@property (strong) id<MTLFunction> grVertexFunction;
@property (strong) id<MTLFunction> grFragmentFunction;
@property (strong) id<MTLRenderPipelineState> grPipeline;

// Compute pipeline
@property (strong) id<MTLComputePipelineState> fkPipeline;
@property (strong) id<MTLFunction> fkFunction;
@property (strong) id<MTLBuffer> fkBuffer;

// Shadow map (2D texture of floats)
@property (strong) id<MTLTexture> shadowMap;

// G-Buffer
@property (strong) id<MTLTexture> colorMap;
@property (strong) id<MTLTexture> normalMap;

// Depth stencil
@property (strong) id<MTLDepthStencilState> depth;
@property (strong) id<MTLDepthStencilState> fairyDepth;
@property (strong) id<MTLDepthStencilState> drawStencil;
@property (strong) id<MTLDepthStencilState> maskStencil;
@property (strong) id<MTLDepthStencilState> illuminationStencil;

// Textures and support
@property (strong) id<MTLTexture> texture;
@property (strong) id<MTLTexture> fairyTexture;

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
	[self setupFairyVertex];
	[self setupFairyLights];
	[self setupComputePipeline];

	// Kludge to make sure our size is drawin in the proper order
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self mtkView:self drawableSizeWillChange:self.bounds.size];
	});
}

/****************************************************************************/
/*																			*/
/*	GBuffer Setup															*/
/*																			*/
/****************************************************************************/
#pragma mark - Texture Loading

/*
 *	Generate the textures used for our gbuffer when the screen resizes
 */

- (void)setupGBufferTexturesWithSize:(CGSize)size
{
	MTLTextureDescriptor *gbufferDescriptor;

	// Color map
	gbufferDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float width:size.width height:size.height mipmapped:NO];
	gbufferDescriptor.storageMode = MTLStorageModePrivate;
	gbufferDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
	self.colorMap = [self.device newTextureWithDescriptor:gbufferDescriptor];

	// normal vectors
	gbufferDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float width:size.width height:size.height mipmapped:NO];
	gbufferDescriptor.storageMode = MTLStorageModePrivate;
	gbufferDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
	self.normalMap = [self.device newTextureWithDescriptor:gbufferDescriptor];
}

/****************************************************************************/
/*																			*/
/*	Randomly populate fairy lights											*/
/*																			*/
/****************************************************************************/
#pragma mark - Texture Loading

- (void)setupFairyVertex
{
	static const MXFairyVertex square[] = {
		{ { -1, -1 } },
		{ { -1,  1 } },
		{ {  1, -1 } },
		{ { -1,  1 } },
		{ {  1, -1 } },
		{ {  1,  1 } }
	};
	self.square = [self.device newBufferWithBytes:square length:sizeof(square) options:MTLResourceOptionCPUCacheModeDefault];
}

- (void)setupFairyLights
{
	srand((unsigned int)time(NULL));

	for (int i = 0; i < MAX_FAIRYLIGHTS; ++i) {
		MXFairyLocation *l = fairyLights + i;

		/*
		 *	Randomly pick a color
		 */

		int c = (rand() % 6);
		if (c < 0) c += 6;
		switch (c) {
			default:
			case 0:
				l->color[0] = 1;
				l->color[1] = 0;
				l->color[2] = 0;
				break;
			case 1:
				l->color[0] = 0;
				l->color[1] = 1;
				l->color[2] = 0;
				break;
			case 2:
				l->color[0] = 0;
				l->color[1] = 0;
				l->color[2] = 1;
				break;
			case 3:
				l->color[0] = 1;
				l->color[1] = 1;
				l->color[2] = 0;
				break;
			case 4:
				l->color[0] = 0;
				l->color[1] = 1;
				l->color[2] = 1;
				break;
			case 5:
				l->color[0] = 1;
				l->color[1] = 0;
				l->color[2] = 1;
				break;
		}

		/*
		 *	Randomly pick a starting angle and speed
		 */

		int x = rand() % 360;
		if (x < 0) x += 360;

		l->angle[0] = x * M_PI / 180.0;

		int y = rand() % 30;
		if (y < 0) y += 30;
		y -= 15;
		l->angle[1] = y * M_PI / 180.0;

		int speed = rand() % 100;
		if (speed < 0) speed += 100;
		l->speed = speed / 50.0;

		int radius = rand() % 100;
		if (radius < 0) radius += 100;
		l->radius = 0.4 + radius/1500.0;

		l->size = 5;
	}

	self.fkBuffer = [self.device newBufferWithBytes:fairyLights length:sizeof(fairyLights) options:MTLResourceOptionCPUCacheModeDefault];
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
	self.fairyTexture = [textureLoader newTextureWithName:@"fairy" scaleFactor:1.0 bundle:nil options:@{} error:nil];
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
	 *	Get our library. This is the library of GPU methods that have
	 *	been precompiled by Xcode
	 */

	self.library = [self.device newDefaultLibrary];

	/*
	 *	Set certain parameters for our view's behavior, color depth, background
	 *	color and the like.
	 */

	self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
	self.clearColor = MTLClearColorMake(0.1, 0.1, 0.2, 1.0);
	self.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

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

	/*
	 *	Set up the depth stencil for our fairy lights. We disable writing to
	 *	the depth buffer so our fairy lights do not intefere with each other.
	 */

	MTLDepthStencilDescriptor *fairyDepthDescriptor = [[MTLDepthStencilDescriptor alloc] init];
	fairyDepthDescriptor.depthCompareFunction = MTLCompareFunctionLess;
	[fairyDepthDescriptor setDepthWriteEnabled:NO];

	self.fairyDepth = [self.device newDepthStencilStateWithDescriptor:fairyDepthDescriptor];

	/*
	 *	Set up the depth stencil for our gbuffer renderer. This flips the
	 *	stencil value for the pixels we draw in, so on our second pass
	 *	coloring our surface, we only color the pixels that have content in
	 *	them.
	 */

	MTLDepthStencilDescriptor *drawStencilDescriptor = [[MTLDepthStencilDescriptor alloc] init];
	drawStencilDescriptor.depthCompareFunction = MTLCompareFunctionLess;
	[drawStencilDescriptor setDepthWriteEnabled:YES];

	MTLStencilDescriptor *drawStencil = [[MTLStencilDescriptor alloc] init];
	drawStencil.stencilCompareFunction = MTLCompareFunctionAlways;
	drawStencil.depthStencilPassOperation = MTLStencilOperationReplace;
	drawStencilDescriptor.backFaceStencil = drawStencil;
	drawStencilDescriptor.frontFaceStencil = drawStencil;

	self.drawStencil = [self.device newDepthStencilStateWithDescriptor:drawStencilDescriptor];

	/*
	 *	Set up the mask stencil. This causes our renderer to only operate on
	 *	pixels that have been filled in
	 */

	MTLDepthStencilDescriptor *maskStencilDescriptor = [[MTLDepthStencilDescriptor alloc] init];
	maskStencilDescriptor.depthCompareFunction = MTLCompareFunctionLess;
	[maskStencilDescriptor setDepthWriteEnabled:NO];

	MTLStencilDescriptor *maskStencil = [[MTLStencilDescriptor alloc] init];
	maskStencil.stencilCompareFunction = MTLCompareFunctionEqual;
	maskStencilDescriptor.backFaceStencil = maskStencil;
	maskStencilDescriptor.frontFaceStencil = maskStencil;

	self.maskStencil = [self.device newDepthStencilStateWithDescriptor:maskStencilDescriptor];

	/*
	 *	Set up the mask stencil. This causes our renderer to only operate on
	 *	pixels that have been filled in
	 */

	MTLDepthStencilDescriptor *illuminationStencilDescriptor = [[MTLDepthStencilDescriptor alloc] init];
	illuminationStencilDescriptor.depthCompareFunction = MTLCompareFunctionAlways;
	[illuminationStencilDescriptor setDepthWriteEnabled:NO];

	MTLStencilDescriptor *illuminationStencil = [[MTLStencilDescriptor alloc] init];
	illuminationStencil.stencilCompareFunction = MTLCompareFunctionEqual;
	illuminationStencilDescriptor.backFaceStencil = illuminationStencil;
	illuminationStencilDescriptor.frontFaceStencil = illuminationStencil;

	self.illuminationStencil = [self.device newDepthStencilStateWithDescriptor:illuminationStencilDescriptor];
}

/*
 *	Set up our compute pipeline.
 */

- (void)setupComputePipeline
{
	/*
	 *	Get the kernel function from our library
	 */

	self.fkFunction = [self.library newFunctionWithName:@"fairy_kernel"];

	/*
	 *	Generate the compute pipeline state
	 */

	self.fkPipeline = [self.device newComputePipelineStateWithFunction:self.fkFunction error:nil];
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

	self.shadowVertexFunction = [self.library newFunctionWithName:@"vertex_shadow"];
	self.shadowFragmentFunction = [self.library newFunctionWithName:@"fragment_shadow"];

	self.fairyVertexFunction = [self.library newFunctionWithName:@"vertex_fairy"];
	self.fairyFragmentFunction = [self.library newFunctionWithName:@"fragment_fairy"];

	self.fairyLightVertexFunction = [self.library newFunctionWithName:@"vertex_illumination"];
	self.fairyLightFragmentFunction = [self.library newFunctionWithName:@"fragment_illumination"];

	self.gVertexFunction = [self.library newFunctionWithName:@"vertex_gbuffer"];
	self.gFragmentFunction = [self.library newFunctionWithName:@"fragment_gbuffer"];

	self.grVertexFunction = [self.library newFunctionWithName:@"vertex_grender"];
	self.grFragmentFunction = [self.library newFunctionWithName:@"fragment_grender"];

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
	 *	Next, build our pipeline descriptor for our shadow pipeline
	 */

	MTLRenderPipelineDescriptor *shadowPipelineDescriptor = [MTLRenderPipelineDescriptor new];
	shadowPipelineDescriptor.vertexFunction = self.shadowVertexFunction;
	shadowPipelineDescriptor.fragmentFunction = self.shadowFragmentFunction;
	shadowPipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(d);
	shadowPipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
	shadowPipelineDescriptor.colorAttachments[0].writeMask = MTLColorWriteMaskNone;

	self.shadowPipeline = [self.device newRenderPipelineStateWithDescriptor:shadowPipelineDescriptor error:nil];

	/*
	 *	Fairy lights pipeline renderer
	 */

	MTLVertexDescriptor *fairyDescriptors = [[MTLVertexDescriptor alloc] init];
	fairyDescriptors.attributes[MXAttributeIndexPosition].format = MTLVertexFormatFloat2;
	fairyDescriptors.attributes[MXAttributeIndexPosition].offset = 0;
	fairyDescriptors.attributes[MXAttributeIndexPosition].bufferIndex = 0;
	fairyDescriptors.layouts[0].stride = sizeof(MXFairyVertex);

	MTLRenderPipelineDescriptor *fairyPipelineDescriptor = [MTLRenderPipelineDescriptor new];
	fairyPipelineDescriptor.vertexFunction = self.fairyVertexFunction;
	fairyPipelineDescriptor.fragmentFunction = self.fairyFragmentFunction;
	fairyPipelineDescriptor.vertexDescriptor = fairyDescriptors;
	fairyPipelineDescriptor.depthAttachmentPixelFormat = self.depthStencilPixelFormat;
	fairyPipelineDescriptor.stencilAttachmentPixelFormat = self.depthStencilPixelFormat;
	fairyPipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;

	fairyPipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
	fairyPipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
	fairyPipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
	fairyPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
	fairyPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
	fairyPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
	fairyPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

	self.fairyPipeline = [self.device newRenderPipelineStateWithDescriptor:fairyPipelineDescriptor error:nil];

	/*
	 *	Fairy lights pipeline renderer
	 */

	MTLRenderPipelineDescriptor *fairyLightPipelineDescriptor = [MTLRenderPipelineDescriptor new];
	fairyLightPipelineDescriptor.vertexFunction = self.fairyLightVertexFunction;
	fairyLightPipelineDescriptor.fragmentFunction = self.fairyLightFragmentFunction;
	fairyLightPipelineDescriptor.vertexDescriptor = fairyDescriptors;
	fairyLightPipelineDescriptor.depthAttachmentPixelFormat = self.depthStencilPixelFormat;
	fairyLightPipelineDescriptor.stencilAttachmentPixelFormat = self.depthStencilPixelFormat;
	fairyLightPipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;

	fairyLightPipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
	fairyLightPipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
	fairyLightPipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
	fairyLightPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
	fairyLightPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
	fairyLightPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
	fairyLightPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

	self.fairyLightPipeline = [self.device newRenderPipelineStateWithDescriptor:fairyLightPipelineDescriptor error:nil];

	/*
	 *	GBuffer pipeline
	 */

	MTLRenderPipelineDescriptor *gBufferPipelineDescriptor = [MTLRenderPipelineDescriptor new];
	gBufferPipelineDescriptor.vertexFunction = self.gVertexFunction;
	gBufferPipelineDescriptor.fragmentFunction = self.gFragmentFunction;
	gBufferPipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
	gBufferPipelineDescriptor.colorAttachments[1].pixelFormat = MTLPixelFormatRGBA32Float;
	gBufferPipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(d);
	gBufferPipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
	gBufferPipelineDescriptor.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

	self.gPipeline = [self.device newRenderPipelineStateWithDescriptor:gBufferPipelineDescriptor error:nil];

	/*
	 *	GBuffer rendering pipeline
	 */

	MTLRenderPipelineDescriptor *grBufferPipelineDescriptor = [MTLRenderPipelineDescriptor new];
	grBufferPipelineDescriptor.vertexFunction = self.grVertexFunction;
	grBufferPipelineDescriptor.fragmentFunction = self.grFragmentFunction;
	grBufferPipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
	grBufferPipelineDescriptor.vertexDescriptor = fairyDescriptors;
	grBufferPipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
	grBufferPipelineDescriptor.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

	self.grPipeline = [self.device newRenderPipelineStateWithDescriptor:grBufferPipelineDescriptor error:nil];

	/*
	 *	Generate a fixed depth texture for shadow mapping
	 */

	MTLTextureDescriptor *shadowDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:SHADOW_WIDTH height:SHADOW_HEIGHT mipmapped:NO];
	shadowDescriptor.storageMode = MTLStorageModePrivate;
	shadowDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
	self.shadowMap = [self.device newTextureWithDescriptor:shadowDescriptor];

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
/*	Drawing Support															*/
/*																			*/
/****************************************************************************/
#pragma mark - Drawing Support

- (void)renderMesh:(NSArray<MTKMesh *> *)meshArray inEncoder:(id<MTLRenderCommandEncoder>)encoder
{
	for (MTKMesh *mesh in meshArray) {
		MTKMeshBuffer *vertexBuffer = [[mesh vertexBuffers] firstObject];
		[encoder setVertexBuffer:vertexBuffer.buffer offset:vertexBuffer.offset atIndex:MXVertexIndexVertices];

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

	[self setupGBufferTexturesWithSize:size];
}

- (void)drawInMTKView:(MTKView *)view
{
	MTLRenderPassDescriptor *descriptor;
	id<MTLRenderCommandEncoder> encoder;
	id<MTLComputeCommandEncoder> compute;

	/*
	 *	Test to see if we've constructed our G Buffer. If we haven't we
	 *	completely skip all of this. (That's because sometimes our
	 *	mtxView call is made before the drawing, and sometimes it happens
	 *	afterwards.)
	 */

	if (self.colorMap == nil) return;

	/*
	 *	Update our model transformation
	 */

	double elapsed = CACurrentMediaTime() - self.startTime;
	[self.model clear];
	[self.model translateByX:0 y:0 z:-2];
	[self.model rotateAroundFixedAxis:MTXXAxis byAngle:0.4];
	[self.model rotateAroundAxis:(vector_float3){ 0, 1, 0 } byAngle:elapsed];
	[self.model scaleBy:2];

	CGSize size = self.bounds.size;

	MXUniforms u;
	u.aspect = size.width/size.height;
	u.view = self.view.ctm;
	u.model = self.model.ctm;
	u.inverse = self.model.inverseCtm;
	u.vinverse = self.view.inverseCtm;
	u.elapsed = elapsed;

	/*
	 *	Populate u.shadow with the transformation which renders our scene from
	 *	the point of view of the light. For our test we simply recreate the
	 *	model/view transformation on the view stack, but rotating the
	 *	scene by anextra -0.3 radians, which is approximately where our
	 *	light is in our tests.
	 *
	 *	A more sophisticated system would actually figure out the location of
	 *	the light
	 */

	// Generate transformations to figure out light position
	[self.view push];
	[self.view translateByX:0 y:0 z:-2];
	[self.view rotateAroundFixedAxis:MTXXAxis byAngle:0.4];
	[self.view rotateAroundFixedAxis:MTXYAxis byAngle:-0.3];
	[self.view rotateAroundAxis:(vector_float3){ 0, 1, 0 } byAngle:elapsed];
	[self.view scaleBy:2];
	u.shadow = self.view.ctm;
	[self.view pop];

	/*
	 *	First step: get the command buffer. We delay if we're still drawing
	 *	a frame.
	 */

	id<MTLCommandBuffer> buffer = [self.commandQueue commandBuffer];

	/*
	 *	Create the compute pass to update the fairy locations in our compute
	 *	buffer
	 */

	compute = [buffer computeCommandEncoder];

	[compute setBuffer:self.fkBuffer offset:0 atIndex:MXVertexIndexLocations];
	[compute setBytes:&u length:sizeof(MXUniforms) atIndex:MXVertexIndexUniforms];
	[compute setComputePipelineState:self.fkPipeline];

	MTLSize totalThreadSize = MTLSizeMake(MAX_FAIRYLIGHTS, 1, 1);
	MTLSize threadsPerGroup = MTLSizeMake(MAX_FAIRYLIGHTS, 1, 1);
	[compute dispatchThreads:totalThreadSize threadsPerThreadgroup:threadsPerGroup];
	[compute endEncoding];

	/*
	 *	Create the render pass for our first pass for rendering the shadow mask
	 */

	descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
	descriptor.depthAttachment.texture = self.shadowMap;
	descriptor.depthAttachment.loadAction = MTLLoadActionClear;
	descriptor.depthAttachment.storeAction = MTLStoreActionStore;
	descriptor.depthAttachment.clearDepth = 1.0;

	encoder = [buffer renderCommandEncoderWithDescriptor:descriptor];
	[encoder setRenderPipelineState:self.shadowPipeline];
	[encoder setVertexBytes:&u length:sizeof(MXUniforms) atIndex:MXVertexIndexUniforms];
	[encoder setDepthStencilState:self.depth];
	[self renderMesh:self.teapot inEncoder:encoder];
	[encoder endEncoding];

	/*
	 *	Create the render pass for rendering our gbuffer
	 */

	descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
	descriptor.depthAttachment.texture = self.depthStencilTexture;
	descriptor.depthAttachment.loadAction = MTLLoadActionClear;
	descriptor.depthAttachment.storeAction = MTLStoreActionStore;
	descriptor.depthAttachment.clearDepth = 1.0;
	descriptor.stencilAttachment.texture = self.depthStencilTexture;
	descriptor.stencilAttachment.loadAction = MTLLoadActionClear;
	descriptor.stencilAttachment.storeAction = MTLStoreActionStore;
	descriptor.stencilAttachment.clearStencil = 0;

	descriptor.colorAttachments[MXColorIndexColor].texture = self.colorMap;
	descriptor.colorAttachments[MXColorIndexColor].clearColor = MTLClearColorMake(0.1, 0.1, 0.2, 1.0);
	descriptor.colorAttachments[MXColorIndexColor].loadAction = MTLLoadActionClear;
	descriptor.colorAttachments[MXColorIndexColor].storeAction = MTLStoreActionStore;
	descriptor.colorAttachments[MXColorIndexNormal].texture = self.normalMap;
	descriptor.colorAttachments[MXColorIndexNormal].clearColor = MTLClearColorMake(1, 0, 0, 0);
	descriptor.colorAttachments[MXColorIndexNormal].loadAction = MTLLoadActionClear;
	descriptor.colorAttachments[MXColorIndexNormal].storeAction = MTLStoreActionStore;
	encoder = [buffer renderCommandEncoderWithDescriptor:descriptor];

	[encoder setRenderPipelineState:self.gPipeline];
	[encoder setVertexBytes:&u length:sizeof(MXUniforms) atIndex:MXVertexIndexUniforms];
	[encoder setDepthStencilState:self.drawStencil];
	[encoder setStencilReferenceValue:1];
	[encoder setFragmentTexture:self.texture atIndex:MXTextureIndex0];
	[encoder setFragmentTexture:self.shadowMap atIndex:MXTextureIndexShadow];
	[self renderMesh:self.teapot inEncoder:encoder];
	[encoder endEncoding];

	/*
	 *	Render pipeline to draw our teapot from the gbuffer data. This basically
	 *	draws a square, passing in the color and normal data from the GBuffer
	 *	to actually handle shading.
	 */

	descriptor = [view currentRenderPassDescriptor];
	descriptor.depthAttachment.loadAction = MTLLoadActionLoad;
	descriptor.stencilAttachment.loadAction = MTLLoadActionLoad;
	encoder = [buffer renderCommandEncoderWithDescriptor:descriptor];

	[encoder setRenderPipelineState:self.grPipeline];
	[encoder setStencilReferenceValue:1];
	[encoder setVertexBuffer:self.square offset:0 atIndex:MXVertexIndexVertices];
	[encoder setDepthStencilState:self.maskStencil];
	[encoder setFragmentTexture:self.colorMap atIndex:MXTextureIndexColor];
	[encoder setFragmentTexture:self.normalMap atIndex:MXTextureIndexNormal];
	[encoder setFragmentTexture:self.depthStencilTexture atIndex:MXTextureIndexDepth];
	[encoder setFragmentBytes:&u length:sizeof(MXUniforms) atIndex:MXVertexIndexUniforms];
	[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];

	/*
	 *	Update fairy light positions
	 */

	for (int i = 0; i < MAX_FAIRYLIGHTS; ++i) {
		MXFairyLocation *loc = fairyLights + i;

		float a = loc->angle[0] + loc->speed * elapsed;

		float sx = sinf(a);
		float cx = cosf(a);
		float sy = sinf(loc->angle[1]);
		float cy = cosf(loc->angle[1]);

		loc->position[0] = cx * cy * loc->radius;
		loc->position[2] = sx * cy * loc->radius;
		loc->position[1] = sy * loc->radius;
	}

	/*
	 *	Render fairy light illumination on the teapot
	 */

	[encoder setRenderPipelineState:self.fairyLightPipeline];
	[encoder setDepthStencilState:self.illuminationStencil];
	[encoder setVertexBuffer:self.square offset:0 atIndex:MXVertexIndexVertices];
	[encoder setVertexBytes:&u length:sizeof(MXUniforms) atIndex:MXVertexIndexUniforms];
	[encoder setVertexBuffer:self.fkBuffer offset:0 atIndex:MXVertexIndexLocations];
	[encoder setFragmentTexture:self.colorMap atIndex:MXTextureIndexColor];
	[encoder setFragmentTexture:self.normalMap atIndex:MXTextureIndexNormal];
	[encoder setFragmentTexture:self.depthStencilTexture atIndex:MXTextureIndexDepth];
	[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:MAX_FAIRYLIGHTS];

	/*
	 *	Render fairy lights
	 */

	[encoder setRenderPipelineState:self.fairyPipeline];
	[encoder setDepthStencilState:self.fairyDepth];
	[encoder setVertexBuffer:self.square offset:0 atIndex:MXVertexIndexVertices];
	[encoder setVertexBytes:&u length:sizeof(MXUniforms) atIndex:MXVertexIndexUniforms];
	[encoder setVertexBuffer:self.fkBuffer offset:0 atIndex:MXVertexIndexLocations];
	[encoder setFragmentTexture:self.fairyTexture atIndex:MXTextureIndex0];
	[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:MAX_FAIRYLIGHTS];

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
