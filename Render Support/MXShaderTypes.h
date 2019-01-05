//
//  MXShaderTypes.h
//  Metal
//
//  Created by William Woody on 12/27/18.
//  Copyright © 2018 Glenview Software. All rights reserved.
//

#ifndef MXShaderTypes_h
#define MXShaderTypes_h

#include <simd/simd.h>

/*
 *	Buffer index values. We use an enumeration to declare the values, and
 *	do it in a way which can be shared between the .metal and the .m files
 *	so we don't accidentally get the indexes mismatched.
 */

typedef enum MXVertexIndex
{
	MXVertexIndexVertices = 0,		/* For [[stage_in]], the vertex buffer MUST BE 0 */
	MXVertexIndexUniforms = 1,		/* Location of uniforms */
	MXVertexIndexLocations = 2,		/* Locations of our fairy lights */
} MXVertexIndex;

/*
 *	Attribute indexes. This is the same idea as above, but for attributes.
 */

typedef enum MXAttributeIndex
{
	MXAttributeIndexPosition = 0,
	MXAttributeIndexNormal = 1,
	MXAttributeIndexTexture = 2,

	MXAttributeIndexUV = 1,			// UV of our matrix
	MXAttributeIndexColor = 2,		// attribute index for fairy lights
} MXAttributeIndex;

/*
 *	Attribute indexes. This is the same idea as above, but for attributes.
 */

typedef enum MXTextureIndex
{
	MXTextureIndex0 = 0,
	MXTextureIndexShadow = 1,
	MXTextureIndexColor = 0,		// gbuffer
	MXTextureIndexNormal = 1,
	MXTextureIndexDepth = 2,
} MXTextureIndex;

/*
 *	Attribute indexes. This is the same idea as above, but for attributes.
 */

typedef enum MXColorIndex
{
	MXColorIndexColor = 0,
	MXColorIndexNormal = 1,
} MXColorIndex;

/*
 *	Uniforms structure
 */

typedef struct MXUniforms
{
	float aspect;
	matrix_float4x4 model;
	matrix_float4x4 view;
	matrix_float4x4 inverse;	// inverse of model
	matrix_float4x4 shadow;		// matrix for light position/shadow mapping
} MXUniforms;

#endif /* MXShaderTypes_h */
